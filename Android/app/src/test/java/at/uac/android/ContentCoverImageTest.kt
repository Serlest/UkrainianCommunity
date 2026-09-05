package at.uac.android

import at.uac.android.core.LocalImageException
import at.uac.android.core.LocalImageFailure
import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import org.junit.Assert.*
import org.junit.Test

class ContentCoverImageTest {
    private val cover = LocalImagePolicy.CONTENT_COVER_16_9

    @Test
    fun coverAspectIsExplicitAndExistingPoliciesRemainUnchanged() {
        assertFalse(cover.square)
        assertEquals(16 to 9, cover.cropAspect)
        assertNull(LocalImagePolicy.AVATAR.cropAspect)
        assertNull(LocalImagePolicy.ORG_LOGO.cropAspect)
        assertEquals(
            512 to 512,
            LocalImagePreparation.outputSize(2048, 512, LocalImagePolicy.AVATAR),
        )
        assertEquals(
            1600 to 800,
            LocalImagePreparation.outputSize(3200, 1600, LocalImagePolicy.ORG_LOGO),
        )
    }

    @Test
    fun coverDimensionsUseExactAspectNoUpscaleAndBoundedLongEdge() {
        for ((width, height) in
            listOf(3200 to 2000, 1000 to 2000, 2000 to 500, 317 to 179, 16 to 9)) {
            val (outWidth, outHeight) = LocalImagePreparation.outputSize(width, height, cover)
            assertEquals(outWidth * 9, outHeight * 16)
            assertTrue(outWidth <= width && outHeight <= height && outWidth <= 1600)
        }
        assertEquals(1600 to 900, LocalImagePreparation.outputSize(3200, 2000, cover))
        assertEquals(992 to 558, LocalImagePreparation.outputSize(1000, 2000, cover))
    }

    @Test
    fun smallerThanOneAspectUnitIsExplicitlyRejected() {
        try {
            LocalImagePreparation.outputSize(15, 9, cover)
            fail("Too small for a cover")
        } catch (error: LocalImageException) {
            assertEquals(LocalImageFailure.INVALID, error.reason)
        }
    }

    @Test
    fun strictCoverByteLimitRejectsExactThreeMillionBytes() {
        fun jpeg(size: Int) =
            ByteArray(size).apply {
                this[0] = -1
                this[1] = -40
                this[size - 2] = -1
                this[size - 1] = -39
            }
        assertTrue(LocalImagePreparation.validJpeg(jpeg(2_999_999), cover))
        assertFalse(LocalImagePreparation.validJpeg(jpeg(3_000_000), cover))
    }

    @Test
    fun galleryPolicyPreservesAspectAndUsesItsOwnConservativeSizeLimit() {
        val gallery = LocalImagePolicy.GALLERY_PHOTO
        assertNull(gallery.cropAspect)
        assertFalse(gallery.square)
        assertEquals(3_000_000, gallery.maximumBytes)
        assertEquals(1600 to 800, LocalImagePreparation.outputSize(3200, 1600, gallery))
        assertEquals(400 to 1600, LocalImagePreparation.outputSize(1000, 4000, gallery))
        assertEquals(320 to 180, LocalImagePreparation.outputSize(320, 180, gallery))
    }
}
