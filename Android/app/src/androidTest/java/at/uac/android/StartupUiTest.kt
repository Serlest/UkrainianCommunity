package at.uac.android

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.design.UacTheme
import at.uac.android.feature.startup.StartupScreen
import at.uac.android.feature.startup.StartupState
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Pure presentation tests. Neither the fake media slot nor these tests prove native codec playback.
 */
@RunWith(AndroidJUnit4::class)
class StartupUiTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun reducedMotionNeverCreatesPlayerAndKeepsAccessibleStaticBrand() {
        var playerCompositions = 0
        compose.setContent {
            UacTheme("light") {
                StartupScreen("uk", reduceMotion = true, playbackAllowed = true) {
                    playerCompositions++
                }
            }
        }
        compose.onNodeWithTag("startup.static").assertIsDisplayed()
        compose
            .onNodeWithTag("startup.logo")
            .assertIsDisplayed()
            .assertContentDescriptionEquals("Ukrainian Community")
        compose
            .onNodeWithTag("startup.progress")
            .assertContentDescriptionEquals("Завантаження UAC…")
        compose.onNodeWithTag("startup.video").assertDoesNotExist()
        compose.runOnIdle { assertEquals(0, playerCompositions) }
    }

    @Test
    fun privacyOrBackgroundPlaybackDisallowanceDoesNotCreateNativePlayer() {
        var playerCompositions = 0
        compose.setContent {
            UacTheme("dark") {
                StartupScreen("de", reduceMotion = false, playbackAllowed = false) {
                    playerCompositions++
                }
            }
        }
        compose.onNodeWithTag("startup.static").assertIsDisplayed()
        compose
            .onNodeWithTag("startup.progress")
            .assertContentDescriptionEquals("UAC wird geladen …")
        compose.runOnIdle { assertEquals(0, playerCompositions) }
    }

    @Test
    fun motionPreferenceChangeImmediatelyRemovesDecorativeMedia() {
        val reduced = mutableStateOf(false)
        var mediaComposed = false
        compose.setContent {
            UacTheme {
                StartupScreen("de", reduced.value, playbackAllowed = true) { modifier ->
                    DisposableEffect(Unit) {
                        mediaComposed = true
                        onDispose { mediaComposed = false }
                    }
                    // The host modifier already owns startup.video. A second test
                    // tag on the same semantics node does not replace that tag.
                    Box(modifier)
                }
            }
        }
        compose.onNodeWithTag("startup.video").assertExists()
        compose.runOnIdle { assertTrue(mediaComposed) }
        compose.runOnIdle { reduced.value = true }
        compose.onNodeWithTag("startup.video").assertDoesNotExist()
        compose.runOnIdle { assertFalse(mediaComposed) }
        compose.onNodeWithTag("startup.logo").assertExists()
        compose.onNodeWithTag("startup.progress").assertExists()
    }

    @Test
    fun brandAndLoadingRemainReachableAtTwoHundredPercentInDarkMode() {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                UacTheme("dark") {
                    StartupScreen("uk", reduceMotion = true, playbackAllowed = false)
                }
            }
        }
        compose.onNodeWithTag("startup.logo").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("startup.progress").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun initialAuthCompletionRemovesStartupWithoutWaitingForVideoOrReopening() {
        val state = mutableStateOf(StartupState())
        compose.setContent {
            UacTheme {
                if (state.value.covered)
                    StartupScreen("de", reduceMotion = true, playbackAllowed = false)
                else Box(Modifier.testTag("content"))
            }
        }
        compose.onNodeWithTag("startup.splash").assertExists()
        compose.onNodeWithTag("content").assertDoesNotExist()
        compose.runOnIdle { state.value = state.value.observe(false) }
        compose.onNodeWithTag("startup.splash").assertDoesNotExist()
        compose.onNodeWithTag("content").assertExists()
        compose.runOnIdle { state.value = state.value.observe(true) }
        compose.onNodeWithTag("startup.splash").assertDoesNotExist()
        compose.onNodeWithTag("content").assertExists()
    }
}
