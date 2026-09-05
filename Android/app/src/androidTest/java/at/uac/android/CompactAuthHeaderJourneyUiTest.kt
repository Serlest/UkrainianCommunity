package at.uac.android

import android.graphics.Bitmap
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
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

/**
 * Actual guest navigation; no registration, password submission, network fixture or fake density.
 */
@RunWith(AndroidJUnit4::class)
class CompactAuthHeaderJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val auth
        get() = LocalAuthSession.get(instrumentation.targetContext)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    @Test
    fun exactGuestAuthPagesStayCompactAcrossLanguagesRecreationAndActualBackNavigation() {
        AccountDeletionFixtures.requireLocalAvd()
        val original = browse.state.value
        val scale = compose.activity.resources.configuration.fontScale
        assertTrue("Use the actual normal or200% AVD setting", scale == 1f || scale == 2f)
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
        try {
            for ((language, theme) in listOf("de" to "light", "uk" to "dark")) {
                compose.runOnIdle {
                    browse.preference("mode", "synthetic")
                    browse.preference("language", language)
                    browse.preference("theme", theme)
                    browse.navigate("profile", true)
                }
                compose.onNodeWithTag("guest-welcome").assertExists()
                compose.onNodeWithContentDescription("Ukrainian Community").assertIsDisplayed()
                compose.onNodeWithTag("uac-compact-header-brand").assertDoesNotExist()

                compose.openGuestLogin()
                assertPage("login", language, scale)
                compose
                    .onNodeWithTag("auth-tab-register")
                    .performScrollTo()
                    .assertIsDisplayed()
                    .performClick()
                assertPage("register", language, scale)
                compose
                    .onNodeWithTag("auth-tab-reset")
                    .performScrollTo()
                    .assertIsDisplayed()
                    .performClick()
                assertPage("reset", language, scale)

                compose.activityRule.scenario.recreate()
                compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
                assertPage("reset", language, scale, "recreated")
                for (page in listOf("register", "login")) {
                    compose
                        .onNodeWithTag("back")
                        .assertIsDisplayed()
                        .assertIsEnabled()
                        .performClick()
                    assertPage(page, language, scale, "back")
                }
                compose.onNodeWithTag("back").assertIsDisplayed().performClick()
                compose.waitUntil(15_000) { browse.state.value.route == "profile" }
                compose.onNodeWithTag("guest-welcome").assertExists()
                compose.onNodeWithContentDescription("Ukrainian Community").assertIsDisplayed()
                compose.onNodeWithTag("uac-compact-header-brand").assertDoesNotExist()
                assertEquals(AuthStage.GUEST, auth.state.value.stage)
                assertNull(LocalFirebase.auth(instrumentation.targetContext).currentUser)
            }
        } finally {
            compose.runOnIdle {
                browse.preference("language", original.language)
                browse.preference("theme", original.theme)
                browse.preference("mode", original.mode)
                browse.navigate("profile", true)
            }
        }
    }

    private fun assertPage(
        page: String,
        language: String,
        scale: Float,
        suffix: String = "initial",
    ) {
        compose.waitUntil(15_000) { browse.state.value.route == "profile/$page" }
        val header = compose.onNodeWithTag("uac-compact-header-brand")
        header.assertIsDisplayed().assertTextEquals("UAC")
        compose.onNodeWithContentDescription("Ukrainian Community").assertDoesNotExist()
        val layouts = mutableListOf<TextLayoutResult>()
        header.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertEquals(1, layouts.size)
        assertEquals(scale, layouts.single().layoutInput.density.fontScale, 0.01f)
        assertFalse(layouts.single().didOverflowHeight)
        for (tag in listOf("settings", "back") + PrimaryTab.entries.map { "tab-${it.route}" }) {
            compose
                .onNodeWithTag(tag)
                .assertIsDisplayed()
                .assertHeightIsAtLeast(48.dp)
                .assertWidthIsAtLeast(48.dp)
        }
        compose.onNodeWithTag("tab-profile").assertIsSelected()
        compose.assertNavigationPresentation(scale)
        capture("$page-$language-${browse.state.value.theme}-${(scale * 100).toInt()}-$suffix")
        compose.onNodeWithTag("auth-email").performScrollTo().assertIsDisplayed().assertIsEnabled()
        if (page == "login")
            compose.onNodeWithTag("auth-password").performScrollTo().assertIsDisplayed()
        val submit =
            when (page) {
                "register" -> "auth-register-submit"
                "reset" -> "auth-reset-submit"
                else -> "auth-login-submit"
            }
        compose
            .onNodeWithTag(submit)
            .performScrollTo()
            .assertIsDisplayed()
            .assertHeightIsAtLeast(48.dp)
        assertEquals(AuthStage.GUEST, auth.state.value.stage)
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            File(instrumentation.targetContext.cacheDir, "compact-auth-$name.png")
                .outputStream()
                .use {
                    check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                }
        } finally {
            bitmap.recycle()
        }
    }
}
