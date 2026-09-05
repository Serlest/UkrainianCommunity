package at.uac.android

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.design.UacTheme
import at.uac.android.feature.reminders.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReminderUiTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun compositionNeverRequestsPermissionAndDisabledStateCannotRunLocalTest() {
        var requests = 0
        var tests = 0
        compose.setContent {
            UacTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    ReminderSettingsCard(ReminderState(), "de", { requests++ }, {}, {}, { tests++ })
                }
            }
        }
        compose.runOnIdle {
            assertEquals(0, requests)
            assertEquals(0, tests)
        }
        compose.onNodeWithTag("reminders-local-test").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("reminders-permission-request").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, requests) }
    }

    @Test
    fun channelDeniedExposesSettingsWithoutPretendingAppPermissionWasDenied() {
        var settings = 0
        compose.setContent {
            UacTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    ReminderSettingsCard(
                        ReminderState(permission = ReminderPermission.CHANNEL_DENIED),
                        "uk",
                        {},
                        { settings++ },
                        {},
                        {},
                    )
                }
            }
        }
        compose.onNodeWithTag("reminders-permission-request").assertDoesNotExist()
        compose.onNodeWithTag("reminders-system-settings").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, settings) }
        compose.onNodeWithTag("reminders-local-test").assertIsNotEnabled()
    }

    @Test
    fun scheduledIsNotDeliveredAndLocalTestRemainsExplicitAtTwoHundredPercent() {
        var tests = 0
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                UacTheme("dark") {
                    Column(Modifier.verticalScroll(rememberScrollState())) {
                        ReminderSettingsCard(
                            ReminderState(ReminderStage.SCHEDULED, ReminderPermission.ALLOWED, 2),
                            "uk",
                            {},
                            {},
                            {},
                            { tests++ },
                        )
                    }
                }
            }
        }
        compose
            .onNodeWithTag("reminders-status")
            .performScrollTo()
            .assertTextContains("Це ще не підтверджує доставку.", substring = true)
        compose
            .onNodeWithTag("reminders-local-test")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        compose.runOnIdle { assertEquals(1, tests) }
    }

    @Test
    fun storageFailureKeepsRetryReachableAndNeverShowsScheduledSuccess() {
        var retries = 0
        compose.setContent {
            UacTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    ReminderSettingsCard(
                        ReminderState(
                            ReminderStage.FAILED,
                            ReminderPermission.ALLOWED,
                            error = ReminderFailure.STORAGE,
                        ),
                        "de",
                        {},
                        {},
                        { retries++ },
                        {},
                    )
                }
            }
        }
        compose
            .onNodeWithTag("reminders-status")
            .performScrollTo()
            .assertTextContains("nicht sicher gespeichert", substring = true)
        compose.onNodeWithTag("reminders-retry").performScrollTo().performClick()
        compose.onNodeWithTag("reminders-local-test").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(1, retries) }
    }

    @Test
    fun requestedLocalTestClearlyDoesNotClaimCloudPushProof() {
        compose.setContent {
            UacTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    ReminderSettingsCard(
                        ReminderState(
                            ReminderStage.SCHEDULED,
                            ReminderPermission.ALLOWED,
                            localTestRequested = true,
                        ),
                        "de",
                        {},
                        {},
                        {},
                        {},
                    )
                }
            }
        }
        compose
            .onNodeWithTag("reminders-local-test-requested")
            .performScrollTo()
            .assertTextContains("kein Cloud-Push-Test", substring = true)
    }
}
