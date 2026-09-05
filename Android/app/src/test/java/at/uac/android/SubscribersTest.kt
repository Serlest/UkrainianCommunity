package at.uac.android

import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.subscribers.*
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SubscribersTest {
    private val session = SubscriberSession("ordinary-reader", 1, true)
    private var current: SubscriberSession? = session
    private var visible = true
    private val blocked = mutableSetOf<String>()
    private val time = Instant.parse("2026-09-03T10:00:00Z")
    private val id = "synthetic-subscribers"

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    private fun organization(extra: Fields = emptyMap()) =
        RawDocument(
            id,
            mapOf(
                "id" to id,
                "name" to "Synthetic community",
                "moderationStatus" to "approved",
                "ownerId" to "official-owner",
                "adminIds" to listOf("official-admin"),
                "updatedAt" to time,
            ) + extra,
        )

    private fun row(
        index: Int,
        uid: String = "person-${index.toString().padStart(3, '0')}",
        date: Instant = time.minusSeconds(index.toLong()),
    ): RawDocument {
        val documentId = "organization_follow_${id}_$uid"
        return RawDocument(
            documentId,
            mapOf(
                "id" to documentId,
                "subscribedOrganizationId" to id,
                "userId" to uid,
                "createdAt" to date,
            ),
        )
    }

    private inner class Fake : SubscribersSource {
        var organization: RawDocument? = organization()
        var rows = (0..60).map(::row)
        var profiles: List<RawDocument>? = null
        var pageOverride: List<RawDocument>? = null
        var failure: SubscribersFailure? = null
        var confirmationFailure: SubscribersFailure? = null
        var afterProfiles: () -> Unit = {}
        var afterPage: () -> Unit = {}
        var pageDelay = 0L
        var ignoresCancellation = false
        var reads = 0
        var pageCalls = 0
        var profileCalls = 0
        var watchStarts = 0
        val cursorRequests = mutableListOf<SubscriberCursor?>()
        val profileRequests = mutableListOf<List<String>>()
        val signal = MutableSharedFlow<Result<Unit>>(extraBufferCapacity = 4)

        override suspend fun organization(id: String, session: SubscriberSession): RawDocument? {
            reads++
            return organization
        }

        override suspend fun page(
            id: String,
            after: SubscriberCursor?,
            session: SubscriberSession,
        ): List<RawDocument> {
            pageCalls++
            cursorRequests += after
            failure?.let { throw SubscribersException(it) }
            if (pageCalls % 2 == 0) confirmationFailure?.let { throw SubscribersException(it) }
            if (ignoresCancellation) withContext(NonCancellable) { delay(pageDelay) }
            else delay(pageDelay)
            afterPage()
            pageOverride?.let {
                return it
            }
            return rows
                .filter { row ->
                    after == null ||
                        SubscribersContract.order(
                            SubscriberReference("", after.createdAt, after.documentId),
                            SubscriberReference(
                                row.fields["userId"] as String,
                                row.fields["createdAt"] as Instant,
                                row.id,
                            ),
                        ) < 0
                }
                .take(51)
        }

        override suspend fun profiles(
            ids: List<String>,
            session: SubscriberSession,
        ): List<RawDocument> {
            profileCalls++
            profileRequests += ids
            afterProfiles()
            return profiles?.filter { it.id in ids }
                ?: ids.map {
                    RawDocument(
                        it,
                        mapOf(
                            "id" to it,
                            "displayName" to "Public $it",
                            "city" to "Wien",
                            "email" to "must-not-copy@example.invalid",
                            "bio" to "Never copy private biography",
                        ),
                    )
                }
        }

        override fun changes(id: String, session: SubscriberSession): Flow<Result<Unit>> {
            watchStarts++
            return signal
        }
    }

    private fun repository(source: SubscribersSource) =
        SubscribersRepository(source, { current }, { visible }, { it !in blocked })

    private fun model(source: SubscribersSource) =
        SubscribersViewModel(source, { current }, { visible }, { it !in blocked })

    private suspend fun fails(reason: SubscribersFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected $reason")
        } catch (error: SubscribersException) {
            assertEquals(reason, error.failure)
        }
    }

    @Test
    fun ordinaryVerifiedReaderDoesNotNeedOrganizationRole() = runTest {
        val source = Fake()
        val page = repository(source).load(id)
        assertEquals(50, page.references.size)
        assertEquals(SubscriberRole.OWNER, page.members.first().role)
        assertFalse(page.organization.roles.containsKey(session.uid))
        assertEquals(2, source.pageCalls)
    }

    @Test
    fun approvedSystemOrganizationUsesSameReadContract() {
        val raw =
            organization()
                .copy(
                    id = "ukrainian-community",
                    fields =
                        organization().fields +
                            mapOf("id" to "ukrainian-community", "isSystemManaged" to true),
                )
        assertEquals("ukrainian-community", SubscribersContract.organization(raw, session).id)
    }

    @Test
    fun guestAndNotReadyPerformNoReads() = runTest {
        val source = Fake()
        current = null
        fails(SubscribersFailure.SIGN_IN) { repository(source).load(id) }
        current = session.copy(ready = false)
        fails(SubscribersFailure.NOT_READY) { repository(source).load(id) }
        assertEquals(0, source.reads)
        assertEquals(0, source.pageCalls)
    }

    @Test
    fun missingDraftForeignIdentityAndInvalidIdsFailClosed() = runTest {
        val source = Fake()
        source.organization = null
        fails(SubscribersFailure.MISSING) { repository(source).load(id) }
        source.organization = organization(mapOf("moderationStatus" to "draft"))
        fails(SubscribersFailure.DENIED) { repository(source).load(id) }
        source.organization = organization(mapOf("id" to "foreign"))
        fails(SubscribersFailure.INVALID) { repository(source).load(id) }
        fails(SubscribersFailure.INVALID) { repository(source).load("../foreign") }
        assertEquals(0, source.pageCalls)
    }

    @Test
    fun rolePrecedenceDeduplicatesAndBoundsOfficialProfiles() {
        val raw =
            organization(
                mapOf(
                    "ownerId" to "same",
                    "adminIds" to (listOf("same") + (0..205).map { "admin-$it" }),
                    "moderatorIds" to listOf("same", "admin-1", "moderator"),
                )
            )
        val value = SubscribersContract.organization(raw, session)
        assertEquals(SubscriberRole.OWNER, value.roles["same"])
        assertEquals(SubscriberRole.ADMIN, value.roles["admin-1"])
        assertEquals(200, value.roles.size)
        assertTrue(value.teamTruncated)
    }

    @Test
    fun malformedRoleArraysDoNotBecomePublicRows() = runTest {
        for (field in
            listOf(
                mapOf("adminIds" to "not-array"),
                mapOf("moderatorIds" to listOf(4)),
                mapOf("ownerId" to "../escape"),
            )) fails(SubscribersFailure.INVALID) {
            SubscribersContract.organization(organization(field), session)
        }
    }

    @Test
    fun pageCursorUsesLastRawRecordEvenWhenThatPublicProfileIsMissing() = runTest {
        val source = Fake()
        source.profiles = emptyList()
        val page = repository(source).load(id)
        assertEquals(2, page.members.size)
        assertTrue(page.members.all { it.profile == null })
        assertEquals(row(49).id, page.next?.documentId)
        assertEquals(50, page.unavailable)
        val next = repository(source).load(id, page)
        assertEquals(61, next.references.size)
        assertNull(next.next)
    }

    @Test
    fun canonicalSubscriberFieldsAndTimestampAreMandatory() = runTest {
        for (invalid in
            listOf(
                row(0).copy(id = "wrong"),
                row(0).copy(fields = row(0).fields + ("id" to "wrong")),
                row(0).copy(fields = row(0).fields + ("subscribedOrganizationId" to "other")),
                row(0).copy(fields = row(0).fields + ("createdAt" to "not-timestamp")),
                row(0).copy(fields = row(0).fields + ("newsId" to "mixed-target")),
            )) {
            fails(SubscribersFailure.INVALID) {
                SubscribersContract.page(listOf(invalid), id, null)
            }
        }
    }

    @Test
    fun dateAndUtf8TiesHaveStrictDescendingOrder() = runTest {
        val supplementary = row(0, "\uD800\uDC00", time)
        val bmp = row(0, "\uE000", time)
        assertTrue(SubscribersContract.compareIds(supplementary.id, bmp.id) > 0)
        assertEquals(2, SubscribersContract.page(listOf(supplementary, bmp), id, null).size)
        fails(SubscribersFailure.INVALID) {
            SubscribersContract.page(listOf(bmp, supplementary), id, null)
        }
        fails(SubscribersFailure.INVALID) { SubscribersContract.page(listOf(bmp, bmp), id, null) }
    }

    @Test
    fun foreignBackwardAndOverlargePagesAreRejected() = runTest {
        val cursor = SubscriberCursor(id, time.minusSeconds(49), row(49).id, 50)
        fails(SubscribersFailure.INVALID) { SubscribersContract.page(listOf(row(0)), id, cursor) }
        fails(SubscribersFailure.INVALID) {
            SubscribersContract.page(emptyList(), id, cursor.copy(organizationId = "foreign"))
        }
        fails(SubscribersFailure.INVALID) {
            SubscribersContract.page(
                emptyList(),
                id,
                cursor.copy(documentId = "organization_follow_other_uid"),
            )
        }
        fails(SubscribersFailure.INVALID) { SubscribersContract.page((0..51).map(::row), id, null) }
        fails(SubscribersFailure.INVALID) {
            SubscribersContract.page(emptyList(), id, cursor.copy(consumed = 200))
        }
    }

    @Test
    fun fourPagesStopAt200WithHonestLookahead() = runTest {
        val source = Fake()
        source.rows = (0..204).map(::row)
        var page = repository(source).load(id)
        repeat(3) { page = repository(source).load(id, page) }
        assertEquals(200, page.references.size)
        assertTrue(page.capped)
        assertNull(page.next)
        assertEquals(8, source.pageCalls)
        assertTrue(source.profileRequests.all { it.size <= 10 })
        fails(SubscribersFailure.INVALID) { repository(source).load(id, page) }
    }

    @Test
    fun exactly200RecordsAreCompleteWithoutFalseCap() = runTest {
        val source = Fake()
        source.rows = (0 until 200).map(::row)
        var page = repository(source).load(id)
        repeat(3) { page = repository(source).load(id, page) }
        assertEquals(200, page.references.size)
        assertFalse(page.capped)
        assertNull(page.next)
    }

    @Test
    fun staleOrForgedPreviousSessionAndCursorCannotBeReused() = runTest {
        val source = Fake()
        val page = repository(source).load(id)
        fails(SubscribersFailure.INVALID) {
            repository(source).load(id, page.copy(session = session.copy(revision = 2)))
        }
        fails(SubscribersFailure.INVALID) {
            repository(source).load(id, page.copy(next = page.next!!.copy(documentId = row(40).id)))
        }
        source.organization = organization(mapOf("updatedAt" to time.plusSeconds(1)))
        fails(SubscribersFailure.STALE) { repository(source).load(id, page) }
    }

    @Test
    fun privateFieldsAreNeverProjectedAndWrongProfileIdIsUnavailable() {
        val uid = "person"
        val raw =
            RawDocument(
                uid,
                mapOf(
                    "id" to uid,
                    "displayName" to "  Safe\n Name ",
                    "city" to " Wien\n ",
                    "federalState" to "wien",
                    "avatarURL" to "file:///private/photo",
                    "email" to "private@example.invalid",
                    "bio" to "private biography",
                ),
            )
        val profile = SubscribersContract.profile(uid, raw)!!
        assertEquals("Safe Name", profile.displayName)
        assertEquals("Wien", profile.city)
        assertEquals("wien", profile.region)
        assertNull(profile.avatarUrl)
        assertFalse(profile.toString().contains(uid))
        assertFalse(profile.toString().contains("private"))
        assertNull(
            SubscribersContract.profile(uid, raw.copy(fields = raw.fields + ("id" to "different")))
        )
        assertNull(
            SubscribersContract.profile(
                uid,
                raw.copy(fields = mapOf("email" to "private@example.invalid")),
            )
        )
    }

    @Test
    fun unsafeRegionIsOmittedAndPublicTextIsBounded() {
        val profile =
            SubscribersContract.profile(
                "p",
                RawDocument(
                    "p",
                    mapOf(
                        "displayName" to "x".repeat(1000),
                        "city" to "c".repeat(1000),
                        "federalState" to "invalid",
                    ),
                ),
            )!!
        assertEquals(160, profile.displayName.length)
        assertEquals(160, profile.city.length)
        assertNull(profile.region)
    }

    @Test
    fun deniedOrOfflineConfirmationCannotPublishPublicJoin() = runTest {
        for (failure in listOf(SubscribersFailure.DENIED, SubscribersFailure.OFFLINE)) {
            val source = Fake()
            source.confirmationFailure = failure
            fails(failure) { repository(source).load(id) }
            assertTrue(source.profileCalls > 0)
        }
    }

    @Test
    fun changedSubscriptionDuringJoinFailsConfirmation() = runTest {
        val source = Fake()
        source.afterProfiles = { source.rows = source.rows.filter { it.id != row(0).id } }
        fails(SubscribersFailure.STALE) { repository(source).load(id) }
    }

    @Test
    fun moderationLossDuringJoinStopsBeforePublishing() = runTest {
        val source = Fake()
        source.afterProfiles = {
            source.organization = organization(mapOf("moderationStatus" to "draft"))
        }
        fails(SubscribersFailure.DENIED) { repository(source).load(id) }
    }

    @Test
    fun currentScopeIsCheckedBeforeEveryPublicProfileBatch() = runTest {
        val source = Fake()
        source.afterProfiles = { current = session.copy(revision = 2) }
        try {
            repository(source).load(id)
            fail("Old scope")
        } catch (_: CancellationException) {}
        assertEquals(1, source.profileCalls)
        assertEquals(1, source.pageCalls)
    }

    @Test
    fun unknownOrBlockedOrganizationNeverQueriesSubscriptions() = runTest {
        val source = Fake()
        visible = false
        fails(SubscribersFailure.POLICY) { repository(source).load(id) }
        assertEquals(0, source.pageCalls)
        assertEquals(0, source.profileCalls)
    }

    @Test
    fun blockedAuthorsAreNotFetchedAndLiveProjectionMasksOldRows() = runTest {
        val source = Fake()
        blocked += "person-000"
        val page = repository(source).load(id)
        assertFalse(source.profileRequests.flatten().contains("person-000"))
        assertFalse(page.members.any { it.userId == "person-000" })
        val state = SubscribersState(session, id, true, page = page)
        blocked += "person-001"
        assertFalse(
            state.visiblePage({ true }, { it !in blocked })!!.members.any {
                it.userId == "person-001"
            }
        )
        assertNull(state.visiblePage({ false }, { true }))
    }

    @Test
    fun orderingKeepsRolesBeforeNewestSubscriptionsAndSearchUsesOnlyPublicNames() = runTest {
        val page = repository(Fake()).load(id)
        val people = SubscribersContract.visible(page.members, "", "de") { true }
        assertEquals(
            listOf(SubscriberRole.OWNER, SubscriberRole.ADMIN),
            people.take(2).map { it.role },
        )
        assertEquals("person-000", people[2].userId)
        assertTrue(
            SubscribersContract.visible(page.members, "must-not-copy", "de") { true }.isEmpty()
        )
        assertEquals(
            listOf("person-010"),
            SubscribersContract.visible(page.members, "person-010", "uk") { true }
                .map { it.userId },
        )
    }

    @Test
    fun projectionRequiresExactSessionTargetForegroundAndNoError() = runTest {
        val page = repository(Fake()).load(id)
        val state = SubscribersState(session, id, true, page = page)
        for (hidden in
            listOf(
                state.copy(visible = false),
                state.copy(loading = true),
                state.copy(error = SubscribersFailure.OFFLINE),
                state.copy(session = session.copy(revision = 2)),
                state.copy(organizationId = "other"),
                state.forSession(null, id),
            )) assertNull(hidden.visiblePage({ true }, { true }))
    }

    @Test
    fun modelAttachHideAndDuplicateMoreAreBounded() = runTest {
        val source = Fake()
        val vm = model(source)
        vm.show(id)
        advanceUntilIdle()
        assertEquals(50, vm.state.value.page?.references?.size)
        assertEquals(1, source.watchStarts)
        vm.refresh(more = true)
        vm.refresh(more = true)
        advanceUntilIdle()
        assertEquals(61, vm.state.value.page?.references?.size)
        assertEquals(4, source.pageCalls)
        vm.hide()
        assertNull(vm.state.value.page)
        assertFalse(vm.state.value.visible)
    }

    @Test
    fun lateOldAccountPageCannotReappear() = runTest {
        val source = Fake()
        source.pageDelay = 100
        source.ignoresCancellation = true
        val vm = model(source)
        vm.show(id)
        runCurrent()
        current = session.copy(uid = "new-reader", revision = 2)
        vm.bind(current)
        advanceUntilIdle()
        assertNull(vm.state.value.page)
        assertEquals(current, vm.state.value.session)
        assertEquals(0, source.profileCalls)
    }

    @Test
    fun failedWatchClearsRowsAndExplicitRetryReattaches() = runTest {
        val source = Fake()
        val vm = model(source)
        vm.show(id)
        advanceUntilIdle()
        source.signal.emit(Result.failure(SubscribersException(SubscribersFailure.OFFLINE)))
        advanceUntilIdle()
        assertNull(vm.state.value.page)
        assertEquals(SubscribersFailure.OFFLINE, vm.state.value.error)
        vm.refresh()
        advanceUntilIdle()
        assertNotNull(vm.state.value.page)
        assertEquals(2, source.watchStarts)
        vm.hide()
    }

    @Test
    fun metadataInvalidationHidesImmediatelyAndOfflineReadCannotPublish() = runTest {
        val source = Fake()
        val vm = model(source)
        vm.show(id)
        advanceUntilIdle()
        source.pageDelay = 100
        source.signal.emit(Result.success(Unit))
        runCurrent()
        assertTrue(vm.state.value.loading)
        assertNull(vm.state.value.page)
        source.confirmationFailure = SubscribersFailure.OFFLINE
        advanceUntilIdle()
        assertNull(vm.state.value.page)
        assertEquals(SubscribersFailure.OFFLINE, vm.state.value.error)
        source.confirmationFailure = null
        vm.refresh()
        advanceUntilIdle()
        assertNotNull(vm.state.value.page)
        assertEquals(2, source.watchStarts)
        vm.hide()
    }

    @Test
    fun burstInvalidationsCoalesceAndRecheckWithoutCanceledReadSpin() = runTest {
        val source = Fake()
        val vm = model(source)
        vm.show(id)
        advanceUntilIdle()
        source.pageDelay = 50
        source.signal.emit(Result.success(Unit))
        runCurrent()
        repeat(3) { source.signal.emit(Result.success(Unit)) }
        runCurrent()
        assertTrue(vm.state.value.loading)
        assertNull(vm.state.value.page)
        advanceUntilIdle()
        assertEquals(50, vm.state.value.page?.references?.size)
        assertEquals(
            6,
            source.pageCalls,
        ) // Initial page + one in-flight check + one coalesced recheck.
        assertEquals(1, source.watchStarts)
        vm.hide()
    }

    @Test
    fun continuouslyChangingWatchIsBoundedAndOffersExplicitRetry() = runTest {
        val source = Fake()
        val vm = model(source)
        vm.show(id)
        advanceUntilIdle()
        source.pageDelay = 1
        source.afterProfiles = { source.signal.tryEmit(Result.success(Unit)) }
        source.signal.emit(Result.success(Unit))
        advanceUntilIdle()
        assertNull(vm.state.value.page)
        assertFalse(vm.state.value.loading)
        assertEquals(SubscribersFailure.STALE, vm.state.value.error)
        assertEquals(8, source.pageCalls)
        source.afterProfiles = {}
        vm.refresh()
        advanceUntilIdle()
        assertNotNull(vm.state.value.page)
        assertEquals(2, source.watchStarts)
        vm.hide()
    }

    @Test
    fun watchedChangeRevalidatesTheLoadedWindowWithoutRevertingToFirstPage() = runTest {
        val source = Fake()
        val vm = model(source)
        vm.show(id)
        advanceUntilIdle()
        vm.refresh(more = true)
        advanceUntilIdle()
        assertEquals(61, vm.state.value.page?.references?.size)
        source.signal.emit(Result.success(Unit))
        advanceUntilIdle()
        assertEquals(61, vm.state.value.page?.references?.size)
        assertEquals(1, source.watchStarts)
        vm.hide()
    }

    @Test
    fun accountAndPolicyTransitionsClearNamesThenRecoverThroughFreshRead() = runTest {
        val source = Fake()
        val vm = model(source)
        vm.show(id)
        advanceUntilIdle()
        visible = false
        vm.visibilityChanged()
        advanceUntilIdle()
        assertNull(vm.state.value.page)
        assertEquals(SubscribersFailure.POLICY, vm.state.value.error)
        visible = true
        vm.visibilityChanged()
        advanceUntilIdle()
        assertNotNull(vm.state.value.page)
        current = null
        vm.bind(null)
        assertNull(vm.state.value.page)
        assertEquals("", vm.state.value.search)
    }

    @Test
    fun notReadyModelHasAnExplicitAccountStateWithoutSourceReads() = runTest {
        val source = Fake()
        current = session.copy(ready = false)
        val vm = model(source)
        vm.show(id)
        advanceUntilIdle()
        assertEquals(SubscribersFailure.NOT_READY, vm.state.value.error)
        assertFalse(vm.state.value.loading)
        assertEquals(0, source.reads)
    }
}
