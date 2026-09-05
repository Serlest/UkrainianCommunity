package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.inbox.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class InboxPopupUiTest {
    @get:Rule val compose = createComposeRule()
    private val now = Instant.parse("2026-09-03T01:00:00Z")
    private val session = InboxSession("synthetic-popup-ui", 1, false)
    private val account = InboxPopupAccount(session.uid, session.revision, session)
    private val notice =
        InboxNotice(
            "important",
            session.uid,
            InboxKind.SYSTEM,
            now,
            false,
            actionType = "openEvent",
            sourceId = "synthetic-event-01",
            title = "Wichtige Information / Важлива інформація",
            message = "Synthetic important details. Тестове важливе повідомлення. ".repeat(30),
            severity = "critical",
            requiresPopup = true,
        )

    private fun state() = InboxPopupState(account, notice, confirmed = true)

    private fun scroll(tag: String) {
        compose.onNodeWithTag(tag).performScrollTo()
    }

    @Test
    fun longPopupRemainsScrollableAndActionableAtTwoHundredPercent() {
        var opened: String? = null
        var dismissed: String? = null
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                MaterialTheme {
                    InboxPopupHost(
                        state(),
                        "uk",
                        { dismissed = it },
                        { opened = it },
                        {},
                        now = { now },
                    )
                }
            }
        }
        scroll("inbox-popup-open")
        compose.onNodeWithTag("inbox-popup-open").performClick()
        compose.runOnIdle { assertEquals(notice.id, opened) }
        scroll("inbox-popup-dismiss")
        compose.onNodeWithTag("inbox-popup-dismiss").performClick()
        compose.runOnIdle { assertEquals(notice.id, dismissed) }
    }

    @Test
    fun unknownKindRemainsReadableWithoutAnAction() {
        compose.setContent {
            MaterialTheme {
                InboxPopupHost(
                    state().copy(active = notice.copy(kind = InboxKind.UNKNOWN)),
                    "de",
                    {},
                    {},
                    {},
                    now = { now },
                )
            }
        }
        compose.onNodeWithTag("inbox-popup-title").assertExists()
        compose.onNodeWithTag("inbox-popup-open").assertDoesNotExist()
        scroll("inbox-popup-dismiss")
        compose.onNodeWithTag("inbox-popup-dismiss").assertIsEnabled()
    }

    @Test
    fun expiredCachedAndChangedAccountContentIsNotDisplayed() {
        val snapshot = mutableStateOf(state())
        val authority = mutableStateOf(account)
        compose.setContent {
            MaterialTheme {
                InboxPopupHost(
                    snapshot.value.forAccount(authority.value),
                    "de",
                    {},
                    {},
                    {},
                    now = { now },
                )
            }
        }
        compose.onNodeWithTag("inbox-popup").assertExists()
        compose.runOnIdle { snapshot.value = state().copy(confirmed = false) }
        compose.onNodeWithTag("inbox-popup").assertDoesNotExist()
        compose.runOnIdle { snapshot.value = state().copy(active = notice.copy(expiresAt = now)) }
        compose.onNodeWithTag("inbox-popup").assertDoesNotExist()
        compose.runOnIdle {
            snapshot.value = state()
            authority.value = account.copy(revision = 2, session = session.copy(revision = 2))
        }
        compose.onNodeWithTag("inbox-popup").assertDoesNotExist()
    }

    @Test
    fun partialReceiptErrorKeepsExplicitInboxEscapeWithoutFalseSuccess() {
        var inbox = false
        var cleared = false
        compose.setContent {
            MaterialTheme {
                InboxPopupHost(
                    InboxPopupState(
                        account,
                        error = InboxFailure.OFFLINE,
                        acknowledgementFailed = true,
                    ),
                    "uk",
                    {},
                    {},
                    { cleared = true },
                    onInbox = { inbox = true },
                    now = { now },
                )
            }
        }
        compose.onNodeWithTag("inbox-popup-error").assertExists()
        compose.onNodeWithTag("inbox-popup-open").assertDoesNotExist()
        scroll("inbox-popup-inbox")
        compose.onNodeWithTag("inbox-popup-inbox").performClick()
        compose.runOnIdle {
            assertTrue(inbox)
            assertTrue(cleared)
        }
    }

    @Test
    fun unavailableRouteIsHiddenAndInFlightWritePreventsAnotherDialogTap() {
        val snapshot = mutableStateOf(state())
        compose.setContent {
            MaterialTheme {
                InboxPopupHost(
                    snapshot.value,
                    "de",
                    {},
                    {},
                    {},
                    destinationAvailable = { false },
                    now = { now },
                )
            }
        }
        compose.onNodeWithTag("inbox-popup-open").assertDoesNotExist()
        scroll("inbox-popup-dismiss")
        compose.onNodeWithTag("inbox-popup-dismiss").assertExists()
        compose.runOnIdle { snapshot.value = state().copy(mutating = true) }
        compose.onNodeWithTag("inbox-popup").assertDoesNotExist()
    }
}
