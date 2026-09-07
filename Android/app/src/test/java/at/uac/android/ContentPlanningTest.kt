package at.uac.android

import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.authoring.AuthoringContract
import at.uac.android.feature.contentplanning.*
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ContentPlanningTest {
    private val session = ModerationSession("owner-planning", 68, "owner", true)
    private val draftId = "a".repeat(40)
    private val now = Instant.parse("2026-09-07T16:00:00.456Z")

    private fun draft(
        state: ContentPlanningState = ContentPlanningState.READY,
        missing: List<String> = emptyList(),
        sources: List<ContentPlanningSource> =
            listOf(ContentPlanningSource("https://example.org/source", "Primary", true, now)),
    ) =
        ContentPlanningDraft(
            draftId,
            3,
            session.uid,
            ContentPlanningKind.NEWS,
            state,
            "Verified title",
            mapOf(
                "title" to "Verified title",
                "summary" to "Summary",
                "body" to "Full body",
                "sourceInput" to "https://example.org/source",
            ),
            sources,
            listOf("Compared with source"),
            missing,
            now,
            now,
            null,
            null,
            null,
            null,
            if (state == ContentPlanningState.PUBLISHING) now.plusSeconds(600) else null,
            null,
            null,
            null,
            null,
            null,
        )

    @Test
    fun callableShapesMatchBuild68AndMutationsBecomeUnconfirmedAfterDispatch() {
        val names =
            setOf(
                ContentPlanningContract.BEGIN,
                ContentPlanningContract.FINALIZE,
                ContentPlanningContract.FAIL,
                ContentPlanningContract.ARCHIVE,
                ContentPlanningContract.DELETE,
            )
        names.forEach {
            LocalCallableProtocol.requireAllowed(it)
            assertTrue(LocalCallableProtocol.nonIdempotent(it))
            assertEquals(
                LocalCallableFailure.UNCONFIRMED,
                LocalCallableProtocol.transportFailure(it, true, LocalCallableFailure.UNAVAILABLE),
            )
        }
        assertEquals(
            mapOf("draftId" to draftId, "attemptId" to "12345678-1234-1234-1234-123456789012"),
            ContentPlanningContract.beginPayload(draftId, "12345678-1234-1234-1234-123456789012"),
        )
    }

    @Test
    fun fractionalLeaseDatesAndExistingScheduledRecoveryAreAccepted() {
        val lease =
            ContentPlanningContract.lease(
                mapOf(
                    "draftId" to draftId,
                    "kind" to "news",
                    "contentId" to "planning-$draftId",
                    "leaseId" to "12345678-1234-1234-1234-123456789012",
                    "expiresAt" to "2026-09-07T16:10:00.456Z",
                    "contentAlreadyExists" to true,
                    "existingModerationStatus" to "draft",
                    "existingScheduledAt" to "2026-09-08T10:00:00.789Z",
                ),
                draftId,
            )
        assertEquals(456_000_000, lease.expiresAt.nano)
        assertEquals(789_000_000, lease.existingScheduledAt?.nano)
        assertEquals("planning-$draftId", lease.contentId)
    }

    @Test
    fun sourceAndMissingFieldValidationFailClosed() {
        ContentPlanningContract.validateDraft(draft(), session.uid)
        assertEquals(
            ContentPlanningFailure.INVALID,
            assertThrows(ContentPlanningException::class.java) {
                    ContentPlanningContract.validateDraft(
                        draft(
                            sources =
                                listOf(ContentPlanningSource("file:///private", null, true, null))
                        ),
                        session.uid,
                    )
                }
                .failure,
        )
        assertEquals(
            ContentPlanningFailure.INVALID,
            assertThrows(ContentPlanningException::class.java) {
                    ContentPlanningContract.validateDraft(
                        draft(ContentPlanningState.ATTENTION, emptyList()),
                        session.uid,
                    )
                }
                .failure,
        )
        ContentPlanningContract.validateDraft(
            draft(ContentPlanningState.ATTENTION, listOf("germanBody")),
            session.uid,
        )
    }

    @Test
    fun planningPrefillUsesReservedStableContentId() {
        val first = AuthoringContract.planningDraft(draft())
        val second = AuthoringContract.planningDraft(draft())

        assertEquals("planning-$draftId", first.id)
        assertEquals("Verified title", first.title)
        assertEquals("Full body", first.body)
        assertEquals("https://example.org/source", first.source)
        assertEquals(first, second)
    }

    @Test
    fun ambiguousBeginUsesSameAttemptOnlyAfterExplicitRetry() = runTest {
        val repository = FakeRepository(session, draft())
        repository.beginFailures = 1
        val model = ContentPlanningViewModel(repository, this)
        model.show(session)
        advanceUntilIdle()

        model.begin(draft())
        advanceUntilIdle()
        assertEquals(
            ContentPlanningRecoveryPhase.BEGIN_UNCONFIRMED,
            model.state.value.recovery?.phase,
        )
        assertEquals(1, repository.attempts.size)

        model.retryRecovery()
        advanceUntilIdle()
        assertEquals(ContentPlanningRecoveryPhase.LEASED, model.state.value.recovery?.phase)
        assertEquals(2, repository.attempts.size)
        assertEquals(repository.attempts.first(), repository.attempts.last())
    }

    @Test
    fun ambiguousFinalizeRetainsExactLeaseAndNeverRunsAutomatically() = runTest {
        val item = draft()
        val repository = FakeRepository(session, item)
        repository.finalizeFailures = 1
        val model = ContentPlanningViewModel(repository, this)
        model.show(session)
        advanceUntilIdle()
        model.begin(item)
        advanceUntilIdle()
        val publication =
            ContentPlanningPublication(ContentPlanningKind.NEWS, "planning-$draftId", null)

        model.finalize(item, publication)
        advanceUntilIdle()
        assertEquals(1, repository.finalizeLeases.size)
        assertEquals(
            ContentPlanningRecoveryPhase.FINALIZE_UNCONFIRMED,
            model.state.value.recovery?.phase,
        )

        model.retryRecovery()
        advanceUntilIdle()
        assertEquals(2, repository.finalizeLeases.size)
        assertEquals(repository.finalizeLeases.first(), repository.finalizeLeases.last())
        assertNull(model.state.value.recovery)
    }

    @Test
    fun editorLeaseRemainsAuthorizedAfterPlanningScreenIsHidden() = runTest {
        val repository = FakeRepository(session, draft())
        val model = ContentPlanningViewModel(repository, this)
        model.show(session)
        advanceUntilIdle()
        model.hide()

        val lease = model.beginForEditor(draft())

        assertEquals("planning-$draftId", lease.contentId)
        assertEquals(1, repository.attempts.size)
    }

    @Test
    fun adminAndRevokedOwnerNeverReadOrMutate() = runTest {
        var current: ModerationSession? = session.copy(role = "admin")
        val repository = FakeRepository(current!!, draft()).also { it.live = { current } }
        val model = ContentPlanningViewModel(repository, this)
        model.show(current)
        advanceUntilIdle()
        assertFalse(model.state.value.allowed)
        assertEquals(0, repository.pages)

        current = session
        repository.expected = session
        model.show(session)
        advanceUntilIdle()
        assertEquals(1, repository.pages)
        current = null
        model.begin(draft())
        advanceUntilIdle()
        assertEquals(0, repository.attempts.size)
    }

    private class FakeRepository(
        var expected: ModerationSession,
        private val item: ContentPlanningDraft,
    ) : ContentPlanningRepository {
        override suspend fun organizations(session: ModerationSession) =
            listOf(ContentPlanningOrganization("org-1", "Organisation"))

        var live: () -> ModerationSession? = { expected }
        var pages = 0
        var beginFailures = 0
        var finalizeFailures = 0
        val attempts = mutableListOf<String>()
        val finalizeLeases = mutableListOf<String>()

        override fun currentSession() = live()

        override suspend fun page(
            session: ModerationSession,
            section: ContentPlanningSection,
            after: ContentPlanningCursor?,
            limit: Int,
        ): ContentPlanningPage {
            pages++
            return ContentPlanningPage(listOf(item), null, false)
        }

        override suspend fun draft(session: ModerationSession, draftId: String) = item

        override suspend fun begin(
            session: ModerationSession,
            draftId: String,
            attemptId: String,
            canDispatch: () -> Boolean,
        ): ContentPlanningLease {
            assertTrue(canDispatch())
            attempts += attemptId
            if (beginFailures-- > 0)
                throw ContentPlanningException(ContentPlanningFailure.UNCONFIRMED)
            return ContentPlanningLease(
                draftId,
                ContentPlanningKind.NEWS,
                "planning-$draftId",
                "lease_1234567890123456",
                Instant.now().plusSeconds(600),
                false,
                null,
                null,
            )
        }

        override suspend fun finalize(
            session: ModerationSession,
            draft: ContentPlanningDraft,
            lease: ContentPlanningLease,
            canDispatch: () -> Boolean,
        ): ContentPlanningState {
            assertTrue(canDispatch())
            finalizeLeases += lease.leaseId
            if (finalizeFailures-- > 0)
                throw ContentPlanningException(ContentPlanningFailure.UNCONFIRMED)
            return ContentPlanningState.COMPLETED
        }

        override suspend fun fail(
            session: ModerationSession,
            draftId: String,
            leaseId: String,
            message: String,
            canDispatch: () -> Boolean,
        ) = Unit

        override suspend fun archive(
            session: ModerationSession,
            draftId: String,
            canDispatch: () -> Boolean,
        ) = true

        override suspend fun delete(
            session: ModerationSession,
            draftId: String,
            canDispatch: () -> Boolean,
        ) = true
    }
}
