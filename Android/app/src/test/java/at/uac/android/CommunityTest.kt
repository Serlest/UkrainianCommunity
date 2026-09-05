package at.uac.android

import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthIdentity
import at.uac.android.feature.auth.AuthProfile
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.community.*
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CommunityTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    private val now = Instant.parse("2026-09-03T01:00:00.123456Z")
    private val alice = CommunitySession("synthetic-alice", 1, true, "user")
    private val bob = CommunitySession("synthetic-bob", 2, true, "user")
    private val event = CommunityTarget(ContentKind.EVENTS, "synthetic-event")
    private val news = CommunityTarget(ContentKind.NEWS, "synthetic-news")

    private fun comment(
        target: CommunityTarget = news,
        id: String = "comment-1",
        text: String = "Добрий день",
        uid: String = alice.uid,
    ): RawDocument =
        RawDocument(
            id,
            mapOf(
                "id" to id,
                "parentId" to target.id,
                "parentType" to target.type,
                "authorId" to uid,
                "authorName" to "Synthetic Person",
                "text" to text,
                "body" to text,
                "createdAt" to now,
                "updatedAt" to null,
                "moderationStatus" to "approved",
                "isDeleted" to false,
            ),
        )

    private inner class FakeSource : CommunitySource {
        var parentFields: Fields =
            mapOf(
                "startDate" to now.plusSeconds(3600),
                "moderationStatus" to "approved",
                "requiresRegistration" to true,
                "registeredCount" to 0L,
                "capacity" to 4L,
            )
        var marker: RawDocument? = null
        val saved = mutableMapOf<String, RawDocument>()
        val calls = mutableListOf<Triple<String, Fields, String>>()
        var receiptOverride: Any? = null
        var leaveRegistrationUnchanged = false
        var differentCountOnRead = false
        var callFailure: CommunityFailure? = null
        var readFailure: CommunityFailure? = null
        var callPause: CompletableDeferred<Unit>? = null
        var readPause: CompletableDeferred<Unit>? = null
        var moderate = false
        var deletes = 0
        var listeners = 0
        val pages = MutableStateFlow(Result.success(CommentPage(emptyList(), false)))

        override suspend fun parent(target: CommunityTarget): RawDocument {
            readPause?.await()
            readFailure?.let { throw CommunityException(it) }
            return RawDocument(target.id, parentFields)
        }

        override suspend fun registration(eventId: String, uid: String) = marker

        override suspend fun call(name: String, data: Fields, uid: String): Any? {
            calls += Triple(name, data, uid)
            callPause?.await()
            callFailure?.let { throw CommunityException(it) }
            if (name == "saveComment") {
                val target =
                    CommunityTarget(
                        when (data["parentType"]) {
                            "event" -> ContentKind.EVENTS
                            "organization" -> ContentKind.ORGANIZATIONS
                            else -> ContentKind.NEWS
                        },
                        data["parentId"] as String,
                    )
                val row = comment(target, "comment-${calls.size}", data["text"] as String, uid)
                saved[row.id] = row
                pages.value =
                    Result.success(
                        CommentPage(
                            saved.values.mapNotNull { CommunityContract.comment(target, it) },
                            false,
                        )
                    )
                return receiptOverride
                    ?: row.fields.mapValues {
                        if (it.value is Instant) it.value.toString() else it.value
                    }
            }
            val selected = name == "registerForEvent"
            if (!leaveRegistrationUnchanged) {
                val id = CommunityContract.registrationId(data["eventId"] as String, uid)
                marker =
                    if (selected)
                        RawDocument(
                            id,
                            mapOf(
                                "id" to id,
                                "eventId" to data["eventId"],
                                "userId" to uid,
                                "registeredAt" to now,
                            ),
                        )
                    else null
                parentFields =
                    parentFields +
                        ("registeredCount" to
                            if (differentCountOnRead) 3L else if (selected) 1L else 0L)
            }
            return receiptOverride
                ?: mapOf(
                    "eventId" to data["eventId"],
                    "registrationState" to if (selected) "registered" else "notRegistered",
                    "registeredCount" to if (selected) 1 else 0,
                    "didChange" to true,
                )
        }

        override suspend fun comment(target: CommunityTarget, id: String): RawDocument? {
            readFailure?.let { throw CommunityException(it) }
            return saved[id]
        }

        override fun comments(target: CommunityTarget): Flow<Result<CommentPage>> = flow {
            listeners++
            try {
                emitAll(pages)
            } finally {
                listeners--
            }
        }

        override suspend fun moderation(target: CommunityTarget, session: CommunitySession) =
            moderate

        override suspend fun deleteComment(
            target: CommunityTarget,
            id: String,
            uid: String,
            stillCurrent: () -> Boolean,
        ) {
            if (!stillCurrent()) throw CancellationException()
            if (!moderate) throw CommunityException(CommunityFailure.DENIED)
            saved.remove(id)
            deletes++
        }
    }

    private fun failure(expected: CommunityFailure, action: () -> Unit) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: CommunityException) {
            assertEquals(expected, error.failure)
        }
    }

    private suspend fun failureAsync(expected: CommunityFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: CommunityException) {
            assertEquals(expected, error.failure)
        }
    }

    @Test
    fun canonicalIdentifiersAndStrictNumbers() {
        assertEquals(
            "event_synthetic-event_synthetic-alice",
            CommunityContract.registrationId(event.id, alice.uid),
        )
        listOf("", "a/b", ".", "..", "a\nb", " leading", "a".repeat(513)).forEach {
            assertFalse(communityId(it))
        }
        for (bad in
            listOf(
                -1,
                0.1,
                Double.NaN,
                Double.POSITIVE_INFINITY,
                "3",
                true,
                9_007_199_254_740_992.0,
            )) failure(CommunityFailure.INVALID) { CommunityContract.count(bad) }
        assertEquals(0L, CommunityContract.count(null, true))
        assertEquals(3L, CommunityContract.count(3.0))
    }

    @Test
    fun eventRegistrationKeepsItsLongerIdContractWithoutInventingCommentSupport() = runTest {
        val target = CommunityTarget(ContentKind.EVENTS, "a".repeat(512))
        assertFalse(target.acceptsNewComments)
        assertTrue(CommunityTarget(ContentKind.EVENTS, "a".repeat(256)).acceptsNewComments)
        assertTrue(CommunityContract.registrationId(target.id, alice.uid).endsWith(alice.uid))
        try {
            CommunityTarget(ContentKind.EVENTS, "a".repeat(513))
            fail("Oversized target")
        } catch (_: IllegalArgumentException) {}
        failureAsync(CommunityFailure.INVALID) {
            CommunityRepository(FakeSource(), { alice }).addComment(target, "Hello")
        }
    }

    @Test
    fun registrationReceiptRejectsMismatchesAndNonBoolean() {
        val valid =
            mapOf(
                "eventId" to event.id,
                "registrationState" to "registered",
                "registeredCount" to 2,
                "didChange" to false,
            )
        assertEquals(
            RegistrationReceipt(event.id, true, 2, false),
            CommunityContract.receipt(valid, event.id),
        )
        listOf(
                mapOf("eventId" to "other"),
                mapOf("registrationState" to "waitlist"),
                mapOf("registeredCount" to -1),
                mapOf("didChange" to 1),
            )
            .forEach {
                failure(CommunityFailure.INVALID) {
                    CommunityContract.receipt(valid + it, event.id)
                }
            }
    }

    @Test
    fun foreignRegistrationNeverAppearsAsOwn() {
        val source = FakeSource()
        val id = CommunityContract.registrationId(event.id, alice.uid)
        val foreign =
            RawDocument(
                id,
                mapOf(
                    "id" to id,
                    "eventId" to event.id,
                    "userId" to bob.uid,
                    "registeredAt" to now,
                ),
            )
        failure(CommunityFailure.INVALID) {
            CommunityContract.participation(
                RawDocument(event.id, source.parentFields),
                foreign,
                alice.uid,
            )
        }
    }

    @Test
    fun unavailableEventsRetainCancellationForExistingAttendee() {
        val base = EventParticipation(event.id, false, 1, 1, now.plusSeconds(1), false, true, true)
        assertEquals(CommunityFailure.FULL, base.unavailable(now))
        assertEquals(CommunityFailure.PAST, base.copy(start = now).unavailable(now))
        assertEquals(CommunityFailure.CANCELLED, base.copy(cancelled = true).unavailable(now))
        assertEquals(
            CommunityFailure.NOT_REQUIRED,
            base.copy(required = false, capacity = null).unavailable(now),
        )
        assertNull(
            base
                .copy(registered = true, cancelled = true, start = now.minusSeconds(1))
                .unavailable(now)
        )
    }

    @Test
    fun exactServerErrorsAreLocalizedWithoutSubstringGuessing() {
        val reasons =
            mapOf(
                "event-full" to CommunityFailure.FULL,
                "event-past" to CommunityFailure.PAST,
                "event-cancelled" to CommunityFailure.CANCELLED,
                "registration-not-required" to CommunityFailure.NOT_REQUIRED,
                "event-not-approved" to CommunityFailure.NOT_APPROVED,
                "invalid-registration-counter" to CommunityFailure.INVALID,
            )
        for ((reason, expected) in reasons) assertEquals(
            expected,
            communityCallableFailure(
                if (reason == "event-full") "RESOURCE_EXHAUSTED" else "FAILED_PRECONDITION",
                reason,
            ),
        )
        assertEquals(
            CommunityFailure.NOT_READY,
            communityCallableFailure("FAILED_PRECONDITION", null),
        )
        assertEquals(
            CommunityFailure.REJECTED_TEXT,
            communityCallableFailure("INVALID_ARGUMENT", "objectionable-content"),
        )
        assertEquals(
            CommunityFailure.UNKNOWN,
            communityCallableFailure("RESOURCE_EXHAUSTED", "quota"),
        )
        for (reason in CommunityFailure.entries) for (language in listOf("uk", "de")) assertTrue(
            communityFailureText(reason, language).isNotBlank()
        )
    }

    @Test
    fun textLengthMatchesUtf16AndPreservesRealContent() {
        assertEquals("Добрий день", CommunityContract.text("  Добрий день\n"))
        assertEquals(1000, CommunityContract.text("😀".repeat(500)).length)
        failure(CommunityFailure.TEXT_TOO_LONG) { CommunityContract.text("😀".repeat(501)) }
        failure(CommunityFailure.EMPTY_TEXT) { CommunityContract.text(" \n\t") }
    }

    @Test
    fun commentContextLegacyFallbackAndModerationAreFailClosed() {
        val row = comment()
        val legacy =
            row.copy(
                fields =
                    row.fields -
                        setOf("parentType", "parentId", "authorId", "moderationStatus", "text")
            )
        assertEquals("Добрий день", CommunityContract.comment(news, legacy)!!.text)
        assertNull(CommunityContract.comment(news, legacy)!!.authorId)
        failure(CommunityFailure.INVALID) { CommunityContract.comment(event, row) }
        assertNull(
            CommunityContract.comment(
                news,
                row.copy(fields = row.fields + ("moderationStatus" to "pendingReview")),
            )
        )
        assertNull(
            CommunityContract.comment(news, row.copy(fields = row.fields + ("isDeleted" to true)))
        )
        failure(CommunityFailure.INVALID) {
            CommunityContract.comment(
                news,
                row.copy(fields = row.fields + ("moderationStatus" to "surprise")),
            )
        }
        failure(CommunityFailure.INVALID) {
            CommunityContract.comment(news, legacy, response = true)
        }
    }

    @Test
    fun authorDisplayIsPlainSanitizedTextWithoutPhotoFetch() {
        val row =
            comment().let {
                it.copy(
                    fields =
                        it.fields +
                            mapOf(
                                "authorName" to "\u202E Fake\nPerson\u2066",
                                "authorPhotoURL" to "file:///private/secret",
                            )
                )
            }
        assertEquals("FakePerson", CommunityContract.comment(news, row)!!.authorName)
        assertEquals(
            160,
            CommunityContract.comment(
                    news,
                    row.copy(fields = row.fields + ("authorName" to "a".repeat(1000))),
                )!!
                .authorName
                .length,
        )
    }

    @Test
    fun ownAuthorshipDoesNotGrantModerationButOrganizationScopeDoes() {
        val parent =
            mapOf(
                "sourceType" to "organization",
                "organizationId" to "org",
                "authorId" to alice.uid,
            )
        assertFalse(CommunityContract.canModerate(news, parent, null, alice))
        assertTrue(
            CommunityContract.canModerate(
                news,
                parent,
                mapOf("moderatorIds" to listOf(alice.uid)),
                alice,
            )
        )
        assertFalse(
            CommunityContract.canModerate(
                news,
                parent + ("sourceType" to "app"),
                mapOf("ownerId" to alice.uid),
                alice,
            )
        )
        assertTrue(CommunityContract.canModerate(news, parent, null, alice.copy(role = "admin")))
        assertFalse(
            CommunityContract.canModerate(
                news,
                parent,
                null,
                alice.copy(role = "owner", ready = false),
            )
        )
    }

    @Test
    fun authGateIncludesLegalMfaAndActiveProfile() {
        val profile = AuthProfile(alice.uid, "alice@example.invalid", "Alice")
        val session =
            AuthSession(
                AuthStage.AUTHENTICATED,
                AuthIdentity(alice.uid, profile.email, true),
                profile,
                1,
            )
        assertTrue(session.communityScope()!!.ready)
        for (gate in
            listOf(
                AuthGate.MFA_REQUIRED,
                AuthGate.LEGAL_REQUIRED,
                AuthGate.RESTRICTED,
            )) assertFalse(session.copy(gate = gate).communityScope()!!.ready)
        assertFalse(
            session
                .copy(profile = profile.copy(accountStatus = "suspended"))
                .communityScope()!!
                .ready
        )
    }

    @Test
    fun exactCallableWireAndFreshCountReadBack() = runTest {
        val source = FakeSource().apply { differentCountOnRead = true }
        val repository = CommunityRepository(source, { alice })
        val actual = repository.setRegistration(event, true)
        assertTrue(actual.registered)
        assertEquals(3L, actual.count)
        assertEquals(
            Triple("registerForEvent", mapOf("eventId" to event.id), alice.uid),
            source.calls.single(),
        )
        assertFalse(repository.setRegistration(event, false).registered)
        assertEquals("unregisterFromEvent", source.calls.last().first)
    }

    @Test
    fun receiptWithoutMatchingPersistenceIsNeverSuccess() = runTest {
        val source = FakeSource().apply { leaveRegistrationUnchanged = true }
        failureAsync(CommunityFailure.UNCONFIRMED) {
            CommunityRepository(source, { alice }).setRegistration(event, true)
        }
    }

    @Test
    fun createOnlyCommentContractHasExactAuthorTargetTextReadBack() = runTest {
        val source = FakeSource()
        val actual = CommunityRepository(source, { alice }).addComment(news, "  Test comment  ")
        assertEquals("Test comment", actual.text)
        assertEquals(alice.uid, actual.authorId)
        assertEquals(
            mapOf("parentType" to "news", "parentId" to news.id, "text" to "Test comment"),
            source.calls.single().second,
        )
        assertFalse(source.calls.single().second.containsKey("commentId"))
    }

    @Test
    fun unknownCommentOutcomeNeverRetriesAndCannotClaimSuccess() = runTest {
        for (source in
            listOf(
                FakeSource().apply { readFailure = CommunityFailure.OFFLINE },
                FakeSource().apply { receiptOverride = mapOf("id" to "bad") },
                FakeSource().apply { callFailure = CommunityFailure.OFFLINE },
            )) {
            failureAsync(CommunityFailure.UNCONFIRMED) {
                CommunityRepository(source, { alice }).addComment(news, "Test")
            }
            assertEquals(1, source.calls.size)
        }
    }

    @Test
    fun unreadyAndGuestSessionsNeverReachMutationAndAuthorCannotDelete() = runTest {
        val source = FakeSource()
        failureAsync(CommunityFailure.SIGN_IN) {
            CommunityRepository(source, { null }).setRegistration(event, true)
        }
        failureAsync(CommunityFailure.NOT_READY) {
            CommunityRepository(source, { alice.copy(ready = false) }).addComment(news, "Test")
        }
        failureAsync(CommunityFailure.DENIED) {
            CommunityRepository(source, { alice }).deleteComment(news, "comment-1")
        }
        assertTrue(source.calls.isEmpty())
        assertEquals(0, source.deletes)
    }

    @Test
    fun moderatorDeleteIsReadBackAndNeverTouchesCounters() = runTest {
        val source =
            FakeSource().apply {
                moderate = true
                saved["comment-1"] = comment()
            }
        val before = source.parentFields
        CommunityRepository(source, { alice.copy(role = "admin") }).deleteComment(news, "comment-1")
        assertTrue(source.saved.isEmpty())
        assertEquals(before, source.parentFields)
        assertEquals(1, source.deletes)
    }

    @Test
    fun staleSessionResultIsSuppressedAfterSdkCompletes() = runTest {
        var session = alice
        val pause = CompletableDeferred<Unit>()
        val source = FakeSource().apply { callPause = pause }
        val pending = async {
            CommunityRepository(source, { session }).setRegistration(event, true)
        }
        runCurrent()
        session = bob
        pause.complete(Unit)
        try {
            pending.await()
            fail("Stale success must not escape")
        } catch (_: CancellationException) {}
        assertEquals(alice.uid, source.calls.single().third)
    }

    @Test
    fun viewModelDoubleTapOneMutationAndEditedDraftIsNotLost() = runTest {
        val source = FakeSource()
        val model = CommunityViewModel(source, { alice }, DirectCommunityMutationGate)
        model.show(news)
        runCurrent()
        val pause = CompletableDeferred<Unit>()
        source.callPause = pause
        model.draft("First")
        model.addComment()
        model.addComment()
        runCurrent()
        assertEquals(1, source.calls.size)
        model.draft("Second draft")
        pause.complete(Unit)
        runCurrent()
        assertEquals("Second draft", model.state.value.draft)
        assertNotNull(model.state.value.sentId)
        model.hide(news)
        runCurrent()
        assertEquals(0, source.listeners)
    }

    @Test
    fun listenersStopOnHideAndSessionSwitchClearsPrivateState() = runTest {
        val sessions = MutableStateFlow<CommunitySession?>(alice)
        val source = FakeSource()
        val model = CommunityViewModel(source, { sessions.value }, DirectCommunityMutationGate)
        model.observeSessions(sessions)
        model.show(news)
        runCurrent()
        assertEquals(1, source.listeners)
        model.draft("Private draft")
        sessions.value = bob
        runCurrent()
        assertEquals("", model.state.value.draft)
        assertEquals(bob, model.state.value.session)
        assertEquals(1, source.listeners)
        model.hide(news)
        runCurrent()
        assertEquals(0, source.listeners)
        assertNull(model.state.value.page)
    }

    @Test
    fun uncertainSendRequiresFreshDiscussionAndExplicitAcknowledgement() = runTest {
        val source = FakeSource().apply { callFailure = CommunityFailure.OFFLINE }
        val model = CommunityViewModel(source, { alice }, DirectCommunityMutationGate)
        model.show(news)
        runCurrent()
        model.draft("Test")
        model.addComment()
        runCurrent()
        assertTrue(model.state.value.uncertain)
        model.addComment()
        runCurrent()
        assertEquals(1, source.calls.size)
        model.hide(news)
        model.show(news)
        runCurrent()
        assertTrue(model.state.value.uncertain)
        source.pages.value = Result.success(CommentPage(emptyList(), true))
        runCurrent()
        model.acknowledgeUncertainSend()
        assertTrue(model.state.value.uncertain)
        source.pages.value = Result.success(CommentPage(emptyList(), false))
        runCurrent()
        model.acknowledgeUncertainSend()
        assertFalse(model.state.value.uncertain)
        model.hide(news)
        advanceUntilIdle()
    }
}
