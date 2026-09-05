package at.uac.android

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.feedback.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class FeedbackCaseContextTest {
    private val time = Instant.ofEpochSecond(123, 987_654_321)
    private val actor = FeedbackSession("reporter", 7, true, false, "Synthetic")

    private fun fields(): Map<String, Any?> =
        mapOf(
            "caseNumber" to "SYNTHETIC-CASE",
            "status" to "submitted",
            "category" to "other",
            "exactLocation" to "https://invalid.example/private-location",
            "illegalExplanation" to "PRIVATE EXPLANATION",
            "legalBasis" to "PRIVATE BASIS",
            "evidence" to "PRIVATE EVIDENCE",
            "goodFaithConfirmed" to true,
            "acknowledgementAt" to time,
            "preferredLanguage" to "uk",
        )

    private fun decode(extra: Map<String, Any?> = emptyMap()) =
        FeedbackCaseContextContract.decode(fields() + extra)

    private fun item(extra: Map<String, Any?> = mapOf("dsaCase" to fields())) =
        FeedbackContract.item(
            RawDocument(
                "report",
                FeedbackContract.creation("report", actor, FeedbackDraft(message = "Body"), time) +
                    extra,
            )
        )

    private fun state() =
        FeedbackState(
            session = actor,
            selectedId = "report",
            conversation = FeedbackConversation(item(), emptyList()),
        )

    @Test
    fun completeProjectionPreservesTextAndTimestampNanoseconds() {
        val context = requireNotNull(decode())
        assertEquals("PRIVATE EXPLANATION", context.illegalExplanation)
        assertEquals("https://invalid.example/private-location", context.exactLocation)
        assertEquals(time, context.acknowledgementAt)
        assertEquals(987_654_321, context.acknowledgementAt.nano)
        assertTrue(context.goodFaithConfirmed)
        assertEquals(context, item().caseContext)
    }

    @Test
    fun reviewNavigationIsOnlyAnOwnClosedDecidedHint() {
        fun ready(
            status: String = "closed",
            case: Map<String, Any?> = fields() + ("status" to "decided"),
        ) =
            state()
                .copy(
                    conversation =
                        FeedbackConversation(
                            item(mapOf("status" to status, "dsaCase" to case)),
                            emptyList(),
                        )
                )
        assertTrue(ready().canReviewOwnDecision())
        assertTrue(ready("archived").canReviewOwnDecision())
        for (status in listOf("open", "answered", "unknown")) assertFalse(
            ready(status).canReviewOwnDecision()
        )
        for (invalid in
            listOf(
                ready().copy(audience = FeedbackAudience.MANAGEMENT),
                ready().copy(loading = true),
                ready().copy(error = FeedbackFailure.DENIED),
                ready().copy(selectedId = "another"),
                ready().copy(session = actor.copy(uid = "another", canManage = true)),
                ready().copy(session = actor.copy(ready = false)),
            )) assertFalse(invalid.canReviewOwnDecision())
        assertFalse(ready(case = fields()).canReviewOwnDecision())
        assertFalse(
            ready(
                    case =
                        fields() +
                            mapOf(
                                "status" to "decided",
                                "appeal" to mapOf("status" to "pending", "reason" to "Synthetic"),
                            )
                )
                .canReviewOwnDecision()
        )
    }

    @Test
    fun reviewRouteValidatesCanonicalTargetAndIsScrubbedOnLogout() {
        val navigation =
            at.uac.android.feature.browse.BrowseNavigation.restore("profile")
                .navigate("profile/feedback/report")
                .navigate("profile/dsa-review/report")
        assertEquals("profile/feedback/report", navigation.back().route)
        assertEquals("profile", navigation.scrubPrivateDestinations().route)
        for (id in listOf("", "..", "a/b", " report", "x".repeat(201))) assertTrue(
            runCatching { navigation.navigate("profile/dsa-review/$id") }.isFailure
        )
    }

    @Test
    fun absentSummaryKeepsOrdinaryConversationUnchanged() {
        val item = item(emptyMap())
        assertFalse(item.hasDsaCase)
        assertNull(item.caseContext)
        assertEquals("Body", item.message)
    }

    @Test
    fun legacyAndMalformedSummaryDoNotDropConversationOrInventDetails() {
        for (raw in
            listOf(
                "bad",
                mapOf("caseNumber" to "LEGACY"),
                fields() + ("goodFaithConfirmed" to "true"),
            )) {
            val item = item(mapOf("dsaCase" to raw))
            assertTrue(item.hasDsaCase)
            assertNull(item.caseContext)
            assertEquals("Body", item.message)
        }
    }

    @Test
    fun everyRequiredFieldMustHaveItsActualType() {
        for (key in fields().keys - setOf("legalBasis", "evidence")) {
            assertNull("Missing $key", FeedbackCaseContextContract.decode(fields() - key))
            assertNull("Invalid $key", decode(mapOf(key to listOf("wrong"))))
        }
    }

    @Test
    fun optionalTextAllowsNullAndEmptyButNotCoercion() {
        assertNull(decode(mapOf("legalBasis" to null, "evidence" to null))!!.legalBasis)
        assertEquals("", decode(mapOf("evidence" to ""))!!.evidence)
        assertNull(decode(mapOf("evidence" to 12)))
    }

    @Test
    fun falseGoodFaithAndUnknownStatusRemainHonest() {
        val context =
            decode(
                mapOf("goodFaithConfirmed" to false, "status" to "future", "category" to "new")
            )!!
        assertFalse(context.goodFaithConfirmed)
        assertEquals("future", context.status)
        assertEquals("new", context.category)
    }

    @Test
    fun appealProjectionKeepsReasonWithoutInventingOutcome() {
        val pending =
            decode(mapOf("appeal" to mapOf("status" to "pending", "reason" to "PRIVATE APPEAL")))!!
                .appeal!!
        assertEquals("PRIVATE APPEAL", pending.reason)
        assertNull(pending.outcome)
        val decided =
            decode(
                    mapOf(
                        "appeal" to
                            mapOf(
                                "status" to "decided",
                                "reason" to "REVIEW REASON",
                                "outcome" to "future",
                            )
                    )
                )!!
                .appeal!!
        assertEquals("future", decided.outcome)
    }

    @Test
    fun malformedAppealRejectsWholeAdditionalContextWithoutHidingMessages() {
        for (appeal in
            listOf(
                "bad",
                mapOf("status" to "pending"),
                mapOf("status" to "pending", "reason" to true),
            )) {
            assertNull(decode(mapOf("appeal" to appeal)))
        }
        assertNotNull(decode(mapOf("appeal" to null)))
    }

    @Test
    fun extraPrivateFieldsAndDecisionsAreNotRetainedAndDiagnosticsAreRedacted() {
        val map =
            (fields() +
                    mapOf(
                        "reporterEmail" to "PRIVATE CONTACT",
                        "accessToken" to "PRIVATE TOKEN",
                        "decision" to mapOf("secret" to "PRIVATE DECISION"),
                    ))
                .toMutableMap()
        val context = FeedbackCaseContextContract.decode(map)!!
        map["illegalExplanation"] = "REPLACED"
        assertEquals("PRIVATE EXPLANATION", context.illegalExplanation)
        assertEquals(decode(), context)
        assertEquals("FeedbackCaseContext(<redacted>)", context.toString())
        assertEquals(
            "FeedbackCaseAppeal(<redacted>)",
            FeedbackCaseAppeal("pending", "PRIVATE", null).toString(),
        )
        assertFalse(item().toString().contains("PRIVATE EXPLANATION"))
    }

    @Test
    fun totalBudgetCountsUtf8AcrossAllSelectedFieldsWithoutTruncation() {
        val base = fields().mapValues { (_, value) -> if (value is String) "" else value }
        val exact =
            base + ("illegalExplanation" to "x".repeat(FeedbackCaseContextContract.MAX_TEXT_BYTES))
        assertEquals(65_536, FeedbackCaseContextContract.decode(exact)!!.illegalExplanation.length)
        assertNull(FeedbackCaseContextContract.decode(exact + ("evidence" to "x")))
        assertNull(decode(mapOf("illegalExplanation" to "я".repeat(32_768))))
        assertNull(
            decode(mapOf("appeal" to mapOf("status" to "pending", "reason" to "x".repeat(65_536))))
        )
    }

    @Test
    fun malformedUnicodeIsRejectedButEmojiAndCombiningMarksArePreserved() {
        for (bad in listOf("\uD800", "\uDC00", "a\uD800b")) assertNull(
            decode(mapOf("evidence" to bad))
        )
        val text = "👩‍💻 е́\nhttps://invalid.example/a"
        assertEquals(text, decode(mapOf("evidence" to text))!!.evidence)
    }

    @Test
    fun ownAndManagementAuthoritiesStayDistinct() {
        assertTrue(state().canReadCaseContext())
        assertFalse(state().copy(session = actor.copy(uid = "other")).canReadCaseContext())
        assertFalse(state().copy(audience = FeedbackAudience.MANAGEMENT).canReadCaseContext())
        assertTrue(
            state()
                .copy(
                    audience = FeedbackAudience.MANAGEMENT,
                    session = actor.copy(uid = "support", canManage = true),
                )
                .canReadCaseContext()
        )
        assertFalse(
            state()
                .copy(session = actor.copy(uid = "support", canManage = true))
                .canReadCaseContext()
        )
    }

    @Test
    fun LoadingErrorWrongSelectionAndUnreadyCannotShowOldContext() {
        for (masked in
            listOf(
                state().copy(loading = true),
                state().copy(error = FeedbackFailure.DENIED),
                state().copy(selectedId = "different"),
                state().copy(session = null),
                state().copy(session = actor.copy(ready = false)),
            )) assertFalse(masked.canReadCaseContext())
    }

    @Test
    fun accountRevisionMaskClearsFullProjection() {
        assertNull(state().forSession(actor.copy(revision = 8)).conversation)
        assertFalse(state().forSession(actor.copy(revision = 8)).canReadCaseContext())
        assertFalse(
            state()
                .copy(conversation = FeedbackConversation(item(emptyMap()), emptyList()))
                .canReadCaseContext()
        )
    }
}
