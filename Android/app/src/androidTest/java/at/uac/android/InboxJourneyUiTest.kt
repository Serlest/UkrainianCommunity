package at.uac.android

import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.inbox.InboxViewModel
import com.google.firebase.firestore.Source
import java.io.File
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

@RunWith(AndroidJUnit4::class)
class InboxJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val inbox
        get() = ViewModelProvider(compose.activity)[InboxViewModel::class.java]

    private val store
        get() = LocalAuthSession.get(context)

    private val fixtures
        get() = LocalEmulatorFixtures(context)

    private fun scroll(tag: String) {
        compose.onNodeWithTag("inbox-list").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo()
    }

    @Test
    fun inboxEntryDetailDestinationPreferencesAndLogoutOrGuestGate() {
        runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.navigate("profile", true)
        }
        compose.waitUntil(15_000) { store.state.value.stage == AuthStage.GUEST }
        if (InstrumentationRegistry.getArguments().getString("expectEmulator") != "true") {
            compose.onNodeWithTag("account-open-inbox").assertDoesNotExist()
            assertNull(inbox.state.value.session)
            return
        }
        try {
            val uid = prepare()
            compose.onNodeWithTag("account-open-inbox").performScrollTo().performClick()
            compose.waitUntil(20_000) {
                inbox.state.value.items.any { it.id == "journey" } && !inbox.state.value.loading
            }
            assertEquals("profile/inbox", browse.state.value.route)
            scroll("inbox-details-journey")
            compose.onNodeWithTag("inbox-details-journey").performClick()
            compose.waitUntil(15_000) {
                !inbox.state.value.mutating && inbox.state.value.unreadCount == 0L
            }
            runBlocking {
                val record =
                    LocalFirebase.firestore(context)
                        .document("users/$uid/notificationInbox/journey")
                        .get(Source.SERVER)
                        .await()
                assertEquals(true, record.getBoolean("isRead"))
                assertNotNull(record.getTimestamp("readAt"))
            }
            scroll("inbox-open-journey")
            screenshot()
            compose.onNodeWithTag("inbox-open-journey").performClick()
            compose.waitUntil(15_000) {
                browse.state.value.route == "news/synthetic-news-01" &&
                    !browse.state.value.data.loading
            }
            assertEquals("emulator", browse.state.value.mode)
            assertEquals("synthetic-news-01", browse.state.value.data.detail?.id)
            compose.onNodeWithTag("back").performClick()
            compose.waitUntil(5_000) { browse.state.value.route == "profile/inbox" }
            scroll("inbox-settings")
            compose.onNodeWithTag("inbox-settings").performClick()
            compose.waitUntil(10_000) { inbox.state.value.preferences != null }
            compose
                .onNodeWithTag("inbox-preferences")
                .performScrollToNode(hasTestTag("inbox-push-toggle"))
            compose.onNodeWithTag("inbox-push-toggle").performClick()
            compose.waitUntil(15_000) {
                inbox.state.value.preferencesSaved && !inbox.state.value.mutating
            }
            runBlocking {
                assertEquals(
                    true,
                    LocalFirebase.firestore(context)
                        .document("users/$uid/notificationPreferences/settings")
                        .get(Source.SERVER)
                        .await()
                        .getBoolean("notificationsEnabled"),
                )
            }
            compose.onNodeWithTag("back").performClick()
            compose.onNodeWithTag("back").performClick()
            compose.onNodeWithTag("auth-signout").performScrollTo().performClick()
            compose.waitUntil(10_000) {
                store.state.value.stage == AuthStage.GUEST && inbox.state.value.session == null
            }
            assertTrue(inbox.state.value.items.isEmpty())
            assertEquals(0L, inbox.state.value.unreadCount)
            compose.onNodeWithTag("account-open-inbox").assertDoesNotExist()
        } finally {
            runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        }
    }

    private fun prepare(): String = runBlocking {
        fixtures.seedLegal()
        val email = "inbox-journey-${UUID.randomUUID()}@example.invalid"
        val password = "Synthetic-inbox-journey-only!"
        withContext(Dispatchers.Main) {
                store.register(
                    AuthRegistration(
                        email,
                        "Inbox Journey",
                        "wien",
                        acceptedTerms = true,
                        acceptedPrivacy = true,
                        minimumAgeConfirmed = true,
                    ),
                    password,
                    password,
                    "de",
                )!!
            }
            .join()
        assertEquals(AuthStage.VERIFICATION_PENDING, store.state.value.stage)
        val uid = store.state.value.identity!!.uid
        val code = fixtures.verificationCode(email)
        withContext(Dispatchers.Main) { store.applyVerificationCode(code)!! }.join()
        assertTrue(store.state.value.readyForActions)
        fixtures.seed(
            "users/$uid/notificationInbox/journey",
            mapOf(
                "type" to "organizationNewsPublished",
                "actionType" to "openNews",
                "sourceType" to "organization",
                "sourceId" to "synthetic-org-01",
                "actionTargetId" to "synthetic-news-01",
                "createdAt" to Instant.now(),
                "title" to "Neuigkeiten aus deiner Community",
                "message" to
                    "Ein lokaler Test: Details öffnen und sicher zur Nachricht zurückkehren.",
                "isRead" to false,
                "archivedAt" to null,
                "deletedAt" to null,
            ),
        )
        uid
    }

    private fun screenshot() {
        compose.waitForIdle()
        val bitmap =
            InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
                ?: error("Screenshot unavailable")
        File(context.externalCacheDir, "inbox-journey.png").outputStream().use {
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
        }
    }
}
