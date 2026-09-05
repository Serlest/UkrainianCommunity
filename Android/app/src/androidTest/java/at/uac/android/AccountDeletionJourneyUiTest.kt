package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalAccountDeletionJournal
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.accountdeletion.*
import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.personal.PersonalViewModel
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Actual MainActivity login → destructive confirmation → real callable → server read-back → cleared
 * account.
 */
@RunWith(AndroidJUnit4::class)
class AccountDeletionJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val fixture
        get() = AccountDeletionFixtures

    private val store
        get() = LocalAuthSession.get(fixture.context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val deletion
        get() = ViewModelProvider(compose.activity)[AccountDeletionViewModel::class.java]

    private fun click(tag: String) {
        val node = compose.onNodeWithTag(tag)
        if (
            tag !in
                setOf("account-delete-submit", "account-delete-mfa-submit", "account-delete-cancel")
        )
            node.performScrollTo()
        node.assertIsEnabled().performClick()
    }

    private fun type(tag: String, value: String) {
        compose.onNodeWithTag(tag).performScrollTo().performTextReplacement(value)
    }

    @Test
    fun explicitMainDeletionWithWrongPasswordRecoveryAndIndependentReadBackOrGuestGate() {
        fixture.requireLocalAvd()
        runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.navigate("profile", true)
        }
        if (!fixture.online()) {
            compose.onNodeWithTag("account-open-delete").assertDoesNotExist()
            return
        }
        val user = runBlocking {
            AuthEmulatorFixtures.seedLegalReference()
            fixture.create("deletion-main")
        }
        val bookmark = "users/${user.uid}/bookmarks/deletion-main-${UUID.randomUUID()}"
        runBlocking {
            fixture.patch(
                bookmark,
                mapOf("contentId" to "synthetic-news-01", "contentType" to "news"),
            )
        }
        try {
            // Auth account creation above is fixture setup; the application still requires its
            // actual login flow.
            LocalFirebase.auth(fixture.context).signOut()
            compose.openGuestLogin()
            type("auth-email", user.email)
            type("auth-password", fixture.PASSWORD)
            click("auth-login-submit")
            compose.waitUntil(30_000) {
                store.state.value.accountDeletionScope() != null && !store.state.value.busy
            }
            assertEquals(user.uid, store.state.value.identity?.uid)
            click("account-open-delete")
            compose.waitUntil(25_000) {
                deletion.state.value.policy != null || deletion.state.value.error != null
            }
            assertNull(deletion.state.value.error)
            click("account-delete-open")
            compose.onNodeWithTag("account-delete-submit").assertIsNotEnabled()
            type("account-delete-password", "Not-the-password")
            type("account-delete-confirmation", "LÖSCHEN")
            click("account-delete-acknowledge")
            click("account-delete-submit")
            compose.waitUntil(25_000) {
                !deletion.state.value.busy && deletion.state.value.error != null
            }
            assertEquals(AccountDeletionFailure.INVALID_CREDENTIALS, deletion.state.value.error)
            runBlocking {
                assertNull(LocalAccountDeletionJournal.get(fixture.context).pending(user.uid))
                assertNotNull(fixture.document("users/${user.uid}"))
                assertNotNull(fixture.document(bookmark))
            }
            type("account-delete-password", fixture.PASSWORD)
            val attemptStarted = android.os.SystemClock.elapsedRealtime()
            click("account-delete-submit")
            try {
                compose.waitUntil(330_000) {
                    browse.state.value.route == "profile/deleted" ||
                        !deletion.state.value.busy && deletion.state.value.error != null
                }
                assertNull(
                    "No automatic retry or optimistic deletion result",
                    deletion.state.value.error,
                )
                compose.onNodeWithTag("account-deletion-complete").assertIsDisplayed()
                compose.waitUntil(20_000) { store.state.value.stage == AuthStage.GUEST }
            } catch (error: Throwable) {
                val state = deletion.state.value
                val diagnostic = state.freshnessDiagnostic
                val pendingJournal = runBlocking {
                    runCatching {
                        LocalAccountDeletionJournal.get(fixture.context).pending(user.uid) != null
                    }
                        .getOrNull()
                }
                val attemptElapsed = android.os.SystemClock.elapsedRealtime() - attemptStarted
                throw AssertionError(
                    "Deletion Main phase=${state.phase}, error=${state.error}, " +
                        "pending=${state.unresolved}, pendingJournal=$pendingJournal, " +
                        "freshnessStage=${diagnostic?.stage}, freshnessReason=${diagnostic?.reason}, " +
                        "proofAgeMillis=${diagnostic?.ageMillis}, attemptElapsedMillis=$attemptElapsed, " +
                        "authStage=${store.state.value.stage}, " +
                        "sameAccount=${store.state.value.identity?.uid == user.uid}, " +
                        "route=${browse.state.value.route}",
                    error,
                )
            }
            assertNull(LocalFirebase.auth(fixture.context).currentUser)
            val personal =
                ViewModelProvider(compose.activity)[PersonalViewModel::class.java].state.value
            assertNull(personal.session)
            assertNull(personal.profile)
            assertNull(deletion.state.value.session)
            runBlocking {
                assertNull(fixture.document("users/${user.uid}"))
                assertNull(fixture.document("publicProfiles/${user.uid}"))
                assertNull(fixture.document(bookmark))
                assertNull(LocalAccountDeletionJournal.get(fixture.context).pending(user.uid))
                fixture.assertAuthAbsent(user)
            }
        } finally {
            runBlocking {
                fixture.clean(user, listOf(bookmark))
                withContext(Dispatchers.Main) { store.signOut() }.join()
            }
        }
    }
}
