package at.uac.android

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.AnnotatedString
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.PrimaryTab
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GuestProfileJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val auth
        get() = LocalAuthSession.get(compose.activity)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    @Test
    fun guestCanBrowseUseSeparateAuthScreensAndReadLegalWithoutCreatingASession() {
        AccountDeletionFixtures.requireLocalAvd()
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
        compose.runOnIdle {
            browse.preference("mode", "synthetic")
            browse.preference("language", "de")
            browse.navigate("profile", true)
        }
        compose.onNodeWithTag("guest-welcome").assertExists()
        compose.onNodeWithTag("auth-email").assertDoesNotExist()

        for ((tag, tab) in
            listOf(
                "guest-browse-news" to PrimaryTab.HOME,
                "guest-browse-events" to PrimaryTab.EVENTS,
                "guest-browse-organizations" to PrimaryTab.ORGANIZATIONS,
            )) {
            compose.onNodeWithTag(tag).performScrollTo().performClick()
            compose.waitUntil(20_000) {
                browse.state.value.let {
                    it.selectedTab == tab && it.route == tab.route && !it.data.loading
                }
            }
            compose.onNodeWithTag("tab-${tab.route}").assertIsSelected()
            compose.onNodeWithTag("tab-profile").performClick()
            compose.onNodeWithTag("guest-welcome").assertExists()
        }

        compose.openGuestLogin()
        assertEquals("profile/login", browse.state.value.route)
        compose
            .onNodeWithTag("auth-email")
            .performScrollTo()
            .performTextReplacement("never-submit@example.invalid")
        compose
            .onNodeWithTag("auth-password")
            .performScrollTo()
            .performTextReplacement("NeverPersistThisPassword")
        compose.onNodeWithTag("back").performClick()
        compose.onNodeWithTag("guest-welcome").assertExists()
        compose.openGuestLogin()
        for (tag in listOf("auth-email", "auth-password")) compose
            .onNodeWithTag(tag)
            .performScrollTo()
            .assert(
                SemanticsMatcher.expectValue(SemanticsProperties.EditableText, AnnotatedString(""))
            )
        compose.onNodeWithTag("back").performClick()

        compose.onNodeWithTag("guest-create-account").performScrollTo().performClick()
        assertEquals("profile/register", browse.state.value.route)
        compose.onNodeWithTag("auth-register-submit").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("back").performClick()
        compose.onNodeWithTag("guest-settings").performScrollTo().performClick()
        assertEquals("settings", browse.state.value.route)
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("settings-legal-terms"))
        compose.onNodeWithTag("settings-legal-terms").performScrollTo().performClick()
        compose.assertLegalReferenceVisible("Unveränderte iOS-Referenz")
        compose
            .onNodeWithTag("legal-close")
            .assertContentDescriptionEquals("Schließen")
            .assertIsDisplayed()
            .performClick()
        compose.onNodeWithTag("back").performClick()
        compose.onNodeWithTag("guest-welcome").assertExists()
        assertEquals(AuthStage.GUEST, auth.state.value.stage)
        assertNull(LocalFirebase.auth(compose.activity).currentUser)
    }
}
