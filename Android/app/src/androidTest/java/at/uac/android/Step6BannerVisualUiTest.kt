package at.uac.android

import android.graphics.Bitmap
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.UacTheme
import at.uac.android.feature.browse.Banner
import at.uac.android.feature.browse.BannerHero
import at.uac.android.feature.featuredmanagement.FeaturedDraft
import at.uac.android.feature.featuredmanagement.FeaturedImagePreview
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** One published UAC photo exercises loaded media, fallback geometry and a bounded large-text pass. */
class Step6BannerVisualUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun realPhotoKeepsVisibleMediaAndAdminPreviewAtBothTextSizes() {
        val bytes = InstrumentationRegistry.getInstrumentation().context.assets
            .open("visual-tirol-banner.jpg").use { it.readBytes() }
        withLocalImageFixture(bytes) { url ->
            val large = mutableStateOf(false)
            val language = mutableStateOf("de")
            val theme = mutableStateOf("light")
            val banner = Banner("step6-banner", mapOf(
                "imageURL" to url,
                "title" to "Community-Treffen in Tirol",
                "subtitle" to "Ein regionales Treffen für Familien und Freiwillige.",
                "localizations" to mapOf(
                    "de" to mapOf("title" to "Community-Treffen in Tirol",
                        "subtitle" to "Ein regionales Treffen für Familien und Freiwillige."),
                    "uk" to mapOf("title" to "Зустріч громади в Тіролі",
                        "subtitle" to "Регіональна зустріч для родин і волонтерів."),
                ),
                "actionType" to "news",
                "actionTargetID" to "synthetic-news-01",
            ))
            compose.setContent {
                val base = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(base.density,
                    if (large.value) 1.5f else 1f)) {
                    UacTheme(theme.value) {
                        Surface(Modifier.fillMaxSize()) {
                            Column(Modifier.padding(16.dp)) {
                                BannerHero(banner, language.value, {})
                                FeaturedImagePreview(FeaturedDraft(id = "step6-photo", imageUrl = url,
                                    title = "Community-Treffen in Tirol"), language.value)
                            }
                        }
                    }
                }
            }
            compose.waitUntil(10_000) {
                compose.onAllNodesWithTag("loaded-media").fetchSemanticsNodes().size == 2
            }
            compose.onNodeWithTag("banner-media").assertIsDisplayed()
            compose.onNodeWithTag("banner-caption-below").assertDoesNotExist()
            capture("photo-normal")
            compose.runOnIdle { large.value = true }
            compose.onNodeWithTag("banner-caption-below").assertIsDisplayed()
            compose.onAllNodesWithTag("loaded-media").assertCountEquals(2)
            assertTrue(compose.onNodeWithTag("banner-caption-below")
                .getUnclippedBoundsInRoot().top >=
                compose.onNodeWithTag("banner-media").getUnclippedBoundsInRoot().bottom)
            capture("photo-large")
            compose.runOnIdle {
                large.value = false
                language.value = "uk"
                theme.value = "dark"
            }
            compose.onNodeWithText("Зустріч громади в Тіролі").assertIsDisplayed()
            compose.onAllNodesWithTag("loaded-media").assertCountEquals(2)
            capture("photo-uk-dark")
        }
    }

    @Test fun invalidAdminImageUsesCompactStatus() {
        compose.setContent {
            UacTheme("dark") { FeaturedImagePreview(FeaturedDraft(
                id = "step6-broken", imageUrl = "https://example.invalid/missing.jpg"), "uk") }
        }
        compose.waitUntil(5_000) {
            compose.onAllNodesWithText("Зображення недоступне").fetchSemanticsNodes().isNotEmpty()
        }
        val frame = compose.onNodeWithTag("featured-preview-step6-broken")
            .getUnclippedBoundsInRoot()
        assertTrue(frame.bottom - frame.top <= 80.dp)
        capture("admin-fallback")
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        try {
            File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
                "step6-$name.png").outputStream().use {
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
            }
        } finally { bitmap.recycle() }
    }
}
