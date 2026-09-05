package at.uac.android.feature.organization

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import at.uac.android.core.LocalStorage
import at.uac.android.core.backend.AppBackend
import com.google.firebase.storage.FirebaseStorage
import com.google.firebase.storage.StorageMetadata
import kotlinx.coroutines.tasks.await

interface OrganizationLogoStorage {
    suspend fun upload(organizationId: String, jpeg: ByteArray): String
}

object LocalOrganizationStorage {
    private var instance: OrganizationLogoStorage? = null

    @Synchronized
    fun instance(context: Context): OrganizationLogoStorage {
        LocalEnvironment.requireSafe()
        return instance
            ?: LocalOrganizationLogoStorage(AppBackend.storage(context)).also { instance = it }
    }

    fun validateUrl(value: String, id: String): Boolean =
        LocalStorage.urlMatches(value, "organizations/$id/logo.jpg")
}

private class LocalOrganizationLogoStorage(private val storage: FirebaseStorage) :
    OrganizationLogoStorage {
    override suspend fun upload(organizationId: String, jpeg: ByteArray): String {
        if (!OrganizationContract.id(organizationId) || !OrganizationLogo.jpeg(jpeg))
            throw OrganizationException(OrganizationFailure.INVALID)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, bounds)
        if (
            bounds.outWidth !in 1..1600 ||
                bounds.outHeight !in 1..1600 ||
                bounds.outMimeType != "image/jpeg"
        )
            throw OrganizationException(OrganizationFailure.INVALID)
        val reference = storage.reference.child("organizations/$organizationId/logo.jpg")
        val metadata = StorageMetadata.Builder().setContentType("image/jpeg").build()
        // SDK retry is bounded; the Auth mutex remains held until the actual upload task completes.
        reference.putBytes(jpeg, metadata).await()
        val actual = reference.metadata.await()
        if (
            actual.sizeBytes != jpeg.size.toLong() ||
                actual.contentType != "image/jpeg" ||
                !reference.getBytes(OrganizationLogo.MAX_BYTES.toLong()).await().contentEquals(jpeg)
        )
            throw OrganizationException(OrganizationFailure.UNCONFIRMED)
        return reference.downloadUrl.await().toString().also {
            if (!LocalOrganizationStorage.validateUrl(it, organizationId))
                throw OrganizationException(OrganizationFailure.INVALID)
        }
    }
}

object OrganizationLogo {
    const val MAX_BYTES = 3_000_000

    fun jpeg(bytes: ByteArray): Boolean =
        LocalImagePreparation.validJpeg(bytes, LocalImagePolicy.ORG_LOGO)

    /**
     * User-selected content URI only. Decode downsampled, normalize orientation, drop metadata,
     * flatten alpha.
     */
    suspend fun prepare(context: Context, uri: Uri): ByteArray =
        LocalImagePreparation.prepare(context, uri, LocalImagePolicy.ORG_LOGO)
}
