package at.uac.android

import android.view.View
import android.view.Window
import android.view.WindowManager.LayoutParams
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.window.DialogWindowProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalWindowPrivacy
import at.uac.android.core.ProtectedDialog
import at.uac.android.core.ProtectedDropdownMenu
import at.uac.android.core.WindowPrivacy
import at.uac.android.core.WindowSecurity
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Actual Window flags/ownership, with real Compose editors; native unlock is a separate journey.
 */
@RunWith(AndroidJUnit4::class)
class WindowPrivacyUiTest {
    @get:Rule val compose = createComposeRule()
    private val privacy = WindowPrivacy()
    private lateinit var main: Window

    @After
    fun closeRegistry() {
        compose.runOnIdle { privacy.close() }
    }

    private fun windowOf(view: View): Window {
        var parent = view.parent
        while (parent != null) {
            (parent as? DialogWindowProvider)?.let {
                return it.window
            }
            parent = parent.parent
        }
        error("Protected dialog window was not found")
    }

    private fun assertProtected(window: Window) {
        assertEquals(PROTECTION_FLAGS, window.attributes.flags and PROTECTION_FLAGS)
        assertEquals(
            View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS,
            window.decorView.importantForAccessibility,
        )
    }

    @Test
    fun openDialogAndMainEditorAreProtectedSynchronouslyWithoutLosingDrafts() {
        val mainDraft = mutableStateOf("")
        val dialogDraft = mutableStateOf("")
        val open = mutableStateOf(false)
        lateinit var dialog: Window
        compose.setContent {
            main = requireNotNull(LocalActivity.current).window
            DisposableEffect(main) {
                val lease = privacy.register(main)
                onDispose { lease.close() }
            }
            CompositionLocalProvider(LocalWindowPrivacy provides privacy) {
                MaterialTheme {
                    Column {
                        OutlinedTextField(
                            mainDraft.value,
                            { mainDraft.value = it },
                            Modifier.testTag("private-main-draft"),
                        )
                        Button({ open.value = true }, Modifier.testTag("private-open")) {
                            Text("Open")
                        }
                    }
                    if (open.value)
                        ProtectedDialog({ open.value = false }) {
                            val view = LocalView.current
                            SideEffect { dialog = windowOf(view) }
                            Column {
                                OutlinedTextField(
                                    dialogDraft.value,
                                    { dialogDraft.value = it },
                                    Modifier.testTag("private-dialog-draft"),
                                )
                                Button({ open.value = false }, Modifier.testTag("private-close")) {
                                    Text("Close")
                                }
                            }
                        }
                }
            }
        }
        compose.onNodeWithTag("private-main-draft").performTextInput("Unsaved profile")
        compose.onNodeWithTag("private-open").performClick()
        compose.onNodeWithTag("private-dialog-draft").performTextInput("Unsaved form")
        var mainFlags = 0
        var dialogFlags = 0
        var mainAccessibility = 0
        var dialogAccessibility = 0
        compose.runOnIdle {
            mainFlags = main.attributes.flags
            dialogFlags = dialog.attributes.flags
            mainAccessibility = main.decorView.importantForAccessibility
            dialogAccessibility = dialog.decorView.importantForAccessibility
            privacy.update(secure = true, blocked = true)
            // Same call stack: no recomposition/extra frame is needed for these two windows.
            assertProtected(main)
            assertProtected(dialog)
        }
        compose.runOnIdle {
            // Compose has now also reapplied DialogProperties; neither flag may be lost.
            assertProtected(main)
            assertProtected(dialog)
            privacy.update(secure = false, blocked = false)
            assertEquals(mainFlags and PROTECTION_FLAGS, main.attributes.flags and PROTECTION_FLAGS)
            assertEquals(
                dialogFlags and PROTECTION_FLAGS,
                dialog.attributes.flags and PROTECTION_FLAGS,
            )
            assertEquals(mainAccessibility, main.decorView.importantForAccessibility)
            assertEquals(dialogAccessibility, dialog.decorView.importantForAccessibility)
        }
        compose
            .onNodeWithTag("private-dialog-draft")
            .assertTextEquals("Unsaved form")
            .performTextInput(" preserved")
        compose.onNodeWithTag("private-close").performClick()
        compose
            .onNodeWithTag("private-main-draft")
            .assertTextEquals("Unsaved profile")
            .performTextInput(" preserved")
        compose.runOnIdle {
            assertEquals("Unsaved form preserved", dialogDraft.value)
            assertEquals("Unsaved profile preserved", mainDraft.value)
        }
    }

    @Test
    fun dialogRegisteredDuringBlockImmediatelyInheritsProtection() {
        val open = mutableStateOf(false)
        lateinit var dialog: Window
        compose.setContent {
            main = requireNotNull(LocalActivity.current).window
            CompositionLocalProvider(LocalWindowPrivacy provides privacy) {
                MaterialTheme {
                    if (open.value)
                        ProtectedDialog({}) {
                            val view = LocalView.current
                            SideEffect { dialog = windowOf(view) }
                            Text("Private synthetic form")
                        }
                }
            }
        }
        compose.runOnIdle {
            privacy.update(secure = true, blocked = true)
            open.value = true
        }
        compose.runOnIdle { assertProtected(dialog) }
        compose.runOnIdle { privacy.update(secure = false, blocked = false) }
        compose.runOnIdle { assertEquals(0, dialog.attributes.flags and PROTECTION_FLAGS) }
    }

    @Test
    fun independentMfaSecureLeaseSurvivesUnlockAndRegistryClosure() {
        compose.setContent {
            main = requireNotNull(LocalActivity.current).window
            Text("Synthetic")
        }
        compose.runOnIdle {
            val original = main.attributes.flags and LayoutParams.FLAG_SECURE
            val registration = privacy.register(main)
            val mfa = WindowSecurity.acquire(main)
            try {
                privacy.update(secure = true, blocked = true)
                privacy.update(secure = false, blocked = false)
                assertEquals(
                    LayoutParams.FLAG_SECURE,
                    main.attributes.flags and LayoutParams.FLAG_SECURE,
                )
                registration.close()
                registration.close()
                privacy.close()
                assertEquals(
                    LayoutParams.FLAG_SECURE,
                    main.attributes.flags and LayoutParams.FLAG_SECURE,
                )
            } finally {
                mfa.close()
            }
            assertEquals(original, main.attributes.flags and LayoutParams.FLAG_SECURE)
        }
    }

    @Test
    fun duplicateRegistrationsAndPreexistingFlagsRetainTheirOriginalOwners() {
        compose.setContent {
            main = requireNotNull(LocalActivity.current).window
            Text("Synthetic")
        }
        compose.runOnIdle {
            val originalFlags = main.attributes.flags
            val originalAccessibility = main.decorView.importantForAccessibility
            main.addFlags(LayoutParams.FLAG_SECURE or LayoutParams.FLAG_NOT_FOCUSABLE)
            main.decorView.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
            try {
                val first = privacy.register(main)
                val second = privacy.register(main)
                privacy.update(secure = true, blocked = true)
                first.close()
                first.close()
                assertProtected(main)
                second.close()
                assertEquals(
                    LayoutParams.FLAG_SECURE or LayoutParams.FLAG_NOT_FOCUSABLE,
                    main.attributes.flags and PROTECTION_FLAGS,
                )
                assertEquals(
                    View.IMPORTANT_FOR_ACCESSIBILITY_YES,
                    main.decorView.importantForAccessibility,
                )
            } finally {
                main.setFlags(originalFlags, PROTECTION_FLAGS)
                main.decorView.importantForAccessibility = originalAccessibility
            }
        }
    }

    @Test
    fun privateDropdownClosesDuringProtectionWithoutResettingItsParentDraft() {
        val draft = mutableStateOf("Synthetic unsaved draft")
        lateinit var selectionWindow: Window
        compose.setContent {
            main = requireNotNull(LocalActivity.current).window
            CompositionLocalProvider(LocalWindowPrivacy provides privacy) {
                MaterialTheme {
                    Column {
                        OutlinedTextField(
                            draft.value,
                            { draft.value = it },
                            Modifier.testTag("menu-parent-draft"),
                        )
                        ProtectedDropdownMenu(expanded = true, onDismissRequest = {}) {
                            val view = LocalView.current
                            SideEffect { selectionWindow = windowOf(view) }
                            DropdownMenuItem(
                                text = { Text("Private menu option") },
                                onClick = {},
                                modifier = Modifier.testTag("private-menu-option"),
                            )
                        }
                    }
                }
            }
        }
        compose.onNodeWithTag("private-menu-option").assertExists()
        compose.runOnIdle {
            privacy.update(secure = true, blocked = true)
            assertProtected(selectionWindow)
        }
        compose.onNodeWithTag("private-menu-option").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals("Synthetic unsaved draft", draft.value)
            privacy.update(secure = false, blocked = false)
        }
        compose.onNodeWithTag("private-menu-option").assertExists()
        compose.onNodeWithTag("menu-parent-draft").assertTextEquals("Synthetic unsaved draft")
    }

    private companion object {
        const val PROTECTION_FLAGS =
            LayoutParams.FLAG_SECURE or
                LayoutParams.FLAG_NOT_TOUCHABLE or
                LayoutParams.FLAG_NOT_FOCUSABLE
    }
}
