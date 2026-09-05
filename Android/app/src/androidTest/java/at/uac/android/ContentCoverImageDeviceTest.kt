package at.uac.android

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.exifinterface.media.ExifInterface
import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class ContentCoverImageDeviceTest {
    @Test
    fun actualHeroRasterIsCentralSixteenNineOpaqueJpegWithoutDistortion() = runBlocking {
        val source = Bitmap.createBitmap(1600, 1200, Bitmap.Config.ARGB_8888)
        val png =
            try {
                Canvas(source).apply {
                    drawColor(Color.TRANSPARENT)
                    drawRect(0f, 0f, 1600f, 150f, Paint().apply { color = Color.RED })
                    drawRect(0f, 1050f, 1600f, 1200f, Paint().apply { color = Color.BLUE })
                    drawCircle(800f, 600f, 150f, Paint().apply { color = Color.GREEN })
                }
                ByteArrayOutputStream().use {
                    source.compress(Bitmap.CompressFormat.PNG, 100, it)
                    it.toByteArray()
                }
            } finally {
                source.recycle()
            }
        val jpeg = LocalImagePreparation.prepareBytes(png, LocalImagePolicy.CONTENT_COVER_16_9)
        assertTrue(LocalImagePreparation.validJpeg(jpeg, LocalImagePolicy.CONTENT_COVER_16_9))
        val image = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)!!
        try {
            assertEquals(1600, image.width)
            assertEquals(900, image.height)
            assertTrue(distance(Color.WHITE, image.getPixel(20, 20)) < 40)
            assertTrue(distance(Color.WHITE, image.getPixel(20, 880)) < 40)
            assertTrue(distance(Color.GREEN, image.getPixel(800, 450)) < 40)
            // A circle remains a circle: it is not stretched from 4:3 into 16:9.
            assertTrue(distance(Color.GREEN, image.getPixel(930, 450)) < 50)
            assertTrue(distance(Color.GREEN, image.getPixel(800, 580)) < 50)
            assertTrue(distance(Color.WHITE, image.getPixel(970, 450)) < 50)
            assertTrue(distance(Color.WHITE, image.getPixel(800, 620)) < 50)
        } finally {
            image.recycle()
        }
        val exif = ExifInterface(jpeg.inputStream())
        assertNull(exif.getAttribute(ExifInterface.TAG_MAKE))
        assertNull(exif.latLong)
    }

    private fun distance(a: Int, b: Int) =
        kotlin.math.abs(Color.red(a) - Color.red(b)) +
            kotlin.math.abs(Color.green(a) - Color.green(b)) +
            kotlin.math.abs(Color.blue(a) - Color.blue(b))
}
