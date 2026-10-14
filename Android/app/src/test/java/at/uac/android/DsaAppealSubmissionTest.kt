package at.uac.android

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.dsaappeal.*
import at.uac.android.feature.feedback.*
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class DsaAppealSubmissionTest {
    private val now = Instant.parse("2026-10-14T12:00:00Z")
    private val actor = DsaAppealSession("reporter", 7, "synthetic", true)
    private var authority: DsaAppealSession? = actor
    private var row = decidedRow()
    private var calls = 0
    private var receiptValid = true
    private var projectionOffline = false
    private var projectionOfflineAfterSend = false
    private var malformedResponse = false
    private var payload: Map<String, String>? = null
    private val source = DsaAppealReadSource { _, _ ->
        if (projectionOffline) throw DsaAppealReviewException(DsaAppealReviewFailure.OFFLINE)
        row
    }
    private val gate = object : DsaAppealReadGate {
        override suspend fun <T> withSession(session: DsaAppealSession, action: suspend () -> T): T = action()
    }
    private val read = DsaAppealReadRepository(source, { authority }, gate) { now }
    private val mutation = DsaAppealSubmissionRepository(
        read, source,
        DsaAppealSubmissionSource { _, submitted ->
            calls++
            payload = submitted
            val reason = submitted.getValue("reason")
            val fields = row.fields
            val case = fields.getValue("dsaCase") as Map<*, *>
            row = RawDocument(row.id, fields + mapOf(
                "status" to "open",
                "updatedAt" to now.plusSeconds(1),
                "dsaCase" to case + mapOf(
                    "status" to "appealed",
                    "appeal" to mapOf(
                        "status" to "pending", "reason" to
                            (if (receiptValid) reason else "changed"),
                        "submittedAt" to now.plusSeconds(1),
                    ),
                ),
            ))
            if (projectionOfflineAfterSend) projectionOffline = true
            if (malformedResponse) return@DsaAppealSubmissionSource mapOf("unexpected" to true)
            mapOf(
                "reportId" to "report", "caseNumber" to "CASE-1", "status" to "appealed",
                "submittedAt" to "2026-10-14T12:00:01.000Z", "replayed" to false,
            )
        },
        { authority }, gate,
        DsaAppealCharacterCounter { it.codePointCount(0, it.length) },
        { now }, { "op-one" },
    )

    private fun decidedRow(): RawDocument {
        val fields = FeedbackContract.creation(
            "report", FeedbackSession("reporter", 7, true, false, "Reporter"),
            FeedbackDraft(FeedbackType.REPORT, "Synthetic report"), now.minusSeconds(60),
        )
        return RawDocument("report", fields + mapOf(
            "status" to "closed", "updatedAt" to now,
            "dsaCase" to mapOf(
                "caseNumber" to "CASE-1", "status" to "decided", "category" to "other",
                "exactLocation" to "Location", "illegalExplanation" to "Explanation",
                "legalBasis" to null, "evidence" to null,
                "goodFaithConfirmed" to true, "acknowledgementAt" to now.minusSeconds(60),
                "preferredLanguage" to "de",
                "decision" to mapOf(
                    "outcome" to "noAction", "factsAndCircumstances" to "Facts",
                    "legalBasis" to "Legal basis", "termsBasis" to null,
                    "territorialScope" to "AT", "duration" to "Until review",
                    "redressInformation" to "Appeal available", "automationUsed" to false,
                    "humanReviewConfirmed" to true, "actionVerifiedAt" to now,
                    "decidedAt" to now, "decidedByUserId" to "owner",
                    "appealDeadline" to now.plusSeconds(3600),
                ),
            ),
        ))
    }

    private suspend fun shown() = read.read(actor, "report")

    @Test fun freshSubmissionUsesRevisionAndConfirmsOwnProjection() = runBlocking {
        val result = mutation.submit(shown(), "A reason that is long enough")
        assertEquals("CASE-1", result.caseNumber)
        assertEquals(false, result.replayed)
        assertEquals(1, calls)
        assertEquals("op-one", payload?.get("operationId"))
        assertEquals("${now.epochSecond}:0", payload?.get("expectedRevision"))
    }

    @Test fun changedReviewCannotDispatch() = runBlocking {
        val review = shown()
        row = RawDocument("report", row.fields + ("updatedAt" to now.plusMillis(1)))
        try {
            mutation.submit(review, "A reason that is long enough")
            fail("stale review must stop before callable")
        } catch (error: DsaAppealReviewException) {
            assertEquals(DsaAppealReviewFailure.STALE, error.failure)
        }
        assertEquals(0, calls)
    }

    @Test fun accountSwitchCannotDispatch() = runBlocking {
        val review = shown()
        authority = actor.copy(uid = "other")
        try {
            mutation.submit(review, "A reason that is long enough")
            fail("new account must not submit old appeal")
        } catch (error: DsaAppealReviewException) {
            assertEquals(DsaAppealReviewFailure.ACCESS, error.failure)
        }
        assertEquals(0, calls)
    }

    @Test fun incorrectServerProjectionIsNotSuccess() = runBlocking {
        receiptValid = false
        try {
            mutation.submit(shown(), "A reason that is long enough")
            fail("readback mismatch must not be presented as confirmed")
        } catch (error: DsaAppealReviewException) {
            assertEquals(DsaAppealReviewFailure.UNCONFIRMED, error.failure)
        }
        assertEquals(1, calls)
    }

    @Test fun readbackFailureAfterDispatchIsUnconfirmed() = runBlocking {
        val review = shown()
        projectionOfflineAfterSend = true
        try {
            mutation.submit(review, "A reason that is long enough")
            fail("a committed mutation without a readback is not confirmed")
        } catch (error: DsaAppealReviewException) {
            assertEquals(DsaAppealReviewFailure.UNCONFIRMED, error.failure)
        }
        assertEquals(1, calls)
    }

    @Test fun malformedCallableResponseAfterDispatchIsUnconfirmed() = runBlocking {
        malformedResponse = true
        try {
            mutation.submit(shown(), "A reason that is long enough")
            fail("malformed response is not a receipt")
        } catch (error: DsaAppealReviewException) {
            assertEquals(DsaAppealReviewFailure.UNCONFIRMED, error.failure)
        }
        assertEquals(1, calls)
    }
}
