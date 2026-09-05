package at.uac.android

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.dsaappeal.*
import at.uac.android.feature.feedback.*
import java.io.IOException
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DsaAppealReviewTest {
    private val decided = Instant.parse("2026-09-03T12:00:00.123456789Z")
    private val now = decided.plusSeconds(1)
    private val actor = FeedbackSession("reporter", 1, true, false, "Synthetic")
    private val readActor = DsaAppealSession(actor.uid, 1, "synthetic-backend", true)

    private class ReadGate : DsaAppealReadGate {
        var before: suspend () -> Unit = {}
        var after: suspend () -> Unit = {}

        override suspend fun <T> withSession(
            session: DsaAppealSession,
            action: suspend () -> T,
        ): T =
            withContext(NonCancellable) {
                before()
                val result = action()
                after()
                result
            }
    }

    private suspend fun readFailure(expected: DsaAppealReviewFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected ${expected.name}")
        } catch (error: DsaAppealReviewException) {
            assertEquals(expected, error.failure)
            assertEquals(expected.name, error.message)
            assertNull(error.cause)
        }
    }

    private suspend fun cancelled(action: suspend () -> Unit) {
        try {
            action()
            fail("Expected cancelled review")
        } catch (_: CancellationException) {}
    }

    private fun decision(extra: Map<String, Any?> = emptyMap()) =
        mapOf<String, Any?>(
            "outcome" to "noAction",
            "factsAndCircumstances" to "PRIVATE FACTS",
            "legalBasis" to "PRIVATE BASIS",
            "termsBasis" to null,
            "territorialScope" to "AT",
            "duration" to "Synthetic duration",
            "redressInformation" to "PRIVATE REDRESS",
            "automationUsed" to false,
            "humanReviewConfirmed" to true,
            "actionVerifiedAt" to decided,
            "decidedAt" to decided,
            "decidedByUserId" to "synthetic-owner",
            "appealDeadline" to decided.plusSeconds(3_600),
        ) + extra

    private fun context(extra: Map<String, Any?> = emptyMap()) =
        mapOf<String, Any?>(
            "caseNumber" to "SYNTHETIC CASE",
            "status" to "decided",
            "category" to "other",
            "exactLocation" to "PRIVATE LOCATION",
            "illegalExplanation" to "PRIVATE EXPLANATION",
            "legalBasis" to null,
            "evidence" to "PRIVATE EVIDENCE",
            "goodFaithConfirmed" to true,
            "acknowledgementAt" to decided.minusSeconds(60),
            "preferredLanguage" to "de",
            "decision" to decision(),
        ) + extra

    private fun row(extra: Map<String, Any?> = emptyMap()) =
        RawDocument(
            "report",
            FeedbackContract.creation(
                "report",
                actor,
                FeedbackDraft(FeedbackType.REPORT, "Original report"),
                decided.minusSeconds(60),
            ) + mapOf("status" to "closed", "updatedAt" to decided, "dsaCase" to context()) + extra,
        )

    private fun snapshot(row: RawDocument = row(), at: Instant = now) =
        DsaAppealReviewContract.snapshot(row, actor.uid, at)

    private fun caseRow(extra: Map<String, Any?>) = row(mapOf("dsaCase" to context(extra)))

    private fun decisionRow(extra: Map<String, Any?>) =
        caseRow(mapOf("decision" to decision(extra)))

    private fun failure(expected: DsaAppealReviewFailure, action: () -> Unit) {
        try {
            action()
            fail("Expected ${expected.name}")
        } catch (error: DsaAppealReviewException) {
            assertEquals(expected, error.failure)
            assertEquals(expected.name, error.message)
            assertNull(error.cause)
        }
    }

    @Test
    fun exactOwnClosedDecisionProducesPrivateReadOnlySnapshot() {
        val value = snapshot()
        assertEquals("report", value.reportId)
        assertEquals(actor.uid, value.reporterUid)
        assertEquals("PRIVATE EXPLANATION", value.context.illegalExplanation)
        assertEquals("PRIVATE FACTS", value.decision.facts)
        assertEquals("PRIVATE REDRESS", value.decision.redress)
        assertFalse(value.decision.automationUsed)
        assertTrue(value.decision.humanReviewConfirmed)
        assertEquals(decided, value.decision.decidedAt)
        assertEquals(123_456_789, value.decision.decidedAt.nano)
        assertTrue(value.fingerprint.matches(Regex("[a-f0-9]{64}")))
    }

    @Test
    fun anotherReporterAndPublicPortalNeverAcquireOwnReviewAccess() {
        for (uid in listOf("other", "")) failure(DsaAppealReviewFailure.ACCESS) {
            snapshot(row(mapOf("userId" to uid, "dsaCase" to "PRIVATE MALFORMED")))
        }
    }

    @Test
    fun exactTargetAndActorIdentifiersRejectAliases() {
        for (id in listOf(" report", "a/b", "..", "x".repeat(201))) failure(
            DsaAppealReviewFailure.INVALID
        ) {
            snapshot(row().copy(id = id))
        }
        failure(DsaAppealReviewFailure.INVALID) {
            DsaAppealReviewContract.snapshot(row(), "reporter ", now)
        }
        failure(DsaAppealReviewFailure.INVALID) { snapshot(row(mapOf("id" to "different"))) }
    }

    @Test
    fun onlyKnownClosedOrArchivedFeedbackCanBeReviewed() {
        assertNotNull(snapshot(row(mapOf("status" to "archived"))))
        for (status in listOf("open", "answered", "reviewed", "future")) failure(
            DsaAppealReviewFailure.INELIGIBLE
        ) {
            snapshot(row(mapOf("status" to status)))
        }
    }

    @Test
    fun onlyDecidedCaseWithoutAnyExistingAppealCanBePrepared() {
        for (status in
            listOf("submitted", "underReview", "appealed", "appealDecided", "future")) failure(
            DsaAppealReviewFailure.INELIGIBLE
        ) {
            snapshot(caseRow(mapOf("status" to status)))
        }
        for (appeal in
            listOf(
                emptyMap<String, Any?>(),
                mapOf("status" to "pending", "reason" to "X"),
                mapOf("status" to "decided", "reason" to "X"),
            )) failure(DsaAppealReviewFailure.INELIGIBLE) {
            snapshot(caseRow(mapOf("appeal" to appeal)))
        }
        assertNotNull(snapshot(caseRow(mapOf("appeal" to null))))
    }

    @Test
    fun deadlineEqualityAndExpiryAreNotAnOpenReviewWindow() {
        val deadline = decided.plusSeconds(3_600)
        assertNotNull(snapshot(at = deadline.minusNanos(1)))
        failure(DsaAppealReviewFailure.EXPIRED) { snapshot(at = deadline) }
        failure(DsaAppealReviewFailure.EXPIRED) { snapshot(at = deadline.plusNanos(1)) }
        failure(DsaAppealReviewFailure.INELIGIBLE) { snapshot(at = decided.minusNanos(1)) }
    }

    @Test
    fun invalidOrInvertedDatesAreNeverCoerced() {
        for (bad in listOf("tomorrow", decided, decided.minusSeconds(1), Instant.MAX)) failure(
            DsaAppealReviewFailure.INVALID
        ) {
            snapshot(decisionRow(mapOf("appealDeadline" to bad)))
        }
        failure(DsaAppealReviewFailure.INVALID) { snapshot(row(mapOf("updatedAt" to "today"))) }
        failure(DsaAppealReviewFailure.INVALID) {
            snapshot(caseRow(mapOf("acknowledgementAt" to Instant.MIN)))
        }
    }

    @Test
    fun missingDecisionAndUnknownSchemaRequireExplicitCompatibilityReview() {
        for (extra in
            listOf(mapOf("decision" to null), mapOf("newEligibilityFlag" to true))) failure(
            DsaAppealReviewFailure.INVALID
        ) {
            snapshot(caseRow(extra))
        }
        failure(DsaAppealReviewFailure.INVALID) {
            snapshot(decisionRow(mapOf("secret" to "PRIVATE")))
        }
    }

    @Test
    fun requiredDecisionTypesRemainStrictIncludingServerMetadata() {
        for (key in decision().keys - setOf("legalBasis", "termsBasis")) failure(
            DsaAppealReviewFailure.INVALID
        ) {
            snapshot(caseRow(mapOf("decision" to (decision() - key))))
        }
        for (key in listOf("automationUsed", "humanReviewConfirmed")) failure(
            DsaAppealReviewFailure.INVALID
        ) {
            snapshot(decisionRow(mapOf(key to "true")))
        }
    }

    @Test
    fun supportedOutcomesStayExactAndUnknownDoesNotBecomeNoAction() {
        for (outcome in listOf("noAction", "restricted", "removed")) assertEquals(
            outcome,
            snapshot(decisionRow(mapOf("outcome" to outcome))).decision.outcome,
        )
        failure(DsaAppealReviewFailure.INELIGIBLE) {
            snapshot(decisionRow(mapOf("outcome" to "future")))
        }
    }

    @Test
    fun legalBasisOrTermsMustExistWithoutSilentTruncation() {
        assertNull(
            snapshot(decisionRow(mapOf("legalBasis" to null, "termsBasis" to "Terms")))
                .decision
                .legalBasis
        )
        failure(DsaAppealReviewFailure.INVALID) {
            snapshot(decisionRow(mapOf("legalBasis" to null)))
        }
        failure(DsaAppealReviewFailure.INVALID) {
            snapshot(decisionRow(mapOf("factsAndCircumstances" to "x".repeat(5_001))))
        }
    }

    @Test
    fun wellFormedUnicodeAndHonestAutomationFlagsArePreserved() {
        val value =
            snapshot(
                decisionRow(
                    mapOf(
                        "factsAndCircumstances" to "👩‍💻 е́\nText",
                        "automationUsed" to true,
                        "humanReviewConfirmed" to false,
                    )
                )
            )
        assertEquals("👩‍💻 е́\nText", value.decision.facts)
        assertTrue(value.decision.automationUsed)
        assertFalse(value.decision.humanReviewConfirmed)
        failure(DsaAppealReviewFailure.INVALID) {
            snapshot(decisionRow(mapOf("factsAndCircumstances" to "bad\uD800")))
        }
    }

    @Test
    fun fingerprintIsOrderIndependentButTracksExactReviewFieldsAndNanos() {
        val original = snapshot()
        val reordered =
            context(mapOf("decision" to decision().entries.reversed().associate { it.toPair() }))
                .entries
                .reversed()
                .associate { it.toPair() }
        assertEquals(original.fingerprint, snapshot(row(mapOf("dsaCase" to reordered))).fingerprint)
        for (changed in
            listOf(
                row(mapOf("updatedAt" to decided.plusNanos(1))),
                row(mapOf("status" to "archived")),
                caseRow(mapOf("illegalExplanation" to "Changed")),
                decisionRow(mapOf("decidedByUserId" to "another-owner")),
            )) assertNotEquals(original.fingerprint, snapshot(changed).fingerprint)
    }

    @Test
    fun missingAndExplicitNullOptionalMetadataAreDistinctVersions() {
        val missing = snapshot(caseRow(mapOf("decision" to (decision() - "termsBasis"))))
        assertEquals(snapshot().decision, missing.decision)
        assertNotEquals(snapshot().fingerprint, missing.fingerprint)
    }

    @Test
    fun everyDisplayedReporterContextFieldIndependentlyChangesReviewedVersion() {
        val original = snapshot().fingerprint
        val changes =
            mapOf<String, Any?>(
                "caseNumber" to "ANOTHER SYNTHETIC CASE",
                "category" to "future-category",
                "exactLocation" to "Changed location",
                "illegalExplanation" to "Changed explanation",
                "legalBasis" to "Changed report basis",
                "evidence" to "Changed evidence",
                "goodFaithConfirmed" to false,
                "acknowledgementAt" to decided.minusSeconds(60).plusNanos(1),
                "preferredLanguage" to "uk",
            )
        for ((key, value) in changes) assertNotEquals(
            key,
            original,
            snapshot(caseRow(mapOf(key to value))).fingerprint,
        )
    }

    @Test
    fun everyDecisionFieldIncludingFalseFlagsAndNanosecondsChangesReviewedVersion() {
        val original = snapshot().fingerprint
        val changes =
            mapOf<String, Any?>(
                "outcome" to "restricted",
                "factsAndCircumstances" to "Changed facts",
                "legalBasis" to "Changed legal basis",
                "termsBasis" to "Changed terms",
                "territorialScope" to "EU",
                "duration" to "Changed duration",
                "redressInformation" to "Changed redress",
                "automationUsed" to true,
                "humanReviewConfirmed" to false,
                "actionVerifiedAt" to decided.plusNanos(1),
                "decidedAt" to decided.plusNanos(1),
                "decidedByUserId" to "another-synthetic-owner",
                "appealDeadline" to decided.plusSeconds(3600).plusNanos(1),
            )
        for ((key, value) in changes) assertNotEquals(
            key,
            original,
            snapshot(decisionRow(mapOf(key to value))).fingerprint,
        )
    }

    @Test
    fun unicodeNormalizationAndFieldBoundariesAreNotSilentlyCollapsedInFingerprint() {
        val composed = snapshot(decisionRow(mapOf("factsAndCircumstances" to "Caf\u00e9")))
        val decomposed = snapshot(decisionRow(mapOf("factsAndCircumstances" to "Cafe\u0301")))
        assertNotEquals(composed.fingerprint, decomposed.fingerprint)
        val first = snapshot(caseRow(mapOf("legalBasis" to "ab", "evidence" to "c")))
        val second = snapshot(caseRow(mapOf("legalBasis" to "a", "evidence" to "bc")))
        assertNotEquals(first.fingerprint, second.fingerprint)
    }

    @Test
    fun fingerprintExplicitlyIsNotAFullParentOrTransportReceipt() {
        val original = snapshot()
        val unrelated =
            snapshot(
                row(
                    mapOf(
                        "subject" to "Another parent subject",
                        "lastMessageText" to "Other summary",
                        "unreadForUser" to true,
                    )
                )
            )
        assertEquals(original.fingerprint, unrelated.fingerprint)
        // No operation identifier or server acknowledgement is created by reading this digest.
        assertEquals(original, unrelated)
    }

    @Test
    fun sourceBackingMapChangesCannotModifyReturnedSnapshot() {
        val decision = decision().toMutableMap()
        val context = context(mapOf("decision" to decision)).toMutableMap()
        val value = snapshot(row(mapOf("dsaCase" to context)))
        decision["factsAndCircumstances"] = "CHANGED"
        context["illegalExplanation"] = "CHANGED"
        assertEquals("PRIVATE FACTS", value.decision.facts)
        assertEquals("PRIVATE EXPLANATION", value.context.illegalExplanation)
        assertNotEquals(value.fingerprint, snapshot(row(mapOf("dsaCase" to context))).fingerprint)
    }

    @Test
    fun oversizedDeepAndUnsupportedMetadataFailWithoutRetainingIt() {
        for (value in
            listOf(
                "x".repeat(131_073),
                listOf("unexpected"),
                mapOf("nested" to mapOf("nested" to mapOf("nested" to mapOf("nested" to "x")))),
            )) failure(DsaAppealReviewFailure.INVALID) {
            snapshot(caseRow(mapOf("evidence" to value)))
        }
    }

    @Test
    fun diagnosticsNeverPrintReporterDecisionOrAccountDetails() {
        val value = snapshot()
        val session = DsaAppealSession(actor.uid, 7, "synthetic-backend", true)
        assertEquals("DsaAppealReviewSnapshot(<redacted>)", value.toString())
        assertEquals("DsaAppealDecision(<redacted>)", value.decision.toString())
        assertEquals("DsaAppealSession(<redacted>)", session.toString())
        assertEquals("DsaAppealReview(<redacted>)", DsaAppealReview(session, value).toString())
    }

    @Test
    fun repositoryBindsFreshReviewToExactScopeWithoutAnyMutation() = runTest {
        var reads = 0
        val repo =
            DsaAppealReadRepository(
                DsaAppealReadSource { session, id ->
                    assertEquals(readActor, session)
                    assertEquals("report", id)
                    reads++
                    row()
                },
                { readActor },
                ReadGate(),
                { now },
            )
        val review = repo.read(readActor, "report")
        assertEquals(readActor, review.session)
        assertEquals(snapshot(), review.snapshot)
        assertEquals(1, reads)
    }

    @Test
    fun repositoryRejectsUnreadyOrInvalidScopesBeforeSourceRead() = runTest {
        for (actor in
            listOf(
                readActor.copy(ready = false),
                readActor.copy(uid = "a/b"),
                readActor.copy(backend = ""),
                readActor.copy(backend = "x".repeat(1_025)),
            )) {
            var reads = 0
            val repo =
                DsaAppealReadRepository(
                    DsaAppealReadSource { _, _ ->
                        reads++
                        row()
                    },
                    { actor },
                    ReadGate(),
                    { now },
                )
            readFailure(DsaAppealReviewFailure.ACCESS) { repo.read(actor, "report") }
            assertEquals(0, reads)
        }
    }

    @Test
    fun reviewedFingerprintRequiresAnotherFreshReadAndRejectsChangedDecision() = runTest {
        var stored = row()
        var reads = 0
        val repo =
            DsaAppealReadRepository(
                DsaAppealReadSource { _, _ ->
                    reads++
                    stored
                },
                { readActor },
                ReadGate(),
                { now },
            )
        val first = repo.read(readActor, "report")
        stored = decisionRow(mapOf("factsAndCircumstances" to "New decision text"))
        readFailure(DsaAppealReviewFailure.STALE) {
            repo.read(readActor, "report", first.snapshot.fingerprint)
        }
        assertEquals(2, reads)
        readFailure(DsaAppealReviewFailure.INVALID) {
            repo.read(readActor, "report", "not-a-digest")
        }
        assertEquals(2, reads)
    }

    @Test
    fun missingWrongParentAndForeignReporterAreNotAReadableReview() = runTest {
        for ((raw, expected) in
            listOf(
                null to DsaAppealReviewFailure.MISSING,
                row().copy(id = "another") to DsaAppealReviewFailure.STALE,
                row(mapOf("userId" to "another")) to DsaAppealReviewFailure.ACCESS,
            )) {
            val repo =
                DsaAppealReadRepository(
                    DsaAppealReadSource { _, _ -> raw },
                    { readActor },
                    ReadGate(),
                    { now },
                )
            readFailure(expected) { repo.read(readActor, "report") }
        }
    }

    @Test
    fun privateSourceFailuresAreRedactedWithoutInventingAbsenceOrRetry() = runTest {
        for ((error, expected) in
            listOf(
                IOException("PRIVATE SOURCE TEXT") to DsaAppealReviewFailure.OFFLINE,
                IllegalStateException("PRIVATE CASE") to DsaAppealReviewFailure.UNKNOWN,
                DsaAppealReviewException(DsaAppealReviewFailure.ACCESS) to
                    DsaAppealReviewFailure.ACCESS,
            )) {
            var reads = 0
            val repo =
                DsaAppealReadRepository(
                    DsaAppealReadSource { _, _ ->
                        reads++
                        throw error
                    },
                    { readActor },
                    ReadGate(),
                    { now },
                )
            readFailure(expected) { repo.read(readActor, "report") }
            assertEquals(1, reads)
        }
    }

    @Test
    fun accountChangeWhileWaitingForGatePreventsSourceAccess() = runTest {
        var authority = readActor
        var reads = 0
        val gate = ReadGate().apply { before = { authority = readActor.copy(revision = 2) } }
        val repo =
            DsaAppealReadRepository(
                DsaAppealReadSource { _, _ ->
                    reads++
                    row()
                },
                { authority },
                gate,
                { now },
            )
        cancelled { repo.read(readActor, "report") }
        assertEquals(0, reads)
    }

    @Test
    fun lateAccountBackendReadinessOrRevisionChangesDiscardTheResult() = runTest {
        for (next in
            listOf(
                null,
                readActor.copy(uid = "other"),
                readActor.copy(revision = 2),
                readActor.copy(backend = "other"),
                readActor.copy(ready = false),
            )) {
            var authority: DsaAppealSession? = readActor
            val repo =
                DsaAppealReadRepository(
                    DsaAppealReadSource { _, _ ->
                        authority = next
                        row()
                    },
                    { authority },
                    ReadGate(),
                    { now },
                )
            cancelled { repo.read(readActor, "report") }
        }
    }

    @Test
    fun selectionLossBeforeSourceAndAfterGateCannotExposeOldReview() = runTest {
        var selected = false
        var reads = 0
        val gate = ReadGate()
        val repo =
            DsaAppealReadRepository(
                DsaAppealReadSource { _, _ ->
                    reads++
                    row()
                },
                { readActor },
                gate,
                { now },
            )
        readFailure(DsaAppealReviewFailure.STALE) {
            repo.read(readActor, "report", stillSelected = { selected })
        }
        assertEquals(0, reads)
        selected = true
        gate.after = { selected = false }
        readFailure(DsaAppealReviewFailure.STALE) {
            repo.read(readActor, "report", stillSelected = { selected })
        }
        assertEquals(1, reads)
    }

    @Test
    fun lateErrorsFromAnotherSelectionOrAccountAreDiscardedToo() = runTest {
        var selected = true
        val repo =
            DsaAppealReadRepository(
                DsaAppealReadSource { _, _ ->
                    selected = false
                    throw IOException("PRIVATE")
                },
                { readActor },
                ReadGate(),
                { now },
            )
        readFailure(DsaAppealReviewFailure.STALE) {
            repo.read(readActor, "report", stillSelected = { selected })
        }
        var authority = readActor
        val changed =
            DsaAppealReadRepository(
                DsaAppealReadSource { _, _ ->
                    authority = readActor.copy(revision = 2)
                    throw DsaAppealReviewException(DsaAppealReviewFailure.ACCESS)
                },
                { authority },
                ReadGate(),
                { now },
            )
        cancelled { changed.read(readActor, "report") }
    }

    @Test
    fun expirationAfterActualReadButBeforeGateReturnsStillRejectsReview() = runTest {
        var time = now
        val gate = ReadGate().apply { after = { time = decided.plusSeconds(3_600) } }
        val repo =
            DsaAppealReadRepository(
                DsaAppealReadSource { _, _ -> row() },
                { readActor },
                gate,
                { time },
            )
        readFailure(DsaAppealReviewFailure.EXPIRED) { repo.read(readActor, "report") }
    }

    @Test
    fun callerCancellationSurvivesNonCancellableGateUntilActualReadDrains() = runTest {
        var drained = false
        var delivered = false
        val repo =
            DsaAppealReadRepository(
                DsaAppealReadSource { _, _ ->
                    delay(100)
                    drained = true
                    row()
                },
                { readActor },
                ReadGate(),
                { now },
            )
        val job = launch {
            repo.read(readActor, "report")
            delivered = true
        }
        runCurrent()
        job.cancel()
        advanceUntilIdle()
        assertTrue(drained)
        assertFalse(delivered)
        assertTrue(job.isCancelled)
    }

    @Test
    fun internalTimeoutIsOfflineButCallerTimeoutRemainsCancellation() = runTest {
        val internal =
            DsaAppealReadRepository(
                DsaAppealReadSource { _, _ ->
                    withTimeout(1) {
                        delay(2)
                        row()
                    }
                },
                { readActor },
                ReadGate(),
                { now },
            )
        readFailure(DsaAppealReviewFailure.OFFLINE) { internal.read(readActor, "report") }
        val external =
            DsaAppealReadRepository(
                DsaAppealReadSource { _, _ ->
                    delay(2)
                    row()
                },
                { readActor },
                ReadGate(),
                { now },
            )
        cancelled { withTimeout(1) { external.read(readActor, "report") } }
    }
}
