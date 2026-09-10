package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Rule
import org.junit.Test

class Build85SystemThemeAccessUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    @Test
    fun systemThemeFollowsPhoneAndExplicitThemesOverrideItAcrossRecreation() {
        AccountDeletionFixtures.requireLocalAvd()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val original = browse.state.value
        fun night(value: String) {
            instrumentation.uiAutomation.executeShellCommand("cmd uimode night $value").use {
                java.io.FileInputStream(it.fileDescriptor).use { stream -> stream.readBytes() }
            }
        }
        fun expect(theme: String) {
            compose.waitUntil(15_000) {
                compose.onAllNodesWithTag("uac-theme-$theme").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("uac-theme-$theme").assertIsDisplayed()
        }
        try {
            compose.runOnIdle {
                browse.preference("theme", "system")
                browse.navigate("profile", true)
            }
            night("yes")
            expect("dark")
            night("no")
            expect("light")
            compose.runOnIdle { browse.preference("theme", "dark") }
            expect("dark")
            compose.activityRule.scenario.recreate()
            expect("dark")
            night("yes")
            compose.runOnIdle { browse.preference("theme", "light") }
            expect("light")
            compose.activityRule.scenario.recreate()
            expect("light")
            compose.runOnIdle { browse.preference("theme", "system") }
            expect("dark")
        } finally {
            night("no")
            compose.runOnIdle {
                browse.preference("theme", original.theme)
                browse.navigate("profile", true)
            }
        }
    }

    @Test
    fun guestCannotRenderManagementPagesEvenThroughDirectRoutes() {
        AccountDeletionFixtures.requireLocalAvd()
        val auth = LocalAuthSession.get(compose.activity)
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
        for (route in
            listOf(
                "administration",
                "analytics",
                "donation-settings",
                "system-logs",
                "users",
                "moderation",
                "organization-review",
                "featured-banners",
                "content-planning",
                "announcements/manage",
                "support",
            )) {
            compose.runOnIdle { browse.navigate("profile/$route", true) }
            compose.onNodeWithTag("management-access-denied").assertIsDisplayed()
            listOf(
                    "owner-analytics",
                    "donation-settings",
                    "system-logs",
                    "managed-users-list",
                    "moderation-list",
                    "featured-management",
                )
                .forEach {
                    compose.onNodeWithTag(it).assertDoesNotExist()
                }
        }
        compose.runOnIdle { browse.navigate("profile", true) }
        compose.onNodeWithTag("account-open-administration").assertDoesNotExist()
        compose.onNodeWithTag("account-open-owner-analytics").assertDoesNotExist()
    }
}
