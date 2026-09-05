package at.uac.android.feature.contentmedia

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Base64
import at.uac.android.core.*
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.organization.OrganizationSession
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageException
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

fun interface ContentCoverPreparation {
    suspend fun prepare(contentUri: String): PreparedContentCover
}

class LocalContentCoverPreparation(private val context: Context) : ContentCoverPreparation {
    override suspend fun prepare(contentUri: String): PreparedContentCover =
        withContext(Dispatchers.Default) {
            val bytes =
                LocalImagePreparation.prepare(
                    context,
                    Uri.parse(contentUri),
                    LocalImagePolicy.CONTENT_COVER_16_9,
                )
            val dimensions = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, dimensions)
            PreparedContentCover(bytes, dimensions.outWidth, dimensions.outHeight)
        }
}

fun localContentCoverSource(context: Context): ContentCoverSource =
    FirebaseContentCoverSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.storage(context),
        AppBackend.callables(context),
    )

class FirebaseContentCoverSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val storage: FirebaseStorage,
    private val functions: CallableGateway,
) : ContentCoverSource {
    private val authoring = FirebaseAuthoringSource(db, auth)

    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
        FirebaseBackendGuard.requireStorage(storage, db.app)
        functions.requireBoundTo(auth)
    }

    private fun identity(session: OrganizationSession) {
        if (auth.currentUser?.uid != session.uid)
            throw CancellationException("Content cover identity changed")
        if (
            !session.ready ||
                auth.currentUser?.isEmailVerified != true ||
                auth.currentUser?.isAnonymous != false
        )
            ContentCoverContract.fail(ContentCoverFailure.NOT_READY)
    }

    private suspend fun <T> read(session: OrganizationSession, action: suspend () -> T): T =
        try {
            identity(session)
            withTimeout(20_000) { action() }.also { identity(session) }
        } catch (error: TimeoutCancellationException) {
            throw ContentCoverException(ContentCoverFailure.OFFLINE, error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw ContentCoverException(contentCoverFailure(error), error)
        }

    override suspend fun snapshot(
        target: ContentCoverTarget,
        session: OrganizationSession,
    ): ContentCoverSnapshot =
        read(session) {
            val org =
                authoring.organization(target.organizationId, session)
                    ?: ContentCoverContract.fail(ContentCoverFailure.MISSING)
            AuthoringContract.authority(org, session)
            val item =
                authoring.find(target.organizationId, target.kind, target.contentId, session)
                    ?: ContentCoverContract.fail(ContentCoverFailure.MISSING)
            val latest =
                authoring.organization(target.organizationId, session)
                    ?: ContentCoverContract.fail(ContentCoverFailure.MISSING)
            AuthoringContract.authority(latest, session)
            if (org.fields != latest.fields) ContentCoverContract.fail(ContentCoverFailure.STALE)
            ContentCoverSnapshot(target, latest, item).also {
                ContentCoverContract.validate(it, target)
            }
        }

    override suspend fun image(
        snapshot: ContentCoverSnapshot,
        session: OrganizationSession,
    ): ContentCoverAsset? =
        read(session) {
            val url = snapshot.imageUrl ?: return@read null
            val token =
                ContentCoverContract.token(url, snapshot.target)
                    ?: ContentCoverContract.fail(ContentCoverFailure.IMAGE_UNAVAILABLE)
            // The URL never becomes a destination. All operations use this exact validated local
            // SDK path.
            val reference = storage.reference.child(snapshot.target.path)
            val metadata = reference.metadata.await()
            val download = reference.downloadUrl.await().toString()
            val bytes = reference.getBytes(3_000_000).await()
            val checks = linkedSetOf<ContentCoverCheck>()
            if (metadata.contentType != "image/jpeg") checks += ContentCoverCheck.CONTENT_TYPE
            if (metadata.sizeBytes != bytes.size.toLong()) checks += ContentCoverCheck.BYTE_COUNT
            if (!LocalImagePreparation.validJpeg(bytes, LocalImagePolicy.CONTENT_COVER_16_9))
                checks += ContentCoverCheck.JPEG
            if (ContentCoverContract.token(download, snapshot.target) != token)
                checks += ContentCoverCheck.TOKEN
            if (checks.isNotEmpty())
                throw ContentCoverException(
                    ContentCoverFailure.IMAGE_UNAVAILABLE,
                    diagnostic =
                        ContentCoverDiagnostic(ContentCoverStage.READ_IMAGE, failedChecks = checks),
                )
            ContentCoverAsset(bytes, token)
        }

    override fun changes(snapshot: ContentCoverSnapshot, session: OrganizationSession) =
        authoring.changes(
            snapshot.target.organizationId,
            snapshot.target.kind,
            snapshot.item.status,
            session,
            snapshot.item,
        )

    override suspend fun upload(
        intent: ContentCoverIntent.Upload,
        session: OrganizationSession,
    ): ContentCoverResponse =
        withContext(Dispatchers.IO) {
            identity(session)
            var stage = ContentCoverStage.UPLOAD_CALL
            try {
                val target = intent.snapshot.target
                val payload =
                    mapOf(
                        "kind" to target.wireKind,
                        "contentId" to target.contentId,
                        "imageBase64" to Base64.encodeToString(intent.photo.jpeg, Base64.NO_WRAP),
                    )
                val result =
                    functions
                        .getHttpsCallable("uploadOrganizationContentCover")
                        .withTimeout(120_000, TimeUnit.MILLISECONDS)
                        .call(payload)
                        .await()
                        .data
                identity(session)
                stage = ContentCoverStage.UPLOAD_RECEIPT
                ContentCoverContract.response(result, target, intent.photo)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                val reason = contentCoverFailure(error)
                // Handler may have overwritten the object before an INTERNAL/update failure. Never
                // infer rollback success.
                throw ContentCoverException(
                    if (reason in setOf(ContentCoverFailure.UNKNOWN, ContentCoverFailure.OFFLINE))
                        ContentCoverFailure.UNCONFIRMED
                    else reason,
                    error,
                    contentCoverDiagnostic(stage, error),
                )
            }
        }

    override suspend fun remove(intent: ContentCoverIntent.Remove, session: OrganizationSession) {
        identity(session)
        if (!intent.snapshot.removable || intent.snapshot.target.kind != ContentKind.NEWS)
            ContentCoverContract.fail(ContentCoverFailure.READ_ONLY)
        try {
            db.runTransaction { transaction ->
                    identity(session)
                    val target = intent.snapshot.target
                    val orgDoc =
                        transaction.get(db.document("organizations/${target.organizationId}"))
                    val org =
                        OrganizationContract.record(
                            RawDocument(orgDoc.id, fields(orgDoc.data)),
                            session,
                        )
                    AuthoringContract.authority(org, session)
                    val reference = db.document("news/${target.contentId}")
                    val doc = transaction.get(reference)
                    val data = fields(doc.data)
                    val status =
                        AuthoringStatus.entries.firstOrNull { it.wire == data["moderationStatus"] }
                            ?: ContentCoverContract.fail(ContentCoverFailure.INVALID)
                    val item =
                        AuthoringContract.item(
                            ContentKind.NEWS,
                            RawDocument(doc.id, data),
                            target.organizationId,
                            status,
                            session,
                        )
                    val current = ContentCoverSnapshot(target, org, item)
                    ContentCoverContract.unchanged(intent.snapshot, current)
                    if (!current.removable) ContentCoverContract.fail(ContentCoverFailure.READ_ONLY)
                    transaction.update(
                        reference,
                        mapOf(
                            "imageURL" to FieldValue.delete(),
                            "updatedAt" to FieldValue.serverTimestamp(),
                        ),
                    )
                }
                .await()
            identity(session)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            val reason = contentCoverFailure(error)
            throw ContentCoverException(
                if (reason in setOf(ContentCoverFailure.UNKNOWN, ContentCoverFailure.OFFLINE))
                    ContentCoverFailure.UNCONFIRMED
                else reason,
                error,
            )
        }
    }

    private fun fields(data: Map<String, Any>?): Map<String, Any?> =
        (data ?: ContentCoverContract.fail(ContentCoverFailure.MISSING)).mapValues {
            decode(it.value)
        }

    private fun decode(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to decode(it.value) }
            is List<*> -> value.map(::decode)
            else -> value
        }
}

internal fun contentCoverSdkFailure(error: Throwable): ContentCoverFailure =
    when (error) {
        is FirebaseFirestoreException ->
            when (error.code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                FirebaseFirestoreException.Code.UNAUTHENTICATED -> ContentCoverFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> ContentCoverFailure.OFFLINE
                FirebaseFirestoreException.Code.NOT_FOUND -> ContentCoverFailure.MISSING
                FirebaseFirestoreException.Code.ABORTED ->
                    error.cause?.let(::contentCoverFailure) ?: ContentCoverFailure.STALE
                else -> error.cause?.let(::contentCoverFailure) ?: ContentCoverFailure.UNKNOWN
            }
        is StorageException ->
            when (error.errorCode) {
                StorageException.ERROR_NOT_AUTHORIZED,
                StorageException.ERROR_NOT_AUTHENTICATED -> ContentCoverFailure.DENIED
                StorageException.ERROR_OBJECT_NOT_FOUND -> ContentCoverFailure.IMAGE_UNAVAILABLE
                StorageException.ERROR_RETRY_LIMIT_EXCEEDED -> ContentCoverFailure.OFFLINE
                else -> ContentCoverFailure.UNKNOWN
            }
        else -> ContentCoverFailure.UNKNOWN
    }

/** Kept outside the pure mapper; no enum switch/static mapping initialization. */
internal fun contentCoverSdkCode(error: Throwable): String? {
    if (error is FirebaseFirestoreException) return error.code.name
    if (error is StorageException) return error.errorCode.toString()
    return null
}
