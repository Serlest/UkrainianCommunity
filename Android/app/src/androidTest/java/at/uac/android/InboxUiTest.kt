package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.inbox.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class InboxUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = InboxSession("synthetic-ui-inbox", 1, true)
    private val notice =
        InboxNotice(
            "test",
            session.uid,
            InboxKind.EVENT_UPDATED,
            Instant.EPOCH,
            false,
            actionType = "openEvent",
            sourceId = "synthetic-event-01",
            message = "Synthetic details",
        )

    private fun scroll(tag: String) {
        compose.onNodeWithTag("inbox-list").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo()
    }

    @Test
    fun detailReadAndRouteRemainAvailableWithLargeText() {
        var changed: InboxMutation? = null
        var opened: InboxDestination? = null
        compose.setContent {
            MaterialTheme {
                InboxScreen(
                    InboxState(session, listOf(notice), unreadCount = 1),
                    "uk",
                    {},
                    {},
                    { _, action -> changed = action },
                    {},
                    { _, route -> opened = route },
                    {},
                )
            }
        }
        scroll("inbox-details-test")
        compose.onNodeWithTag("inbox-details-test").performClick()
        compose.runOnIdle { assertEquals(InboxMutation.READ, changed) }
        scroll("inbox-open-test")
        compose.onNodeWithTag("inbox-open-test").performClick()
        compose.runOnIdle {
            assertEquals(InboxDestination(InboxDestinationKind.EVENT, "synthetic-event-01"), opened)
        }
    }

    @Test
    fun unreadDetailPendingReadBlocksEarlyOpenUntilItsAcknowledgedStateIsPresented() {
        val snapshot = mutableStateOf(InboxState(session, listOf(notice), unreadCount = 1))
        var reads = 0
        var opens = 0
        compose.setContent {
            MaterialTheme {
                InboxScreen(
                    snapshot.value,
                    "uk",
                    {},
                    {},
                    { _, action ->
                        assertEquals(InboxMutation.READ, action)
                        reads++
                        snapshot.value = snapshot.value.copy(mutating = true)
                    },
                    {},
                    { _, route ->
                        assertEquals(
                            InboxDestination(InboxDestinationKind.EVENT, "synthetic-event-01"),
                            route,
                        )
                        opens++
                    },
                    {},
                )
            }
        }
        scroll("inbox-details-test")
        compose.onNodeWithTag("inbox-details-test").performClick()
        scroll("inbox-open-test")
        // This is the same premature action as the old Journey, held deterministically in READ.
        compose.onNodeWithTag("inbox-open-test").assertIsNotEnabled().performClick()
        compose.runOnIdle {
            assertEquals(1, reads)
            assertEquals(0, opens)
            snapshot.value =
                snapshot.value.copy(
                    mutating = false,
                    items = listOf(notice.copy(isRead = true)),
                    unreadCount = 0,
                )
        }
        scroll("inbox-open-test")
        compose.onNodeWithTag("inbox-open-test").assertIsEnabled().performClick()
        compose.runOnIdle {
            assertEquals(1, reads)
            assertEquals(1, opens)
        }
    }

    @Test
    fun clearingNeedsConfirmationAndAccountSwitchClearsVisibleState() {
        var cleared = false
        val authority = mutableStateOf<InboxSession?>(session)
        val snapshot = InboxState(session, listOf(notice), unreadCount = 1)
        compose.setContent {
            MaterialTheme {
                InboxScreen(
                    snapshot.forSession(authority.value),
                    "de",
                    {},
                    {},
                    { _, _ -> },
                    { cleared = true },
                    { _, _ -> },
                    {},
                )
            }
        }
        scroll("inbox-clear")
        compose.onNodeWithTag("inbox-clear").performClick()
        compose.runOnIdle { assertFalse(cleared) }
        compose.onNodeWithTag("inbox-confirm-delete").performClick()
        compose.runOnIdle {
            assertTrue(cleared)
            authority.value = null
        }
        compose.onNodeWithTag("inbox-test").assertDoesNotExist()
        compose.onNodeWithTag("inbox-clear").assertDoesNotExist()
    }

    @Test
    fun preferencePendingPreventsDuplicateChangeAndKeepsInboxIndependent() {
        var saved: InboxPreferences? = null
        val snapshot = mutableStateOf(InboxState(session, preferences = InboxPreferences()))
        compose.setContent {
            MaterialTheme {
                InboxPreferencesScreen(
                    snapshot.value,
                    "de",
                    {},
                    {
                        saved = it
                        snapshot.value = snapshot.value.copy(mutating = true)
                    },
                )
            }
        }
        compose
            .onNodeWithTag("inbox-preferences")
            .performScrollToNode(hasTestTag("inbox-push-toggle"))
        compose.onNodeWithTag("inbox-push-toggle").performClick()
        compose.onNodeWithTag("inbox-push-toggle").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(InboxPreferences(true, true, 60), saved) }
    }
}
