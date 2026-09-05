package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.browse.*
import at.uac.android.feature.personal.*
import at.uac.android.feature.registrations.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RegistrationsUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = PersonalSession("synthetic-ui", true, true, 1)
    private val event =
        Content(
            ContentKind.EVENTS,
            "synthetic-registration",
            mapOf(
                "title" to
                    "Eine lange Veranstaltung aus der Community / Тривала назва події спільноти",
                "startDate" to Instant.now().plusSeconds(86_400),
                "endDate" to Instant.now().plusSeconds(90_000),
                "city" to "Wien",
            ),
        )

    private fun scroll(tag: String) {
        compose.onNodeWithTag("registrations-list").performScrollToNode(hasTestTag(tag))
    }

    @Test
    fun longCardsAndPaginationAreReachableAtTwoHundredPercent() {
        var opened: Content? = null
        var more = false
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                MaterialTheme {
                    RegistrationsScreen(
                        RegistrationsState(session, listOf(event), loaded = true, hasMore = true),
                        "uk",
                        { if (it) more = true },
                        {},
                        { opened = it },
                        {},
                    )
                }
            }
        }
        scroll("registration-${event.id}")
        compose.onNodeWithTag("registration-${event.id}").performClick()
        scroll("registrations-more")
        compose.onNodeWithTag("registrations-more").performClick()
        compose.runOnIdle {
            assertEquals(event, opened)
            assertTrue(more)
        }
    }

    @Test
    fun changedAccountMasksEveryCardAndOffersAccountGate() {
        val current = mutableStateOf<PersonalSession?>(session)
        val state = RegistrationsState(session, listOf(event), loaded = true)
        compose.setContent {
            MaterialTheme {
                RegistrationsScreen(state.forSession(current.value), "de", {}, {}, {}, {})
            }
        }
        scroll("registration-${event.id}")
        compose.onNodeWithTag("registration-${event.id}").assertExists()
        compose.runOnIdle { current.value = null }
        compose.onNodeWithTag("registration-${event.id}").assertDoesNotExist()
        scroll("registrations-account")
        compose.onNodeWithTag("registrations-account").assertIsEnabled()
    }

    @Test
    fun unavailableAndOfflineRemainExplicitInsteadOfFalseEmptySuccess() {
        compose.setContent {
            MaterialTheme {
                RegistrationsScreen(
                    RegistrationsState(
                        session,
                        listOf(event),
                        loaded = true,
                        unavailable = 1,
                        error = PersonalFailure.OFFLINE,
                    ),
                    "de",
                    {},
                    {},
                    {},
                    {},
                )
            }
        }
        scroll("registrations-error")
        compose.onNodeWithTag("registrations-error").assertExists()
        scroll("registrations-unavailable")
        compose.onNodeWithTag("registrations-unavailable").assertExists()
        compose.onNodeWithTag("registrations-empty").assertDoesNotExist()
    }
}
