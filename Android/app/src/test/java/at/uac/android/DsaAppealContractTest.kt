package at.uac.android

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.dsaappeal.*
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class DsaAppealContractTest {
    private val ascii = "abcdefghijklmnopqrst"
    private val counter = DsaAppealCharacterCounter { it.codePointCount(0, it.length) }

    private fun review(raw: String = ascii) = DsaAppealContract.review(raw, counter)

    private fun failure(expected: DsaAppealTextFailure, action: () -> Unit) {
        try {
            action()
            fail("Expected ${expected.name}")
        } catch (error: DsaAppealTextException) {
            assertEquals(expected, error.failure)
            assertEquals(expected.name, error.message)
            assertNull(error.cause)
        }
    }

    private fun response(extra: Map<String, Any?> = emptyMap()) =
        mapOf<String, Any?>(
            "reportId" to "report",
            "caseNumber" to "SYNTHETIC CASE",
            "status" to "appealed",
            "submittedAt" to "2026-09-03T12:34:56.123Z",
        ) + extra

    private fun decode(fields: Any? = response()) =
        DsaAppealContract.response("report", "SYNTHETIC CASE", fields)

    @Test
    fun normalizationMatchesActualServerWhitespaceAndIsIdempotent() {
        val normalized = DsaAppealContract.normalize(" \uFEFFa\t\n b\u00A0 ")
        assertEquals("a b", normalized)
        assertEquals(normalized, DsaAppealContract.normalize(normalized))
    }

    @Test
    fun allTwentyFiveEcmaWhitespaceCodePointsAreHandled() {
        val points =
            (9..13).toList() +
                listOf(0x20, 0xA0, 0x1680) +
                (0x2000..0x200A).toList() +
                listOf(0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF)
        assertEquals(25, points.size)
        for (point in points) assertEquals(
            "a b",
            DsaAppealContract.normalize(
                "${point.toChar()}a${point.toChar()}${point.toChar()}b${point.toChar()}"
            ),
        )
    }

    @Test
    fun nonWhitespaceFormattingCharactersAreNotSilentlyRemoved() {
        val raw = "a\u180Eb\u200Bc\u200Dd"
        assertEquals(raw, DsaAppealContract.normalize(raw))
    }

    @Test
    fun unsupportedControlsAreRejectedRatherThanRewritten() {
        for (char in listOf('\u0000', '\u001C', '\u007F', '\u0085')) failure(
            DsaAppealTextFailure.INVALID
        ) {
            DsaAppealContract.normalize("a${char}b")
        }
    }

    @Test
    fun emptyAndWhitespaceOnlyAreInvalid() {
        for (raw in listOf("", " \n\uFEFF\u00A0")) failure(DsaAppealTextFailure.INVALID) {
            DsaAppealContract.normalize(raw)
        }
    }

    @Test
    fun rawInputBoundIsSeparateFromServerNormalizedLength() {
        assertEquals(ascii, DsaAppealContract.normalize(" ".repeat(60_000) + ascii))
        failure(DsaAppealTextFailure.TOO_LONG) {
            DsaAppealContract.normalize(" ".repeat(65_537) + ascii)
        }
    }

    @Test
    fun serverLimitUsesUtf16AfterNormalizationAndNeverTruncates() {
        assertEquals(5_000, DsaAppealContract.normalize("x".repeat(5_000)).length)
        failure(DsaAppealTextFailure.TOO_LONG) { DsaAppealContract.normalize("x".repeat(5_001)) }
        assertEquals(5_000, DsaAppealContract.normalize("😀".repeat(2_500)).length)
        failure(DsaAppealTextFailure.TOO_LONG) {
            DsaAppealContract.normalize("😀".repeat(2_500) + "x")
        }
    }

    @Test
    fun malformedSurrogatesAreInvalidNotReplacementCharacters() {
        for (raw in listOf("\uD800", "\uDC00", "x\uD800y")) failure(DsaAppealTextFailure.INVALID) {
            DsaAppealContract.normalize(raw)
        }
        assertEquals("👩‍💻 е́", DsaAppealContract.normalize("👩‍💻 е́"))
    }

    @Test
    fun minimumAppliesToReviewedLogicalCharactersNotUtf16Units() {
        assertEquals(20, review().logicalCharacters)
        failure(DsaAppealTextFailure.TOO_SHORT) { review(ascii.dropLast(1)) }
        failure(DsaAppealTextFailure.TOO_SHORT) {
            DsaAppealContract.review("e\u0301".repeat(19), DsaAppealCharacterCounter { 19 })
        }
    }

    @Test
    fun counterReceivesExactNormalizedTextAndReviewExposesChange() {
        var observed = ""
        val result =
            DsaAppealContract.review(
                "\n$ascii \t",
                DsaAppealCharacterCounter {
                    observed = it
                    20
                },
            )
        assertEquals(ascii, observed)
        assertEquals(ascii, result.reason)
        assertTrue(result.normalizationChanged)
        assertFalse(review().normalizationChanged)
    }

    @Test
    fun invalidCounterResultsFailClosed() {
        for (count in listOf(-1, 0, 21, Int.MAX_VALUE)) failure(DsaAppealTextFailure.INVALID) {
            DsaAppealContract.review(ascii, DsaAppealCharacterCounter { count })
        }
    }

    @Test
    fun payloadContainsOnlyExactCanonicalTargetAndReviewedText() {
        assertEquals(
            mapOf("reportId" to "report", "reason" to ascii),
            DsaAppealContract.payload("report", review(" $ascii ")),
        )
        assertEquals(
            200,
            DsaAppealContract.payload("x".repeat(200), review()).getValue("reportId").length,
        )
        for (id in
            listOf(
                " report",
                "report ",
                "a/b",
                "..",
                "x".repeat(201),
                "re\uFEFFport",
                "a\uD800",
            )) failure(DsaAppealTextFailure.INVALID) { DsaAppealContract.payload(id, review()) }
    }

    @Test
    fun internalMalformedReviewCannotBypassPayloadChecks() {
        failure(DsaAppealTextFailure.INVALID) {
            DsaAppealContract.payload("report", DsaAppealReviewedText(" $ascii", 20, false))
        }
        failure(DsaAppealTextFailure.INVALID) {
            DsaAppealContract.payload("report", DsaAppealReviewedText(ascii, 19, false))
        }
    }

    @Test
    fun exactResponsePreservesServerMillisecondsAndDoesNotRetainRawMap() {
        val fields = response().toMutableMap()
        val decoded = decode(fields)
        fields["caseNumber"] = "CHANGED"
        assertEquals("SYNTHETIC CASE", decoded.caseNumber)
        assertEquals("report", decoded.reportId)
        assertEquals(Instant.parse("2026-09-03T12:34:56.123Z"), decoded.submittedAt)
        assertEquals(123_000_000, decoded.submittedAt.nano)
    }

    @Test
    fun responseMustEchoExactTargetCaseAndStatus() {
        for (extra in
            listOf(
                mapOf("reportId" to "other"),
                mapOf("caseNumber" to "other"),
                mapOf("status" to "pending"),
                mapOf("status" to true),
            )) failure(DsaAppealTextFailure.RESPONSE) { decode(response(extra)) }
    }

    @Test
    fun missingExtraAndWrongResponseTypesAreRejected() {
        for (key in response().keys) failure(DsaAppealTextFailure.RESPONSE) {
            decode(response() - key)
        }
        failure(DsaAppealTextFailure.RESPONSE) {
            decode(response(mapOf("privateToken" to "SECRET")))
        }
        for (value in listOf(null, "ok", listOf(response()))) failure(
            DsaAppealTextFailure.RESPONSE
        ) {
            decode(value)
        }
    }

    @Test
    fun timestampMustBeCanonicalServerIsoMillisecondsNotNormalizedOrGuessed() {
        for (time in
            listOf(
                "2026-09-03T12:34:56Z",
                "2026-09-03T12:34:56.123456Z",
                "2026-09-03T12:34:56.123+00:00",
                "2026-02-30T12:34:56.123Z",
                "2026-09-03T24:00:00.000Z",
                "2016-12-31T23:59:60.000Z",
                "0000-01-01T00:00:00.000Z",
            )) failure(DsaAppealTextFailure.RESPONSE) {
            decode(response(mapOf("submittedAt" to time)))
        }
        assertEquals(
            Instant.parse("2026-09-03T00:00:00Z"),
            decode(response(mapOf("submittedAt" to "2026-09-03T00:00:00.000Z"))).submittedAt,
        )
    }

    @Test
    fun expectedCaseAndTargetAreValidatedBeforeAcceptingAResponse() {
        for (number in listOf("", " ", "x".repeat(201), "case\n", "case\uD800")) failure(
            DsaAppealTextFailure.RESPONSE
        ) {
            DsaAppealContract.response("report", number, response(mapOf("caseNumber" to number)))
        }
        failure(DsaAppealTextFailure.RESPONSE) {
            DsaAppealContract.response(
                "bad/id",
                "SYNTHETIC CASE",
                response(mapOf("reportId" to "bad/id")),
            )
        }
    }

    @Test
    fun modelsAndErrorsDoNotPrintPrivateReasonOrCase() {
        assertEquals("DsaAppealReviewedText(<redacted>)", review().toString())
        assertEquals("DsaAppealResponse(<redacted>)", decode().toString())
        assertFalse(DsaAppealTextException(DsaAppealTextFailure.INVALID).toString().contains(ascii))
    }

    @Test
    fun noAppealDecisionOrPortalEndpointWasEnabled() {
        for (name in
            listOf(
                "submitDsaAppeal",
                "decideDsaCase",
                "decideDsaAppeal",
                "dsaCasePortal",
            )) assertTrue(runCatching { LocalCallableProtocol.endpoint(name) }.isFailure)
        assertTrue(
            LocalCallableProtocol.endpoint("getMyDsaStatement").contains("getMyDsaStatement")
        )
    }
}
