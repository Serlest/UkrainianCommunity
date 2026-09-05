package at.uac.android

import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthIdentity
import at.uac.android.feature.auth.AuthProfile
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.decodeContent
import at.uac.android.feature.personal.*
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PersonalTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    private val now = Instant.parse("2026-09-03T01:00:00.123456Z")
    private val alice = PersonalSession("synthetic-alice", true, true, 1)
    private val bob = PersonalSession("synthetic-bob", true, true, 2)
    private val draft =
        ProfileDraft("Demo Person", "Demo", "Wien", "Biography", "demo_user", "wien")
    private val news = PersonalTarget(ContentKind.NEWS, "synthetic-news-01")

    private fun content(kind: ContentKind, id: String): RawDocument =
        RawDocument(
            id,
            mapOf(
                "title" to id,
                "summary" to "Summary",
                "body" to "Body",
                "details" to "Details",
                "name" to id,
                "description" to "Description",
                "city" to "Wien",
                "moderationStatus" to "approved",
                "sourceType" to "organization",
                "createdAt" to now,
                "updatedAt" to now,
                "publishedAt" to now,
                "startDate" to now,
                "endDate" to now.plusSeconds(3_600),
            ),
        )

    private inner class FakeSource : PersonalSource {
        val markers = mutableMapOf<String, RawDocument>()
        val content = mutableMapOf<String, RawDocument>()
        var writes = 0
        var profileSaves = 0
        var profileDelay = 0L
        var writeDelay = 0L
        var pageDelay = 0L
        var failReadAfterWrite = false
        var readFailure: PersonalFailure? = null
        var contentCalls = 0
        var beforeContent: () -> Unit = {}
        var beforeRead: suspend () -> Unit = {}
        var profileDraft = draft

        override suspend fun profile(uid: String): PersonalProfile {
            delay(profileDelay)
            return PersonalProfile(uid, "$uid@example.invalid", profileDraft, now)
        }

        override suspend fun saveProfile(
            uid: String,
            draft: ProfileDraft,
            stillCurrent: () -> Boolean,
        ): PersonalProfile {
            if (!stillCurrent()) throw CancellationException()
            profileSaves++
            profileDraft = draft
            return profile(uid)
        }

        override suspend fun marker(marker: PersonalMarker): RawDocument? {
            beforeRead()
            readFailure?.let { throw PersonalException(it) }
            if (failReadAfterWrite && writes > 0) throw PersonalException(PersonalFailure.OFFLINE)
            return markers[marker.path]
        }

        override suspend fun setMarker(
            marker: PersonalMarker,
            enabled: Boolean,
            stillCurrent: () -> Boolean,
        ) {
            delay(writeDelay)
            if (!stillCurrent()) throw CancellationException()
            if (enabled && !markers.containsKey(marker.path)) {
                markers[marker.path] =
                    RawDocument(marker.id, marker.identityFields() + ("createdAt" to now))
                writes++
            } else if (!enabled && markers.remove(marker.path) != null) writes++
        }

        private fun page(rows: List<RawDocument>, after: String?, size: Int): MarkerPage {
            val values =
                rows.sortedBy { it.id }.filter { after == null || it.id > after }.take(size + 1)
            return MarkerPage(
                values.take(size),
                values.take(size).lastOrNull()?.id ?: after,
                values.size > size,
            )
        }

        override suspend fun bookmarkPage(
            uid: String,
            kind: ContentKind,
            after: String?,
            size: Int,
        ): MarkerPage {
            delay(pageDelay)
            val collection = PersonalTarget(kind, "x").bookmarkCollection
            return page(
                markers.filterKeys { it.startsWith("users/$uid/$collection/") }.values.toList(),
                after,
                size,
            )
        }

        override suspend fun relationPage(uid: String, after: String?, size: Int): MarkerPage =
            page(
                markers
                    .filter { (path, value) ->
                        path.startsWith("likes/") && value.fields["userId"] == uid
                    }
                    .values
                    .toList(),
                after,
                size,
            )

        override suspend fun approvedContent(
            kind: ContentKind,
            ids: List<String>,
        ): List<RawDocument> {
            contentCalls++
            beforeContent()
            return ids.mapNotNull { content["${kind.collection}/$it"] }
                .filter { it.fields["moderationStatus"] == "approved" }
        }

        fun seed(
            target: PersonalTarget,
            action: PersonalAction = PersonalAction.BOOKMARK,
            uid: String = alice.uid,
        ) {
            val marker = PersonalMarker(target, uid, action)
            markers[marker.path] =
                RawDocument(marker.id, marker.identityFields() + ("createdAt" to now))
            content[target.key] = this@PersonalTest.content(target.kind, target.id)
        }
    }

    @Test
    fun canonicalPathsMatchIosAndRules() {
        assertEquals(
            "likes/synthetic-news-01_synthetic-alice",
            PersonalMarker(news, alice.uid, PersonalAction.LIKE).path,
        )
        val event = PersonalTarget(ContentKind.EVENTS, "e")
        assertEquals(
            "likes/event_e_synthetic-alice",
            PersonalMarker(event, alice.uid, PersonalAction.LIKE).path,
        )
        val org = PersonalTarget(ContentKind.ORGANIZATIONS, "o")
        assertEquals(
            "likes/organization_o_synthetic-alice",
            PersonalMarker(org, alice.uid, PersonalAction.LIKE).path,
        )
        assertEquals(
            "likes/organization_follow_o_synthetic-alice",
            PersonalMarker(org, alice.uid, PersonalAction.SUBSCRIBE).path,
        )
        assertEquals(
            "users/synthetic-alice/newsBookmarks/synthetic-news-01",
            PersonalMarker(news, alice.uid, PersonalAction.BOOKMARK).path,
        )
        assertEquals(
            setOf("id", "userId", "subscribedOrganizationId"),
            PersonalMarker(org, alice.uid, PersonalAction.SUBSCRIBE).identityFields().keys,
        )
    }

    @Test
    fun invalidIdsAndReservedLikeNamespacesAreRejected() {
        listOf("", "a/b", "..", "a\nb", "a".repeat(1501)).forEach {
            assertFalse(validDocumentId(it))
        }
        for (target in
            listOf(
                PersonalTarget(ContentKind.NEWS, "event_reserved"),
                PersonalTarget(ContentKind.ORGANIZATIONS, "follow_reserved"),
            )) {
            try {
                PersonalMarker(target, alice.uid, PersonalAction.LIKE)
                fail("Reserved ID")
            } catch (_: IllegalArgumentException) {}
        }
        try {
            PersonalMarker(news, alice.uid, PersonalAction.SUBSCRIBE)
            fail("Not an organization")
        } catch (_: IllegalArgumentException) {}
    }

    @Test
    fun profileValidatesContractBoundsAndSafeAvatar() {
        assertTrue(draft.valid())
        assertTrue(draft.copy(displayName = "x".repeat(160), bio = "b".repeat(2_000)).valid())
        assertFalse(draft.copy(displayName = "x".repeat(161)).valid())
        assertFalse(draft.copy(fullName = "   ").valid())
        assertFalse(draft.copy(city = "x".repeat(161)).valid())
        assertFalse(draft.copy(bio = "x".repeat(2_001)).valid())
        assertFalse(draft.copy(telegramUsername = "x".repeat(81)).valid())
        assertFalse(draft.copy(federalState = "unknown").valid())
        assertFalse(draft.copy(avatarUrl = "http://example.invalid/a.jpg").valid())
        assertFalse(draft.copy(avatarUrl = "https://user@example.invalid/a.jpg").valid())
        assertTrue(draft.copy(avatarUrl = "https://example.invalid/a.jpg").valid())
        assertFalse(draft.copy(displayName = "name\nrole").valid())
    }

    @Test
    fun profileDecoderNeverIncludesAuthorityInEditableDraft() {
        val fields =
            mapOf(
                "id" to alice.uid,
                "fullName" to "Full",
                "email" to "demo@example.invalid",
                "city" to "",
                "bio" to "",
                "globalRole" to "owner",
                "accountStatus" to "bannedPermanent",
                "selectedFederalState" to "wien",
            )
        val profile = decodePersonalProfile(alice.uid, fields)
        assertEquals("Full", profile.draft.displayName)
        assertEquals("wien", profile.draft.federalState)
        try {
            decodePersonalProfile(bob.uid, fields)
            fail("Wrong identity")
        } catch (error: PersonalException) {
            assertEquals(PersonalFailure.INVALID, error.reason)
        }
    }

    @Test
    fun saveNormalizesAndReadsBackWithoutChangingSession() = runTest {
        val source = FakeSource()
        val repository = PersonalRepository(source, { alice })
        val saved =
            repository.saveProfile(
                draft.copy(displayName = "  New Name  ", city = " Wien ", telegramUsername = "   ")
            )
        assertEquals("New Name", saved.draft.displayName)
        assertEquals("", saved.draft.telegramUsername)
        assertEquals(1, source.profileSaves)
    }

    @Test
    fun guestAndRestrictedMutationsStopBeforeSource() = runTest {
        val source = FakeSource()
        for (session in
            listOf(null, alice.copy(emailVerified = false), alice.copy(active = false))) {
            val repository = PersonalRepository(source, { session })
            try {
                repository.set(news, PersonalAction.LIKE, true)
                fail("Not allowed")
            } catch (error: PersonalException) {
                assertEquals(
                    if (session == null) PersonalFailure.SIGN_IN else PersonalFailure.NOT_READY,
                    error.reason,
                )
            }
        }
        assertEquals(0, source.writes)
    }

    @Test
    fun unverifiedAccountCanReadItsOwnProfileButCannotSave() = runTest {
        val source = FakeSource()
        val repository = PersonalRepository(source, { alice.copy(emailVerified = false) })
        assertEquals(alice.uid, repository.profile().uid)
        try {
            repository.saveProfile(draft)
            fail("Verification gate")
        } catch (error: PersonalException) {
            assertEquals(PersonalFailure.NOT_READY, error.reason)
        }
        assertEquals(0, source.profileSaves)
    }

    @Test
    fun likesAndBookmarksAreExplicitIdempotentDesiredStates() = runTest {
        val source = FakeSource()
        val repository = PersonalRepository(source, { alice })
        for (action in listOf(PersonalAction.LIKE, PersonalAction.BOOKMARK)) {
            assertTrue(repository.set(news, action, true))
            assertTrue(repository.set(news, action, true))
            assertFalse(repository.set(news, action, false))
            assertFalse(repository.set(news, action, false))
        }
        assertEquals(4, source.writes)
        assertTrue(source.markers.isEmpty())
    }

    @Test
    fun retryAfterUncertainReadBackDoesNotInvertOrDuplicate() = runTest {
        val source = FakeSource().apply { failReadAfterWrite = true }
        val repository = PersonalRepository(source, { alice })
        try {
            repository.set(news, PersonalAction.BOOKMARK, true)
            fail("Uncertain read-back")
        } catch (error: PersonalException) {
            assertEquals(PersonalFailure.OFFLINE, error.reason)
        }
        source.failReadAfterWrite = false
        assertTrue(repository.set(news, PersonalAction.BOOKMARK, true))
        assertEquals(1, source.writes)
    }

    @Test
    fun malformedMarkerFailsClosed() = runTest {
        val source = FakeSource()
        val marker = PersonalMarker(news, alice.uid, PersonalAction.LIKE)
        source.markers[marker.path] =
            RawDocument(marker.id, marker.identityFields() + ("userId" to bob.uid))
        try {
            PersonalRepository(source, { alice }).actions(news)
            fail("Wrong marker owner")
        } catch (error: PersonalException) {
            assertEquals(PersonalFailure.INVALID, error.reason)
        }
    }

    @Test
    fun savedPagesPreserveCursorAndHiddenBookmarks() = runTest {
        val source = FakeSource()
        repeat(4) { source.seed(PersonalTarget(ContentKind.NEWS, "news-$it")) }
        source.content.remove("news/news-1")
        source.content["news/news-2"] =
            content(ContentKind.NEWS, "news-2").let {
                it.copy(fields = it.fields + ("moderationStatus" to "draft"))
            }
        val repository = PersonalRepository(source, { alice })
        val first = repository.saved(ContentKind.NEWS, size = 2)
        assertEquals(listOf("news-0"), first.items.map { it.id })
        assertEquals(1, first.unavailable)
        assertTrue(first.hasMore)
        val second = repository.saved(ContentKind.NEWS, first.next, size = 2)
        assertEquals(listOf("news-3"), second.items.map { it.id })
        assertEquals(1, second.unavailable)
        assertFalse(second.hasMore)
        assertEquals(4, source.markers.size)
    }

    @Test
    fun savedVisibilityPolicyDoesNotDeleteBookmarks() = runTest {
        val source = FakeSource().apply { seed(news) }
        val page =
            PersonalRepository(source, { alice }, visible = { false }).saved(ContentKind.NEWS)
        assertTrue(page.items.isEmpty())
        assertEquals(1, page.unavailable)
        assertEquals(1, source.markers.size)
    }

    @Test
    fun targetScopeChangeStopsBeforeReadingTheNextBatch() = runTest {
        var authority = alice
        val source =
            FakeSource().apply {
                repeat(25) { seed(PersonalTarget(ContentKind.NEWS, "scoped-news-$it")) }
                beforeContent = { authority = bob }
            }
        val request = async { PersonalRepository(source, { authority }).saved(ContentKind.NEWS) }
        advanceUntilIdle()
        assertTrue(request.isCancelled)
        assertEquals(1, source.contentCalls)
        assertEquals(25, source.markers.size)
        assertEquals(0, source.writes)
    }

    @Test
    fun legacyTargetSourceDefaultAdapterRejectsAnAlreadyStaleRead() = runTest {
        val source = FakeSource().apply { seed(news) }
        try {
            source.approvedContentCurrent(ContentKind.NEWS, listOf(news.id)) { false }
            fail("Stale read")
        } catch (_: CancellationException) {}
        assertEquals(0, source.contentCalls)
    }

    @Test
    fun targetTransportFailureIsNotSilentlyTreatedAsAnUnavailableBookmark() = runTest {
        val source =
            FakeSource().apply {
                seed(news)
                beforeContent = { throw PersonalException(PersonalFailure.OFFLINE) }
            }
        try {
            PersonalRepository(source, { alice }).saved(ContentKind.NEWS)
            fail("Transport failure must stay visible")
        } catch (error: PersonalException) {
            assertEquals(PersonalFailure.OFFLINE, error.reason)
        }
        assertEquals(1, source.markers.size)
        assertEquals(0, source.writes)
    }

    @Test
    fun otherAccountsBookmarksAreNotIncluded() = runTest {
        val source = FakeSource().apply { seed(news, uid = bob.uid) }
        assertTrue(PersonalRepository(source, { alice }).saved(ContentKind.NEWS).items.isEmpty())
    }

    @Test
    fun subscriptionsSkipLikeRowsButRetainContinuation() = runTest {
        val source =
            FakeSource().apply {
                seed(PersonalTarget(ContentKind.EVENTS, "early"), PersonalAction.LIKE)
                seed(PersonalTarget(ContentKind.ORGANIZATIONS, "org"), PersonalAction.SUBSCRIBE)
            }
        val repository = PersonalRepository(source, { alice })
        val first = repository.subscriptions(size = 1)
        assertTrue(first.items.isEmpty())
        assertTrue(first.hasMore)
        val second = repository.subscriptions(first.next, size = 1)
        assertEquals(listOf("org"), second.items.map { it.id })
        assertFalse(second.hasMore)
    }

    @Test
    fun lateAccountResultIsCancelled() = runTest {
        var session = alice
        val source = FakeSource().apply { profileDelay = 100 }
        val repository = PersonalRepository(source, { session })
        val request = async { repository.profile() }
        runCurrent()
        session = bob
        advanceUntilIdle()
        assertTrue(request.isCancelled)
    }

    @Test
    fun accountSwitchPreventsDelayedWrite() = runTest {
        var session = alice
        val source = FakeSource().apply { writeDelay = 100 }
        val request = async {
            PersonalRepository(source, { session }).set(news, PersonalAction.LIKE, true)
        }
        runCurrent()
        session = bob
        advanceUntilIdle()
        assertTrue(request.isCancelled)
        assertEquals(0, source.writes)
    }

    @Test
    fun timeoutIsOfflineNotSuccess() = runTest {
        val source = FakeSource().apply { profileDelay = 20_000 }
        try {
            PersonalRepository(source, { alice }).profile()
            fail("Timeout")
        } catch (error: PersonalException) {
            assertEquals(PersonalFailure.OFFLINE, error.reason)
        }
    }

    @Test
    fun viewModelDoubleTapMutatesOnlyOnceAndReadBackDrivesState() = runTest {
        val source = FakeSource().apply { writeDelay = 100 }
        val model = PersonalViewModel(source)
        model.bind(alice)
        model.loadActions(news)
        advanceUntilIdle()
        model.set(news, PersonalAction.LIKE, true)
        model.set(news, PersonalAction.LIKE, true)
        advanceUntilIdle()
        assertEquals(1, source.writes)
        assertTrue(model.state.value.actions.getValue(news).liked)
        assertTrue(model.state.value.actionsPending.isEmpty())
    }

    @Test
    fun authRevisionClearsProfileListsActionsAndErrorsImmediately() = runTest {
        val source = FakeSource().apply { seed(news) }
        val model = PersonalViewModel(source)
        model.bind(alice)
        model.loadProfile()
        model.loadSaved()
        model.loadActions(news)
        advanceUntilIdle()
        assertNotNull(model.state.value.profile)
        assertTrue(model.state.value.saved.isNotEmpty())
        model.bind(alice.copy(revision = 2, active = false))
        assertNull(model.state.value.profile)
        assertTrue(model.state.value.saved.isEmpty())
        assertTrue(model.state.value.actions.isEmpty())
        assertTrue(model.state.value.actionErrors.isEmpty())
    }

    @Test
    fun staleFailureCannotPopulateNewAccountsState() = runTest {
        val waiting = CompletableDeferred<Unit>()
        val source =
            FakeSource().apply {
                beforeRead = { withContext(NonCancellable) { waiting.await() } }
                readFailure = PersonalFailure.DENIED
            }
        val model = PersonalViewModel(source)
        model.bind(alice)
        model.loadActions(news)
        runCurrent()
        model.bind(bob)
        waiting.complete(Unit)
        advanceUntilIdle()
        assertEquals(bob, model.state.value.session)
        assertTrue(model.state.value.actionErrors.isEmpty())
        assertTrue(model.state.value.actions.isEmpty())
    }

    @Test
    fun savedModelPaginationDoesNotDuplicateRows() = runTest {
        val source =
            FakeSource().apply {
                repeat(36) {
                    seed(PersonalTarget(ContentKind.NEWS, "news-${it.toString().padStart(2, '0')}"))
                }
            }
        val model = PersonalViewModel(source)
        model.bind(alice)
        model.loadSaved()
        advanceUntilIdle()
        assertEquals(30, model.state.value.saved.getValue(ContentKind.NEWS).items.size)
        model.loadSaved(true)
        model.loadSaved(true)
        advanceUntilIdle()
        assertEquals(36, model.state.value.saved.getValue(ContentKind.NEWS).items.size)
    }

    @Test
    fun sortingHasDeterministicTiesAndLocaleDirection() {
        val items =
            listOf("Bravo", "Alpha").map {
                decodeContent(ContentKind.NEWS, content(ContentKind.NEWS, it))
            }
        assertEquals(
            listOf("Alpha", "Bravo"),
            sortedPersonalContent(items, "de", PersonalSort.NEWEST).map { it.id },
        )
        assertEquals(
            listOf("Bravo", "Alpha"),
            sortedPersonalContent(items, "uk", PersonalSort.NAME_DESCENDING).map { it.id },
        )
    }

    @Test
    fun authoritativeAuthGateDrivesPersonalScope() {
        val identity = AuthIdentity(alice.uid, "demo@example.invalid", true)
        val profile = AuthProfile(alice.uid, identity.email, "Demo")
        val auth = AuthSession(AuthStage.AUTHENTICATED, identity, profile, revision = 4)
        assertEquals(PersonalSession(alice.uid, true, true, 4), auth.personalScope())
        assertFalse(auth.copy(gate = AuthGate.MFA_REQUIRED).personalScope()!!.ready)
        assertFalse(auth.copy(gate = AuthGate.LEGAL_UNAVAILABLE).personalScope()!!.ready)
        assertNull(auth.copy(stage = AuthStage.SESSION_UNAVAILABLE).personalScope())
        assertNull(auth.copy(profile = profile.copy(uid = bob.uid)).personalScope())
    }

    @Test
    fun uiMaskHidesOldAccountBeforeObserverHasResumed() {
        val old =
            PersonalState(
                session = alice,
                profile = PersonalProfile(alice.uid, "a@example.invalid", draft, now),
                actions = mapOf(news to PersonalActions(liked = true)),
            )
        assertEquals(PersonalState(session = bob), old.forSession(bob))
        assertEquals(PersonalState(), old.forSession(null))
        assertSame(old, old.forSession(alice))
    }

    @Test
    fun authorityChangeRejectsStaleTapBeforeSessionCollectorResumes() = runTest {
        var authority = alice
        val source = FakeSource()
        val model = PersonalViewModel(source, sessionAuthority = { authority })
        model.bind(alice)
        authority = bob
        model.set(news, PersonalAction.LIKE, true)
        advanceUntilIdle()
        assertEquals(bob, model.state.value.session)
        assertEquals(0, source.writes)
    }

    @Test
    fun mutationGateReceivesCapturedScopeForBothWriteTypes() = runTest {
        val scopes = mutableListOf<PersonalSession>()
        val gate =
            object : PersonalMutationGate {
                override suspend fun <T> withSession(
                    session: PersonalSession,
                    operation: suspend () -> T,
                ): T {
                    scopes += session
                    return operation()
                }
            }
        val repository = PersonalRepository(FakeSource(), { alice }, mutations = gate)
        repository.set(news, PersonalAction.LIKE, true)
        repository.saveProfile(draft)
        assertEquals(listOf(alice, alice), scopes)
    }

    @Test
    fun runningMutationIsAwaitedInsteadOfTimingOutAndReleasingItsIdentityGate() = runTest {
        val source = FakeSource().apply { writeDelay = 20_000 }
        assertTrue(PersonalRepository(source, { alice }).set(news, PersonalAction.BOOKMARK, true))
        assertEquals(1, source.writes)
    }

    @Test
    fun visibilityChangeReloadsExistingListsAndRestoresUnblockedTargets() = runTest {
        var visible = true
        val source = FakeSource().apply { seed(news) }
        val model = PersonalViewModel(source, visibility = { visible })
        model.bind(alice)
        model.loadSaved()
        advanceUntilIdle()
        assertEquals(1, model.state.value.saved.getValue(ContentKind.NEWS).items.size)
        visible = false
        model.visibilityChanged()
        advanceUntilIdle()
        assertTrue(model.state.value.saved.getValue(ContentKind.NEWS).items.isEmpty())
        visible = true
        model.visibilityChanged()
        advanceUntilIdle()
        assertEquals(news.id, model.state.value.saved.getValue(ContentKind.NEWS).items.single().id)
        assertEquals(0, source.writes)
    }

    @Test
    fun visibilityChangeReplacesInFlightListReadsWithoutLosingTheReplacementJob() = runTest {
        var visible = true
        val source =
            FakeSource().apply {
                seed(news)
                pageDelay = 1_000
            }
        val model = PersonalViewModel(source, visibility = { visible })
        model.bind(alice)
        model.loadSaved()
        runCurrent()
        visible = false
        model.visibilityChanged()
        runCurrent()
        model.loadSaved(true)
        advanceUntilIdle()
        assertFalse(model.state.value.savedLoading)
        assertTrue(model.state.value.saved.getValue(ContentKind.NEWS).items.isEmpty())
        visible = true
        model.visibilityChanged()
        advanceUntilIdle()
        assertEquals(1, model.state.value.saved.getValue(ContentKind.NEWS).items.size)
    }

    @Test
    fun visibilityChangeNeverCancelsAnAlreadySubmittedWrite() = runTest {
        val source =
            FakeSource().apply {
                seed(news)
                writeDelay = 20_000
            }
        val model = PersonalViewModel(source)
        model.bind(alice)
        model.loadSaved()
        advanceUntilIdle()
        model.set(news, PersonalAction.BOOKMARK, false)
        runCurrent()
        model.visibilityChanged()
        advanceUntilIdle()
        assertEquals(1, source.writes)
        assertFalse(model.state.value.actions.getValue(news).bookmarked)
    }
}
