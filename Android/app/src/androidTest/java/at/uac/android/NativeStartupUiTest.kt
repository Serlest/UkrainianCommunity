package at.uac.android

import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.Build
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.material3.Text
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.UacTheme
import at.uac.android.feature.startup.StartupScreen
import at.uac.android.feature.startup.StartupTextureView
import at.uac.android.feature.startup.StartupVideoAsset
import at.uac.android.feature.startup.startupAspectFit
import at.uac.android.feature.startup.supportedStartupVideo
import java.io.File
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Actual bundled codec/TextureView frames. No fake media callback or Auth readiness change. */
@RunWith(AndroidJUnit4::class)
class NativeStartupUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private fun textures(view: View): List<TextureView> =
        when (view) {
            is TextureView -> listOf(view)
            is ViewGroup -> (0 until view.childCount).flatMap { textures(view.getChildAt(it)) }
            else -> emptyList()
        }

    @Test
    fun bundledVideoRendersNewFramesPausesAndReleasesWhenStartupEnds() {
        assumeTrue(
            "Explicit native media test required; skip is not codec proof",
            InstrumentationRegistry.getArguments().getString("expectNativeStartup") == "true",
        )
        check(
            (Build.VERSION.SDK_INT == 37 &&
                Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone") &&
                instrumentation.targetContext.packageName == "at.uac.android.local") ||
                isExplicitApi26CompatibilityAvd()
        )
        val expectedAsset =
            StartupVideoAsset.valueOf(
                requireNotNull(
                    InstrumentationRegistry.getArguments().getString("expectStartupAsset")
                ) {
                    "Root must declare the expected actual capability-selected asset"
                }
            )
        assertEquals("Actual regular AVC capabilities", expectedAsset, supportedStartupVideo())
        val shown = mutableStateOf(true)
        val activity = compose.activity
        compose.setContent {
            UacTheme("dark") {
                if (shown.value) StartupScreen("de", reduceMotion = false, playbackAllowed = true)
                else Text("Synthetic ready content", Modifier.testTag("startup-test-ready"))
            }
        }
        compose.onNodeWithTag("startup-test-ready").assertDoesNotExist()
        var texture: StartupTextureView? = null
        var firstFrameUpdates = 0L
        compose.waitUntil(20_000) {
            instrumentation.runOnMainSync {
                texture = textures(activity.window.decorView).singleOrNull() as? StartupTextureView
                firstFrameUpdates = texture?.takeIf { it.alpha == 1f }?.renderedUpdates ?: 0L
            }
            firstFrameUpdates > 0L
        }
        val original = requireNotNull(texture)
        val initialUpdates = firstFrameUpdates
        var firstGeneration = 0L
        instrumentation.runOnMainSync {
            firstGeneration = original.playbackGeneration
            assertEquals(expectedAsset, original.asset)
            assertEquals(expectedAsset.width to expectedAsset.height, original.decodedSize)
            val expectedFit =
                requireNotNull(
                    startupAspectFit(
                        original.width,
                        original.height,
                        expectedAsset.width,
                        expectedAsset.height,
                    )
                )
            val matrix = FloatArray(9)
            original.getTransform(Matrix()).getValues(matrix)
            assertEquals(expectedFit.scaleX, matrix[Matrix.MSCALE_X], 0.001f)
            assertEquals(expectedFit.scaleY, matrix[Matrix.MSCALE_Y], 0.001f)
        }
        var advancing = false
        compose.waitUntil(5_000) {
            instrumentation.runOnMainSync {
                advancing =
                    original.alpha == 1f &&
                        original.playbackGeneration == firstGeneration &&
                        original.renderedUpdates > initialUpdates
            }
            advancing
        }
        val screenshot = instrumentation.uiAutomation.takeScreenshot()
        File(instrumentation.targetContext.cacheDir, "startup-native-frame.png")
            .outputStream()
            .use {
                screenshot.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        screenshot.recycle()

        compose.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        var paused = false
        compose.waitUntil(5_000) {
            instrumentation.runOnMainSync {
                paused = original.alpha == 0f && !original.hasActivePlayer
            }
            paused
        }
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        var resumed = false
        var resumedGeneration = 0L
        var resumedUpdates = 0L
        compose.waitUntil(20_000) {
            instrumentation.runOnMainSync {
                resumed =
                    original.alpha == 1f &&
                        original.playbackGeneration > firstGeneration &&
                        original.renderedUpdates > 0
                if (resumed) {
                    resumedGeneration = original.playbackGeneration
                    resumedUpdates = original.renderedUpdates
                }
            }
            resumed
        }
        // SurfaceTexture timestamps have no shared zero point between MediaPlayer instances.
        // Prove two real updates within the NEW generation instead of comparing old timestamps.
        compose.waitUntil(5_000) {
            instrumentation.runOnMainSync {
                advancing =
                    original.alpha == 1f &&
                        original.playbackGeneration == resumedGeneration &&
                        original.renderedUpdates > resumedUpdates
            }
            advancing
        }
        compose.runOnIdle { shown.value = false }
        compose.onNodeWithTag("startup.splash").assertDoesNotExist()
        compose.onNodeWithTag("startup-test-ready").assertIsDisplayed()
        instrumentation.runOnMainSync {
            assertTrue(textures(activity.window.decorView).isEmpty())
            assertFalse(original.isAttachedToWindow)
            assertEquals(0f, original.alpha, 0f)
            assertFalse(original.hasActivePlayer)
        }
    }
}
