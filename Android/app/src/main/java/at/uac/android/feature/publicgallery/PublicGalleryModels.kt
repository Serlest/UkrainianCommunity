package at.uac.android.feature.publicgallery

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.ReadFailure
import at.uac.android.feature.browse.string
import at.uac.android.feature.browse.time
import java.time.Instant

/** Display-only projection of an already authorized public query; never a management receipt. */
data class PublicGalleryPhoto(val id: String, val imageUrl: String, val caption: String?) {
    override fun toString() = "PublicGalleryPhoto(id=$id)"
}

data class PublicGalleryWindow(
    val photos: List<PublicGalleryPhoto>,
    val cachedAt: Instant?,
    val failure: ReadFailure?,
    val truncated: Boolean,
)

object PublicGalleryProjection {
    const val MAX_PHOTOS = 30

    fun window(
        rows: List<RawDocument>,
        cachedAt: Instant?,
        failure: ReadFailure?,
    ): PublicGalleryWindow {
        val mayUseRows = failure == null || failure == ReadFailure.OFFLINE && cachedAt != null
        if (!mayUseRows) return PublicGalleryWindow(emptyList(), null, failure, false)
        val bounded = rows.take(MAX_PHOTOS)
        // Document IDs are opaque Firestore IDs, not organization management IDs or URL paths.
        if (
            bounded.any {
                it.id.isBlank() ||
                    '/' in it.id ||
                    it.id.any(Char::isISOControl) ||
                    it.fields.string("imageURL").isEmpty() ||
                    it.fields.string("uploadedBy").isEmpty() ||
                    it.fields.time("createdAt") == null
            } || bounded.map { it.id }.distinct().size != bounded.size
        ) {
            return PublicGalleryWindow(emptyList(), null, ReadFailure.INVALID, false)
        }
        return PublicGalleryWindow(
            bounded.map { row ->
                PublicGalleryPhoto(
                    row.id,
                    row.fields.string("imageURL"),
                    row.fields.string("caption").ifEmpty { null },
                )
            },
            cachedAt,
            failure,
            rows.size > MAX_PHOTOS,
        )
    }

    fun selected(
        window: PublicGalleryWindow,
        id: String?,
        displayable: Boolean,
    ): PublicGalleryPhoto? =
        if (displayable && id != null) window.photos.firstOrNull { it.id == id } else null

    fun columns(widthDp: Float): Int = if (widthDp.isFinite() && widthDp >= 330f) 3 else 2
}
