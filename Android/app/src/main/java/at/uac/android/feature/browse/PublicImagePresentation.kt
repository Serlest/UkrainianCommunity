package at.uac.android.feature.browse

import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit

/** STANDARD retains existing card/detail sizing. Viewports require finite caller-owned bounds. */
enum class PublicImagePresentation {
    STANDARD,
    VIEWPORT_FIT,
    VIEWPORT_CROP,
}

internal object PublicImageSizing {
    const val THUMBNAIL_EDGE = 400

    fun sampleSize(width: Int, height: Int, presentation: PublicImagePresentation): Int {
        var sample = PublicMediaPolicy.sampleSize(width, height)
        if (presentation == PublicImagePresentation.VIEWPORT_CROP) {
            while ((maxOf(width, height) + sample - 1) / sample > THUMBNAIL_EDGE) sample *= 2
        }
        return sample
    }
}

/**
 * Waiting thumbnails are cancellable; closing/disposal does not start queued network/decode work.
 */
internal object PublicImageWork {
    private val thumbnails = Semaphore(4)

    suspend fun <T> load(presentation: PublicImagePresentation, block: suspend () -> T): T =
        if (presentation == PublicImagePresentation.VIEWPORT_CROP) thumbnails.withPermit { block() }
        else block()
}
