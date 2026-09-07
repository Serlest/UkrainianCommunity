package at.uac.android.feature.organizationaccess

import java.util.Base64

data class OrganizationPhotoAttempt(
    val principalId: String,
    val organizationId: String,
    val photoId: String,
    val operationId: String,
    val expectedImageUrl: String?,
    val jpeg: ByteArray,
    val caption: String?,
)

data class OrganizationPhotoVersion(
    val organizationId: String,
    val photoId: String,
    val imageUrl: String,
)

data class OrganizationPhotoReceipt(
    val organizationId: String,
    val photoId: String,
    val didChange: Boolean,
)

object OrganizationPhotoContract {
  private val id = Regex("[A-Za-z0-9_-]{1,200}")

  fun request(value: OrganizationPhotoAttempt, clientVersion: String): Map<String, Any?> {
    require(value.principalId.length in 1..128 && '/' !in value.principalId)
    require(listOf(value.organizationId, value.photoId, value.operationId).all(id::matches))
    require(value.expectedImageUrl == null || value.expectedImageUrl.length <= 4096)
    require(value.caption == null || value.caption.length <= 500)
    require(
        value.jpeg.size in 4..3_000_000 &&
            value.jpeg[0] == 0xff.toByte() &&
            value.jpeg[1] == 0xd8.toByte() &&
            value.jpeg[value.jpeg.lastIndex - 1] == 0xff.toByte() &&
            value.jpeg.last() == 0xd9.toByte()
    )
    require(clientVersion.length in 1..64)
    return mapOf(
        "principalId" to value.principalId,
        "organizationId" to value.organizationId,
        "photoId" to value.photoId,
        "operationId" to value.operationId,
        "expectedImageURL" to value.expectedImageUrl,
        "imageBase64" to Base64.getEncoder().encodeToString(value.jpeg),
        "caption" to value.caption,
        "clientVersion" to clientVersion,
    )
  }

  fun receipt(raw: Any?, expected: OrganizationPhotoAttempt): OrganizationPhotoReceipt {
    val value = raw.record()
    require(value.keys == setOf("organizationId", "photoId", "didChange"))
    require(
        value.string("organizationId") == expected.organizationId &&
            value.string("photoId") == expected.photoId
    )
    return OrganizationPhotoReceipt(
        expected.organizationId,
        expected.photoId,
        value["didChange"] as? Boolean ?: invalid(),
    )
  }

  fun confirms(attempt: OrganizationPhotoAttempt, actual: OrganizationPhotoVersion): Boolean {
    if (actual.organizationId != attempt.organizationId || actual.photoId != attempt.photoId)
        return false
    val storageId = sha256Hex(attempt.principalId + "\u0000" + attempt.operationId)
    return actual.imageUrl.substringBefore('?').endsWith("/photoVersions/$storageId.jpg") ||
        actual.imageUrl.contains("%2FphotoVersions%2F$storageId.jpg")
  }

  private fun sha256Hex(value: String) =
      java.security.MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString(
          ""
      ) {
        "%02x".format(it)
      }
}
