package at.uac.android

import androidx.lifecycle.ViewModelStore
import at.uac.android.feature.attendees.*
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
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
class AttendeesTest {
    private val alice = AttendeesSession("synthetic-manager", 1, true, "user")
    private var authority: AttendeesSession? = alice
    private val instant = Instant.parse("2026-09-03T10:00:00Z")
    private val eventId = "synthetic-event"
    private val organizationId = "synthetic-organization"

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun teardown() {
        Dispatchers.resetMain()
    }

    private fun event(extra: Fields = emptyMap()) =
        RawDocument(
            eventId,
            mapOf(
                "id" to eventId,
                "sourceType" to "organization",
                "organizationId" to organizationId,
                "requiresRegistration" to true,
                "registeredCount" to 31L,
                "capacity" to 100L,
                "title" to "Synthetic managed event",
                "localizations" to
                    mapOf(
                        "de" to mapOf("title" to "Synthetic managed event"),
                        "uk" to mapOf("title" to "Тестова подія"),
                    ),
            ) + extra,
        )

    private fun organization(extra: Fields = emptyMap()) =
        RawDocument(
            organizationId,
            mapOf(
                "ownerId" to alice.uid,
                "adminIds" to emptyList<String>(),
                "moderatorIds" to emptyList<String>(),
            ) + extra,
        )

    private fun row(uid: String = "synthetic-person-00", extra: Fields = emptyMap()): RawDocument {
        val id = "event_${eventId}_$uid"
        return RawDocument(
            id,
            mapOf("id" to id, "eventId" to eventId, "userId" to uid, "registeredAt" to instant) +
                extra,
        )
    }

    private inner class Fake : AttendeesSource {
        var event = event()
        var organization: RawDocument? = organization()
        var rows = listOf(row())
        var profileRows: List<RawDocument>? = null
        var failure: AttendeesFailure? = null
        var forced: AttendeesRawPage? = null
        var delayMs = 0L
        var ignoreCancellation = false
        var afterProfile: () -> Unit = {}
        var eventReads = 0
        var profileReads = 0
        var watchStarts = 0
        val requested = mutableListOf<String?>()
        val signal = MutableSharedFlow<Result<Unit>>(extraBufferCapacity = 4)

        override suspend fun event(id: String, session: AttendeesSession): RawDocument {
            eventReads++
            return event
        }

        override suspend fun organization(id: String, session: AttendeesSession) = organization

        override suspend fun registrations(
            id: String,
            after: String?,
            session: AttendeesSession,
        ): AttendeesRawPage {
            requested += after
            if (ignoreCancellation) withContext(NonCancellable) { delay(delayMs) }
            else delay(delayMs)
            failure?.let { throw AttendeesException(it) }
            forced?.let {
                return it
            }
            val remaining =
                rows
                    .sortedWith { a, b -> AttendeesContract.compareDocumentIds(a.id, b.id) }
                    .filter {
                        after == null || AttendeesContract.compareDocumentIds(it.id, after) > 0
                    }
            val result = remaining.take(25)
            return AttendeesRawPage(result, result.lastOrNull()?.id?.takeIf { remaining.size > 25 })
        }

        override suspend fun profiles(
            ids: List<String>,
            session: AttendeesSession,
        ): List<RawDocument> {
            profileReads++
            afterProfile()
            return profileRows
                ?: ids.map {
                    RawDocument(
                        it,
                        mapOf(
                            "displayName" to "Public $it",
                            "email" to "not-exposed@example.invalid",
                            "bio" to "private",
                        ),
                    )
                }
        }

        override fun changes(
            id: String,
            organizationId: String?,
            session: AttendeesSession,
        ): Flow<Result<Unit>> {
            watchStarts++
            return signal
        }

        override fun accessChanges(
            id: String,
            organizationId: String?,
            session: AttendeesSession,
        ): Flow<Result<Unit>> = signal
    }

    private fun repository(source: AttendeesSource) = AttendeesRepository(source) { authority }

    private suspend fun failure(expected: AttendeesFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: AttendeesException) {
            assertEquals(expected, error.failure)
        }
    }

    private fun model(source: AttendeesSource) = AttendeesViewModel(source) { authority }

    @Test
    fun organizationOwnerAdminAndModeratorMatchIosUi() {
        for (role in listOf("ownerId", "adminIds", "moderatorIds")) {
            val data =
                mapOf(
                    "ownerId" to "someone-else",
                    "adminIds" to emptyList<String>(),
                    "moderatorIds" to emptyList<String>(),
                ) + (role to if (role == "ownerId") alice.uid else listOf(alice.uid))
            assertEquals(
                eventId,
                AttendeesContract.authorize(event(), RawDocument(organizationId, data), alice).id,
            )
        }
    }

    @Test
    fun eventTitlesUseActualLocalizedContract() {
        val target = AttendeesContract.authorize(event(), organization(), alice)
        assertEquals("Тестова подія", target.title("uk"))
        assertEquals("Synthetic managed event", target.title("de"))
    }

    @Test
    fun unassignedPlatformAdminAndAuthorAreNotUiManagers() = runTest {
        failure(AttendeesFailure.DENIED) {
            AttendeesContract.authorize(
                event(mapOf("authorId" to alice.uid)),
                organization(mapOf("ownerId" to "other")),
                alice,
            )
        }
        failure(AttendeesFailure.DENIED) {
            AttendeesContract.authorize(
                event(),
                organization(mapOf("ownerId" to "other")),
                alice.copy(globalRole = "admin"),
            )
        }
    }

    @Test
    fun systemOrganizationOnlyAllowsPlatformOwner() = runTest {
        failure(AttendeesFailure.DENIED) {
            AttendeesContract.authorize(
                event(),
                organization(mapOf("isSystemManaged" to true)),
                alice,
            )
        }
        assertEquals(
            eventId,
            AttendeesContract.authorize(
                    event(mapOf("sourceType" to "app")),
                    null,
                    alice.copy(globalRole = "owner"),
                )
                .id,
        )
    }

    @Test
    fun missingOrForeignOrganizationAndNoRegistrationAreExplicit() = runTest {
        failure(AttendeesFailure.DENIED) { AttendeesContract.authorize(event(), null, alice) }
        failure(AttendeesFailure.DENIED) {
            AttendeesContract.authorize(event(), organization().copy(id = "foreign"), alice)
        }
        failure(AttendeesFailure.NOT_APPLICABLE) {
            AttendeesContract.authorize(
                event(mapOf("requiresRegistration" to false, "registeredCount" to 0L)),
                organization(),
                alice,
            )
        }
        assertEquals(
            1L,
            AttendeesContract.authorize(
                    event(mapOf("requiresRegistration" to false, "registeredCount" to 1)),
                    organization(),
                    alice,
                )
                .registeredCount,
        )
    }

    @Test
    fun invalidEventIdentityCountsAndCapacityFailClosed() = runTest {
        for (extra in
            listOf(
                mapOf("id" to "foreign"),
                mapOf("registeredCount" to -1),
                mapOf("registeredCount" to Double.NaN),
                mapOf("registeredCount" to Double.POSITIVE_INFINITY),
                mapOf("registeredCount" to 2.5),
                mapOf("capacity" to "100"),
            )) {
            failure(AttendeesFailure.INVALID) {
                AttendeesContract.authorize(event(extra), organization(), alice)
            }
        }
    }

    @Test
    fun guestAndEveryNotReadySessionAreRejectedBeforeReads() = runTest {
        val source = Fake()
        authority = null
        failure(AttendeesFailure.SIGN_IN) { repository(source).load(eventId) }
        authority = alice.copy(ready = false)
        failure(AttendeesFailure.NOT_READY) { repository(source).load(eventId) }
        assertEquals(0, source.eventReads)
        assertTrue(source.requested.isEmpty())
    }

    @Test
    fun canonicalRowsValidateEveryIdentityAndKeepLegacyMissingTime() {
        assertNotNull(AttendeesContract.row(row(), eventId))
        assertNull(AttendeesContract.row(row().copy(id = "spoof"), eventId))
        assertNull(AttendeesContract.row(row(extra = mapOf("id" to "spoof")), eventId))
        assertNull(AttendeesContract.row(row(extra = mapOf("eventId" to "other")), eventId))
        assertNull(AttendeesContract.row(row(extra = mapOf("userId" to "../bad")), eventId))
        assertEquals(
            instant.minusSeconds(10),
            AttendeesContract.row(
                    row(
                        extra =
                            mapOf("registeredAt" to null, "createdAt" to instant.minusSeconds(10))
                    ),
                    eventId,
                )
                ?.registeredAt,
        )
        assertNull(
            AttendeesContract.row(row(extra = mapOf("registeredAt" to null)), eventId)?.registeredAt
        )
    }

    @Test
    fun joinsUseOnlyPublicNameAndSafeAvatarWithGenericMissingProfile() = runTest {
        val source = Fake()
        val result = repository(source).load(eventId)
        assertEquals("Public synthetic-person-00", result.people.single().displayName)
        assertNull(result.people.single().avatarUrl)
        assertFalse(result.people.single().toString().contains("synthetic-person"))
        val person = result.people.single().copy(displayName = null)
        assertEquals(
            person,
            AttendeesContract.withProfile(
                person,
                RawDocument("foreign", mapOf("displayName" to "Wrong")),
            ),
        )
        assertEquals(
            person,
            AttendeesContract.withProfile(
                person,
                RawDocument(person.userId, mapOf("displayName" to "  ")),
            ),
        )
        assertNull(
            AttendeesContract.withProfile(
                    person,
                    RawDocument(
                        person.userId,
                        mapOf("displayName" to "Public", "avatarURL" to "file:///private"),
                    ),
                )
                .avatarUrl
        )
        source.profileRows = emptyList()
        assertNull(repository(source).load(eventId).people.single().displayName)
    }

    @Test
    fun paginationIncludesLegacyDatesAndKeepsBoundCursorAndSession() = runTest {
        val source =
            Fake().apply {
                rows =
                    (0..30).map {
                        row(
                            "synthetic-person-${it.toString().padStart(2, '0')}",
                            mapOf("registeredAt" to null),
                        )
                    }
            }
        val repo = repository(source)
        val first = repo.load(eventId)
        assertEquals(25, first.people.size)
        assertNotNull(first.next)
        assertEquals(alice, first.session)
        val second = repo.load(eventId, first)
        assertEquals(31, second.people.size)
        assertNull(second.next)
        assertEquals(listOf(null, first.next!!.documentId), source.requested)
        assertTrue(second.people.all { it.registeredAt == null })
    }

    @Test
    fun malformedRowsAreExplicitlyOmittedWithoutChangingSource() = runTest {
        val source =
            Fake().apply {
                rows = listOf(row(), row("synthetic-person-01", mapOf("eventId" to "foreign")))
            }
        val page = repository(source).load(eventId)
        assertEquals(1, page.people.size)
        assertEquals(1, page.invalid)
        assertEquals(2, source.rows.size)
    }

    @Test
    fun duplicateUnorderedOversizedAndNonAdvancingPagesFailClosed() = runTest {
        val source = Fake()
        for (raw in
            listOf(
                AttendeesRawPage(listOf(row(), row()), null),
                AttendeesRawPage(listOf(row("z"), row("a")), null),
                AttendeesRawPage((0..25).map { row("u${it.toString().padStart(2, '0')}") }, null),
                AttendeesRawPage(listOf(row()), row().id),
            )) {
            source.forced = raw
            failure(AttendeesFailure.INVALID) { repository(source).load(eventId) }
        }
        source.forced = null
        source.rows = (0..25).map { row("u${it.toString().padStart(2, '0')}") }
        val first = repository(source).load(eventId)
        source.forced = AttendeesRawPage(listOf(source.rows.first()), null)
        failure(AttendeesFailure.INVALID) { repository(source).load(eventId, first) }
    }

    @Test
    fun foreignTargetScopeAndCursorCannotReusePrivatePages() = runTest {
        val source =
            Fake().apply { rows = (0..25).map { row("u${it.toString().padStart(2, '0')}") } }
        val first = repository(source).load(eventId)
        for (bad in
            listOf(
                first.copy(session = alice.copy(revision = 2)),
                first.copy(next = AttendeesCursor("foreign", first.next!!.documentId)),
                first.copy(next = AttendeesCursor(eventId, "../bad")),
                first.copy(event = first.event.copy(id = "foreign")),
            )) {
            failure(AttendeesFailure.INVALID) { repository(source).load(eventId, bad) }
        }
    }

    @Test
    fun unexpectedPublicJoinRowsAndDuplicatesAreRejected() = runTest {
        val source = Fake().apply { profileRows = listOf(RawDocument("foreign", emptyMap())) }
        failure(AttendeesFailure.INVALID) { repository(source).load(eventId) }
        source.profileRows =
            listOf(
                RawDocument("synthetic-person-00", emptyMap()),
                RawDocument("synthetic-person-00", emptyMap()),
            )
        failure(AttendeesFailure.INVALID) { repository(source).load(eventId) }
    }

    @Test
    fun roleIsRevalidatedAfterThePublicJoin() = runTest {
        val source =
            Fake().apply {
                afterProfile = { organization = organization(mapOf("ownerId" to "other")) }
            }
        failure(AttendeesFailure.DENIED) { repository(source).load(eventId) }
        assertEquals(2, source.eventReads)
    }

    @Test
    fun sameUidNewRevisionDiscardsResponseWithoutPublishing() = runTest {
        val source = Fake().apply { afterProfile = { authority = alice.copy(revision = 2) } }
        try {
            repository(source).load(eventId)
            fail("Old session accepted")
        } catch (_: CancellationException) {}
    }

    @Test
    fun sortingAndSearchUseOnlyLoadedPublicNamesWithMissingTimesLast() {
        fun person(uid: String, name: String?, time: Instant?) =
            Attendee("event_$uid", uid, time, name, null)
        val rows =
            listOf(
                person("c", "Überblick", instant.plusSeconds(1)),
                person("b", "Alpha", instant),
                person("a", null, null),
            )
        assertEquals(
            listOf("b", "c", "a"),
            AttendeesContract.visible(rows, "", AttendeesSort.OLDEST, "de").map { it.userId },
        )
        assertEquals(
            listOf("c", "b", "a"),
            AttendeesContract.visible(rows, "", AttendeesSort.NEWEST, "de").map { it.userId },
        )
        assertEquals(
            listOf("c"),
            AttendeesContract.visible(rows, "UBER", AttendeesSort.NAME_ASCENDING, "de").map {
                it.userId
            },
        )
        assertTrue(
            AttendeesContract.visible(rows, "a@example.invalid", AttendeesSort.OLDEST, "de")
                .isEmpty()
        )
    }

    @Test
    fun utf8DocumentOrderHandlesNonBmpIds() {
        assertTrue(AttendeesContract.compareDocumentIds("a", "b") < 0)
        assertTrue(AttendeesContract.compareDocumentIds("a", "aa") < 0)
        assertTrue(AttendeesContract.compareDocumentIds("\uE000", "\uD800\uDC00") < 0)
        assertEquals(0, AttendeesContract.compareDocumentIds("подія", "подія"))
    }

    @Test
    fun everySessionOrTargetMismatchMasksTheListSynchronously() = runTest {
        val state = AttendeesState(alice, eventId, true, page = repository(Fake()).load(eventId))
        assertNull(state.forSession(null, eventId).page)
        assertNull(state.forSession(alice.copy(revision = 2), eventId).page)
        assertNull(state.forSession(alice, "foreign").page)
    }

    @Test
    fun viewModelClearsPrivateRowsBeforeReadsAndOnEveryFailure() = runTest {
        val source = Fake()
        val model = model(source)
        model.show(eventId)
        advanceUntilIdle()
        assertEquals(1, model.state.value.page!!.people.size)
        source.failure = AttendeesFailure.OFFLINE
        model.refresh()
        assertNull(model.state.value.page)
        advanceUntilIdle()
        assertEquals(AttendeesFailure.OFFLINE, model.state.value.error)
        assertNull(model.state.value.page)
        source.failure = AttendeesFailure.DENIED
        model.refresh()
        advanceUntilIdle()
        assertEquals(AttendeesFailure.DENIED, model.state.value.error)
        model.hide()
    }

    @Test
    fun permissionAndOfflineSignalsClearAndExplicitRefreshRecovers() = runTest {
        val source = Fake()
        val model = model(source)
        model.show(eventId)
        advanceUntilIdle()
        source.signal.emit(Result.failure(AttendeesException(AttendeesFailure.OFFLINE)))
        runCurrent()
        assertNull(model.state.value.page)
        assertEquals(AttendeesFailure.OFFLINE, model.state.value.error)
        model.refresh()
        advanceUntilIdle()
        assertEquals(1, model.state.value.page!!.people.size)
        source.organization = organization(mapOf("ownerId" to "other"))
        source.signal.emit(Result.success(Unit))
        advanceUntilIdle()
        assertNull(model.state.value.page)
        assertEquals(AttendeesFailure.DENIED, model.state.value.error)
        model.hide()
    }

    @Test
    fun explicitRetryReattachesTheTerminatedRegistrationListener() = runTest {
        val source = Fake()
        val model = model(source)
        model.show(eventId)
        advanceUntilIdle()
        assertEquals(1, source.watchStarts)
        source.signal.emit(Result.failure(AttendeesException(AttendeesFailure.DENIED)))
        runCurrent()
        assertNull(model.state.value.page)
        assertEquals(AttendeesFailure.DENIED, model.state.value.error)
        model.refresh()
        advanceUntilIdle()
        assertEquals(2, source.watchStarts)
        source.rows = listOf(row("person-a"), row("person-b"))
        source.signal.emit(Result.success(Unit))
        advanceUntilIdle()
        assertEquals(2, model.state.value.page!!.people.size)
        assertEquals(2, source.watchStarts)
        model.hide()
    }

    @Test
    fun logoutOrHideDoesNotResurrectUncancellableLateRead() = runTest {
        val source =
            Fake().apply {
                delayMs = 500
                ignoreCancellation = true
            }
        val model = model(source)
        model.show(eventId)
        runCurrent()
        authority = null
        model.bind(null)
        advanceUntilIdle()
        assertNull(model.state.value.page)
        assertNull(model.state.value.session)
        authority = alice
        model.show(eventId)
        runCurrent()
        model.hide()
        advanceUntilIdle()
        assertFalse(model.state.value.visible)
        assertNull(model.state.value.page)
    }

    @Test
    fun duplicateMoreTapUsesOneReadAndSearchIsBounded() = runTest {
        val source =
            Fake().apply { rows = (0..25).map { row("u${it.toString().padStart(2, '0')}") } }
        val model = model(source)
        model.show(eventId)
        advanceUntilIdle()
        model.search("x".repeat(500))
        assertEquals(160, model.state.value.search.length)
        model.refresh(true)
        model.refresh(true)
        advanceUntilIdle()
        assertEquals(2, source.requested.size)
        assertEquals(26, model.state.value.page!!.people.size)
        model.hide()
    }

    @Test
    fun clearingViewModelRemovesEveryPrivateField() = runTest {
        val model = model(Fake())
        val store = ViewModelStore().apply { put("attendees", model) }
        model.show(eventId)
        advanceUntilIdle()
        model.search("private filter")
        store.clear()
        assertEquals(AttendeesState(), model.state.value)
    }

    @Test
    fun accessCheckNeverQueriesRegistrationsOrPublicProfiles() = runTest {
        val source = Fake().apply { failure = AttendeesFailure.DENIED }
        assertEquals(eventId, repository(source).access(eventId).id)
        assertTrue(source.requested.isEmpty())
        assertEquals(0, source.profileReads)
    }

    @Test
    fun accessEntryRevalidatesRoleLossAndGainWithoutPrivatePrefetch() = runTest {
        val source = Fake()
        val model = AttendeesAccessViewModel(source) { authority }
        model.show(eventId)
        advanceUntilIdle()
        assertTrue(model.canOpen(eventId, alice))
        source.organization = organization(mapOf("ownerId" to "other"))
        source.signal.emit(Result.success(Unit))
        advanceUntilIdle()
        assertFalse(model.canOpen(eventId, alice))
        assertEquals(AttendeesFailure.DENIED, model.state.value.error)
        source.organization = organization()
        source.signal.emit(Result.success(Unit))
        advanceUntilIdle()
        assertTrue(model.canOpen(eventId, alice))
        assertTrue(source.requested.isEmpty())
        assertEquals(0, source.profileReads)
        model.hide()
        assertFalse(model.canOpen(eventId, alice))
    }

    @Test
    fun accessMaskAndResumeRequireExactSessionAndFreshPublicAuthority() = runTest {
        val source = Fake()
        val model = AttendeesAccessViewModel(source) { authority }
        model.show(eventId)
        advanceUntilIdle()
        authority = alice.copy(revision = 2)
        assertFalse(model.canOpen(eventId, alice))
        assertFalse(model.state.value.forSession(authority, eventId).permitted)
        model.bind(authority)
        model.show(eventId)
        assertFalse(model.state.value.permitted)
        advanceUntilIdle()
        assertTrue(model.canOpen(eventId, authority))
        source.signal.emit(Result.failure(AttendeesException(AttendeesFailure.OFFLINE)))
        runCurrent()
        assertFalse(model.canOpen(eventId, authority))
        assertEquals(AttendeesFailure.OFFLINE, model.state.value.error)
        model.hide()
        model.show(eventId)
        advanceUntilIdle()
        assertTrue(model.canOpen(eventId, authority))
        model.hide()
    }
}
