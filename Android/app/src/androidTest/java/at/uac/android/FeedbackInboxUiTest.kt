package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.feedback.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Presentation-only synthetic data. No Firebase, deletion, read-state or status writes. */
@RunWith(AndroidJUnit4::class)
class FeedbackInboxUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = FeedbackSession("synthetic-inbox-manager", 1, true, true, "Émilie Müller")
    private val time = Instant.parse("2026-09-03T17:00:00.123456789Z")

    private fun item(id: String, status: FeedbackStatus = FeedbackStatus.OPEN) =
        FeedbackContract.item(
                RawDocument(
                    id,
                    FeedbackContract.creation(
                        id,
                        actor,
                        FeedbackDraft(message = "Synthetic $id Café"),
                        time,
                    ),
                )
            )
            .copy(status = status)

    private val initial =
        FeedbackState(
            session = actor,
            audience = FeedbackAudience.MANAGEMENT,
            page =
                FeedbackPage(
                    listOf(
                        item("open"),
                        item("legacy", FeedbackStatus.REVIEWED),
                        item("closed", FeedbackStatus.ARCHIVED),
                        item("unknown", FeedbackStatus.UNKNOWN),
                    ),
                    FeedbackCursor(time, "unchanged-source-cursor"),
                    true,
                ),
        )

    private fun scroll(tag: String) {
        compose.waitForIdle()
        compose.onNodeWithTag("feedback-list").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo()
    }

    private inner class Harness(language: String = "de") {
        val state = mutableStateOf(initial)
        var more = 0
        var refresh = 0
        var opens = 0
        var lastOpen: String? = null
        val editShapes = mutableListOf<Triple<Int, Boolean, Boolean>>()

        init {
            compose.setContent {
                MaterialTheme {
                    FeedbackList(
                        state.value,
                        language,
                        {},
                        {},
                        { if (it) more++ else refresh++ },
                        {
                            opens++
                            lastOpen = it
                        },
                        {},
                        { query ->
                            editShapes +=
                                Triple(
                                    query.length,
                                    query == state.value.inbox.query,
                                    FeedbackInboxSelector.validQuery(query),
                                )
                            state.value =
                                if (FeedbackInboxSelector.validQuery(query))
                                    state.value.copy(
                                        inbox = state.value.inbox.copy(query = query),
                                        inboxQueryRejected = false,
                                    )
                                else state.value.copy(inboxQueryRejected = true)
                        },
                        {
                            state.value =
                                state.value.copy(inbox = state.value.inbox.copy(filter = it))
                        },
                        {
                            state.value =
                                state.value.copy(inbox = state.value.inbox.copy(sort = it))
                        },
                    )
                }
            }
        }

        fun search(value: String) {
            scroll("feedback-inbox-search")
            compose.onNodeWithTag("feedback-inbox-search").performTextReplacement(value)
            compose.onNodeWithTag("feedback-inbox-search").performImeAction()
        }
    }

    @Test
    fun defaultOpenLoadedCountsAndScopeAreExplicit() {
        Harness()
        scroll("feedback-inbox-filter-OPEN")
        compose.onNodeWithTag("feedback-inbox-filter-OPEN").assertIsSelected()
        scroll("feedback-inbox-count")
        compose.onNodeWithTag("feedback-inbox-count").assertTextEquals("Geladen: 4 · Treffer: 1")
        compose
            .onNodeWithTag("feedback-inbox-scope")
            .assertTextContains("nur für geladene Anfragen", substring = true)
        scroll("feedback-inbox-partial")
        compose
            .onNodeWithTag("feedback-inbox-partial")
            .assertTextContains("noch nicht geladen", substring = true)
        scroll("feedback-item-open")
        compose.onNodeWithTag("feedback-item-open").assertIsDisplayed()
    }

    @Test
    fun zeroMatchesKeepLoadMoreReachableAndNewLoadedMatchAppears() {
        val h = Harness()
        h.search("later-match")
        scroll("feedback-empty")
        compose
            .onNodeWithTag("feedback-empty")
            .assertTextEquals("Keine passenden Anfragen im geladenen Teil.")
        scroll("feedback-more")
        compose.onNodeWithTag("feedback-more").performClick()
        compose.runOnIdle {
            assertEquals(1, h.more)
            assertEquals(0, h.refresh)
            assertEquals(0, h.opens)
            h.state.value =
                h.state.value.copy(
                    page =
                        initial.page!!.copy(
                            items = initial.page.items + item("later-match"),
                            hasMore = false,
                        )
                )
        }
        scroll("feedback-item-later-match")
        compose.onNodeWithTag("feedback-item-later-match").performClick()
        compose.runOnIdle {
            assertEquals(1, h.opens)
            assertEquals("later-match", h.lastOpen)
        }
        compose.onNodeWithTag("feedback-more").assertDoesNotExist()
    }

    @Test
    fun legacyGroupsUnknownAndSortControlsKeepOriginalCursor() {
        val h = Harness()
        for ((filter, target) in
            listOf("ANSWERED" to "legacy", "CLOSED" to "closed", "UNKNOWN" to "unknown")) {
            scroll("feedback-inbox-filter-$filter")
            compose.onNodeWithTag("feedback-inbox-filter-$filter").performClick().assertIsSelected()
            scroll("feedback-item-$target")
            compose.onNodeWithTag("feedback-item-$target").assertIsDisplayed()
        }
        scroll("feedback-inbox-sort-OLDEST")
        compose.onNodeWithTag("feedback-inbox-sort-OLDEST").performClick().assertIsSelected()
        compose.runOnIdle {
            assertEquals(FeedbackInboxSort.OLDEST, h.state.value.inbox.sort)
            assertSame(initial.page!!.next, h.state.value.page!!.next)
            assertEquals(0, h.refresh)
            assertEquals(0, h.more)
        }
    }

    @Test
    fun ukrainianSearchTypeAndRejectedPasteClearWithoutTruncation() {
        val h = Harness("uk")
        h.search("питання cafe")
        scroll("feedback-inbox-count")
        compose
            .onNodeWithTag("feedback-inbox-count")
            .assertTextEquals("Завантажено: 4 · Знайдено: 1")
        h.search("x".repeat(201))
        compose.runOnIdle {
            assertEquals("питання cafe", h.state.value.inbox.query)
            assertTrue(
                "Edit events (length, unchanged, valid): ${h.editShapes}",
                h.state.value.inboxQueryRejected,
            )
            assertEquals(0, h.refresh)
        }
        scroll("feedback-inbox-search-clear")
        compose.onNodeWithTag("feedback-inbox-search-clear").performClick()
        compose.runOnIdle {
            assertEquals("", h.state.value.inbox.query)
            assertFalse(h.state.value.inboxQueryRejected)
        }
    }

    @Test
    fun revokedManagerCannotRenderSuppliedPrivateRowsOrSearch() {
        compose.setContent {
            MaterialTheme {
                FeedbackList(
                    initial.copy(
                        session = actor.copy(canManage = false),
                        inbox = FeedbackInboxOptions("PRIVATE QUERY"),
                    ),
                    "de",
                    {},
                    {},
                    {},
                    {},
                    {},
                )
            }
        }
        compose.onNodeWithTag("feedback-inbox-access").assertIsDisplayed()
        compose.onNodeWithTag("feedback-inbox-search").assertDoesNotExist()
        compose.onNodeWithTag("feedback-item-open").assertDoesNotExist()
        compose.onNodeWithText("PRIVATE QUERY").assertDoesNotExist()
    }

    @Test
    fun rejectedPasteIntoEmptyQuerySurvivesImeAndExplicitClearResetsIt() {
        val h = Harness()
        h.search("x".repeat(201))
        compose.runOnIdle {
            assertEquals("", h.state.value.inbox.query)
            assertTrue("Edit events: ${h.editShapes}", h.state.value.inboxQueryRejected)
        }
        scroll("feedback-inbox-search-clear")
        compose.onNodeWithTag("feedback-inbox-search-clear").performClick()
        compose.runOnIdle {
            assertFalse(h.state.value.inboxQueryRejected)
            assertEquals("", h.state.value.inbox.query)
        }
    }

    @Test
    fun sameCompositionAccountMaskDropsQueryAndOldRowsImmediately() {
        val authority = mutableStateOf<FeedbackSession?>(actor)
        val previous = initial.copy(inbox = FeedbackInboxOptions("PRIVATE QUERY"))
        compose.setContent {
            MaterialTheme {
                FeedbackList(previous.forSession(authority.value), "de", {}, {}, {}, {}, {})
            }
        }
        scroll("feedback-inbox-search")
        compose.onNodeWithTag("feedback-inbox-search").assertTextContains("PRIVATE QUERY")
        compose.runOnIdle { authority.value = actor.copy(uid = "other-manager", revision = 2) }
        compose.onNodeWithTag("feedback-inbox-search").assertDoesNotExist()
        compose.onNodeWithTag("feedback-item-open").assertDoesNotExist()
        compose.onNodeWithText("PRIVATE QUERY").assertDoesNotExist()
    }

    @Test
    fun offlineResultsKeepStaleWarningAndDoNotClaimGlobalEmpty() {
        val h = Harness()
        h.search("no-match")
        compose.runOnIdle { h.state.value = h.state.value.copy(error = FeedbackFailure.OFFLINE) }
        scroll("feedback-error")
        compose
            .onNodeWithTag("feedback-error")
            .assertTextContains("Keine bestätigte Verbindung", substring = true)
        compose.onNodeWithTag("feedback-empty").assertDoesNotExist()
        scroll("feedback-more")
        compose.onNodeWithTag("feedback-more").assertIsDisplayed()
    }

    @Test
    fun ownRequestsKeepComposerWithoutManagementSearchOrFilters() {
        compose.setContent {
            MaterialTheme {
                FeedbackList(
                    initial.copy(
                        audience = FeedbackAudience.OWN,
                        session = actor.copy(canManage = false),
                    ),
                    "de",
                    {},
                    {},
                    {},
                    {},
                    {},
                )
            }
        }
        scroll("feedback-draft")
        compose.onNodeWithTag("feedback-draft").assertIsDisplayed()
        compose.onNodeWithTag("feedback-inbox-search").assertDoesNotExist()
        compose.onNodeWithTag("feedback-inbox-filter-OPEN").assertDoesNotExist()
    }
}
