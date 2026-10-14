package at.uac.android

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.dsaowner.*
import at.uac.android.feature.dsaappeal.DsaAppealCharacterCounter
import at.uac.android.feature.feedback.*
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class DsaOwnerDecisionTest {
    private val now = Instant.parse("2026-10-14T12:00:00Z")
    private val actor = ModerationSession("owner", 3, "owner", true)
    private var authority: ModerationSession? = actor
    private var row = row("submitted")
    private var calls = 0
    private val source = object : DsaOwnerSource {
        override suspend fun read(session: ModerationSession, reportId: String): RawDocument? = row
        override suspend fun call(session: ModerationSession, action: DsaOwnerAction,
            payload: Map<String, Any?>): Any? {
            calls++
            val next = now.plusSeconds(1)
            val oldCase = row.fields.getValue("dsaCase") as Map<*, *>
            val status = if (action == DsaOwnerAction.CASE) "decided"
                else if (payload["outcome"] == "changed") "submitted" else "appealDecided"
            val amended = if (action == DsaOwnerAction.CASE) oldCase + mapOf(
                "status" to status,
                "decision" to mapOf(
                    "outcome" to payload["outcome"],
                    "factsAndCircumstances" to payload["factsAndCircumstances"],
                    "legalBasis" to payload["legalBasis"], "termsBasis" to payload["termsBasis"],
                    "decidedAt" to next,
                ),
            ) else oldCase + mapOf("status" to status, "appeal" to mapOf(
                "status" to "decided", "outcome" to payload["outcome"],
                "reason" to payload["reason"], "decidedAt" to next,
            ))
            row = RawDocument(row.id, row.fields + mapOf(
                "updatedAt" to next, "dsaCase" to amended,
            ))
            return mapOf(
                "reportId" to "report", "caseNumber" to "DSA-1", "status" to status,
                "decidedAt" to "2026-10-14T12:00:01.000Z",
            ) + if (action == DsaOwnerAction.CASE)
                mapOf("appealDeadline" to "2027-04-15T12:00:01.000Z") else emptyMap()
        }
    }
    private val repository = DsaOwnerDecisionRepository(source, { authority },
        { _, action -> action() }, { "owner-op" },
        DsaAppealCharacterCounter { it.codePointCount(0, it.length) })

    private fun row(status: String): RawDocument {
        val base = FeedbackContract.creation(
            "report", FeedbackSession("reporter", 1, true, false, "Reporter"),
            FeedbackDraft(FeedbackType.REPORT, "Synthetic report"), now.minusSeconds(60))
        return RawDocument("report", base + mapOf(
            "status" to "open", "updatedAt" to now,
            "dsaCase" to (mapOf<String, Any?>(
                "caseNumber" to "DSA-1", "status" to status, "category" to "other",
                "exactLocation" to "Synthetic location", "illegalExplanation" to "Explanation",
                "legalBasis" to null, "evidence" to null, "goodFaithConfirmed" to true,
                "acknowledgementAt" to now.minusSeconds(60), "preferredLanguage" to "de",
            ) + if (status == "appealed") mapOf("appeal" to mapOf(
                "status" to "pending", "reason" to "A reason that is long enough",
                "submittedAt" to now,
            )) else emptyMap()),
        ))
    }

    @Test fun caseDecisionUsesExactRevisionAndConfirmsProjection() = runBlocking {
        val review = repository.review(actor, "report")
        assertEquals(DsaOwnerAction.CASE, review.action)
        val receipt = repository.decide(review, DsaOwnerCaseDraft(
            "noAction", "Detailed facts long enough for a decision", "Legal basis", "",
            "AT", "Until review", "Internal appeal available", true))
        assertEquals("decided", receipt.status)
        assertEquals(1, calls)
    }

    @Test fun appealDecisionUsesPendingAppeal() = runBlocking {
        row = row("appealed")
        val review = repository.review(actor, "report")
        assertEquals(DsaOwnerAction.APPEAL, review.action)
        val receipt = repository.decide(review, DsaOwnerAppealDraft(
            "upheld", "The prior decision remains justified", true))
        assertEquals("appealDecided", receipt.status)
        assertEquals(1, calls)
    }

    @Test fun changedAppealReturnsCaseToSubmittedState() = runBlocking {
        row = row("appealed")
        val review = repository.review(actor, "report")
        val receipt = repository.decide(review, DsaOwnerAppealDraft(
            "changed", "The reviewed decision must be reconsidered", true))
        assertEquals("submitted", receipt.status)
        assertEquals(1, calls)
    }

    @Test fun changedCaseStopsBeforeCallable() = runBlocking {
        val review = repository.review(actor, "report")
        row = RawDocument("report", row.fields + ("updatedAt" to now.plusMillis(1)))
        try {
            repository.decide(review, DsaOwnerCaseDraft("noAction", "Detailed facts long enough",
                "Legal", "", "AT", "Until review", "Appeal available", true))
            fail("stale case must not dispatch")
        } catch (error: DsaOwnerException) {
            assertEquals(DsaOwnerFailure.STALE, error.failure)
        }
        assertEquals(0, calls)
    }

    @Test fun administratorCannotReviewOwnerCase() = runBlocking {
        authority = actor.copy(role = "admin")
        try {
            repository.review(actor, "report")
            fail("owner role required")
        } catch (error: DsaOwnerException) {
            assertEquals(DsaOwnerFailure.ACCESS, error.failure)
        }
        assertEquals(0, calls)
    }
}
