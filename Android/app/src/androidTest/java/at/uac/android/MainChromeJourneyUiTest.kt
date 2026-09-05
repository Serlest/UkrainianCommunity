package at.uac.android

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.view.KeyEvent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.PrimaryTab
import at.uac.android.feature.personal.PersonalProfileEditorState
import at.uac.android.feature.personal.PersonalProfileEditorViewModel
import at.uac.android.feature.personal.PersonalViewModel
import at.uac.android.feature.personal.personalScope
import com.google.firebase.firestore.Source
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Actual MainActivity/Scaffold and system IME; the runner supplies the AVD's real 200% font scale.
 */
@RunWith(AndroidJUnit4::class)
class MainChromeJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AccountDeletionFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val editor
        get() = ViewModelProvider(compose.activity)[PersonalProfileEditorViewModel::class.java]

    private val personal
        get() = ViewModelProvider(compose.activity)[PersonalViewModel::class.java]

    private val displayName = "Chrome draft remains local"
    private val biography = "Synthetic keyboard and tab draft"

    private fun field(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun loaded() {
        compose.waitUntil(30_000) {
            auth.state.value.readyForActions &&
                personal.state.value.profile != null &&
                !personal.state.value.profileLoading &&
                editor.state.value.confirmedSession == auth.state.value.personalScope()
        }
    }

    private fun imeVisible(): Boolean {
        var visible = false
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            visible =
                ViewCompat.getRootWindowInsets(compose.activity.window.decorView)
                    ?.isVisible(WindowInsetsCompat.Type.ime()) == true
        }
        return visible
    }

    private fun assertDraft() {
        field("profile-display-name").assertTextContains(displayName)
        field("profile-bio").assertTextContains(biography)
    }

    private fun assertTabs() {
        compose.assertNavigationPresentation(compose.activity.resources.configuration.fontScale)
        PrimaryTab.entries.forEach { tab ->
            compose
                .onNodeWithTag("tab-${tab.route}")
                .assertIsDisplayed()
                .assertWidthIsAtLeast(48.dp)
                .assertHeightIsAtLeast(48.dp)
        }
    }

    @Test
    fun landscapeTwoHundredPercentKeyboardKeepsSaveReachableAndTabsRestoreTheDirtyEditor() {
        AccountDeletionFixtures.requireLocalAvd()
        assumeTrue(
            "A skipped offline run is not a keyboard/profile journey proof",
            AccountDeletionFixtures.online(),
        )
        assertEquals(
            "The runner must set the actual AVD font scale; no simulated Compose density",
            2f,
            compose.activity.resources.configuration.fontScale,
            0.01f,
        )
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.navigate("profile", true)
        }
        val user = runBlocking {
            AuthEmulatorFixtures.seedLegalReference()
            AccountDeletionFixtures.create("deletion-chrome")
        }
        val previousOrientation = compose.activity.requestedOrientation
        var primaryFailure: Throwable? = null
        try {
            LocalFirebase.auth(context).signOut()
            compose.openGuestLogin()
            field("auth-email").performTextReplacement(user.email)
            field("auth-password").performTextReplacement(AccountDeletionFixtures.PASSWORD)
            field("auth-login-submit").assertIsEnabled().performClick()
            compose.waitUntil(30_000) { auth.state.value.readyForActions }
            field("account-open-edit").performClick()
            loaded()
            field("profile-display-name").performTextReplacement(displayName)
            field("profile-bio").performTextReplacement(biography)
            val originalEditor = editor
            compose.runOnIdle {
                compose.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            }
            compose.waitUntil(25_000) {
                compose.activity.resources.configuration.orientation ==
                    Configuration.ORIENTATION_LANDSCAPE
            }
            loaded()
            assertSame(originalEditor, editor)
            assertDraft()

            // A real input tap must show the native IME before checking the scaffold's visible
            // body.
            field("profile-bio").assertIsEnabled().performClick()
            compose.waitUntil(10_000) { imeVisible() }
            PrimaryTab.entries.forEach {
                compose.onNodeWithTag("tab-${it.route}").assertDoesNotExist()
            }
            field("profile-save").assertIsDisplayed().assertIsEnabled().assertHeightIsAtLeast(48.dp)
            assertTrue("Save must remain reachable while the real IME is still open", imeVisible())
            assertEquals(displayName, editor.state.value.draft.displayName)
            assertEquals(biography, editor.state.value.draft.bio)

            // Native Back dismisses only the observed IME, not the current profile destination.
            InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
            // Native visibility can turn false before Compose's animated IME inset reaches zero.
            // Await the actual restored shell in the same deadline; retain all size/display
            // assertions below.
            compose.waitUntil(10_000) {
                !imeVisible() &&
                    PrimaryTab.entries.all {
                        compose.onNodeWithTag("tab-${it.route}").isDisplayed()
                    }
            }
            assertEquals("profile/edit", browse.state.value.route)
            assertTabs()
            for (tab in
                listOf(
                    PrimaryTab.HOME,
                    PrimaryTab.EVENTS,
                    PrimaryTab.ORGANIZATIONS,
                    PrimaryTab.PROFILE,
                )) {
                compose.onNodeWithTag("tab-${tab.route}").performClick()
                compose.waitUntil(10_000) { browse.state.value.selectedTab == tab }
                compose.onNodeWithTag("tab-${tab.route}").assertIsSelected()
                assertTabs()
            }
            assertEquals("profile/edit", browse.state.value.route)
            loaded()
            assertSame(originalEditor, editor)
            assertDraft()
            runBlocking {
                val server =
                    LocalFirebase.firestore(context)
                        .document("users/${user.uid}")
                        .get(Source.SERVER)
                        .await()
                assertEquals(
                    "Reaching Save must not implicitly submit a draft",
                    "Synthetic deletion account",
                    server.getString("displayName"),
                )
                assertNotEquals(biography, server.getString("bio"))
            }
            compose.onNodeWithTag("back").performClick()
            field("auth-signout").performClick()
            compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
            assertEquals(PersonalProfileEditorState(), editor.state.value)
            assertNull(personal.state.value.profile)
        } catch (error: Throwable) {
            primaryFailure = error
            throw error
        } finally {
            val cleanupFailures = mutableListOf<Throwable>()
            fun clean(action: () -> Unit) {
                runCatching(action).onFailure { cleanupFailures += it }
            }
            clean {
                compose.runOnIdle {
                    WindowCompat.getInsetsController(
                            compose.activity.window,
                            compose.activity.window.decorView,
                        )
                        .hide(WindowInsetsCompat.Type.ime())
                    compose.activity.requestedOrientation = previousOrientation
                }
            }
            clean {
                runBlocking {
                    if (LocalFirebase.auth(context).currentUser?.uid != user.uid)
                        LocalFirebase.auth(context)
                            .signInWithEmailAndPassword(
                                user.email,
                                AccountDeletionFixtures.PASSWORD,
                            )
                            .await()
                    AccountDeletionFixtures.clean(user)
                }
            }
            clean { runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() } }
            if (cleanupFailures.isNotEmpty()) {
                val failure =
                    primaryFailure ?: AssertionError("Chrome journey synthetic cleanup failed")
                cleanupFailures.forEach(failure::addSuppressed)
                if (primaryFailure == null) throw failure
            }
        }
    }
}
