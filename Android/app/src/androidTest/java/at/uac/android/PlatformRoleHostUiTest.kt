package at.uac.android

import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.runtime.*
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalWindowPrivacy
import at.uac.android.core.WindowPrivacy
import at.uac.android.design.UacTheme
import at.uac.android.feature.moderation.*
import at.uac.android.feature.platformrolemanagement.*
import at.uac.android.feature.usermanagement.*
import at.uac.android.feature.userstatusmanagement.*
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Actual host/lifecycle/Compose integration, injected in-memory sources; never real TOTP proof. */
@RunWith(AndroidJUnit4::class)
class PlatformRoleHostUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val actor = ModerationSession("role-host-owner", 1, "owner", true)
    private val first = "role-host-first"
    private val second = "role-host-second"
    private val time = Instant.parse("2026-09-03T12:00:00Z")
    private var live by mutableStateOf<ModerationSession?>(actor)
    private var interactive by mutableStateOf(true)
    private var shown by mutableStateOf(true)
    private val privacy = WindowPrivacy()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val events = MutableSharedFlow<Unit>(extraBufferCapacity = 8)
    private val rows = linkedMapOf(first to raw(first), second to raw(second))
    private var missingAuth = false
    private var sends = 0
    private var metadataReads = 0
    private var lostReceipt = false
    private var release: CompletableDeferred<Unit>? = null
    private var readRelease: CompletableDeferred<Unit>? = null
    private var backCalls = 0
    private var statusSends = 0
    private val gate =
        object : ModerationDecisionGate {
            override suspend fun <T> withSession(
                session: ModerationSession,
                action: suspend () -> T,
            ): T = withContext(NonCancellable) { action() }
        }
    private val roleJournal =
        object : PlatformRoleJournal {
            var entries = emptyList<PlatformRolePending>()

            override suspend fun pending(uid: String) = entries.filter {
                it.accountHash == PlatformRoleRecovery.accountHash(uid)
            }

            override suspend fun put(
                uid: String,
                entry: PlatformRolePending,
                expected: PlatformRolePending?,
            ): PlatformRolePending {
                val old = entries.firstOrNull {
                    it.accountHash == entry.accountHash &&
                        it.version.targetId == entry.version.targetId
                }
                check(old == expected)
                entries = entries.filterNot { it == old } + entry
                return entry
            }

            override suspend fun clear(uid: String, expected: PlatformRolePending) {
                check(expected in entries)
                entries = entries - expected
            }
        }
    private val roleSource =
        object : PlatformRoleSource {
            override suspend fun read(session: ModerationSession, targetId: String) =
                PlatformRoleRecovery.snapshot(targetId, rows.getValue(targetId))

            override suspend fun targetAuth(
                session: ModerationSession,
                targetId: String,
            ): PlatformRoleTargetAuth {
                metadataReads++
                if (missingAuth) throw PlatformRoleException(PlatformRoleFailure.STALE)
                return PlatformRoleTargetAuth(targetId, true, false)
            }

            override fun changes(session: ModerationSession, targetId: String) = events

            override suspend fun send(
                session: ModerationSession,
                entry: PlatformRolePending,
                reason: String,
                canDispatch: () -> Boolean,
            ): PlatformRoleReceipt {
                check(canDispatch())
                check(
                    PlatformRoleRecovery.snapshot(
                            entry.version.targetId,
                            rows.getValue(entry.version.targetId),
                        )
                        .version == entry.version
                )
                sends++
                release?.await()
                rows[entry.version.targetId] =
                    rows.getValue(entry.version.targetId) +
                        mapOf(
                            "globalRole" to entry.action.newRole,
                            "roleUpdatedAt" to time.plusNanos(7),
                            "roleUpdatedBy" to session.uid,
                        )
                if (lostReceipt) throw IOException("Synthetic lost role response")
                return PlatformRoleRecovery.receipt(
                    entry,
                    mapOf(
                        "targetUserId" to entry.version.targetId,
                        "previousGlobalRole" to entry.action.previousRole,
                        "newGlobalRole" to entry.action.newRole,
                        "updatedAt" to time.toString(),
                    ),
                )
            }

            override suspend fun reconcile(session: ModerationSession, entry: PlatformRolePending) =
                PlatformRoleRecovery.observation(entry, session.uid, rows[entry.version.targetId])
        }
    private val peopleSource =
        object : ManagedUsersSource {
            override suspend fun page(session: ModerationSession, cursor: ManagedUsersCursor?) =
                ManagedUsersPage(
                    rows.map { ManagedUsersContract.user(it.key, it.value) },
                    null,
                    rows.size,
                    false,
                )

            override suspend fun search(session: ModerationSession, query: ManagedUsersQuery) =
                ManagedUsersSearch(
                    rows.map { ManagedUsersContract.user(it.key, it.value) },
                    rows.size,
                    0,
                )

            override suspend fun user(session: ModerationSession, targetId: String): ManagedUser? {
                readRelease?.await()
                return rows[targetId]?.let { ManagedUsersContract.user(targetId, it) }
            }

            override suspend fun security(
                session: ModerationSession,
                targetId: String,
            ): ManagedUserSecurity {
                if (missingAuth) throw ManagedUsersException(ManagedUsersFailure.MISSING)
                return ManagedUserSecurity(targetId, true, false, null, null, listOf("password"))
            }

            override fun invalidations(session: ModerationSession, targetId: String?) = events
        }
    private val statusJournal =
        object : UserStatusJournal {
            var entries = emptyList<UserStatusPending>()

            override suspend fun pending(uid: String) = entries

            override suspend fun put(
                uid: String,
                entry: UserStatusPending,
                expected: UserStatusPending?,
            ): UserStatusPending {
                val old = entries.firstOrNull { it.version.targetId == entry.version.targetId }
                check(old == expected)
                entries = entries.filterNot { it == old } + entry
                return entry
            }

            override suspend fun clear(uid: String, expected: UserStatusPending) {
                entries = entries - expected
            }
        }
    private val statusSource =
        object : UserStatusSource {
            override suspend fun read(session: ModerationSession, targetId: String) =
                UserStatusContract.snapshot(targetId, rows.getValue(targetId))

            override fun changes(session: ModerationSession, targetId: String) = events

            override suspend fun send(
                session: ModerationSession,
                entry: UserStatusPending,
                reason: String,
                until: Instant?,
                canDispatch: () -> Boolean,
            ): UserStatusReceipt {
                check(canDispatch())
                statusSends++
                release?.await()
                throw UserStatusException(UserStatusFailure.UNCONFIRMED)
            }

            override suspend fun reconcile(session: ModerationSession, entry: UserStatusPending) =
                UserStatusContract.observation(entry, session.uid, rows[entry.version.targetId])
        }
    private val people by lazy {
        ManagedUsersViewModel(
            ManagedUsersRepository(peopleSource, { live }, gate),
            suppliedScope = scope,
        )
    }
    private val roles by lazy {
        PlatformRoleViewModel(
            PlatformRoleRepository(roleSource, roleJournal, { live }, gate),
            workScope = scope,
        )
    }
    private val statuses by lazy {
        UserStatusViewModel(
            UserStatusRepository(statusSource, statusJournal, { live }, gate),
            workScope = scope,
        )
    }

    private fun raw(id: String) =
        mapOf<String, Any?>(
            "id" to id,
            "displayName" to "Synthetic $id",
            "email" to "$id@example.invalid",
            "globalRole" to "user",
            "accountStatus" to "active",
            "blockState" to "active",
            "warningCount" to 0L,
            "createdAt" to time,
            "updatedAt" to time,
        )

    @Before
    fun onlyNamedLocalAvds() {
        LocalEnvironment.requireSafe()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        assertEquals("at.uac.android.local", instrumentation.targetContext.packageName)
        fun property(key: String) =
            ParcelFileDescriptor.AutoCloseInputStream(
                    instrumentation.uiAutomation.executeShellCommand("getprop $key")
                )
                .bufferedReader()
                .use { it.readLine()?.trim().orEmpty() }
        assertTrue(
            (Build.VERSION.SDK_INT == 37 &&
                Build.HARDWARE == "ranchu" &&
                property("ro.kernel.qemu") == "1" &&
                property("ro.boot.qemu.avd_name") == "UAC_API_37_Play_ARM64") ||
                isExplicitApi26CompatibilityAvd()
        )
    }

    @After
    fun closeOnlyOwnedMemorySources() {
        compose.runOnIdle {
            release?.complete(Unit)
            readRelease?.complete(Unit)
            shown = false
            live = null
            roles.bind(null)
            statuses.bind(null)
        }
        compose.waitUntil(10_000) { !roles.state.value.busy && !statuses.state.value.busy }
        compose.runOnIdle {
            privacy.close()
            scope.cancel()
        }
    }

    private fun show() {
        compose.setContent {
            CompositionLocalProvider(LocalWindowPrivacy provides privacy) {
                UacTheme("light") {
                    if (shown)
                        ManagedUsersScreen(
                            people,
                            live,
                            "de",
                            onBack = {
                                backCalls++
                                shown = false
                            },
                            onAccount = { shown = false },
                            interactive = interactive,
                            statuses = statuses,
                            roles = roles,
                        )
                }
            }
        }
        compose.waitUntil(10_000) { people.state.value.visible && !people.state.value.loading }
    }

    private fun scroll(tag: String): SemanticsNodeInteraction {
        val isDialog =
            compose
                .onAllNodesWithTag("platform-role-confirm-scroll")
                .fetchSemanticsNodes()
                .isNotEmpty() ||
                compose
                    .onAllNodesWithTag("user-status-confirm-scroll")
                    .fetchSemanticsNodes()
                    .isNotEmpty()
        // A tall already-composed action item may contain a clipped descendant. Search the lazy
        // list only when the node is uncomposed; otherwise bring that exact existing node into
        // view.
        if (!isDialog && compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty())
            compose.onNodeWithTag("managed-users-list").performScrollToNode(hasTestTag(tag))
        val node = compose.onNodeWithTag(tag)
        var prior: Rect? = null
        var since = SystemClock.uptimeMillis()
        compose.waitUntil(10_000) {
            val bounds =
                if (isDialog) {
                    val rootTag =
                        if (
                            compose
                                .onAllNodesWithTag("platform-role-confirm-scroll")
                                .fetchSemanticsNodes()
                                .isNotEmpty()
                        )
                            "platform-role-confirm-scroll"
                        else "user-status-confirm-scroll"
                    compose.onNodeWithTag(rootTag).fetchSemanticsNode().boundsInWindow
                } else
                    compose.onNodeWithTag("managed-users-list").fetchSemanticsNode().boundsInWindow
            if (prior != bounds) {
                prior = bounds
                since = SystemClock.uptimeMillis()
            }
            bounds.width > 0 && bounds.height > 0 && SystemClock.uptimeMillis() - since >= 150
        }
        node.performScrollTo()
        compose.waitUntil(10_000) { node.isDisplayed() }
        return node.assertIsDisplayed()
    }

    private fun open(id: String = first) {
        scroll("managed-user-row-$id").performClick()
        compose.waitUntil(10_000) {
            people.state.value.detail?.id == id &&
                roles.state.value.fresh &&
                statuses.state.value.fresh
        }
    }

    private fun beginRole() {
        scroll("platform-role-action-ASSIGN").assertIsEnabled().performClick()
        scroll("platform-role-reason").performTextReplacement("Synthetic owner reason")
        scroll("platform-role-confirm").assertIsEnabled()
    }

    @Test
    fun ownerCanSubmitOnceAndOwnOutcomeSurvivesParentRefresh() {
        show()
        open()
        beginRole()
        scroll("platform-role-confirm").performClick()
        compose.waitUntil(10_000) {
            roles.state.value.completion == 1L &&
                !people.state.value.loading &&
                roles.state.value.fresh &&
                people.state.value.detail?.globalRole == "admin" &&
                roles.state.value.snapshot?.target?.role == "admin"
        }
        scroll("platform-role-observation")
            .assertTextContains("Änderung bestätigt", substring = true)
        compose.runOnIdle {
            assertEquals(
                "Parent must show committed role before searching for reverse action",
                "admin",
                people.state.value.detail?.globalRole,
            )
            assertEquals(listOf(PlatformRoleAction.REMOVE), roles.state.value.availableActions)
            assertTrue(roles.state.value.canAct)
        }
        try {
            compose.onNodeWithTag("platform-role-action-REMOVE").assertExists()
        } catch (error: AssertionError) {
            throw AssertionError(
                "Synthetic host after own ACK: target=${roles.state.value.targetId}, " +
                    "fresh=${roles.state.value.fresh}, busy=${roles.state.value.busy}, " +
                    "statusBusy=${statuses.state.value.busy}, " +
                    "statusConfirmation=${statuses.state.value.confirmation}\n" +
                    compose.onRoot(useUnmergedTree = true).printToString(),
                error,
            )
        }
        scroll("platform-role-action-REMOVE").assertIsEnabled()
        scroll("user-status-action-WARN").assertIsEnabled()
        assertEquals(1, sends)
        assertTrue(roleJournal.entries.isEmpty())
        assertEquals("admin", people.state.value.detail?.globalRole)
    }

    @Test
    fun appAdminRetainsStatusManagementButNeverGetsRoleControls() {
        live = actor.copy(role = "admin")
        show()
        scroll("managed-user-row-$first").performClick()
        compose.waitUntil(10_000) { statuses.state.value.fresh }
        scroll("user-status-action-WARN").assertIsEnabled()
        compose.onNodeWithTag("platform-role-panel").assertDoesNotExist()
        assertEquals(0, metadataReads)
        assertEquals(0, sends)
    }

    @Test
    fun statusConfirmationRevokesRolePreviewAndCancelRestoresFreshRead() {
        show()
        open()
        scroll("user-status-action-WARN").performClick()
        compose.waitUntil(10_000) { roles.state.value.snapshot == null }
        assertEquals("", roles.state.value.reason)
        compose.onNodeWithTag("platform-role-confirm-scroll").assertDoesNotExist()
        scroll("user-status-cancel").performClick()
        compose.waitUntil(10_000) { roles.state.value.fresh }
        beginRole()
        compose.waitUntil(10_000) { statuses.state.value.snapshot == null }
        assertNull(statuses.state.value.confirmation)
        assertEquals(0, sends)
        assertEquals(0, statusSends)
    }

    @Test
    fun submittedRoleTaskRejectsSiblingStatusRequest() {
        release = CompletableDeferred()
        show()
        open()
        beginRole()
        scroll("platform-role-confirm").performClick()
        compose.waitUntil(10_000) { sends == 1 }
        compose.runOnIdle {
            statuses.request(UserStatusAction.WARN)
            statuses.editReason("Late synthetic status tap")
            statuses.confirm()
        }
        assertEquals(0, statusSends)
        assertNull(statuses.state.value.confirmation)
        assertTrue(statusJournal.entries.isEmpty())
        compose.runOnIdle { release!!.complete(Unit) }
        compose.waitUntil(10_000) { !roles.state.value.busy }
        assertEquals(1, sends)
    }

    @Test
    fun submittedStatusTaskRejectsSiblingRoleRequest() {
        release = CompletableDeferred()
        show()
        open()
        scroll("user-status-action-WARN").performClick()
        scroll("user-status-reason").performTextReplacement("Synthetic status reason")
        scroll("user-status-confirm").assertIsEnabled().performClick()
        compose.waitUntil(10_000) { statusSends == 1 }
        compose.runOnIdle {
            roles.request(PlatformRoleAction.ASSIGN)
            roles.editReason("Late synthetic role tap")
            roles.confirm()
        }
        assertEquals(0, sends)
        assertNull(roles.state.value.confirmation)
        assertTrue(roleJournal.entries.isEmpty())
        compose.runOnIdle { release!!.complete(Unit) }
        compose.waitUntil(10_000) { !statuses.state.value.busy }
        assertEquals(1, statusSends)
        assertEquals(1, statusJournal.entries.size)
    }

    @Test
    fun privacyLossClearsBothModelsAndOldConfirmationCannotReturn() {
        show()
        open()
        beginRole()
        compose.runOnIdle { privacy.update(secure = true, blocked = true) }
        compose.waitUntil(10_000) {
            roles.state.value.snapshot == null && statuses.state.value.snapshot == null
        }
        assertEquals("", roles.state.value.reason)
        compose.onNodeWithTag("platform-role-confirm-scroll").assertDoesNotExist()
        compose.runOnIdle { privacy.update(secure = false, blocked = false) }
        compose.waitUntil(10_000) { people.state.value.visible && !people.state.value.loading }
        assertNull(roles.state.value.confirmation)
        assertEquals("", roles.state.value.reason)
        assertEquals(0, sends)
    }

    @Test
    fun actualHostPauseDropsPrivateDraftAndResumeDoesNotRestoreIt() {
        show()
        open()
        beginRole()
        compose.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
        assertNull(roles.state.value.snapshot)
        assertNull(statuses.state.value.snapshot)
        assertEquals("", roles.state.value.reason)
        compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        compose.waitUntil(10_000) { people.state.value.visible && !people.state.value.loading }
        assertNull(roles.state.value.confirmation)
        assertEquals(0, sends)
    }

    @Test
    fun unknownOperationSurvivesTargetBackAndOffersOnlyReadOnlyRecovery() {
        lostReceipt = true
        show()
        open()
        beginRole()
        scroll("platform-role-confirm").performClick()
        compose.waitUntil(10_000) { roles.state.value.pending.size == 1 && !roles.state.value.busy }
        scroll("managed-users-back").performClick()
        compose.waitUntil(10_000) {
            people.state.value.selectedId == null && !people.state.value.loading
        }
        scroll("platform-role-reconcile-0").performClick()
        compose.waitUntil(10_000) {
            roles.state.value.observation == PlatformRoleObservation.OBSERVED_WITHOUT_RECEIPT
        }
        assertEquals(1, sends)
        assertEquals(1, roleJournal.entries.size)
        assertEquals(0, backCalls)
        scroll("managed-users-back").performClick()
        assertEquals(1, backCalls)
        assertTrue(roles.state.value.pending.isEmpty())
        assertEquals(1, roleJournal.entries.size)
    }

    @Test
    fun ownerLossDuringSubmittedTaskKeepsOwnAckButNeverOldPrivateUi() {
        release = CompletableDeferred()
        show()
        open()
        beginRole()
        scroll("platform-role-confirm").performClick()
        compose.waitUntil(10_000) { sends == 1 }
        compose.runOnIdle {
            live = actor.copy(uid = "next-owner", revision = 2)
            release!!.complete(Unit)
        }
        compose.waitUntil(10_000) { !roles.state.value.busy }
        assertEquals(PlatformRolePhase.ACKNOWLEDGED, roleJournal.entries.single().phase)
        assertEquals("", roles.state.value.reason)
        assertNull(roles.state.value.attemptOutcome)
        assertTrue(roles.state.value.pending.isEmpty())
    }

    @Test
    fun missingAuthMetadataDoesNotHideRemovalOnRestrictedAdminProfile() {
        rows[first] =
            raw(first) +
                mapOf(
                    "globalRole" to "admin",
                    "accountStatus" to "deactivated",
                    "blockState" to "deactivated",
                )
        missingAuth = true
        show()
        open()
        scroll("platform-role-action-REMOVE").assertIsEnabled().performClick()
        scroll("platform-role-reason").performTextReplacement("Synthetic removal reason")
        scroll("platform-role-confirm").assertIsEnabled().performClick()
        compose.waitUntil(10_000) { roles.state.value.completion == 1L }
        assertEquals(1, sends)
        assertEquals(0, metadataReads)
        assertEquals("user", rows.getValue(first)["globalRole"])
        assertEquals("deactivated", rows.getValue(first)["accountStatus"])
    }

    @Test
    fun parentRefreshClearsOldReasonAndRequiresNewRawReview() {
        show()
        open()
        beginRole()
        val old = roles.state.value.snapshot!!.version
        readRelease = CompletableDeferred()
        compose.runOnIdle {
            rows[first] = rows.getValue(first) + ("privateUnknown" to "changed")
            people.refresh()
        }
        compose.waitUntil(10_000) { roles.state.value.snapshot == null }
        assertEquals("", roles.state.value.reason)
        compose.onNodeWithTag("platform-role-confirm-scroll").assertDoesNotExist()
        compose.runOnIdle { readRelease!!.complete(Unit) }
        compose.waitUntil(10_000) { roles.state.value.fresh }
        assertNotEquals(old, roles.state.value.snapshot!!.version)
        assertNull(roles.state.value.confirmation)
        assertEquals(0, sends)
    }
}
