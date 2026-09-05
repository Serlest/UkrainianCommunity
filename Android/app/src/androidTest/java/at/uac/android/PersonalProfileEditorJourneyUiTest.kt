package at.uac.android

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.personal.*
import at.uac.android.feature.profilemedia.ProfileMediaViewModel
import com.google.firebase.firestore.Source
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real orientation recreation and system picker; no SavedStateHandle or simulated successful
 * callback.
 */
@RunWith(AndroidJUnit4::class)
class PersonalProfileEditorJourneyUiTest {
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

    private val media
        get() = ViewModelProvider(compose.activity)[ProfileMediaViewModel::class.java]

    private fun click(tag: String) {
        compose.onNodeWithTag(tag).performScrollTo().assertIsEnabled().performClick()
    }

    private fun type(tag: String, value: String) {
        compose.onNodeWithTag(tag).performScrollTo().performTextReplacement(value)
    }

    private fun loaded() {
        compose.waitUntil(30_000) {
            personal.state.value.profile != null &&
                !personal.state.value.profileLoading &&
                editor.state.value.confirmedSession == auth.state.value.personalScope()
        }
    }

    private fun assertDraft() {
        compose
            .onNodeWithTag("profile-display-name")
            .performScrollTo()
            .assertTextContains("Memory draft survives rotation")
        compose
            .onNodeWithTag("profile-bio")
            .performScrollTo()
            .assertTextContains("Synthetic private biography survives")
    }

    @Test
    fun dirtyProfileSurvivesRealRotationSameUidRefreshAndPickerCancelButNotLogout() {
        AccountDeletionFixtures.requireLocalAvd()
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.navigate("profile", true)
        }
        if (!AccountDeletionFixtures.online()) {
            compose.onNodeWithTag("account-open-edit").assertDoesNotExist()
            return
        }
        val user = runBlocking {
            AuthEmulatorFixtures.seedLegalReference()
            AccountDeletionFixtures.create("deletion-editor")
        }
        val previousOrientation = compose.activity.requestedOrientation
        try {
            LocalFirebase.auth(context).signOut()
            compose.openGuestLogin()
            type("auth-email", user.email)
            type("auth-password", AccountDeletionFixtures.PASSWORD)
            click("auth-login-submit")
            compose.waitUntil(30_000) { auth.state.value.readyForActions }
            click("account-open-edit")
            loaded()
            type("profile-display-name", "Memory draft survives rotation")
            type("profile-bio", "Synthetic private biography survives")
            val originalActivity = compose.activity
            val originalEditor = editor
            compose.runOnIdle {
                originalActivity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            }
            compose.waitUntil(25_000) {
                compose.activity !== originalActivity &&
                    compose.activity.resources.configuration.orientation ==
                        Configuration.ORIENTATION_LANDSCAPE
            }
            loaded()
            assertSame(originalEditor, editor)
            assertDraft()
            // The next server refresh must adopt untouched fields without erasing the dirty text.
            runBlocking {
                AccountDeletionFixtures.patch("users/${user.uid}", mapOf("city" to "Graz"), true)
                withContext(Dispatchers.Main) { auth.refresh() }.join()
            }
            loaded()
            assertDraft()
            compose.onNodeWithTag("profile-city").performScrollTo().assertTextContains("Graz")
            val revision = auth.state.value.revision
            click("profile-avatar-choose")
            compose.waitUntil(15_000) { PhotoPickerFixtures.pickerVisible() }
            InstrumentationRegistry.getInstrumentation()
                .uiAutomation
                .executeShellCommand("input keyevent 4")
                .close()
            compose.waitUntil(20_000) {
                !PhotoPickerFixtures.pickerVisible() &&
                    !media.state.value.pickerOpen &&
                    auth.state.value.readyForActions
            }
            assertEquals(revision, auth.state.value.revision)
            assertDraft()
            runBlocking {
                val server =
                    LocalFirebase.firestore(context)
                        .document("users/${user.uid}")
                        .get(Source.SERVER)
                        .await()
                assertEquals("Synthetic deletion account", server.getString("displayName"))
                assertNotEquals("Synthetic private biography survives", server.getString("bio"))
                assertEquals("Graz", server.getString("city"))
            }
            compose.onNodeWithTag("back").performClick()
            click("auth-signout")
            compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
            assertEquals(PersonalProfileEditorState(), editor.state.value)
            assertNull(personal.state.value.profile)
            assertNull(media.state.value.session)
        } finally {
            if (PhotoPickerFixtures.pickerVisible())
                InstrumentationRegistry.getInstrumentation()
                    .uiAutomation
                    .executeShellCommand("input keyevent 4")
                    .close()
            compose.runOnIdle { compose.activity.requestedOrientation = previousOrientation }
            runBlocking {
                if (LocalFirebase.auth(context).currentUser == null)
                    LocalFirebase.auth(context)
                        .signInWithEmailAndPassword(user.email, AccountDeletionFixtures.PASSWORD)
                        .await()
                AccountDeletionFixtures.clean(user)
                withContext(Dispatchers.Main) { auth.signOut() }.join()
            }
        }
    }
}
