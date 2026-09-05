package at.uac.android

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.applock.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Content/controls only; root window/TalkBack/recents and native prompt proof are separate. */
@RunWith(AndroidJUnit4::class)
class AppLockUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = AppLockSession("synthetic-lock-ui", 1)

    private fun locked() =
        AppLockState(
            session,
            enabled = true,
            foreground = true,
            availability = AppLockAvailability(true, true),
        )

    @Test
    fun explicitUnlockAndPasswordFallbackRemainReachableAtLargeText() {
        var unlocks = 0
        var passwords = 0
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                MaterialTheme {
                    AppLockScreen(
                        locked().copy(error = AppLockProblem.FAILED),
                        "uk",
                        { unlocks++ },
                        { passwords++ },
                        {},
                    )
                }
            }
        }
        compose.runOnIdle { assertEquals(0, unlocks) }
        compose.onNodeWithTag("app-lock-unlock").performScrollTo().performClick()
        compose.onNodeWithTag("app-lock-password").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(1, unlocks)
            assertEquals(1, passwords)
        }
    }

    @Test
    fun settingsDoNotOptimisticallyEnableAndPendingDisablesDuplicateToggle() {
        var requested: Boolean? = null
        val state = mutableStateOf(locked().copy(enabled = false))
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    AppLockSettingsSection(state.value, "de") { requested = it }
                }
            }
        }
        compose
            .onNodeWithTag("app-lock-toggle")
            .performScrollTo()
            .assertIsOff()
            .performClick()
            .assertIsOff()
        compose.runOnIdle {
            assertEquals(true, requested)
            state.value = state.value.copy(authenticating = true)
        }
        compose.onNodeWithTag("app-lock-toggle").assertIsNotEnabled()
    }

    @Test
    fun unavailableDeviceDoesNotOfferUnlockButPasswordPathRemains() {
        compose.setContent {
            MaterialTheme {
                AppLockScreen(
                    locked()
                        .copy(
                            availability = AppLockAvailability(),
                            error = AppLockProblem.UNAVAILABLE,
                        ),
                    "de",
                    {},
                    {},
                    {},
                )
            }
        }
        compose.onNodeWithTag("app-lock-unlock").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("app-lock-password").performScrollTo().assertIsEnabled()
        compose.onNodeWithTag("app-lock-error").assertExists()
    }

    @Test
    fun inactivePrivacyContentExposesNoAccountOrUnlockControls() {
        compose.setContent {
            MaterialTheme { AppLockScreen(locked().copy(foreground = false), "uk", {}, {}, {}) }
        }
        compose.onNodeWithText("UAC").assertExists()
        compose.onNodeWithTag("app-lock-unlock").assertDoesNotExist()
        compose.onNodeWithTag("app-lock-password").assertDoesNotExist()
        compose.onNodeWithText(session.uid).assertDoesNotExist()
    }

    @Test
    fun enablingProtectionKeepsExplicitCancelReachableOnPrivacyCover() {
        var cancelled = 0
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                MaterialTheme {
                    AppLockScreen(
                        locked().copy(enabled = false, authenticating = true),
                        "de",
                        {},
                        {},
                        { cancelled++ },
                    )
                }
            }
        }
        compose.onNodeWithTag("app-lock-confirmation-progress").assertExists()
        compose.onNodeWithTag("app-lock-unlock").assertDoesNotExist()
        compose.onNodeWithTag("app-lock-password").assertDoesNotExist()
        compose.onNodeWithTag("app-lock-cancel").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, cancelled) }
    }

    @Test
    fun cancelledOrFailedSignOutCannotPresentAnUnlockedScreen() {
        val state = mutableStateOf(locked().copy(authenticating = true))
        var cancellations = 0
        compose.setContent {
            MaterialTheme { AppLockScreen(state.value, "de", {}, {}, { cancellations++ }) }
        }
        compose.onNodeWithTag("app-lock-password").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("app-lock-cancel").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(1, cancellations)
            state.value = locked().copy(error = AppLockProblem.SIGN_OUT)
        }
        compose.onNodeWithTag("app-lock-error").assertExists()
        compose.onNodeWithTag("app-lock-unlock").performScrollTo().assertExists()
    }
}
