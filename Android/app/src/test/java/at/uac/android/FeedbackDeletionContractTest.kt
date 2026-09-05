package at.uac.android

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.feedback.FeedbackAudience
import at.uac.android.feature.feedback.FeedbackStatus
import at.uac.android.feature.feedbackdeletion.*
import at.uac.android.feature.moderation.ModerationSession
import java.math.BigDecimal
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class FeedbackDeletionContractTest {
    private val owner = ModerationSession("owner-a", 7, "owner", true)
    private val id = "feedback-a"
    private val now = Instant.parse("2026-09-03T16:00:00.123456789Z")
    private val fields: Map<String, Any?> =
        mapOf(
            "id" to id,
            "userId" to "author-a",
            "userDisplayName" to "Private author",
            "type" to "question",
            "message" to "Private original message",
            "status" to "open",
            "createdAt" to now,
            "subject" to "  Private original subject  ",
        )

    private fun target(extra: Map<String, Any?> = emptyMap()) =
        FeedbackDeletionContract.target(RawDocument(id, fields + extra))

    private fun denied(expected: FeedbackDeletionFailure, block: () -> Unit) {
        val error = runCatching(block).exceptionOrNull()
        assertTrue("Expected typed rejection", error is FeedbackDeletionException)
        assertEquals(expected, (error as FeedbackDeletionException).failure)
    }

    @Test
    fun onlyReadyOwnerCanEnterDeletion() {
        for (role in listOf("owner", "admin", "user", "topAdmin", "moderator", "OWNER", "")) {
            for (ready in listOf(false, true)) {
                val actor = owner.copy(role = role, ready = ready)
                if (role == "owner" && ready) FeedbackDeletionContract.requireSession(actor)
                else
                    denied(FeedbackDeletionFailure.ACCESS) {
                        FeedbackDeletionContract.requireSession(actor)
                    }
            }
        }
    }

    @Test
    fun ownAudienceCannotBorrowOwnerManagementAuthority() {
        FeedbackDeletionContract.requireTarget(owner, FeedbackAudience.MANAGEMENT, target())
        denied(FeedbackDeletionFailure.ACCESS) {
            FeedbackDeletionContract.requireTarget(owner, FeedbackAudience.OWN, target())
        }
    }

    @Test
    fun invalidActorPathOrRevisionNeverBecomesAuthority() {
        for (uid in
            listOf("", ".", "..", "a/b", "__name__", " owner", "a".repeat(129), "\uD800")) denied(
            FeedbackDeletionFailure.ACCESS
        ) {
            FeedbackDeletionContract.requireSession(owner.copy(uid = uid))
        }
        denied(FeedbackDeletionFailure.ACCESS) {
            FeedbackDeletionContract.requireSession(owner.copy(revision = -1))
        }
    }

    @Test
    fun ownerMayDeleteOwnFeedbackFromManagementWithoutRoleTargetVeto() {
        val own = target(mapOf("userId" to owner.uid))
        FeedbackDeletionContract.requireTarget(owner, FeedbackAudience.MANAGEMENT, own)
        assertEquals(owner.uid, own.authorId)
    }

    @Test
    fun deletionDoesNotInheritReplyOrCloseStatusRules() {
        for (status in
            listOf("open", "answered", "reviewed", "archived", "closed", "future-status")) {
            val value = target(mapOf("status" to status))
            FeedbackDeletionContract.requireTarget(owner, FeedbackAudience.MANAGEMENT, value)
            if (status == "future-status") assertEquals(FeedbackStatus.UNKNOWN, value.status)
        }
    }

    @Test
    fun dsaLinkIsAReviewLabelNotALegalDecisionOrInventedDeletionVeto() {
        val value = target(mapOf("dsaCase" to mapOf("caseNumber" to "DSA-SYNTHETIC")))
        FeedbackDeletionContract.requireTarget(owner, FeedbackAudience.MANAGEMENT, value)
        assertTrue(value.hasDsaCase)
        assertEquals("DSA-SYNTHETIC", value.caseNumber)
        assertEquals(setOf("feedbackId"), FeedbackDeletionContract.payload(value.feedbackId).keys)
    }

    @Test
    fun exactServerUtf16LengthIs200NotCodePointCountOrBrowseLimit() {
        assertTrue(FeedbackDeletionContract.id("a".repeat(200)))
        assertFalse(FeedbackDeletionContract.id("a".repeat(201)))
        assertTrue(FeedbackDeletionContract.id("🙂".repeat(100)))
        assertFalse(FeedbackDeletionContract.id("🙂".repeat(101)))
    }

    @Test
    fun everyServerTrimAliasIsRejectedRatherThanRedirectingSelectedPath() {
        val spaces =
            " \t\n\r\u000B\u000C\u00A0\u1680\u2028\u2029\u202F\u205F\u3000\uFEFF" +
                ('\u2000'..'\u200A').joinToString("")
        for (space in spaces) for (value in listOf("$space$id", "$id$space")) {
            assertFalse(FeedbackDeletionContract.id(value))
            denied(FeedbackDeletionFailure.INVALID) { FeedbackDeletionContract.payload(value) }
        }
    }

    @Test
    fun emptyReservedNestedAndControlPathsCannotBeSubmitted() {
        for (value in listOf("", ".", "..", "/", "a/b", "__id__", "a\u0000b", "a\u007Fb", "a\nb")) {
            assertFalse(FeedbackDeletionContract.id(value))
            denied(FeedbackDeletionFailure.INVALID) { FeedbackDeletionContract.payload(value) }
        }
    }

    @Test
    fun unicodeIsPreservedAndMalformedSurrogatesRejected() {
        for (value in listOf("звернення-ї", "Rückfrage-ß", "意見", "case🙂-é", "e\u0301", "a b")) {
            assertTrue(FeedbackDeletionContract.id(value))
            assertEquals(value, FeedbackDeletionContract.payload(value)["feedbackId"])
        }
        for (value in
            listOf("\uD800", "\uDC00", "a\uD800b", "\uD800\uD800", "\uDC00\uD800")) assertFalse(
            FeedbackDeletionContract.id(value)
        )
    }

    @Test
    fun duplicatedPayloadIdCannotRedirectCanonicalDocumentPath() {
        denied(FeedbackDeletionFailure.INVALID) { target(mapOf("id" to "different")) }
        denied(FeedbackDeletionFailure.INVALID) {
            FeedbackDeletionContract.target(RawDocument("too/long", fields))
        }
    }

    @Test
    fun legacyRecordWithoutDuplicatedIdStillUsesExactDocumentPath() {
        val value = FeedbackDeletionContract.target(RawDocument(id, fields - "id"))
        assertEquals(id, value.feedbackId)
        assertEquals(mapOf("feedbackId" to id), FeedbackDeletionContract.payload(value.feedbackId))
    }

    @Test
    fun malformedOrIncompleteReviewCannotBecomeDeletionTarget() {
        for (key in
            listOf("userId", "userDisplayName", "type", "message", "status", "createdAt")) denied(
            FeedbackDeletionFailure.INVALID
        ) {
            FeedbackDeletionContract.target(RawDocument(id, fields - key))
        }
        denied(FeedbackDeletionFailure.INVALID) { target(mapOf("status" to 1)) }
        denied(FeedbackDeletionFailure.INVALID) { target(mapOf("createdAt" to now.toString())) }
    }

    @Test
    fun malformedAuthorIdentityIsNotTrustedFromRenderedRow() {
        for (author in
            listOf("", "a/b", "__reserved__", " author", "a".repeat(129), "\uD800")) denied(
            FeedbackDeletionFailure.INVALID
        ) {
            target(mapOf("userId" to author))
        }
        denied(FeedbackDeletionFailure.INVALID) {
            FeedbackDeletionContract.requireTarget(
                owner,
                FeedbackAudience.MANAGEMENT,
                target().copy(authorId = "a/b"),
            )
        }
    }

    @Test
    fun rawPrivateReviewLabelsAndTimestampAreNotSilentlyNormalized() {
        val value = target()
        assertEquals("Private author", value.authorName)
        assertEquals("  Private original subject  ", value.subject)
        assertEquals(now, value.createdAt)
        assertEquals(123456789, value.createdAt.nano)
        assertNull(target(mapOf("subject" to null)).subject)
    }

    @Test
    fun payloadHasOnlyCanonicalFeedbackIdAndNormalCallableEnvelope() {
        val path = "quoted-\"-backslash-\\"
        val payload = FeedbackDeletionContract.payload(path)
        assertEquals(mapOf("feedbackId" to path), payload)
        assertEquals(mapOf("data" to payload), LocalCallableProtocol.request(payload))
        assertEquals(300_000L, FeedbackDeletionContract.MAXIMUM_TIMEOUT_MILLIS)
    }

    @Test
    fun onlyExactSingleDeletionCountInSupportedSdkNumbersIsAccepted() {
        for (number in listOf<Any>(1.toByte(), 1.toShort(), 1, 1L, 1F, 1.0)) assertEquals(
            1,
            FeedbackDeletionContract.response(mapOf("deletedCount" to number)).deletedCount,
        )
    }

    @Test
    fun zeroPartialCountsStringsBooleansFractionsAndNonFiniteResultsRemainUnknown() {
        for (count in
            listOf(
                null,
                "1",
                true,
                0,
                -1,
                2,
                10_000,
                1.5,
                Long.MAX_VALUE,
                Double.NaN,
                Double.POSITIVE_INFINITY,
                Double.NEGATIVE_INFINITY,
                BigDecimal.ONE,
            )) denied(FeedbackDeletionFailure.UNCONFIRMED) {
            FeedbackDeletionContract.response(mapOf("deletedCount" to count))
        }
    }

    @Test
    fun errorAbsenceExtraFieldsAndFabricatedEchoAreNotSuccessfulResponses() {
        for (value in
            listOf(
                null,
                true,
                1,
                "deleted",
                emptyMap<String, Any>(),
                emptyList<Any>(),
                mapOf("error" to "not-found"),
                mapOf("deletedCount" to 1, "feedbackId" to id),
                mapOf("deletedCount" to 1, "operationId" to "invented"),
            )) denied(FeedbackDeletionFailure.UNCONFIRMED) {
            FeedbackDeletionContract.response(value)
        }
    }

    @Test
    fun diagnosticStringsDoNotExposeRecordIdentityOrPrivateLabels() {
        val text =
            target().toString() +
                FeedbackDeletionContract.response(mapOf("deletedCount" to 1)) +
                FeedbackDeletionException(FeedbackDeletionFailure.INVALID)
        for (secret in
            listOf(
                id,
                "author-a",
                "Private author",
                "Private original subject",
                "Private original message",
            )) assertFalse(text.contains(secret))
    }

    @Test
    fun allDeletionEndpointsStayClosedUntilDurableSdkIntegrationIsVerified() {
        assertTrue(LocalCallableProtocol.endpoint("assignAppAdmin").endsWith("/assignAppAdmin"))
        for (name in
            listOf(
                FeedbackDeletionContract.CALLABLE,
                "clearFeedbackInbox",
                "deleteMyFeedback",
                "clearMyFeedback",
            )) assertTrue(runCatching { LocalCallableProtocol.endpoint(name) }.isFailure)
    }
}
