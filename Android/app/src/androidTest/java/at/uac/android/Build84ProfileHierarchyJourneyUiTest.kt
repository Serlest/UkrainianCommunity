package at.uac.android

import android.graphics.Bitmap
import android.os.Environment
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
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Real profile navigation with a disposable emulator account; never writes to production. */
@RunWith(AndroidJUnit4::class)
class Build84ProfileHierarchyJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AccountDeletionFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private fun field(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    @Test
    fun profileShowsLogoutAndOpensSecurityAndPrivacyInBothLanguages() {
        AccountDeletionFixtures.requireLocalAvd()
        assumeTrue(
            "Requires running local Auth, Firestore and Functions emulators",
            AccountDeletionFixtures.online(),
        )
        val original = browse.state.value
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("theme", "light")
            browse.navigate("profile", true)
        }
        val user = runBlocking {
            AuthEmulatorFixtures.seedLegalReference()
            AccountDeletionFixtures.create("deletion-profile-ui")
        }
        var primaryFailure: Throwable? = null
        try {
            LocalFirebase.auth(context).signOut()
            compose.openGuestLogin()
            field("auth-email").performTextReplacement(user.email)
            field("auth-password").performTextReplacement(AccountDeletionFixtures.PASSWORD)
            field("auth-login-submit").performClick()
            compose.waitUntil(30_000) { auth.state.value.readyForActions }
            compose.waitForIdle()
            // Do not scroll before this assertion: exiting must be discoverable on entry.
            compose
                .onNodeWithTag("auth-signout")
                .assertIsDisplayed()
                .assertHasClickAction()
                .assertHeightIsAtLeast(48.dp)

            for ((language, theme) in listOf("de" to "light", "uk" to "dark")) {
                compose.runOnIdle {
                    browse.preference("language", language)
                    browse.preference("theme", theme)
                }
                compose.waitUntil(10_000) {
                    browse.state.value.language == language && browse.state.value.theme == theme
                }
                field("auth-profile-name").assertIsDisplayed()
                capture("profile-top", language, theme)
                field("account-open-history").assertHasClickAction().assertHeightIsAtLeast(48.dp)
                capture("profile-personal", language, theme)
                field("account-open-security").assertHasClickAction().assertHeightIsAtLeast(48.dp)
                field("account-open-preferences")
                    .assertHasClickAction()
                    .assertHeightIsAtLeast(48.dp)
                capture("profile-settings", language, theme)

                val destinations =
                    listOf(
                        "edit" to "personal-profile",
                        "saved" to "personal-saved-list",
                        "subscriptions" to "personal-subscriptions-list",
                        "inbox" to "inbox-list",
                        "announcements" to "announcement-history",
                        "organizations" to "organization-hub",
                        "registrations" to "registrations-list",
                        "recent" to "history-list",
                        "history" to "history-list",
                        "feedback" to "feedback-list",
                        "blocked" to "safety-blocked-list",
                        "legal" to "profile-legal-documents",
                    )
                for ((destination, contentTag) in destinations) {
                    field("account-open-$destination").assertIsEnabled().performClick()
                    compose.waitUntil(20_000) {
                        browse.state.value.route == "profile/$destination"
                    }
                    compose.waitUntil(20_000) {
                        compose.onAllNodesWithTag(contentTag).fetchSemanticsNodes().isNotEmpty()
                    }
                    compose.onNodeWithTag(contentTag).assertExists()
                    capture("profile-$destination", language, theme)
                    compose.onNodeWithTag("back").performClick()
                    compose.waitUntil(10_000) { browse.state.value.route == "profile" }
                    assertEquals(user.uid, auth.state.value.identity?.uid)
                }

                field("account-open-security").performClick()
                compose.waitUntil(10_000) { browse.state.value.route == "profile/security" }
                field("auth-security").assertIsDisplayed()
                capture("security", language, theme)
                compose.onNodeWithTag("back").performClick()
                compose.waitUntil(10_000) { browse.state.value.route == "profile" }

                field("account-open-preferences").performClick()
                compose.waitUntil(10_000) { browse.state.value.route == "profile/preferences" }
                field("app-lock-settings").assertIsDisplayed()
                capture("privacy-top", language, theme)
                field("analytics-consent-settings").assertIsDisplayed()
                capture("privacy-consent", language, theme)
                compose.onNodeWithTag("back").performClick()
                compose.waitUntil(10_000) { browse.state.value.route == "profile" }
                assertEquals(user.uid, auth.state.value.identity?.uid)
            }
            field("auth-signout").performClick()
            compose.waitUntil(20_000) { auth.state.value.stage == AuthStage.GUEST }
            compose.onNodeWithTag("guest-sign-in").assertExists()
        } catch (failure: Throwable) {
            primaryFailure = failure
            throw failure
        } finally {
            var cleanupFailure: Throwable? = null
            try {
                runBlocking {
                    if (LocalFirebase.auth(context).currentUser == null)
                        LocalFirebase.auth(context)
                            .signInWithEmailAndPassword(
                                user.email,
                                AccountDeletionFixtures.PASSWORD,
                            )
                            .await()
                    AccountDeletionFixtures.clean(user)
                }
            } catch (failure: Throwable) {
                cleanupFailure = failure
            }
            try {
                runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
                compose.runOnIdle {
                    browse.preference("language", original.language)
                    browse.preference("theme", original.theme)
                    browse.navigate("profile", true)
                }
            } catch (failure: Throwable) {
                val existing = cleanupFailure
                if (existing == null) cleanupFailure = failure else existing.addSuppressed(failure)
            }
            cleanupFailure?.let { failure ->
                val primary = primaryFailure
                if (primary != null) primary.addSuppressed(failure) else throw failure
            }
        }
    }

    private fun capture(screen: String, language: String, theme: String) {
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            val directory =
                File(
                    checkNotNull(context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)),
                    "build84-ui",
                )
            check(directory.isDirectory || directory.mkdirs())
            val scale = (compose.activity.resources.configuration.fontScale * 100).toInt()
            File(directory, "$screen-$language-$theme-$scale.png").outputStream().use {
                check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
            }
        } finally {
            bitmap.recycle()
        }
    }
}
