package at.uac.android

import android.graphics.Bitmap
import android.graphics.Color
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.browse.PublicImage
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URI
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MediaUiTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun localImageReadAndMissingImageFallback() {
        val online = InstrumentationRegistry.getArguments().getString("expectEmulator") == "true"
        val root = "http://10.0.2.2:9198/v0/b/demo-uac-android.appspot.com/o/"
        val objectName = "featuredBanners%2Fsynthetic-media%2Fhero.jpg"
        if (online) {
            // Test-only setup: an invented solid-colour JPEG in the guarded local emulator.
            val bitmap =
                Bitmap.createBitmap(32, 32, Bitmap.Config.ARGB_8888).apply {
                    eraseColor(Color.BLUE)
                }
            val bytes =
                ByteArrayOutputStream()
                    .also { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
                    .toByteArray()
            bitmap.recycle()
            val upload =
                URI(root + "?name=" + objectName).toURL().openConnection() as HttpURLConnection
            try {
                upload.requestMethod = "POST"
                upload.doOutput = true
                upload.connectTimeout = 3000
                upload.readTimeout = 3000
                upload.setRequestProperty(
                    "Authorization",
                    "Bearer owner",
                ) // emulator-only administrative seed, never app code
                upload.setRequestProperty("Content-Type", "image/jpeg")
                upload.outputStream.use { it.write(bytes) }
                assertEquals(200, upload.responseCode)
            } finally {
                upload.disconnect()
            }
        }
        val url = mutableStateOf(root + objectName + "?alt=media")
        compose.setContent {
            MaterialTheme { PublicImage(url.value, "Synthetic blue square", "de") }
        }
        if (online) {
            compose.waitUntil(10_000) {
                compose.onAllNodesWithTag("loaded-media").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithContentDescription("Synthetic blue square").assertIsDisplayed()
            compose.runOnIdle {
                url.value = root + "featuredBanners%2Fsynthetic-missing%2Fhero.jpg?alt=media"
            }
        }
        compose.waitUntil(10_000) {
            compose
                .onAllNodesWithText("Bild nicht verfügbar", substring = true)
                .fetchSemanticsNodes()
                .isNotEmpty()
        }
        compose.onNodeWithText("Bild nicht verfügbar", substring = true).assertIsDisplayed()
    }
}
