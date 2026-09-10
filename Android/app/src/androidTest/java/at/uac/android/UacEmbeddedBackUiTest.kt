package at.uac.android

import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.design.LocalEmbeddedNavigation
import at.uac.android.design.UacBackButton
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class UacEmbeddedBackUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun singleToolbarBackClosesLocalDetailBeforeParent() {
        val detail = mutableStateOf(true)
        var parentBacks = 0
        compose.setContent {
            MaterialTheme {
                BackHandler { parentBacks++ }
                Column {
                    TextButton(
                        { compose.activity.onBackPressedDispatcher.onBackPressed() },
                        Modifier.testTag("toolbar-back"),
                    ) {
                        Text("Back")
                    }
                    CompositionLocalProvider(LocalEmbeddedNavigation provides true) {
                        if (detail.value) {
                            UacBackButton(
                                { detail.value = false },
                                Modifier.testTag("detail-back"),
                            ) {
                                Text("Back")
                            }
                            Text("Detail", Modifier.testTag("detail"))
                        } else Text("List", Modifier.testTag("list"))
                    }
                }
            }
        }
        compose.onAllNodesWithText("Back").assertCountEquals(1)
        compose.onNodeWithTag("detail-back").assertDoesNotExist()
        compose.onNodeWithTag("toolbar-back").performClick()
        compose.onNodeWithTag("list").assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, parentBacks) }
        compose.onNodeWithTag("toolbar-back").performClick()
        compose.runOnIdle { assertEquals(1, parentBacks) }
    }

    @Test
    fun disabledSavingConsumesToolbarAndSystemBackWithoutClosing() {
        val saving = mutableStateOf(true)
        var localBacks = 0
        var parentBacks = 0
        compose.setContent {
            MaterialTheme {
                BackHandler { parentBacks++ }
                Column {
                    TextButton(
                        { compose.activity.onBackPressedDispatcher.onBackPressed() },
                        Modifier.testTag("toolbar-back"),
                    ) {
                        Text("Back")
                    }
                    CompositionLocalProvider(LocalEmbeddedNavigation provides true) {
                        UacBackButton(
                            { localBacks++ },
                            Modifier.testTag("local-back"),
                            enabled = !saving.value,
                        ) {
                            Text("Back")
                        }
                    }
                }
            }
        }
        compose.onNodeWithTag("toolbar-back").performClick()
        compose.runOnIdle {
            compose.activity.onBackPressedDispatcher.onBackPressed()
            assertEquals(0, localBacks)
            assertEquals(0, parentBacks)
            saving.value = false
        }
        compose.onNodeWithTag("toolbar-back").performClick()
        compose.runOnIdle {
            assertEquals(1, localBacks)
            assertEquals(0, parentBacks)
        }
    }

    @Test
    fun standaloneBackRemainsVisibleAndRespectsEnabledState() {
        val enabled = mutableStateOf(false)
        var backs = 0
        compose.setContent {
            MaterialTheme {
                UacBackButton(
                    { backs++ },
                    Modifier.testTag("standalone-back"),
                    enabled = enabled.value,
                ) {
                    Text("Back")
                }
            }
        }
        compose.onNodeWithTag("standalone-back").assertIsDisplayed().assertIsNotEnabled()
        compose.runOnIdle { enabled.value = true }
        compose.onNodeWithTag("standalone-back").assertIsEnabled().performClick()
        compose.runOnIdle { assertEquals(1, backs) }
    }
}
