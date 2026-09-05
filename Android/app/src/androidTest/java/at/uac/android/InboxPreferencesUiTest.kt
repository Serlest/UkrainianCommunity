package at.uac.android

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import at.uac.android.design.UacTheme
import at.uac.android.feature.inbox.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class InboxPreferencesUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = InboxSession("synthetic-preference-ui", 1, true)

    private fun show(tag: String) {
        compose.onNodeWithTag("inbox-preferences").performScrollToNode(hasTestTag(tag))
    }

    @Test
    fun disabledAccountPreferencePreservesButDisablesDependentReminderChoices() {
        var saves = 0
        compose.setContent {
            UacTheme {
                InboxPreferencesScreen(
                    InboxState(session = session, preferences = InboxPreferences(false, true, 120)),
                    "de",
                    {},
                    { saves++ },
                )
            }
        }
        show("inbox-push-toggle")
        compose.onNodeWithTag("inbox-push-toggle").assertIsEnabled().assertIsOff()
        show("inbox-reminders-toggle")
        compose.onNodeWithTag("inbox-reminders-toggle").assertIsNotEnabled().assertIsOn()
        show("inbox-reminder-lead-120")
        compose.onNodeWithTag("inbox-reminder-lead-120").assertIsNotEnabled().assertIsSelected()
        assertEquals(0, saves)
    }

    @Test
    fun twoHourChoiceRequiresBothConsentsAndRemainsReachableAtLargeText() {
        val state =
            mutableStateOf(
                InboxState(session = session, preferences = InboxPreferences(true, false, 60))
            )
        var requested: InboxPreferences? = null
        compose.setContent {
            val density = LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(density, 2f)) {
                UacTheme("dark") {
                    InboxPreferencesScreen(state.value, "uk", {}, { requested = it })
                }
            }
        }
        show("inbox-reminder-lead-120")
        compose.onNodeWithTag("inbox-reminder-lead-120").assertIsNotEnabled()
        compose.runOnIdle {
            state.value = state.value.copy(preferences = InboxPreferences(true, true, 60))
        }
        show("inbox-reminder-lead-120")
        compose.onNodeWithTag("inbox-reminder-lead-120").assertIsEnabled().performClick()
        assertEquals(InboxPreferences(true, true, 120), requested)
        // A tap sends an intent; only the parent's confirmed server state changes the displayed
        // selection.
        compose.onNodeWithTag("inbox-reminder-lead-120").assertIsNotSelected()
    }
}
