package at.uac.android

import at.uac.android.feature.browse.PublicImagePresentation
import at.uac.android.feature.browse.PublicImageSizing
import at.uac.android.feature.browse.PublicImageWork
import at.uac.android.feature.browse.PublicMediaPolicy
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PublicImagePresentationTest {
    private val crop = PublicImagePresentation.VIEWPORT_CROP

    @Test
    fun cropSamplesUseCeilingAtTheExactFourHundredBoundary() {
        assertEquals(1, PublicImageSizing.sampleSize(400, 1, crop))
        assertEquals(2, PublicImageSizing.sampleSize(401, 200, crop))
        assertEquals(4, PublicImageSizing.sampleSize(1600, 800, crop))
        assertEquals(8, PublicImageSizing.sampleSize(1601, 800, crop))
    }

    @Test
    fun extremeDimensionsRemainWithinExistingInputAndThumbnailBounds() {
        for ((width, height) in listOf(1 to 8192, 8192 to 1, 8192 to 8192, 399 to 1, 1 to 1)) {
            val sample = PublicImageSizing.sampleSize(width, height, crop)
            assertTrue((maxOf(width, height) + sample - 1) / sample <= 400)
            assertEquals(0, sample and (sample - 1))
        }
    }

    @Test
    fun defaultAndFitRetainExactlyTheExistingSixteenHundredSampling() {
        for (mode in
            listOf(PublicImagePresentation.STANDARD, PublicImagePresentation.VIEWPORT_FIT)) {
            for ((width, height) in
                listOf(1 to 1, 1600 to 800, 1601 to 799, 8192 to 1, 1 to 8192)) {
                assertEquals(
                    PublicMediaPolicy.sampleSize(width, height),
                    PublicImageSizing.sampleSize(width, height, mode),
                )
            }
        }
    }

    @Test
    fun noPresentationExpandsInvalidDimensionPolicy() {
        for (mode in PublicImagePresentation.entries) for ((width, height) in
            listOf(0 to 1, -1 to 1, 1 to 0, 8193 to 1, 1 to 8193)) {
            try {
                PublicImageSizing.sampleSize(width, height, mode)
                fail("Invalid dimensions were accepted")
            } catch (_: IllegalArgumentException) {}
        }
    }

    @Test
    fun onlyFourThumbnailsRunAndCancelledWaitersNeverStart() = runTest {
        val release = CompletableDeferred<Unit>()
        var active = 0
        var maximum = 0
        var entered = 0
        val jobs =
            List(30) {
                launch {
                    PublicImageWork.load(crop) {
                        entered++
                        active++
                        maximum = maxOf(maximum, active)
                        try {
                            release.await()
                        } finally {
                            active--
                        }
                    }
                }
            }
        runCurrent()
        assertEquals(4, entered)
        assertEquals(4, active)
        jobs.drop(4).forEach { it.cancel() }
        runCurrent()
        release.complete(Unit)
        jobs.forEach { it.join() }
        assertEquals(4, entered)
        assertEquals(4, maximum)
        assertEquals(0, active)
    }

    @Test
    fun fitAndDefaultDoNotWaitForThumbnailQueueAndPermitsReleaseOnFailure() = runTest {
        val release = CompletableDeferred<Unit>()
        val occupied = List(4) { launch { PublicImageWork.load(crop) { release.await() } } }
        runCurrent()
        assertEquals("fit", PublicImageWork.load(PublicImagePresentation.VIEWPORT_FIT) { "fit" })
        assertEquals(
            "default",
            PublicImageWork.load(PublicImagePresentation.STANDARD) { "default" },
        )
        release.complete(Unit)
        occupied.forEach { it.join() }
        try {
            PublicImageWork.load(crop) { error("Synthetic read failure") }
        } catch (_: IllegalStateException) {}
        val allReleased = List(4) { launch { PublicImageWork.load(crop) {} } }
        allReleased.forEach { it.join() }
    }
}
