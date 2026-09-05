package at.uac.android.feature.gallery

import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.organization.OrganizationSession
import java.net.URI
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.MessageDigest
import java.time.Instant
import java.util.UUID

enum class GalleryFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    MISSING,
    INVALID,
    OFFLINE,
    INDEX,
    LIMIT,
    STALE,
    POLICY,
    IMAGE_UNAVAILABLE,
    UNREADABLE,
    JOURNAL,
    CONFLICT,
    UNCONFIRMED,
    CLEANUP_PENDING,
    UNKNOWN,
}

class GalleryException(val failure: GalleryFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

/**
 * Only a rejected PUT or failed pre-PUT authorization may construct this proof, never a later
 * read-back failure.
 */
class GalleryUploadRejected(cause: Throwable, val failure: GalleryFailure = GalleryFailure.DENIED) :
    Exception("UPLOAD_REJECTED", cause)

data class GalleryTarget(val organizationId: String, val photoId: String) {
    init {
        require(OrganizationContract.id(organizationId) && OrganizationContract.id(photoId))
    }

    val path
        get() = "organizations/$organizationId/photos/$photoId.jpg"

    val document
        get() = "organizations/$organizationId/photos/$photoId"
}

class PreparedGalleryPhoto(bytes: ByteArray, val width: Int, val height: Int) {
    private val encoded = bytes.copyOf()

    init {
        require(
            width in 1..1600 &&
                height in 1..1600 &&
                LocalImagePreparation.validJpeg(encoded, LocalImagePolicy.GALLERY_PHOTO)
        )
    }

    val hash = GalleryContract.hash(encoded)
    val byteCount
        get() = encoded.size

    fun bytes() = encoded.copyOf()

    override fun toString() = "PreparedGalleryPhoto(redacted)"
}

data class GalleryPhoto(
    val target: GalleryTarget,
    val imageUrl: String,
    val caption: String?,
    val uploadedBy: String,
    val createdAt: Instant,
    val updatedAt: Instant?,
) {
    override fun toString() = "GalleryPhoto(redacted)"
}

data class GallerySnapshot(
    val organization: RawDocument,
    val photos: List<GalleryPhoto>,
    val overflow: Boolean,
    val counter: Int?,
) {
    val organizationId
        get() = organization.id

    val content
        get() = Content(ContentKind.ORGANIZATIONS, organization.id, organization.fields)

    override fun toString() = "GallerySnapshot(loaded=${photos.size}, overflow=$overflow)"
}

/**
 * The UUID, caption and prepared bytes form one immutable request; retry never invents another
 * UUID.
 */
data class GalleryUploadIntent(
    val target: GalleryTarget,
    val caption: String?,
    val photo: PreparedGalleryPhoto,
) {
    init {
        require(caption == GalleryContract.caption(caption.orEmpty()))
    }

    override fun toString() = "GalleryUploadIntent(redacted)"

    companion object {
        fun create(organizationId: String, caption: String, photo: PreparedGalleryPhoto) =
            GalleryUploadIntent(
                GalleryTarget(organizationId, UUID.randomUUID().toString()),
                GalleryContract.caption(caption),
                photo,
            )
    }
}

data class GalleryReceipt(
    val target: GalleryTarget,
    val count: Int,
    val changed: Boolean,
    val uploadedBy: String?,
    val createdAt: Instant?,
)

class GalleryBlob(bytes: ByteArray, val token: String) {
    private val encoded = bytes.copyOf()
    val hash = GalleryContract.hash(encoded)

    fun bytes() = encoded.copyOf()

    override fun toString() = "GalleryBlob(redacted)"
}

data class GalleryMutationResult(
    val snapshot: GallerySnapshot,
    val pending: GalleryJournalEntry? = null,
)

enum class GalleryRecovery {
    PUBLISHED,
    REMOVED,
    UNCHANGED,
    CLEANUP_AVAILABLE,
    UNRESOLVED,
}

data class GalleryRecoveryResult(
    val status: GalleryRecovery,
    val snapshot: GallerySnapshot,
    val pending: GalleryJournalEntry?,
)

object GalleryContract {
    const val MAX_PHOTOS = 30
    private const val BUCKET = "demo-uac-android.appspot.com"
    private val tokenPattern = Regex("[A-Za-z0-9_-]{1,256}")

    fun hash(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") {
            "%02x".format(it.toInt() and 255)
        }

    fun hashText(text: String) = hash(text.toByteArray(Charsets.UTF_8))

    fun accountHash(uid: String): String {
        if (uid.isBlank() || uid.length > 128 || uid.any(Char::isISOControl))
            fail(GalleryFailure.INVALID)
        return hashText("uac-gallery-v1:$uid")
    }

    fun caption(value: String): String? =
        value
            .trim()
            .takeIf { it.isNotEmpty() }
            ?.also {
                // Kotlin String.length and the real callable's JavaScript string.length both count
                // UTF-16 units.
                if (
                    it.length > 500 ||
                        it.any { character -> character.isISOControl() && character !in "\n\t" }
                )
                    fail(GalleryFailure.INVALID)
            }

    fun canManage(organization: RawDocument, session: OrganizationSession?): Boolean {
        val s = session ?: return false
        val f = organization.fields
        if (!s.ready || !OrganizationContract.id(organization.id) || f["id"] != organization.id)
            return false
        if (organization.id == "ukrainian-community" || f["isSystemManaged"] == true)
            return s.globalRole == "owner"
        return s.globalRole == "owner" ||
            f["ownerId"] == s.uid ||
            s.uid in (f["adminIds"] as? List<*>).orEmpty() ||
            s.uid in (f["moderatorIds"] as? List<*>).orEmpty()
    }

    fun authorize(organization: RawDocument, session: OrganizationSession) {
        if (!session.ready) fail(GalleryFailure.NOT_READY)
        if (!canManage(organization, session)) fail(GalleryFailure.DENIED)
    }

    fun snapshot(
        organization: RawDocument,
        rows: List<RawDocument>,
        session: OrganizationSession,
    ): GallerySnapshot {
        authorize(organization, session)
        if (rows.size > MAX_PHOTOS + 1 || rows.map { it.id }.distinct().size != rows.size)
            fail(GalleryFailure.INVALID)
        val all = rows.map { photo(organization.id, it) }
        if (all.zipWithNext().any { (a, b) -> a.createdAt < b.createdAt })
            fail(GalleryFailure.INVALID)
        val counter =
            (organization.fields["photoCount"] as? Number)?.let {
                val number = it.toLong()
                if (number !in 0..Int.MAX_VALUE || number.toDouble() != it.toDouble())
                    fail(GalleryFailure.INVALID)
                number.toInt()
            }
        return GallerySnapshot(organization, all.take(MAX_PHOTOS), rows.size > MAX_PHOTOS, counter)
    }

    fun photo(organizationId: String, row: RawDocument): GalleryPhoto {
        if (!OrganizationContract.id(row.id)) fail(GalleryFailure.INVALID)
        val f = row.fields
        val target = GalleryTarget(organizationId, row.id)
        if (f["id"] != row.id || f["organizationId"] != organizationId) fail(GalleryFailure.INVALID)
        val image = f["imageURL"] as? String ?: fail(GalleryFailure.INVALID)
        // This local build does not fetch, overwrite or delete arbitrary buckets, URLs, or paths.
        if (token(image, target) == null) fail(GalleryFailure.IMAGE_UNAVAILABLE)
        val text = f["caption"]?.let { it as? String ?: fail(GalleryFailure.INVALID) }
        if (text != caption(text.orEmpty())) fail(GalleryFailure.INVALID)
        val owner = f["uploadedBy"] as? String ?: fail(GalleryFailure.INVALID)
        accountHash(owner)
        val created = f["createdAt"] as? Instant ?: fail(GalleryFailure.INVALID)
        val updated = f["updatedAt"]?.let { it as? Instant ?: fail(GalleryFailure.INVALID) }
        return GalleryPhoto(target, image, text, owner, created, updated)
    }

    fun token(url: String, target: GalleryTarget): String? = runCatching {
        if (url.length !in 1..2048 || url.any(Char::isISOControl)) return null
        val uri = URI(url)
        val local = uri.scheme == "http" && uri.host == "10.0.2.2" && uri.port == 9198
        val alias =
            uri.scheme == "https" && uri.host == "firebasestorage.googleapis.com" && uri.port == -1
        if (
            (!local && !alias) ||
                uri.userInfo != null ||
                uri.fragment != null ||
                URLDecoder.decode(uri.rawPath, "UTF-8") != "/v0/b/$BUCKET/o/${target.path}"
        )
            return null
        val pairs =
            uri.rawQuery?.split('&')?.map { part ->
                val pieces = part.split('=', limit = 2)
                if (pieces.size != 2) return null
                URLDecoder.decode(pieces[0], "UTF-8") to URLDecoder.decode(pieces[1], "UTF-8")
            } ?: return null
        if (pairs.size != 2 || pairs.map { it.first }.toSet() != setOf("alt", "token")) return null
        val query = pairs.toMap()
        query["token"]?.takeIf { query["alt"] == "media" && tokenPattern.matches(it) }
    }
        .getOrNull()

    fun alias(target: GalleryTarget, token: String): String {
        if (!tokenPattern.matches(token)) fail(GalleryFailure.INVALID)
        return "https://firebasestorage.googleapis.com/v0/b/$BUCKET/o/${URLEncoder.encode(target.path, "UTF-8")}?alt=media&token=$token"
    }

    fun receipt(value: Any?, target: GalleryTarget, create: Boolean): GalleryReceipt {
        val f = value as? Map<*, *> ?: fail(GalleryFailure.UNCONFIRMED)
        if (f["organizationId"] != target.organizationId || f["photoId"] != target.photoId)
            fail(GalleryFailure.UNCONFIRMED)
        val number = f["photoCount"] as? Number ?: fail(GalleryFailure.UNCONFIRMED)
        val count = number.toInt()
        if (number.toDouble() != count.toDouble() || count !in 0..MAX_PHOTOS)
            fail(GalleryFailure.UNCONFIRMED)
        val changed = f["didChange"] as? Boolean ?: fail(GalleryFailure.UNCONFIRMED)
        val owner = f["uploadedBy"] as? String
        val time =
            (f["createdAt"] as? String)?.let { runCatching { Instant.parse(it) }.getOrNull() }
        if (create && (owner.isNullOrBlank() || time == null)) fail(GalleryFailure.UNCONFIRMED)
        return GalleryReceipt(target, count, changed, owner, time)
    }

    fun matches(photo: GalleryPhoto, entry: GalleryJournalEntry): Boolean =
        photo.target == entry.target &&
            hashText(photo.caption.orEmpty()) == entry.captionHash &&
            accountHash(photo.uploadedBy) == entry.uploaderHash &&
            token(photo.imageUrl, photo.target) == entry.token

    fun verifyCount(snapshot: GallerySnapshot, receipt: GalleryReceipt) {
        if (
            snapshot.overflow ||
                snapshot.counter != receipt.count ||
                snapshot.photos.size != receipt.count
        )
            fail(GalleryFailure.UNCONFIRMED)
    }

    fun fail(reason: GalleryFailure): Nothing = throw GalleryException(reason)
}
