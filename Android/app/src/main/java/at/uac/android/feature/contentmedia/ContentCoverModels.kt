package at.uac.android.feature.contentmedia

import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import at.uac.android.core.LocalStorage
import at.uac.android.feature.authoring.AuthoringContract
import at.uac.android.feature.authoring.AuthoringItem
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.OrganizationRecord
import java.net.URI
import java.net.URLDecoder
import java.security.MessageDigest

enum class ContentCoverFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    INVALID,
    INVALID_IMAGE,
    TOO_LARGE,
    UNSUPPORTED,
    UNREADABLE,
    MISSING,
    READ_ONLY,
    STALE,
    OFFLINE,
    UNCONFIRMED,
    IMAGE_UNAVAILABLE,
    UNKNOWN,
}

class ContentCoverException(
    val reason: ContentCoverFailure,
    cause: Throwable? = null,
    val diagnostic: ContentCoverDiagnostic? = null,
) : Exception(reason.name, cause)

data class ContentCoverTarget(
    val organizationId: String,
    val kind: ContentKind,
    val contentId: String,
) {
    init {
        require(
            AuthoringContract.id(organizationId) &&
                AuthoringContract.id(contentId) &&
                kind in AuthoringContract.kinds
        )
    }

    val path
        get() = "${kind.collection}/$contentId/cover.jpg"

    val wireKind
        get() = if (kind == ContentKind.NEWS) "news" else "event"
}

data class ContentCoverSnapshot(
    val target: ContentCoverTarget,
    val organization: OrganizationRecord,
    val item: AuthoringItem,
) {
    val imageUrl
        get() = (item.fields["imageURL"] as? String)?.takeIf(String::isNotBlank)

    val editable
        get() = item.editable

    val removable
        get() = editable && target.kind == ContentKind.NEWS && imageUrl != null
}

/**
 * Bytes have passed bounded raster preparation. Expose copies so an in-flight intent cannot be
 * modified.
 */
class PreparedContentCover(bytes: ByteArray, val width: Int, val height: Int) {
    private val data = bytes.copyOf()

    init {
        require(width in 16..1600 && height in 9..900 && width * 9 == height * 16)
        require(LocalImagePreparation.validJpeg(data, LocalImagePolicy.CONTENT_COVER_16_9))
    }

    val jpeg
        get() = data.copyOf()

    val byteCount
        get() = data.size

    val digest: String = contentCoverDigest(data)

    fun matches(bytes: ByteArray) = data.contentEquals(bytes)
}

class ContentCoverAsset(bytes: ByteArray, val token: String) {
    private val data = bytes.copyOf()
    val bytes
        get() = data.copyOf()
}

data class ContentCoverResponse(
    val target: ContentCoverTarget,
    val imageUrl: String,
    val byteCount: Int,
)

sealed interface ContentCoverIntent {
    val snapshot: ContentCoverSnapshot

    data class Upload(
        override val snapshot: ContentCoverSnapshot,
        val photo: PreparedContentCover,
    ) : ContentCoverIntent

    data class Remove(override val snapshot: ContentCoverSnapshot) : ContentCoverIntent
}

data class ContentCoverConfirmation(
    val snapshot: ContentCoverSnapshot,
    val asset: ContentCoverAsset?,
)

data class ContentCoverRecovery(
    val confirmed: ContentCoverConfirmation?,
    val current: ContentCoverSnapshot,
)

internal fun contentCoverDigest(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

object ContentCoverContract {
    /**
     * URLs are evidence only: image reads use the fixed named SDK reference, never this host as a
     * request destination.
     */
    fun token(value: String, target: ContentCoverTarget): String? = runCatching {
        val uri = URI(value)
        val host =
            uri.scheme == "https" &&
                uri.host == "firebasestorage.googleapis.com" &&
                uri.port == -1 || uri.scheme == "http" && uri.host == "10.0.2.2" && uri.port == 9198
        if (
            !host ||
                uri.userInfo != null ||
                uri.fragment != null ||
                URLDecoder.decode(uri.rawPath, "UTF-8") !=
                    "/v0/b/${LocalStorage.BUCKET}/o/${target.path}"
        )
            return null
        val fields =
            uri.rawQuery?.split('&')?.map { pair ->
                pair.split('=', limit = 2).let {
                    if (it.size != 2) return null
                    URLDecoder.decode(it[0], "UTF-8") to URLDecoder.decode(it[1], "UTF-8")
                }
            } ?: return null
        if (
            fields.size != 2 ||
                fields.map { it.first }.toSet() != setOf("alt", "token") ||
                fields.toMap()["alt"] != "media"
        )
            return null
        fields.toMap()["token"]?.takeIf { it.matches(Regex("[A-Za-z0-9_-]{16,128}")) }
    }
        .getOrNull()

    fun validate(snapshot: ContentCoverSnapshot, target: ContentCoverTarget) {
        if (
            snapshot.target != target ||
                snapshot.organization.id != target.organizationId ||
                snapshot.item.organizationId != target.organizationId ||
                snapshot.item.kind != target.kind ||
                snapshot.item.id != target.contentId
        )
            fail(ContentCoverFailure.INVALID)
    }

    fun unchanged(expected: ContentCoverSnapshot, actual: ContentCoverSnapshot) {
        validate(actual, expected.target)
        if (
            expected.organization.fields != actual.organization.fields ||
                expected.item.fields != actual.item.fields
        )
            fail(ContentCoverFailure.STALE)
    }

    fun preserved(before: ContentCoverSnapshot, after: ContentCoverSnapshot): Boolean =
        before.target == after.target &&
            before.item.fields.filterKeys { it !in setOf("imageURL", "updatedAt") } ==
                after.item.fields.filterKeys { it !in setOf("imageURL", "updatedAt") }

    fun response(
        value: Any?,
        target: ContentCoverTarget,
        photo: PreparedContentCover,
    ): ContentCoverResponse {
        val fields = value as? Map<*, *> ?: fail(ContentCoverFailure.UNCONFIRMED)
        if (
            fields.keys != setOf("kind", "contentId", "imageURL", "byteCount") ||
                fields["kind"] != target.wireKind ||
                fields["contentId"] != target.contentId
        )
            fail(ContentCoverFailure.UNCONFIRMED)
        val count =
            (fields["byteCount"] as? Number)?.toDouble() ?: fail(ContentCoverFailure.UNCONFIRMED)
        val url = fields["imageURL"] as? String ?: fail(ContentCoverFailure.UNCONFIRMED)
        if (!count.isFinite() || count != photo.byteCount.toDouble() || token(url, target) == null)
            fail(ContentCoverFailure.UNCONFIRMED)
        return ContentCoverResponse(target, url, photo.byteCount)
    }

    fun fail(reason: ContentCoverFailure): Nothing = throw ContentCoverException(reason)
}
