package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.history.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HistoryUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = HistorySession("private-history-uid", 1, true)
    private val record =
        HistoryRecord(
            "news-synthetic",
            HistorySection.RECENT,
            HistoryTarget(HistoryType.NEWS, "synthetic"),
            null,
            "Never reveal private snapshot",
            "Never reveal private subtitle",
            "https://example.invalid/private-image",
            Instant.EPOCH,
        )
    private val content =
        Content(
            ContentKind.NEWS,
            record.target.id,
            mapOf("title" to "Поточна видима назва / Aktueller öffentlicher Titel"),
        )
    private val page =
        HistoryPage(
            session,
            HistorySection.RECENT,
            listOf(HistoryEntry(record, content)),
            null,
            true,
            30,
        )

    private fun state() = HistoryState(session, HistorySection.RECENT, visible = true, page = page)

    private fun scroll(tag: String) =
        compose.onNodeWithTag("history-list").performScrollToNode(hasTestTag(tag))

    @Test
    fun boundedWindowAndExplicitDeleteAreReachableAtTwoHundredPercent() {
        var selected = emptySet<String>()
        var confirmed = false
        val state = mutableStateOf(state())
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                MaterialTheme {
                    HistoryContent(
                        state.value,
                        "uk",
                        HistoryActions(
                            delete = {
                                selected = it
                                state.value =
                                    state.value.copy(
                                        confirmation =
                                            HistoryDelete(
                                                session,
                                                HistorySection.RECENT,
                                                listOf(record),
                                            )
                                    )
                            },
                            confirm = { confirmed = true },
                        ),
                    )
                }
            }
        }
        scroll("history-bounded")
        compose.onNodeWithTag("history-bounded").assertIsDisplayed()
        scroll("history-delete-visible")
        compose.onNodeWithTag("history-delete-visible").performClick()
        compose.onNodeWithTag("history-confirm-delete").assertIsDisplayed().assertIsEnabled()
        compose.runOnIdle {
            assertEquals(setOf(record.id), selected)
            assertFalse(confirmed)
        }
        compose.onNodeWithTag("history-confirm-delete").performClick()
        compose.runOnIdle { assertTrue(confirmed) }
    }

    @Test
    fun retainedPageCannotExposeDeleteUntilReloadIsRendered() {
        val rendered = mutableStateOf(state())
        var requests = 0
        compose.setContent {
            MaterialTheme {
                HistoryContent(rendered.value, "de", HistoryActions(delete = { requests++ }))
            }
        }
        scroll("history-delete-visible")
        compose.onNodeWithTag("history-delete-visible").assertIsEnabled()
        // Same transition used by the visibility/lifecycle refresh: a previously
        // ready page is not authority to click while the new frame is loading.
        compose.runOnIdle { rendered.value = state().copy(loading = true) }
        compose.onNodeWithTag("history-delete-visible").assertDoesNotExist()
        scroll("history-refresh")
        compose.onNodeWithTag("history-refresh").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(0, requests) }
        compose.runOnIdle { rendered.value = state() }
        compose.onNodeWithTag("history-refresh").assertIsEnabled()
        scroll("history-delete-visible")
        compose.onNodeWithTag("history-delete-visible").assertIsEnabled().performClick()
        compose.runOnIdle { assertEquals(1, requests) }
    }

    @Test
    fun unavailableRowsNeverExposeOldTitleImageOrOpenAction() {
        compose.setContent {
            MaterialTheme {
                HistoryContent(
                    state().copy(page = page.copy(entries = listOf(HistoryEntry(record, null)))),
                    "de",
                    HistoryActions(),
                )
            }
        }
        scroll("history-unavailable-${record.id}")
        compose.onNodeWithTag("history-unavailable-${record.id}").assertIsDisplayed()
        compose.onNodeWithText(record.title).assertDoesNotExist()
        compose.onNodeWithText(record.subtitle!!).assertDoesNotExist()
        compose.onNodeWithTag("history-open-${record.id}").assertDoesNotExist()
        compose.onNodeWithText(session.uid).assertDoesNotExist()
        scroll("history-delete-${record.id}")
        compose.onNodeWithTag("history-delete-${record.id}").assertIsEnabled()
    }

    @Test
    fun accountMaskLoadingAndOfflineHideAllPrivateRows() {
        val state = mutableStateOf(state())
        compose.setContent { MaterialTheme { HistoryContent(state.value, "de", HistoryActions()) } }
        scroll("history-row-${record.id}")
        compose.onNodeWithTag("history-row-${record.id}").assertExists()
        compose.runOnIdle { state.value = state().copy(loading = true) }
        compose.onNodeWithTag("history-row-${record.id}").assertDoesNotExist()
        compose.runOnIdle { state.value = state().copy(error = HistoryFailure.OFFLINE) }
        scroll("history-retry")
        compose.onNodeWithTag("history-retry").assertIsEnabled()
        compose.onNodeWithTag("history-row-${record.id}").assertDoesNotExist()
        compose.runOnIdle { state.value = state().forSession(null, HistorySection.RECENT) }
        scroll("history-account")
        compose.onNodeWithTag("history-account").assertIsEnabled()
        compose.onNodeWithTag("history-row-${record.id}").assertDoesNotExist()
    }

    @Test
    fun filteredVisibleDeleteUsesOnlyFilteredIds() {
        val state = mutableStateOf(state())
        var selected = emptySet<String>()
        compose.setContent {
            MaterialTheme {
                HistoryContent(
                    state.value,
                    "de",
                    HistoryActions(
                        search = { state.value = state.value.copy(search = it) },
                        delete = { selected = it },
                    ),
                )
            }
        }
        scroll("history-search")
        compose.onNodeWithTag("history-search").performTextReplacement("Never reveal")
        scroll("history-empty")
        compose.onNodeWithTag("history-empty").assertIsDisplayed()
        compose.onNodeWithTag("history-delete-visible").assertDoesNotExist()
        scroll("history-search")
        compose.onNodeWithTag("history-search").performTextReplacement("Aktueller")
        scroll("history-delete-visible")
        compose.onNodeWithTag("history-delete-visible").performClick()
        compose.runOnIdle { assertEquals(setOf(record.id), selected) }
    }

    @Test
    fun uncertainMutationOffersReadOnlyStatusNotBlindResend() {
        var checked = false
        compose.setContent {
            MaterialTheme {
                HistoryContent(
                    state()
                        .copy(page = null, pendingWrites = 1, notice = HistoryFailure.UNCONFIRMED),
                    "uk",
                    HistoryActions(reconcile = { checked = true }),
                )
            }
        }
        scroll("history-reconcile")
        compose.onNodeWithTag("history-reconcile").performClick()
        compose.runOnIdle { assertTrue(checked) }
        compose.onNodeWithTag("history-confirm-delete").assertDoesNotExist()
        compose.onNodeWithText("Повторити надсилання").assertDoesNotExist()
    }
}
