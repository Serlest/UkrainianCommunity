package at.uac.android.feature.featuredmanagement

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageException
import com.google.firebase.storage.StorageMetadata
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

fun localFeaturedManagementSource(context: Context): FeaturedManagementSource =
    FirebaseFeaturedManagementSource(AppBackend.firestore(context), AppBackend.auth(context), AppBackend.storage(context), AppBackend.callables(context))

fun localFeaturedImagePreparation(context: Context) = FeaturedImagePreparation { uri ->
    LocalImagePreparation.prepare(context.applicationContext, Uri.parse(uri), LocalImagePolicy.CONTENT_COVER_16_9)
}

class FirebaseFeaturedManagementSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val storage: FirebaseStorage,
    private val functions: CallableGateway,
) : FeaturedManagementSource {
    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        FirebaseBackendGuard.requireStorage(storage, db.app)
        functions.requireBoundTo(auth)
    }

    private fun identity(session: ModerationSession) {
        FeaturedManagementContract.requireOwner(session)
        val user = auth.currentUser
        if (user?.uid != session.uid || user.isAnonymous || !user.isEmailVerified) FeaturedManagementContract.fail(FeaturedFailure.ACCESS)
    }

    override suspend fun list(session: ModerationSession): List<FeaturedBanner> = request {
        identity(session)
        val snapshot = withTimeout(20_000) { db.collection("featuredBanners").get(Source.SERVER).await() }
        identity(session)
        if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites()) FeaturedManagementContract.fail(FeaturedFailure.OFFLINE)
        snapshot.documents.map { parse(it) }.sortedWith(compareByDescending<FeaturedBanner> { it.draft.priority }.thenByDescending { it.version.updatedAt }.thenBy { it.id })
    }

    override suspend fun find(session: ModerationSession, id: String): FeaturedBanner? = request {
        identity(session)
        if (!FeaturedManagementContract.id(id)) FeaturedManagementContract.fail(FeaturedFailure.INVALID)
        val snapshot = withTimeout(15_000) { db.document("featuredBanners/$id").get(Source.SERVER).await() }
        identity(session)
        if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites()) FeaturedManagementContract.fail(FeaturedFailure.OFFLINE)
        if (snapshot.exists()) parse(snapshot) else null
    }

    override suspend fun save(session: ModerationSession, draft: FeaturedDraft, create: Boolean): FeaturedReceipt = callable(session, "saveFeaturedBanner", FeaturedManagementContract.saveRequest(draft, create), draft.id)

    override suspend fun setActive(session: ModerationSession, id: String, active: Boolean): FeaturedReceipt =
        callable(session, "setFeaturedBannerActive", mapOf("id" to id, "isActive" to active), id)

    override suspend fun delete(session: ModerationSession, id: String): FeaturedReceipt =
        callable(session, "deleteFeaturedBanner", mapOf("id" to id), id)

    private suspend fun callable(session: ModerationSession, name: String, payload: Map<String, Any>, id: String): FeaturedReceipt =
        withContext(Dispatchers.IO) {
            identity(session)
            val task = functions.getHttpsCallable(name).withTimeout(60, TimeUnit.SECONDS).call(payload)
            val data = try { task.await().data } catch (error: Exception) {
                if (error is CancellationException) throw error
                throw FeaturedException(FeaturedFailure.UNCONFIRMED, error)
            }
            FeaturedManagementContract.receipt(id, data)
        }

    override suspend fun upload(session: ModerationSession, bannerId: String, jpeg: ByteArray): String = withContext(Dispatchers.IO) {
        identity(session)
        if (!FeaturedManagementContract.id(bannerId) || !LocalImagePreparation.validJpeg(jpeg, LocalImagePolicy.CONTENT_COVER_16_9)) FeaturedManagementContract.fail(FeaturedFailure.IMAGE)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, bounds)
        if (bounds.outMimeType != "image/jpeg" || bounds.outWidth * 9 != bounds.outHeight * 16) FeaturedManagementContract.fail(FeaturedFailure.IMAGE)
        val ref = storage.reference.child("featuredBanners/$bannerId/hero-${UUID.randomUUID()}.jpg")
        try {
            ref.putBytes(jpeg, StorageMetadata.Builder().setContentType("image/jpeg").build()).await()
            identity(session)
            val metadata = ref.metadata.await()
            val stored = ref.getBytes(3_000_000).await()
            if (metadata.contentType != "image/jpeg" || metadata.sizeBytes != jpeg.size.toLong() || !stored.contentEquals(jpeg)) FeaturedManagementContract.fail(FeaturedFailure.UNCONFIRMED)
            ref.downloadUrl.await().toString().also { if (!it.startsWith("http")) FeaturedManagementContract.fail(FeaturedFailure.UNCONFIRMED) }
        } catch (error: Exception) {
            if (error is CancellationException || error is FeaturedException) throw error
            throw FeaturedException(if (error is StorageException && error.errorCode in setOf(StorageException.ERROR_NOT_AUTHENTICATED, StorageException.ERROR_NOT_AUTHORIZED)) FeaturedFailure.ACCESS else FeaturedFailure.UNCONFIRMED, error)
        }
    }

    private fun parse(snapshot: DocumentSnapshot): FeaturedBanner {
        val f = snapshot.data.orEmpty()
        fun text(key: String, max: Int) = (f[key] as? String)?.takeIf { it.length <= max }.orEmpty()
        val updated = (f["updatedAt"] as? Timestamp)?.toDate()?.toInstant() ?: Instant.EPOCH
        val created = (f["createdAt"] as? Timestamp)?.toDate()?.toInstant() ?: Instant.EPOCH
        val action = FeaturedAction.entries.firstOrNull { it.wire == f["actionType"] }
        val region = FeaturedRegion.entries.firstOrNull { it.wire == f["regionScope"] }
        val sections = (f["visibleSections"] as? List<*>)?.mapNotNull { raw -> FeaturedSection.entries.firstOrNull { it.wire == raw } }?.toSet().orEmpty()
        val localizations = (f["localizations"] as? Map<*, *>)?.mapNotNull { (key, raw) ->
            val language = key as? String ?: return@mapNotNull null
            val map = raw as? Map<*, *> ?: return@mapNotNull null
            language to FeaturedLocalized((map["title"] as? String).orEmpty(), (map["subtitle"] as? String).orEmpty())
        }?.toMap().orEmpty()
        val allowed = setOf("id", "internalName", "localizations", "title", "subtitle", "imageURL", "actionType", "actionTargetID", "externalURL", "regionScope", "federalState", "visibleSections", "displayDurationSeconds", "priority", "isActive", "startsAt", "endsAt", "createdAt", "updatedAt", "createdBy", "updatedBy")
        val repair = f["id"] != snapshot.id || action == null || region == null || sections.isEmpty() || f.keys.any { it !in allowed } || updated == Instant.EPOCH || created == Instant.EPOCH
        val draft = FeaturedDraft(
            id = snapshot.id, internalName = text("internalName", 120), localizations = localizations,
            title = text("title", 120), subtitle = text("subtitle", 240), imageUrl = text("imageURL", 2048),
            action = action ?: FeaturedAction.NONE, actionTargetId = text("actionTargetID", 256), externalUrl = text("externalURL", 2048),
            region = region ?: FeaturedRegion.ALL_AUSTRIA, federalState = text("federalState", 64), sections = sections.ifEmpty { setOf(FeaturedSection.HOME) },
            displayDurationSeconds = (f["displayDurationSeconds"] as? Number)?.toInt() ?: 6,
            priority = (f["priority"] as? Number)?.toInt() ?: 0, active = f["isActive"] as? Boolean ?: false,
            startsAt = (f["startsAt"] as? Timestamp)?.toDate()?.toInstant(), endsAt = (f["endsAt"] as? Timestamp)?.toDate()?.toInstant(),
        )
        val safeFingerprint = runCatching { FeaturedManagementContract.fingerprint(draft) }.getOrElse { "repair:${snapshot.id}:$updated" }
        return FeaturedBanner(draft, FeaturedVersion(snapshot.id, updated, safeFingerprint), created, text("createdBy", 128), text("updatedBy", 128).ifEmpty { null }, repair)
    }

    private suspend fun <T> request(block: suspend () -> T): T = try { block() } catch (error: TimeoutCancellationException) {
        throw FeaturedException(FeaturedFailure.OFFLINE, error)
    } catch (error: CancellationException) { throw error } catch (error: FeaturedException) { throw error } catch (error: Exception) {
        val failure = if (error is FirebaseFirestoreException && error.code in setOf(FirebaseFirestoreException.Code.PERMISSION_DENIED, FirebaseFirestoreException.Code.UNAUTHENTICATED)) FeaturedFailure.ACCESS else FeaturedFailure.OFFLINE
        throw FeaturedException(failure, error)
    }
}
