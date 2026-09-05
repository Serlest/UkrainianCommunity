package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.inbox.InboxPopupViewModel
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** MainActivity overlay + real synthetic SDK/Rules; no injected successful UI state. */
@RunWith(AndroidJUnit4::class)
class InboxPopupJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val popup
        get() = ViewModelProvider(compose.activity)[InboxPopupViewModel::class.java]

    private val store
        get() = LocalAuthSession.get(context)

    private val fixtures
        get() = LocalEmulatorFixtures(context)

    private val password = "Synthetic-popup-journey-only-1!"

    private data class Account(val uid: String, val email: String)

    private val created = mutableListOf<Account>()
    private val noticeIds = listOf("old", "new", "expires", "deleted", "logout")

    @Test
    fun realPopupRouteRetirementAndAccountSwitchJourneyOrGuestGate() {
        runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", "emulator")
            browse.navigate("profile", true)
        }
        compose.waitUntil(15_000) { store.state.value.stage == AuthStage.GUEST }
        if (InstrumentationRegistry.getArguments().getString("expectEmulator") != "true") {
            // Disabled-runtime branch only; never counted as online popup proof.
            compose.onNodeWithTag("inbox-popup").assertDoesNotExist()
            return
        }
        try {
            val first = prepare()
            seed(first.uid, "old")
            login(first)
            compose.waitUntil(20_000) {
                popup.state.value.confirmed && popup.state.value.account.uid == first.uid
            }
            assertNull(popup.state.value.active)
            compose.onNodeWithTag("inbox-popup").assertDoesNotExist()

            seed(first.uid, "new")
            shown("new")
            compose.onNodeWithTag("inbox-popup-open").performScrollTo().performClick()
            compose.waitUntil(20_000) {
                browse.state.value.route == "news/synthetic-news-01" &&
                    !browse.state.value.data.loading
            }
            assertEquals("emulator", browse.state.value.mode)
            assertEquals("synthetic-news-01", browse.state.value.data.detail?.id)
            runBlocking {
                val receipt =
                    LocalFirebase.firestore(context)
                        .document("users/${first.uid}/notificationInbox/new")
                        .get(Source.SERVER)
                        .await()
                assertEquals(true, receipt.getBoolean("isRead"))
                assertNotNull(receipt.getTimestamp("popupPresentedAt"))
                assertNotNull(receipt.getTimestamp("readAt"))
                assertEquals("Synthetic important new", receipt.getString("title"))
            }
            compose.onNodeWithTag("back").performClick()
            compose.waitUntil(10_000) { browse.state.value.route == "profile" }
            compose.onNodeWithTag("inbox-popup").assertDoesNotExist()

            seed(first.uid, "expires", mapOf("expiresAt" to Instant.now().plusSeconds(300)))
            shown("expires")
            seed(first.uid, "expires", mapOf("expiresAt" to Instant.now()))
            gone()
            assertNoPopupReceipt(first.uid, "expires")

            seed(first.uid, "deleted")
            shown("deleted")
            seed(first.uid, "deleted", mapOf("deletedAt" to Instant.now()))
            gone()
            assertNoPopupReceipt(first.uid, "deleted")

            seed(first.uid, "logout")
            shown("logout")
            // Actual shared auth transition while a dialog is visible, not a fake state assignment.
            runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
            compose.waitUntil(15_000) {
                store.state.value.stage == AuthStage.GUEST && popup.state.value.account.uid == null
            }
            compose.onNodeWithTag("inbox-popup").assertDoesNotExist()
            assertNoPopupReceiptWithFixture(first.uid, "logout")

            val second = prepare()
            seed(second.uid, "old")
            login(second)
            compose.waitUntil(20_000) {
                popup.state.value.confirmed && popup.state.value.account.uid == second.uid
            }
            assertNull(popup.state.value.active)
            assertNull(popup.state.value.action)
            compose.onNodeWithTag("inbox-popup").assertDoesNotExist()
            compose.onNodeWithText("Synthetic important logout").assertDoesNotExist()
        } finally {
            cleanup()
        }
    }

    private fun prepare(): Account = runBlocking {
        fixtures.seedLegal()
        val backend = FirebaseAuthBackend(LocalFirebase.auth(context))
        val profiles = FirestoreAuthProfiles(LocalFirebase.firestore(context))
        val email = "popup-journey-${UUID.randomUUID()}@example.invalid"
        val identity = backend.create(email, password, "Popup Journey")
        val account = Account(identity.uid, email).also(created::add)
        profiles.create(
            identity.uid,
            AuthRegistration(
                email,
                "Popup Journey",
                "wien",
                acceptedTerms = true,
                acceptedPrivacy = true,
                minimumAgeConfirmed = true,
            ),
        )
        backend.sendVerification("de")
        backend.verifyEmailCode(fixtures.verificationCode(email))
        backend.reload()
        backend.refreshToken()
        backend.signOut()
        account
    }

    private fun login(account: Account) {
        compose.openGuestLogin()
        compose.onNodeWithTag("auth-email").performScrollTo().performTextReplacement(account.email)
        compose.onNodeWithTag("auth-password").performScrollTo().performTextReplacement(password)
        compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
        compose.waitUntil(20_000) {
            store.state.value.readyForActions && store.state.value.identity?.uid == account.uid
        }
    }

    private fun seed(uid: String, id: String, extra: Map<String, Any?> = emptyMap()) = runBlocking {
        fixtures.seed(
            "users/$uid/notificationInbox/$id",
            mapOf(
                "type" to "systemAnnouncement",
                "createdAt" to Instant.now(),
                "isRead" to false,
                "severity" to "critical",
                "requiresPopup" to true,
                "actionType" to "openNews",
                "actionTargetId" to "synthetic-news-01",
                "sourceType" to "system",
                "title" to "Synthetic important $id",
                "message" to "Lokaler Test einer wichtigen Mitteilung. ".repeat(12),
            ) + extra,
        )
    }

    private fun shown(id: String) {
        compose.waitUntil(20_000) {
            popup.state.value.active?.id == id && popup.state.value.confirmed
        }
        compose.onNodeWithTag("inbox-popup-title").assertTextEquals("Synthetic important $id")
    }

    private fun gone() {
        compose.waitUntil(15_000) { popup.state.value.active == null }
        compose.onNodeWithTag("inbox-popup").assertDoesNotExist()
    }

    private fun assertNoPopupReceipt(uid: String, id: String) = runBlocking {
        val row =
            LocalFirebase.firestore(context)
                .document("users/$uid/notificationInbox/$id")
                .get(Source.SERVER)
                .await()
        assertNull(row.getTimestamp("popupPresentedAt"))
        assertEquals(false, row.getBoolean("isRead"))
    }

    private fun assertNoPopupReceiptWithFixture(uid: String, id: String) =
        runBlocking(Dispatchers.IO) {
            val fields =
                AuthEmulatorFixtures.adminRequest(
                        8088,
                        AuthEmulatorFixtures.documentPath("users/$uid/notificationInbox/$id"),
                    )
                    .getJSONObject("fields")
            assertFalse(fields.has("popupPresentedAt"))
            assertFalse(fields.getJSONObject("isRead").getBoolean("booleanValue"))
        }

    private fun cleanup() = runBlocking {
        withContext(Dispatchers.Main) { store.signOut() }.join()
        val backend = FirebaseAuthBackend(LocalFirebase.auth(context))
        try {
            for (account in created) {
                val signedIn = backend.signIn(account.email, password)
                check(signedIn.uid == account.uid)
                backend.deleteCreatedUser(account.uid)
                withContext(Dispatchers.IO) {
                    (noticeIds.map { "users/${account.uid}/notificationInbox/$it" } +
                            listOf("users/${account.uid}", "publicProfiles/${account.uid}"))
                        .forEach { path ->
                            AuthEmulatorFixtures.adminRequest(
                                8088,
                                AuthEmulatorFixtures.documentPath(path),
                                "DELETE",
                            )
                        }
                }
            }
        } finally {
            backend.signOut()
        }
    }
}
