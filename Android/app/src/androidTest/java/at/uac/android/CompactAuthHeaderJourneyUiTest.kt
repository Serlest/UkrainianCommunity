package at.uac.android

import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Guest account pages stay inside the mandatory access gate; no registration or password submission.
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
    fun guestAuthPagesStayInsideGateAcrossLanguagesAndRecreation() {
        AccountDeletionFixtures.requireLocalAvd()
        val original = browse.state.value
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
        try {
            for ((language, theme) in listOf("de" to "light", "uk" to "dark")) {
                compose.runOnIdle {
                    browse.preference("mode", "synthetic")
                    browse.preference("language", language)
                    browse.preference("theme", theme)
                }
                compose.onNodeWithTag("startup-account-gate").assertExists()
                compose.onNodeWithTag("guest-welcome").assertDoesNotExist()
                compose.onNodeWithTag("uac-compact-header-brand").assertDoesNotExist()

                compose.openGuestLogin()
                compose.onNodeWithTag("auth-tab-login").performScrollTo().performClick()
                assertPage("login", language)
                compose
                    .onNodeWithTag("auth-tab-register")
                    .performScrollTo()
                    .assertIsDisplayed()
                    .performClick()
                assertPage("register", language)
                compose
                    .onNodeWithTag("auth-tab-reset")
                    .performScrollTo()
                    .assertIsDisplayed()
                    .performClick()
                assertPage("reset", language)

                compose.activityRule.scenario.recreate()
                compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
                assertPage("reset", language, "recreated")
                compose.onNodeWithTag("auth-tab-register").performScrollTo().performClick()
                assertPage("register", language, "switch")
                compose.onNodeWithTag("auth-tab-login").performScrollTo().performClick()
                assertPage("login", language, "switch")
                compose.onNodeWithTag("startup-account-gate").assertExists()
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
        suffix: String = "initial",
    ) {
        compose.onNodeWithTag("startup-account-gate").assertExists()
        for (tab in listOf("home", "events", "organizations", "profile"))
            compose.onNodeWithTag("tab-$tab").assertDoesNotExist()
        compose.onNodeWithTag("auth-tab-$page").performScrollTo().assertIsSelected()
        capture("$page-$language-${browse.state.value.theme}-$suffix")
        compose.onNodeWithTag("auth-email").performScrollTo().assertIsDisplayed().assertIsEnabled()
        if (page == "login")
            compose.onNodeWithTag("auth-password").performScrollTo().assertIsDisplayed()
        val submit =
            when (page) {
                "register" -> "auth-register-submit"
                "reset" -> "auth-reset-submit"
                else -> "auth-login-submit"
            }
        if (page == "register") {
            compose.onNodeWithTag("auth-registration-legal-unavailable").performScrollTo().assertIsDisplayed()
            compose.onNodeWithTag(submit).assertDoesNotExist()
        } else {
            compose.onNodeWithTag(submit).performScrollTo().assertIsDisplayed().assertHeightIsAtLeast(48.dp)
        }
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
