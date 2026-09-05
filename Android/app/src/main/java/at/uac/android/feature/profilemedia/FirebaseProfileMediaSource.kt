package at.uac.android.feature.profilemedia

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import at.uac.android.core.LocalStorage
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.personal.FirestorePersonalSource
import at.uac.android.feature.personal.PersonalProfile
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageException
import com.google.firebase.storage.StorageMetadata
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

class FirebaseProfileMediaSource(
    private val storage: FirebaseStorage,
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
) : ProfileMediaSource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
        FirebaseBackendGuard.requireStorage(storage, db.app)
    }

    private fun identity(uid: String) {
        profileAvatarPath(uid)
        if (
            auth.currentUser?.uid != uid ||
                auth.currentUser?.isEmailVerified != true ||
                auth.currentUser?.isAnonymous != false
        )
            throw ProfileMediaException(ProfileMediaFailure.NOT_READY)
    }

    override suspend fun upload(
        uid: String,
        photo: PreparedAvatar,
        operation: AvatarOperation,
        onProgress: (Float) -> Unit,
    ): String = request {
        identity(uid)
        operation.check()
        val jpeg = photo.jpeg
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, bounds)
        if (
            !LocalImagePreparation.validJpeg(jpeg, LocalImagePolicy.AVATAR) ||
                bounds.outWidth !in 1..1024 ||
                bounds.outWidth != bounds.outHeight ||
                bounds.outMimeType != "image/jpeg"
        )
            throw ProfileMediaException(ProfileMediaFailure.INVALID)
        val reference = storage.reference.child(profileAvatarPath(uid))
        val task =
            reference.putBytes(jpeg, StorageMetadata.Builder().setContentType("image/jpeg").build())
        operation.attachCancel { task.cancel() }
        val listener =
            com.google.firebase.storage.OnProgressListener<
                com.google.firebase.storage.UploadTask.TaskSnapshot
            > {
                if (it.totalByteCount > 0)
                    onProgress(it.bytesTransferred.toFloat() / it.totalByteCount)
            }
        task.addOnProgressListener(listener)
        try {
            task.await()
        } catch (error: CancellationException) {
            operation.check()
            throw error
        } finally {
            operation.attachCancel(null)
            task.removeOnProgressListener(listener)
        }
        operation.check()
        identity(uid)
        val metadata = reference.metadata.await()
        if (
            metadata.contentType != "image/jpeg" ||
                metadata.sizeBytes != jpeg.size.toLong() ||
                !reference
                    .getBytes(LocalImagePolicy.AVATAR.maximumBytes.toLong())
                    .await()
                    .contentEquals(jpeg)
        )
            throw ProfileMediaException(ProfileMediaFailure.UNCONFIRMED)
        operation.check()
        reference.downloadUrl.await().toString().also {
            if (!LocalStorage.urlMatches(it, profileAvatarPath(uid)))
                throw ProfileMediaException(ProfileMediaFailure.INVALID)
        }
    }

    override suspend fun saveAvatar(
        uid: String,
        url: String,
        stillCurrent: () -> Boolean,
    ): PersonalProfile = request {
        identity(uid)
        if (!LocalStorage.urlMatches(url, profileAvatarPath(uid)))
            throw ProfileMediaException(ProfileMediaFailure.INVALID)
        val user = db.document("users/$uid")
        val public = db.document("publicProfiles/$uid")
        db.runTransaction { transaction ->
                if (!stillCurrent()) throw CancellationException("Account scope changed")
                val latest = transaction.get(user)
                if (latest.getString("id") != uid)
                    throw ProfileMediaException(ProfileMediaFailure.INVALID)
                val name =
                    latest.getString("displayName")?.takeIf(String::isNotBlank)
                        ?: latest.getString("fullName")
                val city = latest.getString("city")
                val region = latest.getString("selectedFederalState")
                if (name == null || city == null || region == null)
                    throw ProfileMediaException(ProfileMediaFailure.INVALID)
                if (!stillCurrent()) throw CancellationException("Account scope changed")
                // Only the avatar changes in the private profile. Public fields reflect this
                // transaction's fresh profile.
                transaction.update(
                    user,
                    mapOf("avatarURL" to url, "updatedAt" to FieldValue.serverTimestamp()),
                )
                transaction.set(
                    public,
                    mapOf(
                        "id" to uid,
                        "displayName" to name,
                        "city" to city,
                        "federalState" to region,
                        "avatarURL" to url,
                        "updatedAt" to FieldValue.serverTimestamp(),
                    ),
                )
            }
            .await()
        if (!stillCurrent()) throw CancellationException("Account scope changed")
        val privateRead = withTimeout(5_000) { FirestorePersonalSource(db).profile(uid) }
        val publicRead = withTimeout(5_000) { public.get(Source.SERVER).await() }
        if (
            privateRead.draft.avatarUrl != url ||
                publicRead.getString("id") != uid ||
                publicRead.getString("avatarURL") != url ||
                publicRead.getString("displayName") != privateRead.draft.displayName ||
                publicRead.getString("city") != privateRead.draft.city ||
                publicRead.getString("federalState") != privateRead.draft.federalState
        )
            throw ProfileMediaException(ProfileMediaFailure.UNCONFIRMED)
        privateRead
    }

    private suspend fun <T> request(action: suspend () -> T): T =
        try {
            action()
        } catch (error: StorageException) {
            throw ProfileMediaException(
                when (error.errorCode) {
                    StorageException.ERROR_NOT_AUTHENTICATED,
                    StorageException.ERROR_NOT_AUTHORIZED -> ProfileMediaFailure.DENIED
                    StorageException.ERROR_RETRY_LIMIT_EXCEEDED -> ProfileMediaFailure.OFFLINE
                    StorageException.ERROR_CANCELED -> ProfileMediaFailure.CANCELLED
                    else -> ProfileMediaFailure.UNCONFIRMED
                },
                error,
            )
        } catch (error: FirebaseFirestoreException) {
            throw ProfileMediaException(
                when (error.code) {
                    FirebaseFirestoreException.Code.PERMISSION_DENIED,
                    FirebaseFirestoreException.Code.UNAUTHENTICATED -> ProfileMediaFailure.DENIED
                    FirebaseFirestoreException.Code.UNAVAILABLE,
                    FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> ProfileMediaFailure.OFFLINE
                    else -> ProfileMediaFailure.UNCONFIRMED
                },
                error,
            )
        }
}

fun localProfileMediaSource(context: Context): ProfileMediaSource =
    FirebaseProfileMediaSource(
        AppBackend.storage(context),
        AppBackend.firestore(context),
        AppBackend.auth(context),
    )

fun localProfilePhotoPreparation(context: Context): ProfilePhotoPreparation {
    val application = context.applicationContext
    return ProfilePhotoPreparation { uri ->
        PreparedAvatar(
            LocalImagePreparation.prepare(application, Uri.parse(uri), LocalImagePolicy.AVATAR)
        )
    }
}
