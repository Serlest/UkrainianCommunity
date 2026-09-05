package at.uac.android

import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.view.View
import android.view.Window
import android.view.WindowManager
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.window.DialogWindowProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalWindowPrivacy
import at.uac.android.core.WindowPrivacy
import at.uac.android.design.UacTheme
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.userstatusmanagement.*
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Synthetic presentation only. No SDK account, TOTP claim, server fixture or mutation is created.
 */
@RunWith(AndroidJUnit4::class)
class UserStatusUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = ModerationSession("synthetic-status-manager", 8, "admin", true)
    private val id = "synthetic-status-target"
    private val time = Instant.parse("2026-09-03T12:00:00Z")

    @Before
    fun exactDisposableAvdOnly() {
        LocalEnvironment.requireSafe()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        assertEquals("at.uac.android.local", instrumentation.targetContext.packageName)
        fun property(key: String) =
            ParcelFileDescriptor.AutoCloseInputStream(
                    instrumentation.uiAutomation.executeShellCommand("getprop $key")
                )
                .bufferedReader()
                .use { it.readLine()?.trim().orEmpty() }
        val primary =
            Build.VERSION.SDK_INT == 37 &&
                Build.HARDWARE == "ranchu" &&
                Build.MODEL.startsWith("sdk_gphone") &&
                property("ro.kernel.qemu") == "1" &&
                property("ro.boot.qemu.avd_name") == "UAC_API_37_Play_ARM64"
        assertTrue(
            "Only the exact primary AVD or explicitly opted-in API26 compatibility AVD",
            primary || isExplicitApi26CompatibilityAvd(),
        )
    }

    private fun ready(action: UserStatusAction? = null, status: String = "active") =
        UserStatusState(
            session = actor,
            targetId = id,
            snapshot =
                UserStatusContract.snapshot(
                    id,
                    mapOf(
                        "id" to id,
                        "displayName" to "Synthetic Person",
                        "email" to "person@example.invalid",
                        "globalRole" to "user",
                        "accountStatus" to status,
                        "blockState" to status,
                        "warningCount" to 2L,
                        "statusReason" to "  Exact previous reason  ",
                        "updatedAt" to time,
                    ),
                ),
            fresh = true,
            journalReady = true,
            confirmation = action,
            confirmationStartedAt = time,
            suspensionZoneId = ZoneId.of("Europe/Vienna"),
        )

    private fun show(
        state: androidx.compose.runtime.State<UserStatusState>,
        language: String,
        actions: UserStatusActions,
    ) {
        compose.setContent {
            UacTheme(if (language == "uk") "dark" else "light") {
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    UserStatusPanel(state.value, language, actions)
                }
            }
        }
    }

    /** One actual scroll; wait for animation/layout settlement, never repeat scroll or click. */
    private fun scroll(tag: String): SemanticsNodeInteraction {
        val node = compose.onNodeWithTag(tag)
        node.performScrollTo()
        var previous: Rect? = null
        var since = SystemClock.uptimeMillis()
        compose.waitUntil(10_000) {
            val bounds = node.fetchSemanticsNode().boundsInWindow
            if (previous != bounds) {
                previous = bounds
                since = SystemClock.uptimeMillis()
            }
            node.isDisplayed() &&
                bounds.width > 0 &&
                bounds.height > 0 &&
                SystemClock.uptimeMillis() - since >= 120
        }
        return node.assertIsDisplayed()
    }

    private fun awaitIme(visible: Boolean) {
        compose.waitUntil(10_000) {
            compose
                .onNodeWithTag("user-status-confirm-scroll")
                .fetchSemanticsNode()
                .config[UserStatusDialogImeVisible] == visible
        }
    }

    private fun assertFullButtonInsideDialog(tag: String) {
        val node = compose.onNodeWithTag(tag).fetchSemanticsNode()
        val bounds = node.boundsInWindow
        val viewport =
            compose.onNodeWithTag("user-status-confirm-scroll").fetchSemanticsNode().boundsInWindow
        val density =
            InstrumentationRegistry.getInstrumentation()
                .targetContext
                .resources
                .displayMetrics
                .density
        val unclipped = compose.onNodeWithTag(tag).getUnclippedBoundsInRoot()
        assertTrue("48dp action height", node.boundsInRoot.height / density >= 48f)
        assertEquals(
            "No vertically clipped action",
            (unclipped.bottom - unclipped.top).value * density,
            bounds.height,
            1.5f,
        )
        assertEquals(
            "No horizontally clipped action",
            (unclipped.right - unclipped.left).value * density,
            bounds.width,
            1.5f,
        )
        assertTrue(
            "Action is inside the current IME-resized viewport",
            bounds.top >= viewport.top - 1 &&
                bounds.bottom <= viewport.bottom + 1 &&
                bounds.left >= viewport.left - 1 &&
                bounds.right <= viewport.right + 1,
        )
    }

    @Test
    fun warningExplainsRemovalEvenRaceAndDoesNotSendOnOpen() {
        val state = mutableStateOf(ready())
        var sends = 0
        show(
            state,
            "de",
            UserStatusActions(request = { state.value = ready(it) }, confirm = { sends++ }),
        )
        scroll("user-status-action-WARN").assertIsEnabled().performClick()
        scroll("user-status-effect")
            .assertTextContains("hebt auch eine vorhandene Sperre", substring = true)
            .assertTextContains("nach dieser Vorschau", substring = true)
        scroll("user-status-previous-reason")
            .assertTextContains("  Exact previous reason  ", substring = true)
        scroll("user-status-confirm").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(0, sends) }
    }

    @Test
    fun restrictedTargetShowsOnlyIOSActionsNotWarning() {
        val state = mutableStateOf(ready(status = "suspendedUntil"))
        val requested = mutableListOf<UserStatusAction>()
        show(state, "uk", UserStatusActions(request = { requested.add(it) }))
        compose.onNodeWithTag("user-status-action-WARN").assertDoesNotExist()
        compose.onNodeWithTag("user-status-action-SUSPEND").assertDoesNotExist()
        scroll("user-status-action-RESTORE").performClick()
        compose.runOnIdle { assertEquals(listOf(UserStatusAction.RESTORE), requested) }
    }

    @Test
    fun reasonValidationAndCancelAreExplicitWithoutMutation() {
        val state = mutableStateOf(ready(UserStatusAction.RESTORE, "bannedPermanent"))
        var sends = 0
        show(
            state,
            "uk",
            UserStatusActions(
                editReason = { state.value = state.value.copy(reason = it) },
                confirm = { sends++ },
                cancel = { state.value = ready(status = "bannedPermanent") },
            ),
        )
        scroll("user-status-confirm").assertIsNotEnabled()
        scroll("user-status-reason").performTextReplacement("Причина відновлення")
        scroll("user-status-confirm").assertIsEnabled()
        scroll("user-status-cancel").performClick()
        compose.onNodeWithTag("user-status-confirm-scroll").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals(0, sends)
            assertEquals("", state.value.reason)
        }
    }

    @Test
    fun calendarChoicesHaveFullLabelsAndOneSelectionCallback() {
        val state = mutableStateOf(ready(UserStatusAction.SUSPEND))
        var changes = 0
        show(
            state,
            "uk",
            UserStatusActions(
                chooseDays = {
                    changes++
                    state.value = state.value.copy(suspensionDays = it)
                }
            ),
        )
        scroll("user-status-days-7").assertIsSelected().assertTextContains("7 днів")
        for (days in listOf(1, 14, 30)) scroll("user-status-days-$days").assertIsNotSelected()
        scroll("user-status-days-14").performClick().assertIsSelected()
        scroll("user-status-days-7").assertIsNotSelected()
        scroll("user-status-calendar-notice")
            .assertTextContains("не завжди має 24 години", substring = true)
        compose.runOnIdle {
            assertEquals(1, changes)
            assertEquals(14, state.value.suspensionDays)
        }
    }

    @Test
    fun pendingOnlyOffersReadOnlyReconciliationAndNeverResend() {
        val initial = ready()
        val entry =
            UserStatusContract.prepared(
                    actor,
                    initial.snapshot!!,
                    UserStatusAction.WARN,
                    "Synthetic reason",
                    null,
                    UUID.randomUUID().toString(),
                )
                .copy(phase = UserStatusPhase.DISPATCHED)
        val state = mutableStateOf(initial.copy(pending = listOf(entry)))
        var requests = 0
        var reconciles = 0
        show(
            state,
            "de",
            UserStatusActions(
                request = { requests++ },
                reconcile = {
                    assertEquals(entry, it)
                    reconciles++
                },
            ),
        )
        scroll("user-status-action-WARN").assertIsNotEnabled()
        scroll("user-status-reconcile-0").assertIsEnabled().performClick()
        compose.runOnIdle {
            assertEquals(0, requests)
            assertEquals(1, reconciles)
        }
    }

    @Test
    fun staleProjectionRemovesConfirmationBeforeAnotherFrameCanSubmit() {
        val state = mutableStateOf(ready(UserStatusAction.WARN).copy(reason = "Synthetic reason"))
        var sends = 0
        show(state, "de", UserStatusActions(confirm = { sends++ }))
        scroll("user-status-confirm").assertIsEnabled()
        compose.runOnIdle {
            state.value =
                state.value.copy(fresh = false, snapshot = null, confirmation = null, reason = "")
        }
        compose.onNodeWithTag("user-status-confirm-scroll").assertDoesNotExist()
        scroll("user-status-refresh").assertIsEnabled()
        compose.runOnIdle { assertEquals(0, sends) }
    }

    @Test
    fun confirmationShowsRawSnapshotNameEmailAndCanonicalTargetThenLegacyFallback() {
        val state = mutableStateOf(ready(UserStatusAction.WARN))
        show(state, "de", UserStatusActions())
        scroll("user-status-target").assertTextContains(id, substring = true)
        scroll("user-status-target-name").assertTextEquals("Synthetic Person")
        scroll("user-status-target-email").assertTextEquals("person@example.invalid")
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    snapshot = state.value.snapshot!!.copy(displayName = null, email = null)
                )
        }
        compose.onNodeWithTag("user-status-target-name").assertDoesNotExist()
        compose.onNodeWithTag("user-status-target-email").assertDoesNotExist()
        scroll("user-status-target").assertTextContains(id, substring = true)
    }

    @Test
    fun attemptFailureSurvivesReadProjectionAndDismissIsExplicitWithoutDuplicateError() {
        val outcome =
            UserStatusAttemptOutcome(id, UserStatusAction.WARN, failure = UserStatusFailure.STALE)
        val state =
            mutableStateOf(
                ready()
                    .copy(
                        targetId = null,
                        snapshot = null,
                        fresh = false,
                        attemptOutcome = outcome,
                        error = UserStatusFailure.STALE,
                    )
            )
        var dismissals = 0
        var requests = 0
        show(
            state,
            "de",
            UserStatusActions(
                request = { requests++ },
                dismissOutcome = {
                    dismissals++
                    state.value = state.value.copy(attemptOutcome = null)
                },
            ),
        )
        scroll("user-status-outcome-target").assertTextContains(id, substring = true)
        scroll("user-status-attempt-error").assertTextContains("geändert", substring = true)
        compose.onNodeWithTag("user-status-error").assertDoesNotExist()
        compose.onNodeWithTag("user-status-action-WARN").assertDoesNotExist()
        compose.runOnIdle {
            state.value = state.value.copy(loading = true, error = UserStatusFailure.OFFLINE)
        }
        scroll("user-status-attempt-error").assertTextContains("geändert", substring = true)
        scroll("user-status-error").assertTextContains("Serverstand", substring = true)
        scroll("user-status-outcome-dismiss").performClick()
        compose.onNodeWithTag("user-status-attempt-outcome").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals(1, dismissals)
            assertEquals(0, requests)
        }
    }

    @Test
    fun acceptedOutcomeStaysDistinctFromReadFailureAndHiddenScopeRemovesIt() {
        val state =
            mutableStateOf(
                ready()
                    .copy(
                        targetId = null,
                        snapshot = null,
                        fresh = false,
                        error = UserStatusFailure.OFFLINE,
                        attemptOutcome =
                            UserStatusAttemptOutcome(
                                id,
                                UserStatusAction.BAN,
                                observation = UserStatusObservation.CONFIRMED_CURRENT,
                            ),
                    )
            )
        show(state, "uk", UserStatusActions())
        scroll("user-status-outcome-target").assertTextContains(id, substring = true)
        scroll("user-status-observation").assertTextContains("Зміну підтверджено", substring = true)
        scroll("user-status-error")
            .assertTextContains("Стан сервера не підтверджено", substring = true)
        compose.runOnIdle { state.value = UserStatusState() }
        compose.onNodeWithTag("user-status-attempt-outcome").assertDoesNotExist()
    }

    @Test
    fun rejectedPasteProjectionKeepsOldTextAndBlocksSendUntilValidEdit() {
        val state =
            mutableStateOf(
                ready(UserStatusAction.WARN)
                    .copy(reason = "Old accepted reason", reasonRejected = true)
            )
        var sends = 0
        show(
            state,
            "de",
            UserStatusActions(
                editReason = {
                    state.value = state.value.copy(reason = it, reasonRejected = false)
                },
                confirm = {
                    sends++
                    state.value = state.value.copy(busy = true)
                },
            ),
        )
        scroll("user-status-reason").assertTextContains("Old accepted reason")
        scroll("user-status-reason-rejected").assertTextContains("nicht ersetzt", substring = true)
        scroll("user-status-confirm").assertIsNotEnabled().performTouchInput { click() }
        compose.runOnIdle {
            assertEquals(0, sends)
            assertEquals("Old accepted reason", state.value.reason)
        }
        scroll("user-status-reason").performTextReplacement("Corrected reason")
        compose.onNodeWithTag("user-status-reason-rejected").assertDoesNotExist()
        scroll("user-status-confirm").assertIsEnabled().performClick()
        compose.runOnIdle {
            assertEquals(1, sends)
            assertEquals("Corrected reason", state.value.reason)
        }
    }

    /** Root runs on both exact AVDs at native font_scale=2.0, without an injected density. */
    @Test
    fun actualFont200ImeStableScrollSingleSubmitAndDisabledFocus() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals(2f, context.resources.configuration.fontScale, 0.01f)
        val state = mutableStateOf(ready(UserStatusAction.SUSPEND))
        var sends = 0
        show(
            state,
            "de",
            UserStatusActions(
                editReason = { state.value = state.value.copy(reason = it) },
                confirm = {
                    sends++
                    state.value = state.value.copy(busy = true)
                },
            ),
        )
        assertEquals(
            2f,
            compose
                .onNodeWithTag("user-status-confirm-scroll")
                .fetchSemanticsNode()
                .config[UserStatusDialogFontScale],
            0.01f,
        )
        scroll("user-status-reason").performClick().assertIsFocused()
        // Do not replace text while the native IME opening animation is still moving the window.
        awaitIme(true)
        scroll("user-status-reason")
            .performTextReplacement("Ausführliche synthetische Begründung. ".repeat(180))
        awaitIme(true)
        scroll("user-status-confirm").assertIsEnabled()
        assertFullButtonInsideDialog("user-status-confirm")
        compose.onNodeWithTag("user-status-confirm").performClick()
        compose.runOnIdle { assertEquals(1, sends) }
        awaitIme(false)
        scroll("user-status-confirm").assertIsNotEnabled().performTouchInput { click() }
        scroll("user-status-reason").assertIsNotEnabled().performTouchInput { click() }
        compose.onAllNodes(isFocused(), useUnmergedTree = true).assertCountEquals(0)
        compose.runOnIdle {
            assertEquals(1, sends)
            assertTrue(state.value.reason.length > 5_000)
        }
    }

    @Test
    fun actualProtectedWindowBlocksInputAndAccessibilityUnderPrivacy() {
        val privacy = WindowPrivacy()
        val state = mutableStateOf(ready(UserStatusAction.WARN).copy(reason = "Приватна причина"))
        try {
            compose.setContent {
                CompositionLocalProvider(LocalWindowPrivacy provides privacy) {
                    UacTheme("dark") { UserStatusPanel(state.value, "uk", UserStatusActions()) }
                }
            }
            val view =
                requireNotNull(
                        compose
                            .onNodeWithTag("user-status-confirm-scroll")
                            .fetchSemanticsNode()
                            .root as? ViewRootForTest
                    )
                    .view
            var parent = view.parent
            var window: Window? = null
            while (parent != null && window == null) {
                window = (parent as? DialogWindowProvider)?.window
                parent = parent.parent
            }
            val dialog = requireNotNull(window)
            compose.runOnIdle {
                privacy.update(secure = true, blocked = true)
                val required =
                    WindowManager.LayoutParams.FLAG_SECURE or
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                assertEquals(required, dialog.attributes.flags and required)
                assertEquals(
                    View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS,
                    dialog.decorView.importantForAccessibility,
                )
            }
            compose.runOnIdle {
                val required =
                    WindowManager.LayoutParams.FLAG_SECURE or
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                assertEquals(required, dialog.attributes.flags and required)
            }
        } finally {
            compose.runOnIdle {
                state.value = UserStatusState()
                privacy.close()
            }
        }
    }
}
