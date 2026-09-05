package at.uac.android

import android.graphics.Bitmap
import android.graphics.Color
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.browse.PublicImagePresentation
import at.uac.android.feature.browse.decodePublicImage
import java.io.ByteArrayOutputStream
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Real native JPEG decoder, no network, fixtures, Firebase or external state. */
@RunWith(AndroidJUnit4::class)
class PublicImagePresentationDeviceTest {
    private fun jpeg(width: Int, height: Int): ByteArray {
        val bitmap =
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
                eraseColor(Color.BLUE)
            }
        return try {
            ByteArrayOutputStream()
                .also { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 82, it)) }
                .toByteArray()
        } finally {
            bitmap.recycle()
        }
    }

    @Test
    fun cropNativeBitmapIsAtMostFourHundredAndFitDefaultStayFullResolution() {
        val bytes = jpeg(1600, 800)
        val original = bytes.copyOf()
        for (mode in PublicImagePresentation.entries) {
            val bitmap = requireNotNull(decodePublicImage(bytes, mode))
            try {
                val expected =
                    if (mode == PublicImagePresentation.VIEWPORT_CROP) 400 to 200 else 1600 to 800
                assertEquals(expected.first, bitmap.width)
                assertEquals(expected.second, bitmap.height)
                assertArrayEquals(original, bytes)
            } finally {
                bitmap.recycle()
            }
        }
    }

    @Test
    fun extremeTallWideAndOddRasterNeverExceedNewCropCeiling() {
        for ((width, height) in listOf(1 to 8192, 8192 to 1, 1601 to 799)) {
            val bytes = jpeg(width, height)
            val bitmap =
                requireNotNull(decodePublicImage(bytes, PublicImagePresentation.VIEWPORT_CROP))
            try {
                assertTrue(bitmap.width in 1..400)
                assertTrue(bitmap.height in 1..400)
            } finally {
                bitmap.recycle()
            }
        }
    }
}
