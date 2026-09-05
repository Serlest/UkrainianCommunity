package at.uac.android

import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.auth.bundledReferenceLegal
import at.uac.android.feature.auth.formatLegalText
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.PrimaryTab
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Real MainActivity window captures; all content is synthetic and no external link is opened. */
@RunWith(AndroidJUnit4::class)
class MainVisualParityJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val auth
        get() = LocalAuthSession.get(instrumentation.targetContext)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    @Test
    fun actualBundledLegalReferencesRemainCompleteAcrossLanguagesAndSystemFont() {
        AccountDeletionFixtures.requireLocalAvd()
        val scale =
            InstrumentationRegistry.getArguments().getString("visualFontScale")?.toFloatOrNull()
                ?: error("Explicit actual AVD font scale required")
        assertTrue(scale == 1f || scale == 2f)
        assertEquals(scale, compose.activity.resources.configuration.fontScale, 0.01f)
        val original = browse.state.value
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
        // Guest settings expose terms/privacy. Organization rules belong to the organization
        // workflow.
        val documents =
            bundledReferenceLegal(compose.activity).filter { it.type in setOf("terms", "privacy") }
        assertEquals(setOf("terms", "privacy"), documents.map { it.type }.toSet())
        try {
            for ((language, theme) in listOf("de" to "light", "uk" to "dark")) {
                configure(language, theme, "settings")
                for (document in documents) {
                    val blocks = formatLegalText(document.text(language))
                    assertTrue(blocks.isNotEmpty())
                    val tag = "settings-legal-${document.type}"
                    compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag(tag))
                    compose.onNodeWithTag(tag).performClick()
                    compose.waitUntil(15_000) { compose.onNodeWithTag("legal-close").isDisplayed() }
                    // The ordinary Column must retain every paragraph, not only a preview of the
                    // legal text.
                    blocks.forEachIndexed { index, block ->
                        compose
                            .onNodeWithTag("legal-block-$index")
                            .assertTextEquals(block.runs.joinToString("") { it.text })
                    }
                    compose.onNodeWithTag("legal-block-0").performScrollTo().assertIsDisplayed()
                    capture("legal-${document.type}", language, theme, scale)
                    compose
                        .onNodeWithTag("legal-block-${blocks.lastIndex}")
                        .performScrollTo()
                        .assertIsDisplayed()
                    compose
                        .onNodeWithTag("legal-close")
                        .assertHeightIsAtLeast(48.dp)
                        .assertIsDisplayed()
                        .performClick()
                }
            }
            assertEquals(AuthStage.GUEST, auth.state.value.stage)
        } finally {
            compose.runOnIdle {
                browse.preference("language", original.language)
                browse.preference("theme", original.theme)
                browse.navigate("home", true)
            }
        }
    }

    @Test
    fun actualMainScreensKeepAccessibleChromeAcrossLanguageThemeAndSystemFont() {
        AccountDeletionFixtures.requireLocalAvd()
        val expectedScale =
            InstrumentationRegistry.getArguments().getString("visualFontScale")?.toFloatOrNull()
                ?: error("The runner must explicitly declare the actual AVD font scale")
        assertTrue(expectedScale == 1f || expectedScale == 2f)
        assertEquals(expectedScale, compose.activity.resources.configuration.fontScale, 0.01f)
        val original = browse.state.value
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
        try {
            compose.runOnIdle {
                browse.preference("mode", "synthetic")
                browse.preference("region", "")
                browse.filters(search = "", category = "", audience = "", past = false)
            }
            for ((language, theme) in
                listOf("de" to "light", "de" to "dark", "uk" to "light", "uk" to "dark")) {
                configure(language, theme, "home")
                compose.onNodeWithTag("browse-list").performScrollToIndex(0)
                compose.onNodeWithTag("banner-hero").assertIsDisplayed()
                chrome()
                capture("home", language, theme, expectedScale)
                compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("banner-auto"))
                compose
                    .onNodeWithTag("banner-auto")
                    .assertHeightIsAtLeast(48.dp)
                    .assertWidthIsAtLeast(48.dp)
                    .assertIsOff()
                    .performClick()
                    .assertIsOn()
                    .performClick()
                    .assertIsOff()
                compose
                    .onNodeWithTag("browse-list")
                    .performScrollToNode(hasTestTag("home-controls"))
                compose.onNodeWithTag("region").assertIsDisplayed().assertHeightIsAtLeast(48.dp)
                compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("banner-open"))
                compose
                    .onNodeWithTag("banner-open")
                    .assertIsDisplayed()
                    .assertWidthIsAtLeast(48.dp)
                    .assertHeightIsAtLeast(48.dp)
            }
            for ((name, route) in
                listOf(
                    "news" to "news",
                    "events" to "events",
                    "organizations" to "organizations",
                    "news-detail" to "news/synthetic-news-01",
                    "event-detail" to "events/synthetic-event-01",
                    "organization-detail" to "organizations/synthetic-org-01",
                    "profile-guest" to "profile",
                )) {
                configure("de", "light", route)
                if (route != "profile") compose.onNodeWithTag("browse-list").performScrollToIndex(0)
                chrome()
                capture(name, "de", "light", expectedScale)
                if (route == "profile") {
                    compose.openGuestLogin()
                    chrome()
                    capture("login", "de", "light", expectedScale)
                    compose
                        .onNodeWithTag("auth-login-submit")
                        .performScrollTo()
                        .assertIsDisplayed()
                        .assertIsEnabled()
                        .assertHeightIsAtLeast(48.dp)
                }
            }
        } finally {
            compose.runOnIdle {
                browse.preference("language", original.language)
                browse.preference("theme", original.theme)
                browse.preference("mode", original.mode)
                browse.preference("region", original.region)
                browse.navigate("home", true)
            }
        }
    }

    private fun configure(language: String, theme: String, route: String) {
        compose.runOnIdle {
            browse.preference("language", language)
            browse.preference("theme", theme)
            browse.navigate(route, true)
        }
        compose.waitUntil(20_000) {
            browse.state.value.let {
                it.route == route &&
                    it.language == language &&
                    it.theme == theme &&
                    !it.data.loading
            }
        }
        assertNull(browse.state.value.data.error)
        compose.waitForIdle()
    }

    private fun chrome() {
        PrimaryTab.entries.forEach { tab ->
            compose
                .onNodeWithTag("tab-${tab.route}")
                .assertIsDisplayed()
                .assertWidthIsAtLeast(48.dp)
                .assertHeightIsAtLeast(48.dp)
        }
        compose.onNodeWithTag("tab-${browse.state.value.selectedTab.route}").assertIsSelected()
        compose
            .onNodeWithTag("settings")
            .assertIsDisplayed()
            .assertWidthIsAtLeast(48.dp)
            .assertHeightIsAtLeast(48.dp)
    }

    private fun capture(screen: String, language: String, theme: String, scale: Float) {
        compose.waitForIdle()
        val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            val name = "visual-main-$screen-$language-$theme-${(scale * 100).toInt()}.png"
            File(instrumentation.targetContext.cacheDir, name).outputStream().use {
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
            }
        } finally {
            bitmap.recycle()
        }
    }
}
