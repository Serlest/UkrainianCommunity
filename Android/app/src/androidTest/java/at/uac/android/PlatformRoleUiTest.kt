package at.uac.android

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.view.View
import android.view.Window
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.window.DialogWindowProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalWindowPrivacy
import at.uac.android.core.WindowPrivacy
import at.uac.android.design.UacTheme
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.platformrolemanagement.*
import java.time.Instant
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
class PlatformRoleUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val actor = ModerationSession("synthetic-role-manager", 8, "owner", true)
    private val id = "synthetic-role-target"
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

    private fun ready(
        action: PlatformRoleAction? = null,
        status: String = "active",
        role: String = if (action == PlatformRoleAction.REMOVE) "admin" else "user",
    ) =
        PlatformRoleState(
            session = actor,
            targetId = id,
            snapshot =
                PlatformRoleRecovery.snapshot(
                    id,
                    mapOf(
                        "id" to id,
                        "displayName" to "Synthetic Person",
                        "email" to "person@example.invalid",
                        "globalRole" to role,
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
            targetAuth = if (role == "user") PlatformRoleTargetAuth(id, true, false) else null,
        )

    private fun show(
        state: androidx.compose.runtime.State<PlatformRoleState>,
        language: String,
        actions: PlatformRoleActions,
    ) {
        compose.setContent {
            UacTheme(if (language == "uk") "dark" else "light") {
                Column(
                    Modifier.fillMaxSize()
                        .testTag("platform-role-test-viewport")
                        .verticalScroll(rememberScrollState())
                ) {
                    PlatformRolePanel(state.value, language, actions)
                }
            }
        }
    }

    /** One actual scroll; wait for animation/layout settlement, never repeat scroll or click. */
    private fun scroll(tag: String): SemanticsNodeInteraction {
        settleViewport()
        val node = compose.onNodeWithTag(tag)
        val before = node.fetchSemanticsNode().boundsInWindow
        val trace = mutableListOf<Rect>()
        node.performScrollTo()
        var previous: Rect? = null
        var since = SystemClock.uptimeMillis()
        try {
            compose.waitUntil(10_000) {
                val bounds = node.fetchSemanticsNode().boundsInWindow
                if (previous != bounds) {
                    if (trace.size < 8) trace.add(bounds)
                    previous = bounds
                    since = SystemClock.uptimeMillis()
                }
                node.isDisplayed() &&
                    bounds.width > 0 &&
                    bounds.height > 0 &&
                    SystemClock.uptimeMillis() - since >= 120
            }
        } catch (error: Exception) {
            // Test-only, exact synthetic AVDs: bounded layout evidence, never auth/contact data.
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val context = instrumentation.targetContext
            val bounds = runCatching { node.fetchSemanticsNode().boundsInWindow }.getOrNull()
            val root = runCatching {
                compose
                    .onNodeWithTag("platform-role-confirm-scroll")
                    .fetchSemanticsNode()
                    .boundsInWindow
            }
                .getOrNull()
            val ime = runCatching {
                compose
                    .onNodeWithTag("platform-role-confirm-scroll")
                    .fetchSemanticsNode()
                    .config[PlatformRoleDialogImeVisible]
            }
                .getOrNull()
            val evidence =
                "ROLE_UI_SCROLL tag=$tag before=$before trace=$trace bounds=$bounds root=$root ime=$ime orientation=" +
                    context.resources.configuration.orientation
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                java.io
                    .File(context.cacheDir, "platform-role-$tag-failure.png")
                    .outputStream()
                    .use {
                        bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                    }
                bitmap.recycle()
            }
            throw AssertionError(evidence, error)
        }
        return node.assertIsDisplayed()
    }

    private fun settleViewport() {
        val dialog =
            compose
                .onAllNodesWithTag("platform-role-confirm-scroll")
                .fetchSemanticsNodes()
                .isNotEmpty()
        val node =
            compose.onNodeWithTag(
                if (dialog) "platform-role-confirm-scroll" else "platform-role-test-viewport"
            )
        var previous: Rect? = null
        var since = SystemClock.uptimeMillis()
        val changes = mutableListOf<Rect>()
        // Native inset animations are not Compose-clock work. Same prerequisite as the existing
        // OrganizationReview UI tests, before (never instead of) the single real scroll.
        compose.waitUntil(10_000) {
            val bounds = node.fetchSemanticsNode().boundsInWindow
            if (bounds != previous) {
                previous = bounds
                since = SystemClock.uptimeMillis()
                if (changes.size < 8) changes.add(bounds)
            }
            bounds.width > 0 && bounds.height > 0 && SystemClock.uptimeMillis() - since >= 150
        }
        if (changes.size > 1)
            android.util.Log.i("UacRoleUiProbe", "VIEWPORT_SETTLED dialog=$dialog bounds=$changes")
    }

    private fun awaitIme(visible: Boolean) {
        compose.waitUntil(10_000) {
            compose
                .onNodeWithTag("platform-role-confirm-scroll")
                .fetchSemanticsNode()
                .config[PlatformRoleDialogImeVisible] == visible
        }
    }

    private fun assertFullButtonInsideDialog(tag: String) {
        val node = compose.onNodeWithTag(tag).fetchSemanticsNode()
        val bounds = node.boundsInWindow
        val viewport =
            compose
                .onNodeWithTag("platform-role-confirm-scroll")
                .fetchSemanticsNode()
                .boundsInWindow
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
    fun assignmentShowsExactTransitionAndMfaBoundaryWithoutSendingOnOpen() {
        val state = mutableStateOf(ready())
        var sends = 0
        show(
            state,
            "de",
            PlatformRoleActions(request = { state.value = ready(it) }, confirm = { sends++ }),
        )
        scroll("platform-role-action-ASSIGN").assertIsEnabled().performClick()
        scroll("platform-role-transition").assertTextContains(" → ", substring = true)
        scroll("platform-role-effect")
            .assertTextContains("keine Eigentümerrolle", substring = true)
            .assertTextContains("nicht automatisch aktiviert", substring = true)
        scroll("platform-role-race-notice")
            .assertTextContains("keine automatische Wiederholung", substring = true)
        scroll("platform-role-confirm").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(0, sends) }
    }

    @Test
    fun restrictedAdminCanRemoveWithoutAuthButRestrictedUserHasNoAssignment() {
        val state = mutableStateOf(ready(status = "deactivated", role = "admin"))
        val requested = mutableListOf<PlatformRoleAction>()
        show(
            state,
            "uk",
            PlatformRoleActions(
                request = {
                    requested.add(it)
                    state.value = ready(it, status = "deactivated")
                }
            ),
        )
        compose.onNodeWithTag("platform-role-action-ASSIGN").assertDoesNotExist()
        scroll("platform-role-action-REMOVE").assertIsEnabled().performClick()
        scroll("platform-role-effect").assertTextContains("не перешкоджає", substring = true)
        compose.onNodeWithTag("platform-role-confirm-eligibility").assertDoesNotExist()
        compose.runOnIdle {
            assertNull(state.value.targetAuth)
            assertEquals(listOf(PlatformRoleAction.REMOVE), requested)
            state.value = ready(status = "deactivated", role = "user")
        }
        compose.onNodeWithTag("platform-role-action-ASSIGN").assertDoesNotExist()
        compose.onNodeWithTag("platform-role-action-REMOVE").assertDoesNotExist()
        scroll("platform-role-read-only").assertIsDisplayed()
    }

    @Test
    fun reasonValidationAndCancelAreExplicitWithoutMutation() {
        val state = mutableStateOf(ready(PlatformRoleAction.REMOVE, "bannedPermanent"))
        var sends = 0
        show(
            state,
            "uk",
            PlatformRoleActions(
                editReason = { state.value = state.value.copy(reason = it) },
                confirm = { sends++ },
                cancel = { state.value = ready(status = "bannedPermanent") },
            ),
        )
        scroll("platform-role-confirm").assertIsNotEnabled()
        scroll("platform-role-reason").performTextReplacement("Причина відновлення")
        scroll("platform-role-confirm").assertIsEnabled()
        scroll("platform-role-cancel").performClick()
        compose.onNodeWithTag("platform-role-confirm-scroll").assertDoesNotExist()
        compose.runOnIdle {
            assertEquals(0, sends)
            assertEquals("", state.value.reason)
        }
    }

    @Test
    fun assignmentMetadataDenialHasSeparateExplanationAndReadOnlyRefresh() {
        val state =
            mutableStateOf(ready().copy(targetAuth = PlatformRoleTargetAuth(id, false, false)))
        var refreshes = 0
        var requests = 0
        show(state, "de", PlatformRoleActions(request = { requests++ }, refresh = { refreshes++ }))
        scroll("platform-role-eligibility").assertTextContains("nicht bestätigt", substring = true)
        scroll("platform-role-action-ASSIGN").assertIsNotEnabled().performTouchInput { click() }
        scroll("platform-role-metadata-refresh").assertIsEnabled().performClick()
        compose.runOnIdle {
            assertEquals(0, requests)
            assertEquals(1, refreshes)
            state.value = ready().copy(targetAuth = PlatformRoleTargetAuth(id, true, true))
        }
        scroll("platform-role-eligibility").assertTextContains("deaktiviert", substring = true)
        scroll("platform-role-action-ASSIGN").assertIsNotEnabled()
        compose.runOnIdle { state.value = ready().copy(targetAuth = null) }
        scroll("platform-role-eligibility").assertTextContains("fehlt", substring = true)
        scroll("platform-role-action-ASSIGN").assertIsNotEnabled()
        compose.runOnIdle { state.value = ready() }
        compose.onNodeWithTag("platform-role-eligibility").assertDoesNotExist()
        scroll("platform-role-action-ASSIGN").assertIsEnabled()
    }

    @Test
    fun staleAssignmentMetadataInOpenConfirmationNeverBlamesValidReasonOrAllowsSend() {
        val state =
            mutableStateOf(
                ready(PlatformRoleAction.ASSIGN)
                    .copy(
                        reason = "Valid reason",
                        targetAuth = PlatformRoleTargetAuth(id, false, false),
                    )
            )
        var sends = 0
        show(state, "uk", PlatformRoleActions(confirm = { sends++ }))
        scroll("platform-role-confirm-eligibility")
            .assertTextContains("не підтверджено", substring = true)
        compose.onNodeWithTag("platform-role-required").assertDoesNotExist()
        scroll("platform-role-confirm").assertIsNotEnabled().performTouchInput { click() }
        compose.runOnIdle { assertEquals(0, sends) }
    }

    @Test
    fun guestAdminNotReadyAndOwnerLossHideAllPrivatePanelState() {
        val state = mutableStateOf(ready(PlatformRoleAction.ASSIGN).copy(reason = "Private reason"))
        var sends = 0
        show(state, "de", PlatformRoleActions(confirm = { sends++ }))
        scroll("platform-role-target-email").assertIsDisplayed()
        for (session in
            listOf(
                null,
                actor.copy(role = "admin"),
                actor.copy(ready = false),
                actor.copy(role = "user"),
            )) {
            compose.runOnIdle {
                state.value =
                    ready(PlatformRoleAction.ASSIGN)
                        .copy(session = session, reason = "Private reason")
            }
            compose.onNodeWithTag("platform-role-panel").assertDoesNotExist()
            compose.onNodeWithTag("platform-role-confirm-scroll").assertDoesNotExist()
            compose.onNodeWithText("person@example.invalid").assertDoesNotExist()
            compose.onNodeWithText("Private reason").assertDoesNotExist()
        }
        compose.runOnIdle { assertEquals(0, sends) }
    }

    @Test
    fun pendingOnlyOffersReadOnlyReconciliationAndNeverResend() {
        val initial = ready()
        val entry =
            PlatformRoleRecovery.prepared(
                    actor,
                    initial.snapshot!!,
                    PlatformRoleAction.ASSIGN,
                    "Synthetic reason",
                    initial.targetAuth,
                    UUID.randomUUID().toString(),
                )
                .copy(phase = PlatformRolePhase.DISPATCHED)
        val state = mutableStateOf(initial.copy(pending = listOf(entry)))
        var requests = 0
        var reconciles = 0
        show(
            state,
            "de",
            PlatformRoleActions(
                request = { requests++ },
                reconcile = {
                    assertEquals(entry, it)
                    reconciles++
                },
            ),
        )
        scroll("platform-role-action-ASSIGN").assertIsNotEnabled()
        scroll("platform-role-reconcile-0").assertIsEnabled().performClick()
        compose.runOnIdle {
            assertEquals(0, requests)
            assertEquals(1, reconciles)
        }
    }

    @Test
    fun staleProjectionRemovesConfirmationBeforeAnotherFrameCanSubmit() {

        val state =
            mutableStateOf(ready(PlatformRoleAction.ASSIGN).copy(reason = "Synthetic reason"))
        var sends = 0
        show(state, "de", PlatformRoleActions(confirm = { sends++ }))
        scroll("platform-role-confirm").assertIsEnabled()
        compose.runOnIdle {
            state.value =
                state.value.copy(fresh = false, snapshot = null, confirmation = null, reason = "")
        }
        compose.onNodeWithTag("platform-role-confirm-scroll").assertDoesNotExist()
        scroll("platform-role-refresh").assertIsEnabled()
        compose.runOnIdle { assertEquals(0, sends) }
    }

    @Test
    fun confirmationShowsRawSnapshotNameEmailAndCanonicalTargetThenLegacyFallback() {
        val state = mutableStateOf(ready(PlatformRoleAction.ASSIGN))
        show(state, "de", PlatformRoleActions())
        scroll("platform-role-target").assertTextContains(id, substring = true)
        scroll("platform-role-target-name").assertTextEquals("Synthetic Person")
        scroll("platform-role-target-email").assertTextEquals("person@example.invalid")
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    snapshot = state.value.snapshot!!.copy(displayName = null, email = null)
                )
        }
        compose.onNodeWithTag("platform-role-target-name").assertDoesNotExist()
        compose.onNodeWithTag("platform-role-target-email").assertDoesNotExist()
        scroll("platform-role-target").assertTextContains(id, substring = true)
    }

    @Test
    fun attemptFailureSurvivesReadProjectionAndDismissIsExplicitWithoutDuplicateError() {
        val outcome =
            PlatformRoleAttemptOutcome(
                id,
                PlatformRoleAction.ASSIGN,
                failure = PlatformRoleFailure.STALE,
            )
        val state =
            mutableStateOf(
                ready()
                    .copy(
                        targetId = null,
                        snapshot = null,
                        fresh = false,
                        attemptOutcome = outcome,
                        error = PlatformRoleFailure.STALE,
                    )
            )
        var dismissals = 0
        var requests = 0
        show(
            state,
            "de",
            PlatformRoleActions(
                request = { requests++ },
                dismissOutcome = {
                    dismissals++
                    state.value = state.value.copy(attemptOutcome = null)
                },
            ),
        )
        scroll("platform-role-outcome-target").assertTextContains(id, substring = true)
        scroll("platform-role-attempt-error").assertTextContains("geändert", substring = true)
        compose.onNodeWithTag("platform-role-error").assertDoesNotExist()
        compose.onNodeWithTag("platform-role-action-ASSIGN").assertDoesNotExist()
        compose.runOnIdle {
            state.value = state.value.copy(loading = true, error = PlatformRoleFailure.OFFLINE)
        }
        scroll("platform-role-attempt-error").assertTextContains("geändert", substring = true)
        scroll("platform-role-error").assertTextContains("Serverstand", substring = true)
        scroll("platform-role-outcome-dismiss").performClick()
        compose.onNodeWithTag("platform-role-attempt-outcome").assertDoesNotExist()
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
                        error = PlatformRoleFailure.OFFLINE,
                        attemptOutcome =
                            PlatformRoleAttemptOutcome(
                                id,
                                PlatformRoleAction.REMOVE,
                                observation = PlatformRoleObservation.CONFIRMED_CURRENT,
                            ),
                    )
            )
        show(state, "uk", PlatformRoleActions())
        scroll("platform-role-outcome-target").assertTextContains(id, substring = true)
        scroll("platform-role-observation")
            .assertTextContains("Зміну підтверджено", substring = true)
        scroll("platform-role-error")
            .assertTextContains("Стан сервера не підтверджено", substring = true)
        compose.runOnIdle { state.value = PlatformRoleState() }
        compose.onNodeWithTag("platform-role-attempt-outcome").assertDoesNotExist()
    }

    @Test
    fun rejectedPasteProjectionKeepsOldTextAndBlocksSendUntilValidEdit() {
        val state =
            mutableStateOf(
                ready(PlatformRoleAction.ASSIGN)
                    .copy(reason = "Old accepted reason", reasonRejected = true)
            )
        var sends = 0
        show(
            state,
            "de",
            PlatformRoleActions(
                editReason = {
                    state.value = state.value.copy(reason = it, reasonRejected = false)
                },
                confirm = {
                    sends++
                    state.value = state.value.copy(busy = true)
                },
            ),
        )
        scroll("platform-role-reason").assertTextContains("Old accepted reason")
        scroll("platform-role-reason-rejected")
            .assertTextContains("nicht ersetzt", substring = true)
        scroll("platform-role-confirm").assertIsNotEnabled().performTouchInput { click() }
        compose.runOnIdle {
            assertEquals(0, sends)
            assertEquals("Old accepted reason", state.value.reason)
        }
        scroll("platform-role-reason").performTextReplacement("Corrected reason")
        compose.onNodeWithTag("platform-role-reason-rejected").assertDoesNotExist()
        scroll("platform-role-confirm").assertIsEnabled().performClick()
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
        val state = mutableStateOf(ready(PlatformRoleAction.ASSIGN))
        var sends = 0
        show(
            state,
            "de",
            PlatformRoleActions(
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
                .onNodeWithTag("platform-role-confirm-scroll")
                .fetchSemanticsNode()
                .config[PlatformRoleDialogFontScale],
            0.01f,
        )
        scroll("platform-role-reason").performClick().assertIsFocused()
        // Do not replace text while the native IME opening animation is still moving the window.
        awaitIme(true)
        scroll("platform-role-reason")
            .performTextReplacement("Ausführliche synthetische Begründung. ".repeat(180))
        awaitIme(true)
        scroll("platform-role-confirm").assertIsEnabled()
        assertFullButtonInsideDialog("platform-role-confirm")
        compose.onNodeWithTag("platform-role-confirm").performClick()
        compose.runOnIdle { assertEquals(1, sends) }
        awaitIme(false)
        scroll("platform-role-confirm").assertIsNotEnabled().performTouchInput { click() }
        scroll("platform-role-reason").assertIsNotEnabled().performTouchInput { click() }
        compose.onAllNodes(isFocused(), useUnmergedTree = true).assertCountEquals(0)
        compose.runOnIdle {
            assertEquals(1, sends)
            assertTrue(state.value.reason.length > 5_000)
        }
    }

    @Test
    fun actualLandscapeFont200KeepsRemovalActionsReachableInUkrainian() {
        val previousOrientation = compose.activity.requestedOrientation
        val originalActivity = compose.activity
        try {
            compose.runOnIdle {
                originalActivity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            }
            compose.waitUntil(25_000) {
                compose.activity !== originalActivity &&
                    compose.activity.resources.configuration.orientation ==
                        Configuration.ORIENTATION_LANDSCAPE
            }
            assertEquals(2f, compose.activity.resources.configuration.fontScale, 0.01f)
            val state = mutableStateOf(ready(PlatformRoleAction.REMOVE, status = "deactivated"))
            var sends = 0
            show(
                state,
                "uk",
                PlatformRoleActions(
                    editReason = { state.value = state.value.copy(reason = it) },
                    confirm = {
                        sends++
                        state.value = state.value.copy(busy = true)
                    },
                ),
            )
            scroll("platform-role-transition")
                .assertTextEquals("Адміністратор застосунку → Користувач")
            scroll("platform-role-reason").performTextReplacement("Синтетична причина зняття ролі")
            scroll("platform-role-confirm").assertIsEnabled()
            assertFullButtonInsideDialog("platform-role-confirm")
            scroll("platform-role-cancel").assertIsEnabled()
            assertFullButtonInsideDialog("platform-role-cancel")
            scroll("platform-role-confirm").performClick()
            compose.runOnIdle { assertEquals(1, sends) }
            scroll("platform-role-cancel").assertIsNotEnabled()
        } finally {
            compose.runOnIdle { compose.activity.requestedOrientation = previousOrientation }
        }
    }

    @Test
    fun actualProtectedWindowBlocksInputAndAccessibilityUnderPrivacy() {
        val privacy = WindowPrivacy()
        val state =
            mutableStateOf(ready(PlatformRoleAction.ASSIGN).copy(reason = "Приватна причина"))
        try {
            compose.setContent {
                CompositionLocalProvider(LocalWindowPrivacy provides privacy) {
                    UacTheme("dark") { PlatformRolePanel(state.value, "uk", PlatformRoleActions()) }
                }
            }
            val view =
                requireNotNull(
                        compose
                            .onNodeWithTag("platform-role-confirm-scroll")
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
                state.value = PlatformRoleState()
                privacy.close()
            }
        }
    }
}
