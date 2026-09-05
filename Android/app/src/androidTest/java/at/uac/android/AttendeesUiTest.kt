package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.attendees.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AttendeesUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = AttendeesSession("synthetic-manager", 1, true, "user")
    private val event =
        AttendeesEvent(
            "synthetic-event",
            "synthetic-org",
            "Eine lange gemeinschaftliche Veranstaltung in Wien",
            "Тривала назва спільної події у Відні",
            100,
            30,
        )
    private val person =
        Attendee(
            "synthetic-registration",
            "never-display-this-uid",
            Instant.EPOCH,
            "Öffentlicher Name mit mehreren Wörtern / Публічне ім’я",
            null,
        )
    private val page =
        AttendeesPage(
            event,
            listOf(person),
            AttendeesCursor(event.id, "synthetic-cursor"),
            session = session,
        )

    private fun state() = AttendeesState(session, event.id, true, page = page)

    private fun scroll(tag: String) =
        compose.onNodeWithTag("attendees-list").performScrollToNode(hasTestTag(tag))

    @Test
    fun loadedOnlySearchSortAndPaginationRemainReachableAtTwoHundredPercent() {
        var more = false
        val state = mutableStateOf(state())
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                MaterialTheme {
                    AttendeesContent(
                        state.value,
                        "uk",
                        AttendeesActions(
                            more = { more = true },
                            search = { state.value = state.value.copy(search = it) },
                            sort = { state.value = state.value.copy(sort = it) },
                        ),
                    )
                }
            }
        }
        scroll("attendees-partial")
        compose.onNodeWithTag("attendees-partial").assertIsDisplayed()
        scroll("attendees-search")
        compose.onNodeWithTag("attendees-search").performTextReplacement("Публічне")
        scroll("attendees-sort-newest")
        compose.onNodeWithTag("attendees-sort-newest").performClick().assertIsSelected()
        scroll("attendee-${person.id}")
        compose.onNodeWithText(person.displayName!!).assertIsDisplayed()
        compose.onNodeWithText(person.userId).assertDoesNotExist()
        scroll("attendees-more")
        compose.onNodeWithTag("attendees-more").performClick()
        compose.runOnIdle {
            assertTrue(more)
            assertEquals(AttendeesSort.NEWEST, state.value.sort)
        }
    }

    @Test
    fun foreignSessionMaskRemovesNamesImmediately() {
        val authority = mutableStateOf<AttendeesSession?>(session)
        compose.setContent {
            MaterialTheme {
                AttendeesContent(
                    state().forSession(authority.value, event.id),
                    "de",
                    AttendeesActions(),
                )
            }
        }
        scroll("attendee-${person.id}")
        compose.onNodeWithTag("attendee-${person.id}").assertExists()
        compose.runOnIdle { authority.value = null }
        compose.onNodeWithTag("attendee-${person.id}").assertDoesNotExist()
        scroll("attendees-account")
        compose.onNodeWithTag("attendees-account").assertIsEnabled()
    }

    @Test
    fun offlineLoadingAndNotReadyNeverRenderAnOldPrivatePage() {
        val state = mutableStateOf(state().copy(error = AttendeesFailure.OFFLINE))
        var retry = false
        compose.setContent {
            MaterialTheme {
                AttendeesContent(state.value, "de", AttendeesActions(refresh = { retry = true }))
            }
        }
        compose.onNodeWithTag("attendee-${person.id}").assertDoesNotExist()
        scroll("attendees-retry")
        compose.onNodeWithTag("attendees-retry").performClick()
        compose.runOnIdle {
            assertTrue(retry)
            state.value = state().copy(loading = true)
        }
        compose.onNodeWithTag("attendee-${person.id}").assertDoesNotExist()
        compose.onNodeWithTag("attendees-empty").assertDoesNotExist()
        compose.runOnIdle { state.value = state().copy(session = session.copy(ready = false)) }
        compose.onNodeWithTag("attendee-${person.id}").assertDoesNotExist()
        scroll("attendees-account")
        compose.onNodeWithTag("attendees-account").assertIsEnabled()
    }

    @Test
    fun missingPublicProfileUsesGenericMemberAndNeverPrivateIdentifiers() {
        compose.setContent {
            MaterialTheme {
                AttendeesContent(
                    state()
                        .copy(
                            page =
                                page.copy(
                                    people =
                                        listOf(
                                            person.copy(displayName = null, registeredAt = null)
                                        ),
                                    next = null,
                                )
                        ),
                    "de",
                    AttendeesActions(),
                )
            }
        }
        scroll("attendee-${person.id}")
        compose.onNodeWithText("Community-Mitglied").assertIsDisplayed()
        compose.onNodeWithText("Anmeldezeitpunkt nicht verfügbar").assertIsDisplayed()
        compose.onNodeWithText(person.userId).assertDoesNotExist()
        compose.onNodeWithTag("attendees-more").assertDoesNotExist()
    }

    @Test
    fun emptySearchAndIncompleteRecordsAreNotACompleteGlobalSearchClaim() {
        compose.setContent {
            MaterialTheme {
                AttendeesContent(
                    state().copy(search = "no such public name", page = page.copy(invalid = 1)),
                    "de",
                    AttendeesActions(),
                )
            }
        }
        scroll("attendees-unavailable")
        compose.onNodeWithTag("attendees-unavailable").assertIsDisplayed()
        scroll("attendees-empty")
        compose.onNodeWithText("Keine passenden geladenen Namen.").assertIsDisplayed()
        scroll("attendees-more")
        compose.onNodeWithTag("attendees-more").assertIsEnabled()
        compose.onNodeWithTag("attendees-complete").assertDoesNotExist()
    }
}
