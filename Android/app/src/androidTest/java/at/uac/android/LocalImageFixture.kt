package at.uac.android

import android.graphics.Bitmap
import android.graphics.Color
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue

/** A unique emulator-only image, deleted and verified absent even when the UI assertion fails. */
internal fun withLocalImageFixture(imageBytes: ByteArray? = null, block: (String) -> Unit) {
    assertTrue("Requires local build", BuildConfig.USE_LOCAL_BACKEND)
    assertEquals(
        "Explicit emulator opt-in is required",
        "true",
        InstrumentationRegistry.getArguments().getString("expectEmulator"),
    )
    val root = "http://10.0.2.2:9198/v0/b/demo-uac-android.appspot.com/o/"
    val name = "featuredBanners%2Fimage-proof-${UUID.randomUUID()}%2Fhero.jpg"
    val bytes = imageBytes ?: run {
        val bitmap = Bitmap.createBitmap(32, 18, Bitmap.Config.ARGB_8888)
            .apply { eraseColor(Color.BLUE) }
        try {
            ByteArrayOutputStream()
                .also { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
                .toByteArray()
        } finally {
            bitmap.recycle()
        }
    }
    fun request(method: String, url: String, payload: ByteArray? = null): Int {
        val connection = URI(url).toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 3000
            connection.readTimeout = 3000
            connection.setRequestProperty("Authorization", "Bearer owner")
            if (payload != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "image/jpeg")
                connection.outputStream.use { it.write(payload) }
            }
            return connection.responseCode
        } finally {
            connection.disconnect()
        }
    }
    try {
        assertEquals(200, request("POST", "$root?name=$name", bytes))
        block("$root$name?alt=media")
    } finally {
        val deleted = request("DELETE", root + name)
        assertTrue("Exact fixture deletion returned $deleted", deleted in setOf(200, 204, 404))
        assertEquals("Fixture must be absent after cleanup", 404, request("GET", root + name))
    }
}
