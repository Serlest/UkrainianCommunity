package at.uac.android

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.dsastatement.*
import java.io.IOException
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class DsaStatementTest {
    private val id = "private-report"
    private val session = DsaStatementSession("private-user", 4, "local-demo", true)

    private fun decision() =
        mapOf<String, Any?>(
            "outcome" to "removed",
            "factsAndCircumstances" to "Приватні факти\nGründe 🙂",
            "legalBasis" to null,
            "termsBasis" to "private-terms",
            "territorialScope" to "AT",
            "duration" to "private-duration",
            "redressInformation" to "private-redress",
            "automationUsed" to false,
        )

    private fun appeal() =
        mapOf<String, Any?>(
            "outcome" to "changed",
            "reason" to "private-reason",
            "automationUsed" to true,
        )

    private fun wire() =
        mapOf<String, Any?>(
            "id" to id,
            "caseNumber" to "private-case",
            "status" to "decided",
            "sourceType" to "comment",
            "sourceId" to "private-content",
            "decision" to decision(),
            "appealDecision" to appeal(),
        )

    private fun parse(raw: Any? = wire()) = DsaStatementContract.response(id, raw)

    private fun invalid(action: () -> Unit) {
        val error = runCatching(action).exceptionOrNull()
        assertTrue(error is DsaStatementException)
        assertEquals(DsaStatementFailure.INVALID, (error as DsaStatementException).failure)
        assertNull(error.cause)
    }

    @Test
    fun exactRequestHasNoInventedOwnerOrOperationFields() {
        assertEquals(mapOf("reportId" to id), DsaStatementContract.payload(id))
        assertTrue(DsaStatementContract.validId("a".repeat(200)))
        assertTrue(DsaStatementContract.validId("🙂".repeat(100)))
    }

    @Test
    fun aliasesPathsAndMalformedIdsNeverRedirect() {
        for (value in
            listOf(
                "",
                " ",
                " a",
                "a ",
                "a b",
                "a\u00A0b",
                "a\uFEFFb",
                ".",
                "..",
                "__x__",
                "a/b",
                "a\n",
                "\uD800",
                "\uDC00",
                "a".repeat(201),
            )) {
            assertFalse(value.length.toString(), DsaStatementContract.validId(value))
            invalid { DsaStatementContract.payload(value) }
        }
    }

    @Test
    fun sanitizedResponsePreservesExactTextAndAutomationBooleans() {
        val item = parse()
        assertEquals(id, item.id)
        assertEquals(DsaStatementStatus.DECIDED, item.status)
        assertEquals(DsaStatementOutcome.REMOVED, item.decision!!.outcome)
        assertEquals(decision()["factsAndCircumstances"], item.decision.factsAndCircumstances)
        assertNull(item.decision.legalBasis)
        assertFalse(item.decision.automationUsed)
        assertTrue(item.appealDecision!!.automationUsed)
        assertEquals(DsaStatementAppealOutcome.CHANGED, item.appealDecision.outcome)
    }

    @Test
    fun nullDecisionsAreLegitimateWithoutInventedDeadlinesOrActions() {
        val item =
            parse(
                wire() +
                    mapOf("status" to "underReview", "decision" to null, "appealDecision" to null)
            )
        assertEquals(DsaStatementStatus.UNDER_REVIEW, item.status)
        assertNull(item.decision)
        assertNull(item.appealDecision)
    }

    @Test
    fun unknownEnumsRetainExactRawValueWithoutMappingToAction() {
        val item =
            parse(
                wire() +
                    mapOf(
                        "status" to "future",
                        "decision" to (decision() + ("outcome" to "future")),
                        "appealDecision" to (appeal() + ("outcome" to "future")),
                    )
            )
        assertEquals("future", item.rawStatus)
        assertEquals(DsaStatementStatus.UNKNOWN, item.status)
        assertEquals(DsaStatementOutcome.UNKNOWN, item.decision!!.outcome)
        assertEquals(DsaStatementAppealOutcome.UNKNOWN, item.appealDecision!!.outcome)
    }

    @Test
    fun eachKnownStatusAndOutcomeHasExactMapping() {
        for ((raw, expected) in
            listOf(
                "submitted" to DsaStatementStatus.SUBMITTED,
                "underReview" to DsaStatementStatus.UNDER_REVIEW,
                "decided" to DsaStatementStatus.DECIDED,
                "appealed" to DsaStatementStatus.APPEALED,
                "appealDecided" to DsaStatementStatus.APPEAL_DECIDED,
            )) assertEquals(expected, parse(wire() + ("status" to raw)).status)
        assertEquals(
            DsaStatementOutcome.NO_ACTION,
            parse(wire() + ("decision" to (decision() + ("outcome" to "noAction"))))
                .decision!!
                .outcome,
        )
        assertEquals(
            DsaStatementOutcome.RESTRICTED,
            parse(wire() + ("decision" to (decision() + ("outcome" to "restricted"))))
                .decision!!
                .outcome,
        )
        assertEquals(
            DsaStatementAppealOutcome.UPHELD,
            parse(wire() + ("appealDecision" to (appeal() + ("outcome" to "upheld"))))
                .appealDecision!!
                .outcome,
        )
    }

    @Test
    fun responseMustMatchExactSelectedReport() {
        invalid { parse(wire() + ("id" to "another-report")) }
    }

    @Test
    fun missingOrUnexpectedTopLevelFieldsFailClosed() {
        for (key in wire().keys) invalid { parse(wire() - key) }
        for (key in listOf("reporterEmail", "evidence", "accessToken", "future")) invalid {
            parse(wire() + (key to "private"))
        }
    }

    @Test
    fun malformedTopLevelStringsAndContainerAreRejected() {
        for (raw in listOf(null, true, listOf(wire()), "private")) invalid { parse(raw) }
        for (key in listOf("id", "caseNumber", "status", "sourceType", "sourceId")) {
            for (raw in listOf(null, true, 1, listOf("x"))) invalid { parse(wire() + (key to raw)) }
        }
    }

    @Test
    fun malformedNestedDecisionNeverBecomesAbsent() {
        for (key in decision().keys) invalid { parse(wire() + ("decision" to (decision() - key))) }
        invalid { parse(wire() + ("decision" to (decision() + ("reporterEmail" to "private")))) }
        for (raw in listOf(false, "private", listOf(decision()))) invalid {
            parse(wire() + ("decision" to raw))
        }
        for (raw in listOf("false", 0, null)) invalid {
            parse(wire() + ("decision" to (decision() + ("automationUsed" to raw))))
        }
        invalid { parse(wire() + ("decision" to (decision() + ("legalBasis" to 1)))) }
    }

    @Test
    fun malformedNestedAppealNeverBecomesAbsent() {
        for (key in appeal().keys) invalid {
            parse(wire() + ("appealDecision" to (appeal() - key)))
        }
        invalid {
            parse(wire() + ("appealDecision" to (appeal() + ("reporterEmail" to "private"))))
        }
        for (raw in listOf(false, "private", listOf(appeal()))) invalid {
            parse(wire() + ("appealDecision" to raw))
        }
        invalid { parse(wire() + ("appealDecision" to (appeal() + ("automationUsed" to "true")))) }
    }

    @Test
    fun invalidUnicodeFailsWithoutReplacement() {
        for (value in listOf("\uD800", "\uDC00", "a\uD800b")) invalid {
            parse(wire() + ("caseNumber" to value))
        }
    }

    @Test
    fun globalUtf8BudgetRejectsRatherThanTruncates() {
        invalid {
            parse(wire() + ("caseNumber" to "a".repeat(DsaStatementContract.MAX_TEXT_BYTES)))
        }
        invalid { parse(wire() + ("caseNumber" to "🙂".repeat(16384))) }
        invalid {
            parse(
                wire() + mapOf("caseNumber" to "a".repeat(33000), "sourceType" to "b".repeat(33000))
            )
        }
        assertEquals(
            5000,
            parse(
                    wire() +
                        ("decision" to (decision() + ("factsAndCircumstances" to "я".repeat(5000))))
                )
                .decision!!
                .factsAndCircumstances
                .length,
        )
    }

    @Test
    fun emptyLegacyStringsArePreservedNotInvented() {
        val item = parse(wire() + mapOf("caseNumber" to "", "sourceId" to "", "status" to ""))
        assertEquals("", item.caseNumber)
        assertEquals("", item.sourceId)
        assertEquals(DsaStatementStatus.UNKNOWN, item.status)
    }

    @Test
    fun modelAndErrorsDoNotPrintPrivatePayload() {
        val item = parse()
        val text =
            "$item ${item.decision} ${item.appealDecision} $session ${DsaStatementException(DsaStatementFailure.INVALID)}"
        assertFalse(text.contains("private"))
        assertFalse(text.contains("Приватні"))
    }

    @Test
    fun onlySanitizedDsaReadEndpointIsEnabled() {
        assertTrue(
            LocalCallableProtocol.endpoint(DsaStatementContract.CALLABLE)
                .endsWith("/getMyDsaStatement")
        )
        assertFalse(LocalCallableProtocol.nonIdempotent(DsaStatementContract.CALLABLE))
        for (name in
            listOf(
                "decideDsaCase",
                "submitDsaAppeal",
                "decideDsaAppeal",
                "dsaCasePortal",
            )) assertTrue(runCatching { LocalCallableProtocol.endpoint(name) }.isFailure)
        assertTrue(LocalCallableProtocol.endpoint("registerForEvent").contains("registerForEvent"))
    }

    private class Gate : DsaStatementReadGate {
        var before: suspend () -> Unit = {}
        var after: suspend () -> Unit = {}

        override suspend fun <T> withSession(
            session: DsaStatementSession,
            action: suspend () -> T,
        ): T =
            withContext(NonCancellable) {
                before()
                action().also { after() }
            }
    }

    private inner class Harness {
        var current: DsaStatementSession? = session
        var selected = true
        var reads = 0
        val gate = Gate()
        var read: suspend () -> Any? = { wire() }
        val repository =
            DsaStatementRepository(
                DsaStatementSource { actor, report ->
                    assertEquals(session, actor)
                    assertEquals(id, report)
                    reads++
                    read()
                },
                gate,
                { current },
            )

        suspend fun load() = repository.read(session, id) { selected }
    }

    @Test
    fun scopeLossOnGateExitDiscardsAlreadyParsedResult() = runBlocking {
        val h = Harness()
        h.gate.after = { h.current = null }
        assertTrue(runCatching { h.load() }.exceptionOrNull() is CancellationException)
        assertEquals(1, h.reads)
    }

    @Test
    fun invalidReportNeverReachesSource() = runBlocking {
        val h = Harness()
        val error = runCatching {
            h.repository.read(session, "wrong/path") { true }
        }
            .exceptionOrNull()
        assertEquals(DsaStatementFailure.INVALID, (error as DsaStatementException).failure)
        assertEquals(0, h.reads)
    }

    @Test
    fun internalReadTimeoutIsOfflineAndDoesNotRetry() = runBlocking {
        val h = Harness()
        h.read = { withTimeout(1) { awaitCancellation() } }
        val error = runCatching { h.load() }.exceptionOrNull() as DsaStatementException
        assertEquals(DsaStatementFailure.OFFLINE, error.failure)
        assertNull(error.cause)
        assertEquals(1, h.reads)
    }

    @Test
    fun exactByteBudgetAcceptsBoundaryAndRejectsOneMoreByte() {
        val empty =
            wire() +
                mapOf(
                    "caseNumber" to "",
                    "status" to "",
                    "sourceType" to "",
                    "sourceId" to "",
                    "decision" to null,
                    "appealDecision" to null,
                )
        val remaining = DsaStatementContract.MAX_TEXT_BYTES - id.toByteArray(Charsets.UTF_8).size
        val exact = "a".repeat(remaining)
        assertEquals(exact, parse(empty + ("caseNumber" to exact)).caseNumber)
        invalid { parse(empty + ("caseNumber" to (exact + "a"))) }
    }

    @Test
    fun ordinaryReadyAuthorNeedsNoOwnerRoleAndReadsExactlyOnce() = runBlocking {
        val h = Harness()
        assertEquals(id, h.load().id)
        assertEquals(1, h.reads)
    }

    @Test
    fun invalidOrUnreadyScopeDoesNotRead() = runBlocking {
        for (bad in
            listOf(
                session.copy(ready = false),
                session.copy(revision = -1),
                session.copy(uid = ""),
                session.copy(backend = ""),
            )) {
            val h = Harness()
            h.current = bad
            val error = runCatching { h.repository.read(bad, id) { true } }.exceptionOrNull()
            assertEquals(DsaStatementFailure.ACCESS, (error as DsaStatementException).failure)
            assertEquals(0, h.reads)
        }
    }

    @Test
    fun initialSelectionLossOrAccountSwitchNeverReads() = runBlocking {
        for (selected in listOf(false, true)) {
            val h = Harness()
            h.selected = selected
            if (selected) h.current = null
            assertTrue(runCatching { h.load() }.exceptionOrNull() is CancellationException)
            assertEquals(0, h.reads)
        }
    }

    @Test
    fun scopeLossInsideNonCancellableGateNeverReads() = runBlocking {
        val h = Harness()
        h.gate.before = { h.current = session.copy(revision = 5) }
        assertTrue(runCatching { h.load() }.exceptionOrNull() is CancellationException)
        assertEquals(0, h.reads)
    }

    @Test
    fun lateAccountBackendReadinessAndSelectionChangesDiscardResponse() = runBlocking {
        for (next in
            listOf(
                null,
                session.copy(uid = "other"),
                session.copy(revision = 5),
                session.copy(backend = "other"),
                session.copy(ready = false),
            )) {
            val h = Harness()
            h.read = {
                h.current = next
                wire()
            }
            assertTrue(runCatching { h.load() }.exceptionOrNull() is CancellationException)
            assertEquals(1, h.reads)
        }
        val h = Harness()
        h.read = {
            h.selected = false
            wire()
        }
        assertTrue(runCatching { h.load() }.exceptionOrNull() is CancellationException)
    }

    @Test
    fun scopeLossTakesPriorityOverLatePrivateError() = runBlocking {
        val h = Harness()
        h.read = {
            h.current = null
            throw IOException("private")
        }
        assertTrue(runCatching { h.load() }.exceptionOrNull() is CancellationException)
    }

    @Test
    fun readErrorsAreDistinctRedactedAndNeverRetried() = runBlocking {
        for ((error, expected) in
            listOf(
                IOException("private") to DsaStatementFailure.OFFLINE,
                IllegalStateException("private") to DsaStatementFailure.UNKNOWN,
                DsaStatementException(DsaStatementFailure.MISSING) to DsaStatementFailure.MISSING,
                DsaStatementException(DsaStatementFailure.ACCESS) to DsaStatementFailure.ACCESS,
            )) {
            val h = Harness()
            h.read = { throw error }
            val actual = runCatching { h.load() }.exceptionOrNull() as DsaStatementException
            assertEquals(expected, actual.failure)
            assertNull(actual.cause)
            assertEquals(1, h.reads)
        }
    }

    @Test
    fun mismatchedResponseIsNotCachedOrReturned() = runBlocking {
        val h = Harness()
        h.read = { wire() + ("id" to "other") }
        assertEquals(
            DsaStatementFailure.INVALID,
            (runCatching { h.load() }.exceptionOrNull() as DsaStatementException).failure,
        )
        h.read = { wire() }
        assertEquals(id, h.load().id)
        assertEquals(2, h.reads)
    }

    @Test
    fun cancellationDuringNonCancellableReadDiscardsLateResponse() = runBlocking {
        val h = Harness()
        val started = CompletableDeferred<Unit>()
        val resume = CompletableDeferred<Unit>()
        var delivered = false
        h.read = {
            started.complete(Unit)
            resume.await()
            wire()
        }
        val job = launch {
            h.load()
            delivered = true
        }
        started.await()
        job.cancel()
        resume.complete(Unit)
        job.join()
        assertFalse(delivered)
        assertTrue(job.isCancelled)
        assertEquals(1, h.reads)
    }

    @Test
    fun cancellationDuringNonCancellableGatePreventsRead() = runBlocking {
        val h = Harness()
        val started = CompletableDeferred<Unit>()
        val resume = CompletableDeferred<Unit>()
        h.gate.before = {
            started.complete(Unit)
            resume.await()
        }
        val job = launch { h.load() }
        started.await()
        job.cancel()
        resume.complete(Unit)
        job.join()
        assertTrue(job.isCancelled)
        assertEquals(0, h.reads)
    }
}
