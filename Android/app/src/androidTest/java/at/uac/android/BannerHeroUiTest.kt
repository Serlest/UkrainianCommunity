package at.uac.android

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import at.uac.android.design.UacPageBackground
import at.uac.android.design.UacTheme
import at.uac.android.feature.browse.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class BannerHeroUiTest {
    @get:Rule val compose = createComposeRule()

    private fun show(
        language: String,
        theme: String,
        scale: Float,
        action: String = "event",
        target: String = "synthetic-event",
    ) {
        val title =
            tr(
                language,
                "Gemeinsam in Tirol: ein offenes Treffen für neue Nachbarn und Familien",
                "Разом у Тіролі: відкрита зустріч для нових сусідів та родин",
            )
        val subtitle =
            tr(
                language,
                "Lokales Testbeispiel mit aktuellen Informationen und persönlichen Begegnungen.",
                "Локальний тестовий приклад з актуальною інформацією та особистими зустрічами.",
            )
        val banner =
            Banner(
                "synthetic-hero",
                mapOf(
                    "title" to title,
                    "subtitle" to subtitle,
                    "actionType" to action,
                    "actionTargetID" to target,
                    "imageURL" to "https://example.invalid/hero.png",
                ),
            )
        var opened: String? = null
        compose.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, scale)) {
                UacTheme(theme) {
                    UacPageBackground(Modifier.fillMaxSize()) {
                        LazyColumn(
                            Modifier.fillMaxSize().safeDrawingPadding().testTag("hero-test-list"),
                            contentPadding = PaddingValues(16.dp),
                        ) {
                            item { BannerHero(banner, language, { opened = it }) }
                        }
                    }
                }
            }
        }
        if (scale > 1.3f)
            listOf("banner-title" to title, "banner-text" to subtitle).forEach { (tag, value) ->
                val layouts = mutableListOf<TextLayoutResult>()
                compose.onNodeWithTag(tag).performSemanticsAction(
                    SemanticsActions.GetTextLayoutResult
                ) {
                    it(layouts)
                }
                assertEquals(value, layouts.single().layoutInput.text.text)
                assertFalse(layouts.single().didOverflowWidth)
                assertFalse(layouts.single().didOverflowHeight)
            }
        val route = bannerRoute(action, target)
        if (route == null) compose.onNodeWithTag("banner-open").assertDoesNotExist()
        else {
            compose.onNodeWithTag("hero-test-list").performScrollToNode(hasTestTag("banner-open"))
            compose
                .onNodeWithTag("banner-open")
                .assertHeightIsAtLeast(48.dp)
                .assertWidthIsAtLeast(48.dp)
                .performClick()
            assertEquals(route, opened)
        }
    }

    @Test fun germanLightHeroKeepsCanonicalAction() = show("de", "light", 1f)

    @Test fun germanDarkLargeTitleAndSubtitleRemainComplete() = show("de", "dark", 2f)

    @Test fun ukrainianLightLargeTitleAndSubtitleRemainComplete() = show("uk", "light", 2f)

    @Test fun ukrainianDarkHeroKeepsCanonicalAction() = show("uk", "dark", 1f)

    @Test
    fun malformedRemoteTargetHasNoInternalAction() =
        show("de", "light", 1f, "organization", "../../profile")

    @Test
    fun changingBannerCannotChangeAnAlreadyOpenedExternalConfirmation() {
        val url = mutableStateOf("https://first.example.invalid/path")
        compose.setContent {
            UacTheme {
                BannerHero(
                    Banner(
                        "synthetic-external",
                        mapOf(
                            "title" to "Synthetic",
                            "subtitle" to "Preview",
                            "actionType" to "externalURL",
                            "externalURL" to url.value,
                        ),
                    ),
                    "de",
                    {},
                )
            }
        }
        compose.onNodeWithText("Ansehen").performClick()
        compose.onNodeWithText("https://first.example.invalid/path").assertIsDisplayed()
        compose.runOnIdle { url.value = "https://second.example.invalid/path" }
        compose.onAllNodes(isDialog()).assertCountEquals(0)
        compose.onNodeWithText("https://second.example.invalid/path").assertDoesNotExist()
    }
}
