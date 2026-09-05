package at.uac.android

import at.uac.android.feature.browse.*
import at.uac.android.feature.community.CommunityContract
import at.uac.android.feature.personal.*
import at.uac.android.feature.registrations.*
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class RegistrationsTest {
    private val alice = PersonalSession("synthetic-alice", true, true, 1)
    private val now = Instant.parse("2026-09-03T10:00:00Z")
    private var current: PersonalSession? = alice

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun teardown() {
        Dispatchers.resetMain()
    }

    private fun event(
        id: String,
        start: Instant = now,
        end: Instant = now.plusSeconds(3600),
        extra: Fields = emptyMap(),
    ) =
        RawDocument(
            id,
            mapOf(
                "title" to "Synthetic $id",
                "summary" to "Synthetic summary",
                "details" to "Synthetic details",
                "createdAt" to now,
                "updatedAt" to now,
                "startDate" to start,
                "endDate" to end,
                "moderationStatus" to "approved",
                "sourceType" to "organization",
                "city" to "Wien",
            ) + extra,
        )

    private fun marker(eventId: String, uid: String = alice.uid): RawDocument {
        val id = CommunityContract.registrationId(eventId, uid)
        return RawDocument(
            id,
            mapOf("id" to id, "eventId" to eventId, "userId" to uid, "registeredAt" to now),
        )
    }

    private inner class Fake : RegistrationsSource {
        var markers = listOf(marker("event-a"))
        var records = listOf(event("event-a"))
        var delayMs = 0L
        var failure: PersonalFailure? = null
        var forced: MarkerPage? = null
        val chunks = mutableListOf<List<String>>()
        var wrongTarget = false

        override suspend fun page(uid: String, after: String?, size: Int): MarkerPage {
            delay(delayMs)
            failure?.let { throw PersonalException(it) }
            forced?.let {
                return it
            }
            val remaining = markers.filter { after == null || it.id > after }.sortedBy { it.id }
            val selected = remaining.take(size)
            return MarkerPage(selected, selected.lastOrNull()?.id ?: after, remaining.size > size)
        }

        override suspend fun events(ids: List<String>): List<RawDocument> {
            chunks += ids
            return if (wrongTarget) listOf(event("foreign-event"))
            else records.filter { it.id in ids }
        }
    }

    private fun repository(source: RegistrationsSource) =
        RegistrationsRepository(source) { current }

    private suspend fun failure(reason: PersonalFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $reason")
        } catch (error: PersonalException) {
            assertEquals(reason, error.reason)
        }
    }

    @Test
    fun ownMarkersResolveApprovedOrganizationEvents() = runTest {
        val result = repository(Fake()).load()
        assertEquals(listOf("event-a"), result.items.map { it.id })
        assertEquals(0, result.unavailable)
        assertFalse(result.hasMore)
    }

    @Test
    fun guestAndUnreadyNeverRead() = runTest {
        val source = Fake()
        current = null
        failure(PersonalFailure.SIGN_IN) { repository(source).load() }
        current = alice.copy(emailVerified = false)
        failure(PersonalFailure.NOT_READY) { repository(source).load() }
        assertTrue(source.chunks.isEmpty())
    }

    @Test
    fun canonicalMarkerIdentityCannotBeSpoofed() = runTest {
        for (bad in
            listOf(
                marker("event-a", "synthetic-bob"),
                marker("event-a").copy(id = "spoof"),
                marker("event-a")
                    .copy(fields = marker("event-a").fields + ("registeredAt" to "date")),
            )) {
            failure(PersonalFailure.INVALID) {
                repository(Fake().apply { markers = listOf(bad) }).load()
            }
        }
    }

    @Test
    fun missingPrivateAndMalformedEventsRemainUnavailableNotDeleted() = runTest {
        val source =
            Fake().apply {
                markers = listOf("a", "b", "c", "d").map { marker(it) }
                records =
                    listOf(
                        event("a", extra = mapOf("moderationStatus" to "rejected")),
                        event("b", extra = mapOf("sourceType" to "app")),
                        event("c", extra = mapOf("startDate" to "bad")),
                    )
            }
        val result = repository(source).load()
        assertTrue(result.items.isEmpty())
        assertEquals(4, result.unavailable)
        assertEquals(4, source.markers.size)
    }

    @Test
    fun paginationUsesMarkerCursorNotEventDateOrFilteredRows() = runTest {
        val source =
            Fake().apply {
                markers = listOf(marker("a"), marker("b"))
                records = listOf(event("b"))
            }
        val first = repository(source).load(size = 1)
        assertTrue(first.items.isEmpty())
        assertTrue(first.hasMore)
        assertEquals(marker("a").id, first.next)
        assertEquals(listOf("b"), repository(source).load(first.next, 1).items.map { it.id })
    }

    @Test
    fun repeatedCursorDuplicateOrForeignRowsAreRejected() = runTest {
        val source = Fake()
        source.forced = MarkerPage(emptyList(), "old", true)
        failure(PersonalFailure.INVALID) { repository(source).load("old") }
        source.forced = MarkerPage(listOf(marker("a"), marker("a")), marker("a").id, false)
        failure(PersonalFailure.INVALID) { repository(source).load() }
        source.forced = null
        source.wrongTarget = true
        failure(PersonalFailure.INVALID) { repository(source).load() }
    }

    @Test
    fun eventResolutionIsBoundedInTenIdChunks() = runTest {
        val source =
            Fake().apply {
                markers = (1..23).map { marker("event-${it.toString().padStart(2, '0')}") }
                records = markers.map { event(it.fields.string("eventId")) }
            }
        assertEquals(23, repository(source).load().items.size)
        assertEquals(listOf(10, 10, 3), source.chunks.map { it.size })
    }

    @Test
    fun sameUidNewRevisionQuarantinesLateResponse() = runTest {
        val source = Fake().apply { delayMs = 500 }
        val pending = async { repository(source).load() }
        runCurrent()
        current = alice.copy(revision = 2)
        advanceUntilIdle()
        try {
            pending.await()
            fail("Old response accepted")
        } catch (_: CancellationException) {}
    }

    @Test
    fun queryDeadlineReportsOfflineNotEmptySuccess() = runTest {
        failure(PersonalFailure.OFFLINE) { repository(Fake().apply { delayMs = 30_000 }).load() }
    }

    @Test
    fun localMidnightAndSameDayFollowBuild65IncludingDst() {
        val zone = ZoneId.of("Europe/Vienna")
        val day = Instant.parse("2026-10-25T12:00:00Z")
        val midnight = Instant.parse("2026-10-24T22:00:00Z")
        val rows =
            listOf(
                    event("boundary", midnight.minusSeconds(3600), midnight),
                    event("past", midnight.minusSeconds(7200), midnight.minusNanos(1)),
                    event("today", day.minusSeconds(7200), day.minusSeconds(3600)),
                )
                .map { decodeContent(ContentKind.EVENTS, it) }
        assertEquals(
            listOf("boundary", "today"),
            registrationEvents(rows, RegistrationSegment.UPCOMING, day, zone).map { it.id },
        )
        assertEquals(
            listOf("past"),
            registrationEvents(rows, RegistrationSegment.PAST, day, zone).map { it.id },
        )
        assertEquals(
            listOf("boundary", "today", "past"),
            registrationEvents(rows, RegistrationSegment.ALL, day, zone).map { it.id },
        )
    }

    @Test
    fun sortingTiesHaveDeterministicIds() {
        val rows = listOf("z", "a").map { decodeContent(ContentKind.EVENTS, event(it)) }
        assertEquals(
            listOf("a", "z"),
            registrationEvents(rows, RegistrationSegment.ALL, now, ZoneId.of("UTC")).map { it.id },
        )
    }

    @Test
    fun accountMaskAndPrivateVisibilityHideImmediately() {
        val state =
            RegistrationsState(
                session = alice,
                items = listOf(decodeContent(ContentKind.EVENTS, event("a"))),
            )
        assertTrue(state.forSession(alice.copy(revision = 2)).items.isEmpty())
        assertTrue(state.visibleTo { false }.items.isEmpty())
        assertEquals(1, state.items.size)
    }

    @Test
    fun viewModelPreservesConfirmedListOnlyForOfflineAndClearsDenied() = runTest {
        val source = Fake()
        val model = RegistrationsViewModel(source, { current }, this)
        model.bind(alice)
        model.refresh()
        advanceUntilIdle()
        assertEquals(1, model.state.value.items.size)
        source.failure = PersonalFailure.OFFLINE
        model.refresh()
        advanceUntilIdle()
        assertEquals(1, model.state.value.items.size)
        assertEquals(PersonalFailure.OFFLINE, model.state.value.error)
        source.failure = PersonalFailure.DENIED
        model.refresh()
        advanceUntilIdle()
        assertTrue(model.state.value.items.isEmpty())
        assertEquals(PersonalFailure.DENIED, model.state.value.error)
    }

    @Test
    fun logoutCancelsPendingLoadWithoutRepopulatingPrivateState() = runTest {
        val source = Fake().apply { delayMs = 500 }
        val model = RegistrationsViewModel(source, { current }, this)
        model.bind(alice)
        model.refresh()
        runCurrent()
        current = null
        model.bind(null)
        advanceUntilIdle()
        assertNull(model.state.value.session)
        assertTrue(model.state.value.items.isEmpty())
        assertFalse(model.state.value.loading)
    }
}
