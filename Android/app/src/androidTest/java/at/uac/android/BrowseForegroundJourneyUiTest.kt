package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.ReadFailure
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test

/** Real lifecycle and server moderation change, not an injected success/error state. */
class BrowseForegroundJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun backgroundDetailIsDiscardedAndRevokedServerContentCannotReappearOnResume() {
        AccountDeletionFixtures.requireLocalAvd()
        assumeTrue("Actual local backend required", AccountDeletionFixtures.online())
        val fixture =
            AttendeesDeviceFixtures(
                "attendees-${UUID.randomUUID()}",
                "synthetic-foreground-manager",
            )
        val auth = LocalAuthSession.get(AccountDeletionFixtures.context)
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        var original: Throwable? = null
        try {
            runBlocking { fixture.seedEventAndOrganization(0) }
            val browse = compose.runOnIdle {
                ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
            }
            compose.runOnIdle {
                browse.preference("mode", "emulator")
                browse.preference("language", "de")
                browse.navigate("events/${fixture.eventId}")
            }
            compose.waitUntil(20_000) {
                !browse.state.value.data.loading &&
                    browse.state.value.data.detail?.id == fixture.eventId
            }
            assertNull(browse.state.value.data.cachedAt)
            compose.onNodeWithTag("detail-content").assertExists()
            compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
            assertNull(
                "Paused details must be invalidated before any new response",
                browse.state.value.data.detail,
            )
            runBlocking {
                fixture.patch("events/${fixture.eventId}", mapOf("moderationStatus" to "rejected"))
            }
            compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
            compose.waitUntil(20_000) { !browse.state.value.data.loading }
            assertEquals(ReadFailure.DENIED, browse.state.value.data.error)
            assertNull(browse.state.value.data.detail)
            compose.onNodeWithTag("detail-content").assertDoesNotExist()
            compose.onNodeWithText("Synthetic managed event").assertDoesNotExist()
            runBlocking {
                fixture.patch("events/${fixture.eventId}", mapOf("moderationStatus" to "approved"))
            }
            compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("browse-retry"))
            compose.onNodeWithTag("browse-retry").performClick()
            compose.waitUntil(20_000) {
                !browse.state.value.data.loading &&
                    browse.state.value.data.detail?.id == fixture.eventId
            }
            assertNull(browse.state.value.data.cachedAt)
            assertNull(browse.state.value.data.error)
        } catch (error: Throwable) {
            original = error
            throw error
        } finally {
            runBlocking { fixture.cleanup(original) }
        }
    }
}
