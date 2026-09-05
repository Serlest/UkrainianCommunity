package at.uac.android

import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.*
import at.uac.android.feature.organization.*
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AuthoringTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    private val now = Instant.parse("2026-09-03T02:00:00.123456789Z")
    private val zone = ZoneId.of("Europe/Vienna")
    private val actor = OrganizationSession("author-alice", 1, true, "Alice", "user")
    private val basics =
        OrganizationDraft(
            "author-org",
            "Local community",
            "A verified local organization",
            region = "wien",
            city = "Wien",
        )

    private fun org(extra: Fields = emptyMap(), session: OrganizationSession = actor) =
        OrganizationContract.record(
            RawDocument(
                basics.id,
                OrganizationContract.create(basics, actor, now) +
                    mapOf("moderationStatus" to "approved", "ownerId" to actor.uid) +
                    extra,
            ),
            session,
        )

    private fun draft(kind: ContentKind = ContentKind.NEWS) =
        AuthoringContract.newDraft(kind, org(), now)
            .copy(
                title = "Synthetic title",
                summary = "Synthetic summary",
                body = "Synthetic full text",
            )
            .let {
                if (kind == ContentKind.EVENTS) it.copy(event = it.event.copy(venue = "Local hall"))
                else it
            }

    private fun submission(
        d: AuthoringDraft = draft(),
        base: AuthoringItem? = null,
        session: OrganizationSession = actor,
    ) = AuthoringContract.submission(d, org(session = session), session, base, now, zone)

    private fun item(
        s: AuthoringSubmission = submission(),
        extra: Fields = emptyMap(),
    ): AuthoringItem {
        val fields = s.base?.fields.orEmpty().toMutableMap()
        s.fields.forEach { (key, value) ->
            if (value == null) fields.remove(key) else fields[key] = value
        }
        fields["updatedAt"] = now.plusSeconds(1)
        fields.putAll(extra)
        return AuthoringContract.item(
            s.kind,
            RawDocument(s.id, fields),
            basics.id,
            AuthoringStatus.entries.first { it.wire == fields["moderationStatus"] },
            actor,
        )
    }

    private fun fails(expected: AuthoringFailure, action: () -> Unit) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: AuthoringException) {
            assertEquals(expected, error.failure)
        }
    }

    private suspend fun failsAsync(expected: AuthoringFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: AuthoringException) {
            assertEquals(expected, error.failure)
        }
    }

    private val gate =
        object : OrganizationMutationGate {
            override suspend fun <T> withSession(
                session: OrganizationSession,
                operation: suspend () -> T,
            ): T = withContext(NonCancellable) { operation() }
        }

    private inner class FakeSource : AuthoringSource {
        var organization = org()
        var record: AuthoringItem? = null
        var pending: CompletableDeferred<Unit>? = null
        var pendingPage: CompletableDeferred<Unit>? = null
        var pageReads = 0
        var watches = 0
        var error: AuthoringFailure? = null
        var commitBeforeError = false
        var writes = 0
        var readError: AuthoringFailure? = null
        val changes = MutableSharedFlow<Result<Unit>>(extraBufferCapacity = 10)

        override suspend fun organization(
            id: String,
            session: OrganizationSession,
        ): OrganizationRecord {
            readError?.let { AuthoringContract.fail(it) }
            return organization
        }

        override suspend fun page(
            organizationId: String,
            kind: ContentKind,
            status: AuthoringStatus,
            after: AuthoringCursor?,
            session: OrganizationSession,
        ): AuthoringPage {
            pageReads++
            // Simulate an SDK callback already queued when cancellation arrives.
            pendingPage?.let { queued -> withContext(NonCancellable) { queued.await() } }
            return AuthoringPage(
                listOfNotNull(record).filter { it.kind == kind && it.status == status },
                null,
            )
        }

        override suspend fun find(
            organizationId: String,
            kind: ContentKind,
            id: String,
            session: OrganizationSession,
        ): AuthoringItem? {
            readError?.let { AuthoringContract.fail(it) }
            return record?.takeIf { it.kind == kind && it.id == id }
        }

        override fun changes(
            organizationId: String,
            kind: ContentKind,
            status: AuthoringStatus,
            session: OrganizationSession,
            target: AuthoringItem?,
        ) = changes.also { watches++ }

        override suspend fun commit(
            submission: AuthoringSubmission,
            organization: OrganizationRecord,
            session: OrganizationSession,
        ) {
            writes++
            pending?.await()
            if (error == null || commitBeforeError) record = item(submission)
            error?.let { AuthoringContract.fail(it) }
        }
    }

    @Test
    fun canonicalOwnersAdminsAndModeratorsMayAuthor() {
        for (field in listOf("ownerId", "adminIds", "moderatorIds")) {
            val extra =
                mapOf("ownerId" to "other") +
                    if (field == "ownerId") mapOf(field to actor.uid)
                    else mapOf(field to listOf(actor.uid))
            assertNotEquals(
                OrganizationAuthority.NONE,
                AuthoringContract.authority(org(extra), actor).authority,
            )
        }
    }

    @Test
    fun globalAdminAndMembershipMirrorsDoNotGrantRights() {
        for (global in listOf("user", "admin", "topAdmin")) fails(AuthoringFailure.DENIED) {
            AuthoringContract.authority(
                org(mapOf("ownerId" to "other")),
                actor.copy(globalRole = global),
            )
        }
    }

    @Test
    fun inactiveAndNonApprovedRemainDenied() {
        fails(AuthoringFailure.NOT_READY) {
            AuthoringContract.authority(org(), actor.copy(ready = false))
        }
        fails(AuthoringFailure.DENIED) {
            AuthoringContract.authority(org(mapOf("moderationStatus" to "rejected")), actor)
        }
    }

    @Test
    fun systemOrganizationNeedsGenuineReadyPlatformOwner() {
        val system =
            org().let {
                it.copy(
                    id = "ukrainian-community",
                    fields = it.fields + ("id" to "ukrainian-community"),
                )
            }
        fails(AuthoringFailure.DENIED) { AuthoringContract.authority(system, actor) }
        assertEquals(
            OrganizationAuthority.PLATFORM_OWNER,
            AuthoringContract.authority(system, actor.copy(globalRole = "owner")).authority,
        )
    }

    @Test
    fun newsAustriaSubmitsWhileRegionalPublishes() {
        assertEquals("approved", submission().fields["moderationStatus"])
        val all = submission(draft().copy(regionScope = "austria"))
        assertEquals("pendingReview", all.fields["moderationStatus"])
        assertNull(all.fields["federalState"])
        assertEquals(
            "approved",
            submission(
                    draft().copy(regionScope = "austria"),
                    session = actor.copy(globalRole = "owner"),
                )
                .fields["moderationStatus"],
        )
    }

    @Test
    fun newDocumentsUseActualAuthorAndZeroCountersNoSchedule() {
        for (kind in AuthoringContract.kinds) {
            val fields = submission(draft(kind)).fields
            assertEquals(actor.uid, fields["authorId"])
            assertEquals(basics.id, fields["organizationId"])
            assertEquals("organization", fields["sourceType"])
            for (key in listOf("likeCount", "viewCount", "commentCount")) assertEquals(
                0L,
                fields[key],
            )
            assertFalse(fields.containsKey("scheduledAt"))
            assertEquals(now.truncatedTo(java.time.temporal.ChronoUnit.MICROS), fields["createdAt"])
        }
    }

    @Test
    fun approvedNewsChangingToAustriaNeedsReview() {
        val base = item()
        assertEquals(
            "pendingReview",
            submission(AuthoringContract.draft(base).copy(regionScope = "austria"), base)
                .fields["moderationStatus"],
        )
    }

    @Test
    fun rejectedNewsEditDoesNotResubmitOrApprove() {
        val base = item(extra = mapOf("moderationStatus" to "rejected"))
        assertEquals(
            "rejected",
            submission(AuthoringContract.draft(base).copy(title = "Revised text"), base)
                .fields["moderationStatus"],
        )
    }

    @Test
    fun editWhitelistNeverEmitsCountersIdentityOrMedia() {
        val base =
            item(
                extra =
                    mapOf(
                        "likeCount" to 22L,
                        "imageURL" to "https://example.invalid/cover",
                        "mediaMetadata" to mapOf("credit" to "Original"),
                    )
            )
        val update = submission(AuthoringContract.draft(base).copy(title = "New title"), base)
        assertTrue(update.fields.keys.all { it in AuthoringContract.editableFields })
        assertTrue(update.fields.keys.none { it in AuthoringContract.immutableFields })
        val result = item(update)
        assertEquals(22L, result.fields["likeCount"])
        assertEquals(base.fields["imageURL"], result.fields["imageURL"])
        assertTrue(AuthoringContract.matches(update, result))
    }

    @Test
    fun readbackMustPreserveExistingCountersAndAuthor() {
        val base = item()
        val change = submission(AuthoringContract.draft(base), base)
        assertFalse(AuthoringContract.matches(change, item(change, mapOf("authorId" to "foreign"))))
        assertFalse(AuthoringContract.matches(change, item(change, mapOf("viewCount" to 99L))))
    }

    @Test
    fun scheduledAndArchivedAreReadOnly() {
        for (status in listOf(AuthoringStatus.SCHEDULED, AuthoringStatus.ARCHIVED)) {
            val base =
                item(
                    extra =
                        mapOf(
                            "moderationStatus" to status.wire,
                            "scheduledAt" to now.plusSeconds(900),
                        )
                )
            assertFalse(base.editable)
            fails(AuthoringFailure.INVALID) { submission(AuthoringContract.draft(base), base) }
        }
    }

    @Test
    fun foreignScheduledDraftRejectedEvenWithOrgRights() {
        fails(AuthoringFailure.DENIED) {
            item(
                extra =
                    mapOf(
                        "moderationStatus" to "draft",
                        "scheduledAt" to now,
                        "authorId" to "foreign",
                    )
            )
        }
    }

    @Test
    fun localizationWireNamesDifferForNewsAndEvents() {
        for (kind in AuthoringContract.kinds) {
            val fields = submission(draft(kind).copy(germanTitle = "Deutscher Titel")).fields
            val de = fields.map("localizations").map("de")
            assertEquals("Deutscher Titel", de["title"])
            assertEquals(
                "Synthetic summary",
                de[if (kind == ContentKind.NEWS) "subtitle" else "summary"],
            )
            assertEquals(
                "Synthetic full text",
                de[if (kind == ContentKind.NEWS) "body" else "details"],
            )
        }
    }

    @Test
    fun removedGermanTranslationDoesNotLeaveStaleText() {
        val base = item(submission(draft().copy(germanTitle = "Alter Titel")))
        val update =
            submission(
                AuthoringContract.draft(base)
                    .copy(germanTitle = "", germanSummary = "", germanBody = ""),
                base,
            )
        assertFalse(update.fields.map("localizations").containsKey("de"))
    }

    @Test
    fun unicodeTitleCountsCodePointsWithoutCuttingEmoji() {
        submission(draft().copy(title = "😀".repeat(120)))
        fails(AuthoringFailure.INVALID) { submission(draft().copy(title = "😀".repeat(121))) }
    }

    @Test
    fun requiredTextAndGermanEventLimitChecked() {
        fails(AuthoringFailure.INVALID) { submission(draft().copy(summary = " ")) }
        fails(AuthoringFailure.INVALID) {
            submission(draft(ContentKind.EVENTS).copy(germanBody = "x".repeat(2001)))
        }
        fails(AuthoringFailure.INVALID) { submission(draft().copy(body = "x".repeat(10001))) }
    }

    @Test
    fun categoryTagsAndControlCharactersBounded() {
        fails(AuthoringFailure.INVALID) {
            submission(draft().copy(additionalCategories = setOf("news")))
        }
        fails(AuthoringFailure.INVALID) {
            submission(draft().copy(additionalCategories = setOf("work", "health", "other")))
        }
        fails(AuthoringFailure.INVALID) {
            submission(draft().copy(tags = (1..9).joinToString(",")))
        }
        fails(AuthoringFailure.INVALID) { submission(draft().copy(title = "control\u0000")) }
        assertEquals(listOf("A", "B"), submission(draft().copy(tags = " A, B, A ")).fields["tags"])
    }

    @Test
    fun webLinksRejectCredentialsSchemesWhitespaceAndBadPorts() {
        for (url in
            listOf(
                "https://user:pass@example.invalid",
                "file:///etc/passwd",
                "https://example.invalid/a b",
                "https://example.invalid:70000",
            )) fails(AuthoringFailure.INVALID) { AuthoringContract.web(url, false) }
        fails(AuthoringFailure.INVALID) { AuthoringContract.web("http://example.invalid", true) }
        assertEquals(
            "https://example.invalid/path",
            AuthoringContract.web(" https://example.invalid/path ", true),
        )
    }

    @Test
    fun newsSourceAcceptsNameAndExtractsHostForURL() {
        assertEquals(
            "Public source",
            submission(draft().copy(source = "Public source")).fields["sourceName"],
        )
        val fields = submission(draft().copy(source = "https://example.invalid/a")).fields
        assertEquals("example.invalid", fields["sourceName"])
        assertEquals("https://example.invalid/a", fields["sourceURL"])
    }

    @Test
    fun externalParticipationRequiresHttpsActionAndNoInAppRegistration() {
        val d =
            draft(ContentKind.EVENTS).let {
                it.copy(event = it.event.copy(participation = "externalTickets"))
            }
        fails(AuthoringFailure.INVALID) { submission(d) }
        val fields = submission(d.copy(actionUrl = "https://example.invalid/ticket")).fields
        assertEquals(false, fields["requiresRegistration"])
        assertEquals("externalTickets", fields["participationMode"])
    }

    @Test
    fun capacityCannotFallBelowExistingRegistrations() {
        val base = item(submission(draft(ContentKind.EVENTS)), mapOf("registeredCount" to 3L))
        val draft = AuthoringContract.draft(base)
        fails(AuthoringFailure.INVALID) {
            submission(draft.copy(event = draft.event.copy(capacity = "2")), base)
        }
        assertEquals(
            3L,
            submission(draft.copy(event = draft.event.copy(capacity = "3")), base)
                .fields["capacity"],
        )
    }

    @Test
    fun ageAndPriceRangesValidated() {
        val d = draft(ContentKind.EVENTS)
        for (event in
            listOf(
                d.event.copy(minimumAge = "20", maximumAge = "10"),
                d.event.copy(minimumAge = "121"),
                d.event.copy(priceKind = "range", amount = "5", maximumAmount = "4"),
                d.event.copy(priceKind = "exact", amount = "NaN"),
            )) fails(AuthoringFailure.INVALID) { submission(d.copy(event = event)) }
        val fields =
            submission(
                    d.copy(
                        event =
                            d.event.copy(
                                priceKind = "range",
                                amount = "5,25",
                                maximumAmount = "10.50",
                            )
                    )
                )
                .fields
        assertEquals(5.25, fields["price"])
        assertEquals(10.5, fields.map("pricing")["maximumAmount"])
    }

    @Test
    fun changingAddressClearsStaleCoordinatesNotCounters() {
        val base =
            item(
                submission(draft(ContentKind.EVENTS)),
                mapOf("latitude" to 48.0, "longitude" to 16.0, "registeredCount" to 3L),
            )
        val d = AuthoringContract.draft(base)
        val update = submission(d.copy(event = d.event.copy(address = "Changed street")), base)
        assertTrue(update.fields.containsKey("latitude"))
        assertNull(update.fields["latitude"])
        assertFalse(update.fields.containsKey("registeredCount"))
    }

    @Test
    fun allDaySpringDstUses23HourCalendarDay() {
        val occurrence =
            AuthoringOccurrence(
                start = Instant.parse("2026-03-29T10:00:00Z"),
                end = Instant.parse("2026-03-29T12:00:00Z"),
                allDay = true,
            )
        val fields = AuthoringContract.occurrence(occurrence, true, now, zone)
        assertEquals(Instant.parse("2026-03-28T23:00:00Z"), fields["startDate"])
        assertEquals(Instant.parse("2026-03-29T22:00:00Z"), fields["endDate"])
    }

    @Test
    fun noExplicitEndIsInstantaneousAndPastNewDateDenied() {
        val occurrence =
            AuthoringOccurrence(
                start = now.minusSeconds(90),
                end = now.plusSeconds(600),
                endKnown = false,
            )
        fails(AuthoringFailure.INVALID) {
            AuthoringContract.occurrence(occurrence, false, now, zone)
        }
        val fields = AuthoringContract.occurrence(occurrence, true, now, zone)
        assertEquals(fields["startDate"], fields["endDate"])
    }

    @Test
    fun springGapIsRejectedAndAutumnOffsetPreserved() {
        assertNull(
            AuthoringCalendar.resolve(LocalDate.of(2026, 3, 29), LocalTime.of(2, 30), zone, now)
        )
        val original = Instant.parse("2026-10-25T01:30:00Z")
        assertEquals(
            original,
            AuthoringCalendar.resolve(
                LocalDate.of(2026, 10, 25),
                LocalTime.of(2, 30),
                zone,
                original,
            ),
        )
    }

    @Test
    fun occurrenceBoundAndDuplicateIdsRejected() {
        val d = draft(ContentKind.EVENTS)
        val one = d.event.occurrences.first()
        fails(AuthoringFailure.INVALID) {
            submission(d.copy(event = d.event.copy(occurrences = listOf(one, one))))
        }
        fails(AuthoringFailure.INVALID) {
            submission(
                d.copy(
                    event =
                        d.event.copy(
                            occurrences =
                                (0..30).map { one.copy(id = UUID.randomUUID().toString()) }
                        )
                )
            )
        }
    }

    @Test
    fun cursorUsesLastDisplayedRowNotLookaheadAndValidatesOrder() {
        val rows =
            (0..25).map { offset ->
                val value =
                    item(
                        submission(draft().copy(id = "item-${offset.toString().padStart(2, '0')}")),
                        mapOf("createdAt" to now.minusSeconds(offset.toLong())),
                    )
                RawDocument(value.id, value.fields)
            }
        val page =
            AuthoringContract.page(
                rows,
                ContentKind.NEWS,
                basics.id,
                AuthoringStatus.APPROVED,
                actor,
                null,
            )
        assertEquals(25, page.items.size)
        assertEquals("item-24", page.next?.id)
        fails(AuthoringFailure.INVALID) {
            AuthoringContract.page(
                rows.reversed(),
                ContentKind.NEWS,
                basics.id,
                AuthoringStatus.APPROVED,
                actor,
                null,
            )
        }
        fails(AuthoringFailure.INVALID) {
            AuthoringContract.page(
                listOf(rows[0], rows[0]),
                ContentKind.NEWS,
                basics.id,
                AuthoringStatus.APPROVED,
                actor,
                null,
            )
        }
    }

    @Test
    fun wrongOrgOrStatusNeverPassesParser() {
        val item = item()
        fails(AuthoringFailure.INVALID) {
            AuthoringContract.item(
                item.kind,
                RawDocument(item.id, item.fields),
                "foreign",
                item.status,
                actor,
            )
        }
        fails(AuthoringFailure.INVALID) {
            AuthoringContract.item(
                item.kind,
                RawDocument(item.id, item.fields),
                basics.id,
                AuthoringStatus.REVIEW,
                actor,
            )
        }
    }

    @Test
    fun repositoryCreatesAndRecoversWithoutDuplicateWrite() = runTest {
        val source = FakeSource()
        val repo = AuthoringRepository(source, { actor }, gate)
        val intent = submission()
        val first = repo.submit(intent)
        assertTrue(AuthoringContract.matches(intent, first))
        assertEquals(first, repo.submit(intent))
        assertEquals(1, source.writes)
    }

    @Test
    fun repositoryDeniesGuestAndRevokedAuthority() = runTest {
        val source = FakeSource()
        failsAsync(AuthoringFailure.SIGN_IN) {
            AuthoringRepository(source, { null }, gate)
                .load(basics.id, ContentKind.NEWS, AuthoringStatus.APPROVED)
        }
        source.organization = org(mapOf("ownerId" to "other"))
        failsAsync(AuthoringFailure.DENIED) {
            AuthoringRepository(source, { actor }, gate).submit(submission())
        }
        assertEquals(0, source.writes)
    }

    @Test
    fun staleBaseNeverOverwritesNewServerText() = runTest {
        val source = FakeSource()
        val base = item()
        source.record = base.copy(fields = base.fields + ("title" to "Changed elsewhere"))
        failsAsync(AuthoringFailure.STALE) {
            AuthoringRepository(source, { actor }, gate)
                .submit(
                    submission(AuthoringContract.draft(base).copy(title = "Local change"), base)
                )
        }
        assertEquals(0, source.writes)
    }

    @Test
    fun sessionSwitchDuringCommitSuppressesResult() = runTest {
        var session: OrganizationSession? = actor
        val source = FakeSource().apply { pending = CompletableDeferred() }
        val work = async { AuthoringRepository(source, { session }, gate).submit(submission()) }
        runCurrent()
        session = actor.copy(uid = "other", revision = 2)
        source.pending!!.complete(Unit)
        try {
            work.await()
            fail("Stale session result")
        } catch (_: CancellationException) {}
    }

    @Test
    fun modelPreservesInMemoryDraftButDoesNotSwitchFilterOrAllocateNewId() = runTest {
        val source = FakeSource()
        val model = AuthoringViewModel(source, { actor }, gate)
        model.show(basics.id)
        advanceUntilIdle()
        model.create()
        val id = model.state.value.draft!!.id
        model.change { it.copy(title = "Unsent") }
        model.select(ContentKind.EVENTS, AuthoringStatus.APPROVED)
        assertEquals(ContentKind.NEWS, model.state.value.kind)
        assertEquals(id, model.state.value.draft!!.id)
        model.hide()
        model.show(basics.id)
        advanceUntilIdle()
        assertEquals("Unsent", model.state.value.draft!!.title)
        assertEquals(0, source.writes)
    }

    @Test
    fun newAccountClearsPrivateDraftImmediately() = runTest {
        val sessions = MutableStateFlow<OrganizationSession?>(actor)
        val source = FakeSource()
        val model = AuthoringViewModel(source, { sessions.value }, gate)
        model.observeSessions(sessions)
        model.show(basics.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "Private") }
        sessions.value = actor.copy(uid = "other-account", revision = 2, ready = false)
        runCurrent()
        assertNull(model.state.value.draft)
        assertNull(model.state.value.hub)
        assertFalse(model.state.value.actionable)
    }

    @Test
    fun sameUidRevisionRetainsTextButRequiresNewReadyAuthorityRead() = runTest {
        val sessions = MutableStateFlow<OrganizationSession?>(actor)
        val source = FakeSource()
        val model = AuthoringViewModel(source, { sessions.value }, gate)
        model.observeSessions(sessions)
        model.show(basics.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "Private unsent text") }
        val id = model.state.value.draft!!.id
        sessions.value = actor.copy(revision = 2, ready = false)
        runCurrent()
        assertEquals(id, model.state.value.draft!!.id)
        assertFalse(model.state.value.draftWritable)
        assertNull(model.state.value.hub)
        sessions.value = actor.copy(revision = 3)
        advanceUntilIdle()
        assertEquals("Private unsent text", model.state.value.draft!!.title)
        assertTrue(model.state.value.draftWritable)
        assertEquals(0, source.writes)
    }

    @Test
    fun enteringOtherKindUsesRequestedRouteWhenNoDraftExists() = runTest {
        val source = FakeSource()
        val model = AuthoringViewModel(source, { actor }, gate)
        model.show(basics.id, ContentKind.NEWS)
        advanceUntilIdle()
        model.hide()
        model.show(basics.id, ContentKind.EVENTS)
        advanceUntilIdle()
        assertEquals(ContentKind.EVENTS, model.state.value.kind)
        model.create()
        assertEquals(ContentKind.EVENTS, model.state.value.draft?.kind)
    }

    @Test
    fun requestedOtherKindNeverConvertsUnsentDraftAndWaitsForExplicitClose() = runTest {
        val source = FakeSource()
        val model = AuthoringViewModel(source, { actor }, gate)
        model.show(basics.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "Keep news") }
        model.hide()
        model.show(basics.id, ContentKind.EVENTS)
        advanceUntilIdle()
        assertEquals(ContentKind.NEWS, model.state.value.draft?.kind)
        assertEquals("Keep news", model.state.value.draft?.title)
        model.discardLocalForm()
        advanceUntilIdle()
        model.create()
        assertEquals(ContentKind.EVENTS, model.state.value.draft?.kind)
        assertEquals(0, source.writes)
    }

    @Test
    fun selectedKindSurvivesForegroundAndClosingItsLocalForm() = runTest {
        val source = FakeSource()
        val model = AuthoringViewModel(source, { actor }, gate)
        model.show(basics.id)
        advanceUntilIdle()
        model.select(ContentKind.EVENTS)
        advanceUntilIdle()
        model.hide()
        model.show(basics.id)
        advanceUntilIdle()
        assertEquals(ContentKind.EVENTS, model.state.value.kind)
        model.create()
        model.discardLocalForm()
        advanceUntilIdle()
        assertEquals(ContentKind.EVENTS, model.state.value.kind)
    }

    @Test
    fun duplicateConfirmIsSuppressedAndExactReadbackConfirmed() = runTest {
        val source = FakeSource().apply { pending = CompletableDeferred() }
        val model = AuthoringViewModel(source, { actor }, gate)
        model.show(basics.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "T", summary = "S", body = "B") }
        model.requestSubmit()
        model.confirm()
        model.confirm()
        runCurrent()
        assertEquals(1, source.writes)
        assertTrue(model.state.value.busy)
        source.pending!!.complete(Unit)
        advanceUntilIdle()
        assertNotNull(model.state.value.confirmed)
        assertNull(model.state.value.draft)
    }

    @Test
    fun lostResponseRecoveryNeverAutomaticallyRepeatsCommittedWrite() = runTest {
        val source =
            FakeSource().apply {
                error = AuthoringFailure.UNCONFIRMED
                commitBeforeError = true
            }
        val model = AuthoringViewModel(source, { actor }, gate)
        model.show(basics.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "T", summary = "S", body = "B") }
        val id = model.state.value.draft!!.id
        model.requestSubmit()
        model.confirm()
        advanceUntilIdle()
        assertNotNull(model.state.value.uncertain)
        assertFalse(model.state.value.draftWritable)
        assertEquals(id, model.state.value.draft!!.id)
        model.recover()
        advanceUntilIdle()
        assertNotNull(model.state.value.confirmed)
        assertEquals(1, source.writes)
    }

    @Test
    fun absentUncertainCreateNeedsExplicitSameIdRetryAfterRead() = runTest {
        val source = FakeSource().apply { error = AuthoringFailure.UNCONFIRMED }
        val model = AuthoringViewModel(source, { actor }, gate)
        model.show(basics.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "T", summary = "S", body = "B") }
        model.requestSubmit()
        model.confirm()
        advanceUntilIdle()
        val id = model.state.value.uncertain!!.id
        model.retryAbsentCreation()
        advanceUntilIdle()
        assertEquals(1, source.writes)
        model.recover()
        advanceUntilIdle()
        assertTrue(model.state.value.recoveryChecked)
        assertEquals(1, source.writes)
        source.error = null
        model.retryAbsentCreation()
        advanceUntilIdle()
        assertEquals(2, source.writes)
        assertEquals(id, model.state.value.confirmed!!.id)
    }

    @Test
    fun visibleAuthorityChangeMakesUnsentFormReadOnly() = runTest {
        val source = FakeSource()
        val model = AuthoringViewModel(source, { actor }, gate)
        model.show(basics.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "Keep me") }
        source.organization = org(mapOf("ownerId" to "other"))
        source.changes.emit(Result.success(Unit))
        advanceUntilIdle()
        assertEquals("Keep me", model.state.value.draft!!.title)
        assertFalse(model.state.value.draftWritable)
        assertEquals(AuthoringFailure.DENIED, model.state.value.error)
    }

    @Test
    fun laterListenerFailureInvalidatesQueuedSuccessfulRefresh() = runTest {
        val source = FakeSource()
        val model = AuthoringViewModel(source, { actor }, gate)
        model.show(basics.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "Unsent text") }
        val queued = CompletableDeferred<Unit>()
        source.pendingPage = queued
        model.refresh()
        runCurrent()
        assertTrue(model.state.value.loading)
        source.changes.emit(Result.failure(AuthoringException(AuthoringFailure.DENIED)))
        runCurrent()
        assertFalse(model.state.value.fresh)
        assertFalse(model.state.value.loading)
        assertFalse(model.state.value.draftWritable)
        queued.complete(Unit)
        advanceUntilIdle()
        assertEquals(AuthoringFailure.DENIED, model.state.value.error)
        assertFalse(model.state.value.fresh)
        assertEquals("Unsent text", model.state.value.draft?.title)
        assertEquals(0, source.writes)
        source.pendingPage = null
        model.refresh()
        advanceUntilIdle()
        assertTrue(model.state.value.draftWritable)
    }

    @Test
    fun cancelledOldReadCannotClearNewForegroundReadOrStartADuplicate() = runTest {
        val source = FakeSource()
        val model = AuthoringViewModel(source, { actor }, gate)
        model.show(basics.id)
        advanceUntilIdle()
        val first = CompletableDeferred<Unit>()
        source.pendingPage = first
        model.refresh()
        runCurrent()
        model.hide()
        val second = CompletableDeferred<Unit>()
        source.pendingPage = second
        model.show(basics.id)
        runCurrent()
        assertTrue(model.state.value.loading)
        val reads = source.pageReads
        first.complete(Unit)
        runCurrent()
        model.refresh()
        runCurrent()
        assertEquals(reads, source.pageReads)
        assertTrue(model.state.value.loading)
        second.complete(Unit)
        advanceUntilIdle()
        assertTrue(model.state.value.fresh)
    }

    @Test
    fun differentRouteDuringReadNeverMixesNewsPageWithEventState() = runTest {
        val source = FakeSource()
        val model = AuthoringViewModel(source, { actor }, gate)
        val newsRead = CompletableDeferred<Unit>()
        source.pendingPage = newsRead
        model.show(basics.id, ContentKind.NEWS)
        runCurrent()
        val eventRead = CompletableDeferred<Unit>()
        source.pendingPage = eventRead
        model.show(basics.id, ContentKind.EVENTS)
        runCurrent()
        newsRead.complete(Unit)
        runCurrent()
        assertNull(model.state.value.hub)
        assertFalse(model.state.value.fresh)
        eventRead.complete(Unit)
        advanceUntilIdle()
        assertEquals(ContentKind.EVENTS, model.state.value.kind)
        assertEquals(ContentKind.EVENTS, model.state.value.hub?.kind)
    }

    @Test
    fun listenerFailureExplicitRetryRegistersNewLiveQueries() = runTest {
        val source = FakeSource()
        val model = AuthoringViewModel(source, { actor }, gate)
        model.show(basics.id)
        advanceUntilIdle()
        assertEquals(1, source.watches)
        source.changes.emit(Result.failure(AuthoringException(AuthoringFailure.OFFLINE)))
        advanceUntilIdle()
        assertFalse(model.state.value.fresh)
        model.refresh()
        advanceUntilIdle()
        assertTrue(model.state.value.fresh)
        assertEquals(2, source.watches)
    }
}
