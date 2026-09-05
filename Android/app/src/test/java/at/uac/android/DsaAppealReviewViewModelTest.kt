package at.uac.android

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.dsaappeal.*
import at.uac.android.feature.feedback.*
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DsaAppealReviewViewModelTest {
    private val base = Instant.parse("2026-09-03T12:00:00Z")
    private val actor = DsaAppealSession("reporter", 1, "synthetic", true)
    private var authority: DsaAppealSession? = actor
    private var reads = 0
    private var operation: suspend (String) -> RawDocument? = { row(it) }
    private val models = mutableListOf<DsaAppealReviewViewModel>()

    private fun row(id: String) =
        RawDocument(
            id,
            FeedbackContract.creation(
                id,
                FeedbackSession(actor.uid, 1, true, false, "Synthetic"),
                FeedbackDraft(FeedbackType.REPORT, "Synthetic report"),
                base.minusSeconds(60),
            ) +
                mapOf(
                    "status" to "closed",
                    "updatedAt" to base,
                    "dsaCase" to
                        mapOf(
                            "caseNumber" to "PRIVATE CASE",
                            "status" to "decided",
                            "category" to "other",
                            "exactLocation" to "PRIVATE LOCATION",
                            "illegalExplanation" to "PRIVATE EXPLANATION",
                            "legalBasis" to null,
                            "evidence" to null,
                            "goodFaithConfirmed" to true,
                            "acknowledgementAt" to base.minusSeconds(60),
                            "preferredLanguage" to "de",
                            "decision" to
                                mapOf(
                                    "outcome" to "noAction",
                                    "factsAndCircumstances" to "PRIVATE FACTS",
                                    "legalBasis" to "Synthetic basis",
                                    "termsBasis" to null,
                                    "territorialScope" to "AT",
                                    "duration" to "Synthetic",
                                    "redressInformation" to "Synthetic redress",
                                    "automationUsed" to false,
                                    "humanReviewConfirmed" to true,
                                    "actionVerifiedAt" to base,
                                    "decidedAt" to base,
                                    "decidedByUserId" to "synthetic-owner",
                                    "appealDeadline" to base.plusSeconds(3),
                                ),
                        ),
                ),
        )

    private fun model(clock: () -> Instant) =
        DsaAppealReviewViewModel(
                DsaAppealReadSource { _, id ->
                    reads++
                    operation(id)
                },
                { authority },
                object : DsaAppealReadGate {
                    override suspend fun <T> withSession(
                        session: DsaAppealSession,
                        action: suspend () -> T,
                    ): T = withContext(NonCancellable) { action() }
                },
                clock,
            )
            .also { models += it }

    private fun checked(block: suspend TestScope.() -> Unit) = runTest {
        try {
            block()
        } finally {
            models.forEach { it.bind(null) }
        }
    }

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        models.forEach { it.bind(null) }
        Dispatchers.resetMain()
    }

    @Test
    fun repeatedShowReadsOnceAndHideRemovesPrivateState() = checked {
        val m = model { base.plusMillis(testScheduler.currentTime) }
        m.show("report")
        runCurrent()
        m.show("report")
        runCurrent()
        assertEquals(1, reads)
        assertNotNull(m.state.value.review)
        m.hide("report")
        assertNull(m.state.value.reportId)
        assertNull(m.state.value.review)
        assertFalse(m.state.value.visible)
    }

    @Test
    fun deadlineEqualityClearsReviewWithoutRequest() = checked {
        val m = model { base.plusMillis(testScheduler.currentTime) }
        m.show("report")
        runCurrent()
        advanceTimeBy(2999)
        runCurrent()
        assertNotNull(m.state.value.review)
        advanceTimeBy(1)
        runCurrent()
        assertNull(m.state.value.review)
        assertEquals(DsaAppealReviewFailure.EXPIRED, m.state.value.error)
        assertEquals(1, reads)
    }

    @Test
    fun nanosecondBoundaryDoesNotExpireEarly() = checked {
        val m = model { base.plusMillis(testScheduler.currentTime).plusNanos(1) }
        m.show("report")
        runCurrent()
        advanceTimeBy(2999)
        runCurrent()
        assertNotNull(m.state.value.review)
        advanceTimeBy(1)
        runCurrent()
        assertEquals(DsaAppealReviewFailure.EXPIRED, m.state.value.error)
    }

    @Test
    fun immediateRenderMaskBlocksExpiryClockRollbackAndRevokedAccount() = checked {
        val m = model { base }
        m.show("report")
        runCurrent()
        val state = m.state.value
        assertNotNull(state.forSession(actor, base).review)
        assertNull(state.forSession(actor, base.plusSeconds(3)).review)
        assertEquals(
            DsaAppealReviewFailure.INELIGIBLE,
            state.forSession(actor, base.minusNanos(1)).error,
        )
        for (scope in
            listOf(
                null,
                actor.copy(uid = "other"),
                actor.copy(revision = 2),
                actor.copy(backend = "other"),
                actor.copy(ready = false),
            )) assertNull(state.forSession(scope, base).review)
    }

    @Test
    fun refreshClearsPrivateReviewAndDoubleTapDoesNotDuplicateRead() = checked {
        val m = model { base }
        m.show("report")
        runCurrent()
        val release = CompletableDeferred<Unit>()
        operation = {
            release.await()
            row(it)
        }
        m.refresh()
        m.refresh()
        runCurrent()
        assertNull(m.state.value.review)
        assertTrue(m.state.value.loading)
        assertEquals(2, reads)
        release.complete(Unit)
        runCurrent()
        assertNotNull(m.state.value.review)
    }

    @Test
    fun hideFencesNonCancellableLateResult() = checked {
        val release = CompletableDeferred<Unit>()
        operation = {
            release.await()
            row(it)
        }
        val m = model { base }
        m.show("report")
        runCurrent()
        m.hide("report")
        release.complete(Unit)
        runCurrent()
        assertNull(m.state.value.review)
        assertFalse(m.state.value.visible)
        assertFalse(m.state.value.loading)
    }

    @Test
    fun newTargetDiscardsOldResultAndOldHide() = checked {
        val release = CompletableDeferred<Unit>()
        operation = {
            if (it == "first") release.await()
            row(it)
        }
        val m = model { base }
        m.show("first")
        runCurrent()
        m.show("second")
        runCurrent()
        m.hide("first")
        release.complete(Unit)
        runCurrent()
        assertEquals("second", m.state.value.review!!.snapshot.reportId)
    }

    @Test
    fun observerRevocationClearsWithoutReload() = checked {
        val sessions = MutableStateFlow<DsaAppealSession?>(actor)
        val m = model { base }
        m.observeSessions(sessions)
        m.show("report")
        runCurrent()
        authority = actor.copy(revision = 2)
        sessions.value = authority
        runCurrent()
        assertNull(m.state.value.review)
        assertFalse(m.state.value.visible)
        assertEquals(1, reads)
    }

    @Test
    fun revocationBeforeObserverStillRejectsLateResponse() = checked {
        val release = CompletableDeferred<Unit>()
        operation = {
            release.await()
            row(it)
        }
        val m = model { base }
        m.show("report")
        runCurrent()
        authority = actor.copy(revision = 2)
        release.complete(Unit)
        runCurrent()
        assertNull(m.state.value.forSession(authority, base).review)
        m.refresh()
        assertEquals(authority, m.state.value.session)
        assertFalse(m.state.value.visible)
    }

    @Test
    fun everyFailureClearsDataAndDoesNotAutomaticallyRetry() = checked {
        for (failure in DsaAppealReviewFailure.entries) {
            operation = { row(it) }
            val m = model { base }
            m.show("report")
            runCurrent()
            val before = reads
            operation = { DsaAppealReviewContract.fail(failure) }
            m.refresh()
            runCurrent()
            assertEquals(failure, m.state.value.error)
            assertNull(m.state.value.review)
            assertFalse(m.state.value.loading)
            assertEquals(before + 1, reads)
            m.hide("report")
        }
    }

    @Test
    fun absentAndInvalidRowsAreNotSuccessfulEmptyReview() = checked {
        val m = model { base }
        operation = { null }
        m.show("report")
        runCurrent()
        assertEquals(DsaAppealReviewFailure.MISSING, m.state.value.error)
        operation = { row(it).copy(fields = emptyMap()) }
        m.refresh()
        runCurrent()
        assertNull(m.state.value.review)
        assertNotNull(m.state.value.error)
    }

    @Test
    fun invalidRouteAndUnreadyScopeNeverRead() = checked {
        val m = model { base }
        m.show("wrong/path")
        runCurrent()
        assertEquals(DsaAppealReviewFailure.INVALID, m.state.value.error)
        authority = actor.copy(ready = false)
        m.show("report")
        runCurrent()
        assertEquals(DsaAppealReviewFailure.ACCESS, m.state.value.error)
        assertEquals(0, reads)
    }

    @Test
    fun explicitReopenAlwaysReadsAgainAndNoPrivateDiagnostics() = checked {
        val m = model { base }
        m.show("report")
        runCurrent()
        assertFalse(m.state.value.toString().contains("PRIVATE"))
        m.hide("report")
        m.show("report")
        runCurrent()
        assertEquals(2, reads)
    }

    @Test
    fun cancellationCanBeRetriedExplicitlyWithoutAutomaticSpin() = checked {
        operation = { throw CancellationException("synthetic") }
        val m = model { base }
        m.show("report")
        runCurrent()
        assertFalse(m.state.value.loading)
        assertNull(m.state.value.review)
        assertEquals(1, reads)
        operation = { row(it) }
        m.refresh()
        runCurrent()
        assertNotNull(m.state.value.review)
        assertEquals(2, reads)
    }
}
