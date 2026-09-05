package at.uac.android.feature.gallery

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import at.uac.android.core.*
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.auth.decodeProfile
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.organization.OrganizationSession
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.*
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageException
import com.google.firebase.storage.StorageMetadata
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

fun interface GalleryPreparation {
    suspend fun prepare(uri: String): PreparedGalleryPhoto
}

class LocalGalleryPreparation(private val context: Context) : GalleryPreparation {
    override suspend fun prepare(uri: String): PreparedGalleryPhoto =
        withContext(Dispatchers.Default) {
            val bytes =
                LocalImagePreparation.prepare(
                    context,
                    Uri.parse(uri),
                    LocalImagePolicy.GALLERY_PHOTO,
                )
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            PreparedGalleryPhoto(bytes, bounds.outWidth, bounds.outHeight)
        }
}

fun localGallerySource(
    context: Context,
    currentSession: () -> OrganizationSession?,
): GallerySource =
    FirebaseGallerySource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.storage(context),
        AppBackend.callables(context),
        currentSession,
    )

class FirebaseGallerySource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val storage: FirebaseStorage,
    private val functions: CallableGateway,
    private val currentSession: () -> OrganizationSession?,
) : GallerySource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
        FirebaseBackendGuard.requireStorage(storage, db.app)
        functions.requireBoundTo(auth)
    }

    private fun identity(session: OrganizationSession) {
        if (currentSession() != session || auth.currentUser?.uid != session.uid)
            throw CancellationException("Gallery identity changed")
        if (
            !session.ready ||
                auth.currentUser?.isAnonymous != false ||
                auth.currentUser?.isEmailVerified != true
        )
            GalleryContract.fail(GalleryFailure.NOT_READY)
    }

    private suspend fun <T> read(session: OrganizationSession, action: suspend () -> T): T =
        try {
            identity(session)
            withTimeout(20_000) { action() }.also { identity(session) }
        } catch (error: TimeoutCancellationException) {
            throw GalleryException(GalleryFailure.OFFLINE, error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw GalleryException(galleryFailure(error), error)
        }

    private suspend fun profile(session: OrganizationSession) {
        val doc = db.document("users/${session.uid}").get(Source.SERVER).await()
        identity(session)
        if (!doc.exists()) GalleryContract.fail(GalleryFailure.NOT_READY)
        val value = decodeProfile(session.uid, doc.data.orEmpty())
        if (!value.active) GalleryContract.fail(GalleryFailure.NOT_READY)
        if (value.globalRole != session.globalRole) GalleryContract.fail(GalleryFailure.STALE)
    }

    private fun decode(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to decode(it.value) }
            is List<*> -> value.map(::decode)
            else -> value
        }

    private fun raw(doc: DocumentSnapshot) =
        RawDocument(doc.id, doc.data.orEmpty().mapValues { decode(it.value) })

    private suspend fun organization(id: String, session: OrganizationSession): RawDocument {
        if (!OrganizationContract.id(id)) GalleryContract.fail(GalleryFailure.INVALID)
        val doc = db.document("organizations/$id").get(Source.SERVER).await()
        identity(session)
        if (!doc.exists()) GalleryContract.fail(GalleryFailure.MISSING)
        return raw(doc).also { GalleryContract.authorize(it, session) }
    }

    private fun photos(id: String) =
        db.collection("organizations/$id/photos")
            .orderBy("createdAt", Query.Direction.DESCENDING)
            .limit((GalleryContract.MAX_PHOTOS + 1).toLong())

    override suspend fun snapshot(
        organizationId: String,
        session: OrganizationSession,
    ): GallerySnapshot =
        read(session) {
            profile(session)
            val before = organization(organizationId, session)
            val documents = photos(organizationId).get(Source.SERVER).await()
            identity(session)
            val after = organization(organizationId, session)
            profile(session)
            if (before.fields != after.fields) GalleryContract.fail(GalleryFailure.STALE)
            GalleryContract.snapshot(after, documents.documents.map(::raw), session)
        }

    override suspend fun photo(target: GalleryTarget, session: OrganizationSession): GalleryPhoto? =
        read(session) {
            val doc = db.document(target.document).get(Source.SERVER).await()
            identity(session)
            doc.takeIf { it.exists() }
                ?.let { GalleryContract.photo(target.organizationId, raw(it)) }
        }

    override suspend fun blob(target: GalleryTarget, session: OrganizationSession): GalleryBlob? =
        read(session) {
            val ref = storage.reference.child(target.path)
            val metadata =
                try {
                    ref.metadata.await()
                } catch (error: StorageException) {
                    if (error.errorCode == StorageException.ERROR_OBJECT_NOT_FOUND) return@read null
                    else throw error
                }
            identity(session)
            if (metadata.contentType != "image/jpeg" || metadata.sizeBytes !in 4 until 3_000_000)
                GalleryContract.fail(GalleryFailure.IMAGE_UNAVAILABLE)
            val url = ref.downloadUrl.await().toString()
            identity(session)
            val token =
                GalleryContract.token(url, target)
                    ?: GalleryContract.fail(GalleryFailure.IMAGE_UNAVAILABLE)
            val bytes = ref.getBytes(3_000_000).await()
            identity(session)
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            if (
                metadata.sizeBytes != bytes.size.toLong() ||
                    !LocalImagePreparation.validJpeg(bytes, LocalImagePolicy.GALLERY_PHOTO) ||
                    bounds.outWidth !in 1..1600 ||
                    bounds.outHeight !in 1..1600
            )
                GalleryContract.fail(GalleryFailure.IMAGE_UNAVAILABLE)
            GalleryBlob(bytes, token)
        }

    override suspend fun upload(
        target: GalleryTarget,
        photo: PreparedGalleryPhoto,
        session: OrganizationSession,
    ): GalleryBlob =
        write(session) {
            try {
                profile(session)
                organization(target.organizationId, session)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                throw GalleryUploadRejected(error, galleryFailure(error))
            }
            // Local gallery Rules require resource == null for CREATE (binary uploads, including
            // replacement).
            // This complements the repository's preflight; UPDATE alone only controls metadata
            // changes.
            try {
                storage.reference
                    .child(target.path)
                    .putBytes(
                        photo.bytes(),
                        StorageMetadata.Builder().setContentType("image/jpeg").build(),
                    )
                    .await()
            } catch (error: StorageException) {
                if (
                    error.errorCode in
                        setOf(
                            StorageException.ERROR_NOT_AUTHENTICATED,
                            StorageException.ERROR_NOT_AUTHORIZED,
                        )
                )
                    throw GalleryUploadRejected(error)
                throw error
            }
            identity(session)
            blob(target, session) ?: GalleryContract.fail(GalleryFailure.UNCONFIRMED)
        }

    override suspend fun create(
        intent: GalleryUploadIntent,
        imageUrl: String,
        session: OrganizationSession,
    ): GalleryReceipt =
        write(session) {
            profile(session)
            organization(intent.target.organizationId, session)
            if (GalleryContract.token(imageUrl, intent.target) == null)
                GalleryContract.fail(GalleryFailure.INVALID)
            val data =
                mapOf(
                    "organizationId" to intent.target.organizationId,
                    "photoId" to intent.target.photoId,
                    "imageURL" to imageUrl,
                ) + (intent.caption?.let { mapOf("caption" to it) } ?: emptyMap())
            val reply =
                functions
                    .getHttpsCallable("createOrganizationPhotoMetadata")
                    .withTimeout(60, TimeUnit.SECONDS)
                    .call(data)
                    .await()
                    .data
            identity(session)
            GalleryContract.receipt(reply, intent.target, create = true)
        }

    override suspend fun remove(
        target: GalleryTarget,
        session: OrganizationSession,
    ): GalleryReceipt =
        write(session) {
            profile(session)
            organization(target.organizationId, session)
            val reply =
                functions
                    .getHttpsCallable("deleteOrganizationPhotoMetadata")
                    .withTimeout(60, TimeUnit.SECONDS)
                    .call(
                        mapOf(
                            "organizationId" to target.organizationId,
                            "photoId" to target.photoId,
                        )
                    )
                    .await()
                    .data
            identity(session)
            GalleryContract.receipt(reply, target, create = false)
        }

    override suspend fun removeBlob(target: GalleryTarget, session: OrganizationSession) =
        write(session) {
            profile(session)
            organization(target.organizationId, session)
            storage.reference.child(target.path).delete().await()
            identity(session)
        }

    private suspend fun <T> write(session: OrganizationSession, action: suspend () -> T): T =
        try {
            identity(session)
            action().also { identity(session) }
        } catch (error: CancellationException) {
            throw error
        } catch (error: GalleryUploadRejected) {
            throw error
        } catch (error: Exception) {
            val failure = galleryFailure(error)
            throw GalleryException(
                if (failure in setOf(GalleryFailure.OFFLINE, GalleryFailure.UNKNOWN))
                    GalleryFailure.UNCONFIRMED
                else failure,
                error,
            )
        }

    override fun changes(organizationId: String, session: OrganizationSession): Flow<Result<Unit>> =
        callbackFlow {
            identity(session)
            if (!OrganizationContract.id(organizationId))
                GalleryContract.fail(GalleryFailure.INVALID)
            val listeners = mutableListOf<ListenerRegistration>()
            fun signal(error: FirebaseFirestoreException?) {
                try {
                    identity(session)
                    trySend(
                        if (error == null) Result.success(Unit)
                        else Result.failure(GalleryException(galleryFailure(error), error))
                    )
                } catch (error: CancellationException) {
                    close(error)
                } catch (error: Exception) {
                    trySend(Result.failure(error))
                }
            }
            try {
                // These are invalidation signals, never authority/data. Every signal hides old data
                // and requires SERVER revalidation.
                listeners +=
                    db.document("organizations/$organizationId").addSnapshotListener(
                        MetadataChanges.INCLUDE
                    ) { _, error ->
                        signal(error)
                    }
                listeners +=
                    db.document("users/${session.uid}").addSnapshotListener(
                        MetadataChanges.INCLUDE
                    ) { _, error ->
                        signal(error)
                    }
                listeners +=
                    photos(organizationId).addSnapshotListener(MetadataChanges.INCLUDE) { _, error
                        ->
                        signal(error)
                    }
                awaitClose {}
            } finally {
                listeners.forEach { it.remove() }
            }
        }
}

fun galleryFailure(error: Throwable): GalleryFailure =
    when (error) {
        is GalleryException -> error.failure
        is LocalCallableException ->
            when (error.code) {
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableFailure.UNAUTHENTICATED -> GalleryFailure.DENIED
                LocalCallableFailure.NOT_FOUND -> GalleryFailure.MISSING
                LocalCallableFailure.INVALID_ARGUMENT -> GalleryFailure.INVALID
                LocalCallableFailure.RESOURCE_EXHAUSTED -> GalleryFailure.LIMIT
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableFailure.DEADLINE_EXCEEDED -> GalleryFailure.OFFLINE
                LocalCallableFailure.UNCONFIRMED -> GalleryFailure.UNCONFIRMED
                else -> GalleryFailure.UNKNOWN
            }
        is LocalImageException -> GalleryFailure.UNREADABLE
        else -> gallerySdkFailure(error)
    }

private fun gallerySdkFailure(error: Throwable): GalleryFailure =
    when (error) {
        is FirebaseFirestoreException ->
            when (error.code.name) {
                "PERMISSION_DENIED",
                "UNAUTHENTICATED" -> GalleryFailure.DENIED
                "NOT_FOUND" -> GalleryFailure.MISSING
                "UNAVAILABLE",
                "DEADLINE_EXCEEDED" -> GalleryFailure.OFFLINE
                "FAILED_PRECONDITION" -> GalleryFailure.INDEX
                else -> GalleryFailure.UNKNOWN
            }
        is StorageException ->
            when (error.errorCode) {
                StorageException.ERROR_NOT_AUTHENTICATED,
                StorageException.ERROR_NOT_AUTHORIZED -> GalleryFailure.DENIED
                StorageException.ERROR_OBJECT_NOT_FOUND -> GalleryFailure.MISSING
                StorageException.ERROR_RETRY_LIMIT_EXCEEDED -> GalleryFailure.OFFLINE
                else -> GalleryFailure.UNKNOWN
            }
        else -> GalleryFailure.UNKNOWN
    }
