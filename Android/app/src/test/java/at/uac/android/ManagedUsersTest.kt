package at.uac.android

import at.uac.android.feature.auth.*
import at.uac.android.feature.moderation.*
import at.uac.android.feature.usermanagement.*
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/** Positive actors here are injected pure fixtures, never proof of an SDK TOTP sign-in. */
@OptIn(ExperimentalCoroutinesApi::class)
class ManagedUsersTest {
    private val actor = ModerationSession("a02-actor", 1, "admin", true)
    private var live: ModerationSession? = actor
    private val now = Instant.parse("2026-09-03T10:00:00Z")

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun teardown() {
        Dispatchers.resetMain()
    }

    private fun user(id: String = "a02-target", extra: Map<String, Any?> = emptyMap()) =
        ManagedUsersContract.user(
            id,
            mapOf(
                "id" to "untrusted-other",
                "displayName" to "Private Name",
                "email" to "private@example.invalid",
                "fullName" to "Private Full",
                "city" to "Wien",
                "globalRole" to "user",
                "accountStatus" to "active",
                "blockState" to "active",
                "createdAt" to now,
            ) + extra,
        )

    private class Cursor(owner: ModerationSession, consumed: Int) :
        ManagedUsersCursor(owner, consumed)

    private fun security(target: String = "a02-target", extra: Map<String, Any?> = emptyMap()) =
        mapOf(
            "targetUserId" to target,
            "emailVerified" to true,
            "authDisabled" to false,
            "creationTime" to "Thu, 03 Sep 2026 10:00:00 GMT",
            "lastSignInTime" to null,
            "providerIds" to listOf("password"),
        ) + extra

    private class Fake : ManagedUsersSource {
        var rows: List<ManagedUser> = emptyList()
        var searchRows: Map<String, List<ManagedUser>> = emptyMap()
        val searchRequests = mutableListOf<String>()
        var total = 0
        var unavailable = 0
        var calls = 0
        var securityCalls = 0
        var pageFailure: ManagedUsersFailure? = null
        var securityFailure: ManagedUsersFailure? = null
        var delay: CompletableDeferred<Unit>? = null
        var detailDelay: CompletableDeferred<Unit>? = null
        var after: (() -> Unit)? = null
        val changes = MutableSharedFlow<Unit>(extraBufferCapacity = 20)

        suspend fun before(detail: Boolean = false) {
            calls++
            (if (detail) detailDelay else delay)?.let { withContext(NonCancellable) { it.await() } }
            after?.invoke()
        }

        override suspend fun page(
            session: ModerationSession,
            cursor: ManagedUsersCursor?,
        ): ManagedUsersPage {
            before()
            pageFailure?.let { throw ManagedUsersException(it) }
            val start = cursor?.consumed ?: 0
            val loaded = rows.drop(start).take(40)
            val consumed = start + loaded.size
            return ManagedUsersPage(
                loaded,
                if (loaded.size == 40 && consumed < 200) Cursor(session, consumed) else null,
                consumed,
                consumed == 200,
            )
        }

        override suspend fun search(
            session: ModerationSession,
            query: ManagedUsersQuery,
        ): ManagedUsersSearch {
            val captured = (searchRows[query.value] ?: rows).take(100)
            searchRequests += query.value
            before()
            return ManagedUsersSearch(
                captured,
                maxOf(total, captured.size + unavailable),
                unavailable,
            )
        }

        override suspend fun user(session: ModerationSession, targetId: String): ManagedUser? {
            before(true)
            return rows.firstOrNull { it.id == targetId }
        }

        override suspend fun security(
            session: ModerationSession,
            targetId: String,
        ): ManagedUserSecurity {
            securityCalls++
            securityFailure?.let { throw ManagedUsersException(it) }
            return ManagedUserSecurity(targetId, true, false, null, null, listOf("password"))
        }

        override fun invalidations(session: ModerationSession, targetId: String?) =
            changes.asSharedFlow()
    }

    private class Gate : ModerationDecisionGate {
        var calls = 0
        var depth = 0
        var before: (() -> Unit)? = null
        private val mutex = Mutex()

        override suspend fun <T> withSession(
            session: ModerationSession,
            action: suspend () -> T,
        ): T = mutex.withLock {
            calls++
            check(depth == 0)
            depth++
            try {
                before?.invoke()
                withContext(NonCancellable) { action() }
            } finally {
                depth--
            }
        }
    }

    private fun repo(fake: Fake, gate: Gate = Gate()) = ManagedUsersRepository(fake, { live }, gate)

    private fun model(fake: Fake, scope: CoroutineScope) =
        ManagedUsersViewModel(repo(fake), { live }, scope)

    private suspend fun fails(failure: ManagedUsersFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected $failure")
        } catch (error: ManagedUsersException) {
            assertEquals(failure, error.failure)
        }
    }

    private fun invalid(action: () -> Any?) {
        try {
            action()
            fail("Invalid contract must fail")
        } catch (error: ManagedUsersException) {
            assertEquals(ManagedUsersFailure.INVALID, error.failure)
        }
    }

    @Test
    fun roleAndReadyRejectBeforeSourceOrGate() = runTest {
        for (session in
            listOf(
                actor.copy(role = "user"),
                actor.copy(role = "topAdmin"),
                actor.copy(role = "moderator"),
                actor.copy(role = "communityOwner"),
            )) {
            live = session
            val fake = Fake()
            val gate = Gate()
            fails(ManagedUsersFailure.DENIED) { repo(fake, gate).page(session, null) }
            assertEquals(0, fake.calls)
            assertEquals(0, gate.calls)
        }
        live = actor.copy(ready = false)
        fails(ManagedUsersFailure.NOT_READY) { repo(Fake()).page(live!!, null) }
    }

    @Test
    fun scopeUsesActualAuthTotpAndLegalActivationRequirements() {
        val profile =
            AuthProfile(
                actor.uid,
                "private@example.invalid",
                "Private",
                globalRole = "admin",
                requiresMultiFactorAuth = true,
            )
        val session =
            AuthSession(
                AuthStage.AUTHENTICATED,
                AuthIdentity(actor.uid, "private@example.invalid", true),
                profile,
                totpAuthenticated = true,
            )
        assertTrue(session.moderationScope()!!.allowed)
        assertFalse(session.copy(totpAuthenticated = false).moderationScope()!!.allowed)
        assertFalse(
            session
                .copy(profile = profile.copy(requiresMultiFactorAuth = false))
                .moderationScope()!!
                .allowed
        )
        assertFalse(session.copy(gate = AuthGate.LEGAL_REQUIRED).moderationScope()!!.allowed)
        assertFalse(
            session
                .copy(profile = profile.copy(accountStatus = "deactivated"))
                .moderationScope()!!
                .allowed
        )
    }

    @Test
    fun canonicalDocumentIdNeverUsesStoredId() {
        assertEquals("canonical", user("canonical").id)
        listOf("", "..", "a/b", " bad", "x".repeat(129), "x\u0000", "__reserved__").forEach {
            invalid { user(it) }
        }
        assertEquals("custom.user@id", user("custom.user@id").id)
    }

    @Test
    fun backendGoldenQueryNormalizationIsPreserved() {
        assertEquals("іван", ManagedUsersQuery.from(" ІВАН ").value)
        assertEquals("muller wien", ManagedUsersQuery.from("Müller-Wien").value)
        assertEquals("ivan example invalid", ManagedUsersQuery.from("Ivan@example.invalid").value)
        invalid { ManagedUsersQuery.from("!") }
        invalid { ManagedUsersQuery.from("a") }
        assertEquals(120, ManagedUsersQuery.from("a".repeat(120)).value.length)
        invalid { ManagedUsersQuery.from("a".repeat(121)) }
    }

    @Test
    fun searchResponseBoundsAndTotalAreStrict() {
        val ids = (0 until 100).map { "target-$it" }
        assertEquals(
            ids to 201,
            ManagedUsersContract.searchIds(mapOf("userIds" to ids, "totalMatches" to 201)),
        )
        listOf(
                mapOf("userIds" to ids + "extra", "totalMatches" to 201),
                mapOf("userIds" to listOf("same", "same"), "totalMatches" to 2),
                mapOf("userIds" to listOf("ok"), "totalMatches" to 0),
                mapOf("userIds" to emptyList<String>(), "totalMatches" to 1.5),
                mapOf("userIds" to listOf("../bad"), "totalMatches" to 1),
                mapOf("userIds" to listOf(2), "totalMatches" to 1),
            )
            .forEach { invalid { ManagedUsersContract.searchIds(it) } }
    }

    @Test
    fun securityRfcAndIsoDatesAndMissingTimesRemainDistinct() {
        assertEquals(now, ManagedUsersContract.security("a02-target", security()).creationTime)
        assertNull(ManagedUsersContract.security("a02-target", security()).lastSignInTime)
        assertEquals(
            now,
            ManagedUsersContract.security(
                    "a02-target",
                    security(extra = mapOf("creationTime" to now.toString())),
                )
                .creationTime,
        )
        invalid { ManagedUsersContract.security("other", security()) }
        invalid {
            ManagedUsersContract.security(
                "a02-target",
                security(extra = mapOf("lastSignInTime" to "broken")),
            )
        }
        invalid {
            ManagedUsersContract.security(
                "a02-target",
                security(extra = mapOf("emailVerified" to "true")),
            )
        }
        invalid {
            ManagedUsersContract.security(
                "a02-target",
                security(extra = mapOf("providerIds" to listOf("password", "password"))),
            )
        }
    }

    @Test
    fun securityExtremeInstantsFailBeforePresentationAndFormatterHasSafeFallback() {
        for (wire in
            listOf(
                Instant.MAX.toString(),
                Instant.MIN.toString(),
                "+10000-01-01T00:00:00Z",
            )) invalid {
            ManagedUsersContract.security(
                "a02-target",
                security(extra = mapOf("creationTime" to wire)),
            )
        }
        assertEquals("Nicht verfügbar", managedUsersDate(Instant.MAX, "de"))
        assertEquals("Недоступно", managedUsersDate(Instant.MIN, "uk"))
    }

    @Test
    fun unknownStatusesNeverAcquireFilterPrivilegesAndLegacyRestrictedMaps() {
        assertFalse(
            ManagedUsersContract.matches(
                user(extra = mapOf("accountStatus" to "strange")),
                ManagedUsersFilter.ACTIVE,
            )
        )
        assertTrue(
            ManagedUsersContract.matches(
                user(extra = mapOf("blockState" to "blocked")),
                ManagedUsersFilter.RESTRICTED,
            )
        )
        assertTrue(
            ManagedUsersContract.matches(
                user(extra = mapOf("accountStatus" to "warned")),
                ManagedUsersFilter.WARNED,
            )
        )
    }

    @Test
    fun malformedExplicitStatesNeverLookActiveAndOnlyMissingUsesLegacyFallback() {
        for (wrong in listOf(null, true, 0, emptyMap<String, String>())) {
            val row =
                ManagedUsersContract.user(
                    "target",
                    mapOf("accountStatus" to wrong, "blockState" to wrong, "globalRole" to wrong),
                )
            assertEquals("unknown", row.accountStatus)
            assertEquals("unknown", row.blockState)
            assertEquals("unknown", row.globalRole)
            assertFalse(ManagedUsersContract.matches(row, ManagedUsersFilter.ACTIVE))
        }
        assertEquals("active", ManagedUsersContract.user("target", emptyMap()).accountStatus)
        assertEquals(
            "suspendedUntil",
            ManagedUsersContract.user("target", mapOf("isBlocked" to true)).accountStatus,
        )
        assertEquals(
            "unknown",
            ManagedUsersContract.user("target", mapOf("isBlocked" to 1)).accountStatus,
        )
        assertEquals(
            "unknown",
            ManagedUsersContract.user("target", mapOf("blockState" to "unrecognized"))
                .accountStatus,
        )
    }

    @Test
    fun warningsAreExactNonnegativeIntegersOrUnknownNotInventedZero() {
        for (wrong in listOf(null, "0", -1, 1.5, Double.NaN, Double.POSITIVE_INFINITY)) assertNull(
            user(extra = mapOf("warningCount" to wrong)).warningCount
        )
        assertEquals(0L, user(extra = mapOf("warningCount" to 0)).warningCount)
        assertEquals(4L, user(extra = mapOf("warningCount" to 4.0)).warningCount)
    }

    @Test
    fun fivePagesStopAt200WithoutPretendingTotalCount() = runTest {
        val fake = Fake().apply { rows = (0..220).map { user("target-$it") } }
        val gate = Gate()
        val repository = repo(fake, gate)
        var cursor: ManagedUsersCursor? = null
        repeat(5) { index ->
            val page = repository.page(actor, cursor)
            assertEquals(40, page.users.size)
            assertEquals((index + 1) * 40, page.consumed)
            cursor = page.next
            assertEquals(index == 4, page.capped)
        }
        assertNull(cursor)
        assertEquals(5, gate.calls)
    }

    @Test
    fun exactMultipleMayHaveEmptyFinalPageAndPartialStops() = runTest {
        val fake = Fake().apply { rows = (0 until 40).map { user("target-$it") } }
        val repository = repo(fake)
        val first = repository.page(actor, null)
        assertNotNull(first.next)
        val last = repository.page(actor, first.next)
        assertTrue(last.users.isEmpty())
        assertNull(last.next)
        assertFalse(last.capped)
        fake.rows = listOf(user())
        assertNull(repository.page(actor, null).next)
    }

    @Test
    fun foreignAndMisalignedCursorsRejectedBeforeSource() = runTest {
        val fake = Fake()
        for (cursor in
            listOf(
                Cursor(actor.copy(revision = 2), 40),
                Cursor(actor, 41),
                Cursor(actor, 200),
            )) fails(ManagedUsersFailure.STALE) { repo(fake).page(actor, cursor) }
        assertEquals(0, fake.calls)
    }

    @Test
    fun gateAndPostAuthorityCannotBeReplacedByClientRole() = runTest {
        val fake =
            Fake().apply {
                rows = listOf(user())
                after = { live = actor.copy(revision = 2) }
            }
        val gate = Gate()
        assertTrue(
            runCatching { repo(fake, gate).page(actor, null) }.exceptionOrNull()
                is CancellationException
        )
        assertEquals(1, gate.calls)
        assertEquals(0, gate.depth)
    }

    @Test
    fun roleChangeInsideGateRejectsBeforeSdkRead() = runTest {
        val fake = Fake()
        val gate = Gate().apply { before = { live = actor.copy(role = "user") } }
        assertTrue(
            runCatching { repo(fake, gate).page(actor, null) }.exceptionOrNull()
                is CancellationException
        )
        assertEquals(0, fake.calls)
    }

    @Test
    fun selfOwnerAdminTargetsAreReadableNotMutationFiltered() = runTest {
        val fake =
            Fake().apply {
                rows =
                    listOf(
                        user(actor.uid),
                        user("owner", mapOf("globalRole" to "owner")),
                        user("admin", mapOf("globalRole" to "admin")),
                    )
            }
        for (target in fake.rows) assertEquals(target, repo(fake).user(actor, target.id))
    }

    @Test
    fun missingProfileIsNotMetadataFailureOrStaleFallback() = runTest {
        assertNull(repo(Fake()).user(actor, "gone"))
    }

    @Test
    fun snapshotMasksBeforeDelayedBindAndLeaseVetoIsSynchronous() = runTest {
        val fake = Fake().apply { rows = listOf(user()) }
        val vm = model(fake, backgroundScope)
        var allowed = true
        val lease = vm.present { allowed }
        runCurrent()
        assertEquals(1, vm.snapshot(actor, lease).users.size)
        allowed = false
        assertTrue(vm.snapshot(actor, lease).users.isEmpty())
        allowed = true
        live = actor.copy(revision = 2)
        assertTrue(vm.snapshot(actor, lease).users.isEmpty())
        vm.bind(live)
        assertEquals("", vm.state.value.query)
        assertNull(vm.state.value.next)
    }

    @Test
    fun delayedUncancellableReadCannotRepopulateAfterDismiss() = runTest {
        val barrier = CompletableDeferred<Unit>()
        val fake =
            Fake().apply {
                rows = listOf(user())
                delay = barrier
            }
        val vm = model(fake, backgroundScope)
        val lease = vm.present()
        runCurrent()
        vm.dismiss(lease)
        barrier.complete(Unit)
        runCurrent()
        assertFalse(vm.state.value.visible)
        assertTrue(vm.state.value.users.isEmpty())
        assertNull(vm.state.value.detail)
    }

    @Test
    fun privacyVetoPermanentlyConsumesLeaseUntilFreshPresentationRead() = runTest {
        val fake = Fake().apply { rows = listOf(user()) }
        val vm = model(fake, backgroundScope)
        var allowed = true
        val old = vm.present { allowed }
        runCurrent()
        assertEquals(1, vm.snapshot(actor, old).users.size)
        allowed = false
        assertTrue(vm.snapshot(actor, old).users.isEmpty())
        assertTrue(vm.state.value.users.isEmpty())
        assertNull(vm.state.value.next)
        assertEquals("", vm.state.value.query)
        assertNull(vm.state.value.detail)
        assertNull(vm.state.value.security)
        allowed = true
        assertFalse(vm.owns(old))
        assertTrue(vm.snapshot(actor, old).users.isEmpty())
        vm.refresh()
        runCurrent()
        assertEquals(1, fake.calls)
        fake.rows = listOf(user("fresh-target"))
        val fresh = vm.present { allowed }
        assertTrue(vm.snapshot(actor, fresh).users.isEmpty())
        runCurrent()
        assertEquals("fresh-target", vm.snapshot(actor, fresh).users.single().id)
        assertEquals(2, fake.calls)
    }

    @Test
    fun privacyVetoBeforeUncancellableResponseDoesNotResurrectAtSameRevision() = runTest {
        val barrier = CompletableDeferred<Unit>()
        val fake =
            Fake().apply {
                rows = listOf(user())
                delay = barrier
            }
        val vm = model(fake, backgroundScope)
        var allowed = true
        val lease = vm.present { allowed }
        runCurrent()
        allowed = false
        assertFalse(vm.owns(lease))
        allowed = true
        barrier.complete(Unit)
        runCurrent()
        assertFalse(vm.owns(lease))
        assertTrue(vm.snapshot(actor, lease).users.isEmpty())
    }

    @Test
    fun oldDisposalCannotDismissReplacementPresentation() = runTest {
        val vm = model(Fake(), backgroundScope)
        val first = vm.present()
        val second = vm.present()
        vm.dismiss(first)
        assertTrue(vm.owns(second))
        runCurrent()
    }

    @Test
    fun searchDebouncesAndClearsPriorPrivateRowsImmediately() = runTest {
        val fake = Fake().apply { rows = listOf(user()) }
        val vm = model(fake, backgroundScope)
        vm.present()
        runCurrent()
        vm.search("iv")
        assertTrue(vm.state.value.users.isEmpty())
        advanceTimeBy(200)
        vm.search("ivan")
        advanceTimeBy(349)
        runCurrent()
        assertEquals(1, fake.calls)
        advanceTimeBy(1)
        runCurrent()
        assertEquals(2, fake.calls)
        assertEquals("ivan", vm.state.value.query)
    }

    @Test
    fun staleSearchCannotPopulateANewerQuery() = runTest {
        val first = user("first-private-target")
        val second = user("second-private-target")
        val fake =
            Fake().apply {
                rows = listOf(user())
                searchRows = mapOf("first" to listOf(first), "second" to listOf(second))
            }
        val vm = model(fake, backgroundScope)
        val delivered = mutableListOf<List<String>>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            vm.state.collect { delivered += it.users.map(ManagedUser::id) }
        }
        vm.present()
        runCurrent()
        val barrier = CompletableDeferred<Unit>()
        fake.delay = barrier
        vm.search("first")
        advanceTimeBy(350)
        runCurrent()
        vm.search("second")
        fake.delay = null
        advanceTimeBy(350)
        runCurrent()
        barrier.complete(Unit)
        runCurrent()
        assertEquals("second", vm.state.value.query)
        assertFalse(vm.state.value.loading)
        assertEquals(listOf("first", "second"), fake.searchRequests)
        assertEquals(listOf(second.id), vm.state.value.users.map(ManagedUser::id))
        assertTrue(delivered.none { first.id in it })
        assertNull(vm.state.value.error)
    }

    @Test
    fun metadataNotFoundIsAnExplicitIndependentDetailState() = runTest {
        val fake =
            Fake().apply {
                rows = listOf(user())
                securityFailure = ManagedUsersFailure.MISSING
            }
        val vm = model(fake, backgroundScope)
        vm.present()
        runCurrent()
        vm.open("a02-target")
        runCurrent()
        assertNotNull(vm.state.value.detail)
        assertNull(vm.state.value.security)
        assertEquals(ManagedUsersFailure.MISSING, vm.state.value.securityError)
        assertNull(vm.state.value.error)
    }

    @Test
    fun metadataDeniedDoesNotLeavePrivateProfileVisible() = runTest {
        val fake =
            Fake().apply {
                rows = listOf(user())
                securityFailure = ManagedUsersFailure.DENIED
            }
        val vm = model(fake, backgroundScope)
        vm.present()
        runCurrent()
        vm.open("a02-target")
        runCurrent()
        assertNull(vm.state.value.detail)
        assertEquals(ManagedUsersFailure.DENIED, vm.state.value.error)
    }

    @Test
    fun targetRemovedDuringFreshOpenDoesNotReuseListFallback() = runTest {
        val fake = Fake().apply { rows = listOf(user()) }
        val vm = model(fake, backgroundScope)
        vm.present()
        runCurrent()
        vm.open("a02-target")
        fake.rows = emptyList()
        runCurrent()
        assertNull(vm.state.value.detail)
        assertEquals(ManagedUsersFailure.MISSING, vm.state.value.error)
        assertEquals(0, fake.securityCalls)
    }

    @Test
    fun unseenTargetCannotBeOpenedFromArbitraryCallback() = runTest {
        val fake = Fake().apply { rows = listOf(user()) }
        val vm = model(fake, backgroundScope)
        vm.present()
        runCurrent()
        vm.open("unknown")
        runCurrent()
        assertNull(vm.state.value.selectedId)
        assertEquals(1, fake.calls)
    }

    @Test
    fun watcherInvalidationMasksThenFreshReadsAndOfflineNeverShowsCache() = runTest {
        val fake = Fake().apply { rows = listOf(user()) }
        val vm = model(fake, backgroundScope)
        vm.present()
        runCurrent()
        fake.pageFailure = ManagedUsersFailure.OFFLINE
        fake.changes.emit(Unit)
        runCurrent()
        assertTrue(vm.state.value.users.isEmpty())
        assertEquals(ManagedUsersFailure.OFFLINE, vm.state.value.error)
        fake.pageFailure = null
        vm.refresh()
        runCurrent()
        assertEquals(1, vm.state.value.users.size)
    }

    @Test
    fun repeatedMetadataSignalsCoalesceBeforePublishingResponse() = runTest {
        val barrier = CompletableDeferred<Unit>()
        val fake =
            Fake().apply {
                rows = listOf(user())
                delay = barrier
            }
        val vm = model(fake, backgroundScope)
        vm.present()
        runCurrent()
        repeat(4) { fake.changes.emit(Unit) }
        runCurrent()
        assertTrue(vm.state.value.users.isEmpty())
        fake.delay = null
        barrier.complete(Unit)
        runCurrent()
        assertEquals(2, fake.calls)
        assertEquals(1, vm.state.value.users.size)
        assertFalse(vm.state.value.loading)
    }

    @Test
    fun backToListPerformsFreshReadAndLogoutErasesAllPrivateState() = runTest {
        val fake = Fake().apply { rows = listOf(user()) }
        val vm = model(fake, backgroundScope)
        vm.present()
        runCurrent()
        vm.open("a02-target")
        runCurrent()
        assertNotNull(vm.state.value.detail)
        vm.closeTarget()
        assertTrue(vm.state.value.users.isEmpty())
        runCurrent()
        assertNull(vm.state.value.selectedId)
        live = null
        vm.bind(null)
        assertTrue(vm.state.value.users.isEmpty())
        assertNull(vm.state.value.security)
        assertEquals("", vm.state.value.query)
    }

    @Test
    fun privateModelStringsNeverLeakFieldsIdsOrQueries() {
        val row = user()
        val query = ManagedUsersQuery.from("private search")
        val values =
            listOf(
                row,
                query,
                ManagedUsersPage(listOf(row), Cursor(actor, 40), 40, false),
                ManagedUsersState(
                    session = actor,
                    users = listOf(row),
                    query = query.value,
                    selectedId = row.id,
                ),
                ManagedUsersContract.security("a02-target", security()),
                ManagedUsersSearch(listOf(row), 2, 1),
            )
        values.forEach { value ->
            assertFalse(value.toString().contains("Private"))
            assertFalse(value.toString().contains("a02-"))
            assertFalse(value.toString().contains("example.invalid"))
            assertFalse(value.toString().contains(query.value))
        }
    }
}
