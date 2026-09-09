package at.uac.android

import at.uac.android.feature.moderation.*
import org.junit.Assert.*
import org.junit.Test

class ModerationBuild80ContractTest {
    @Test
    fun requestUsesExactRevisionAndStableOperation() {
        val pending = ModerationDecisionUnitFixture.pending()
        val request = ModerationBuild80Contract.payload(pending)
        assertEquals("news", request["contentType"])
        assertEquals(pending.operationId, request["operationId"])
        assertEquals(
            "${pending.version.updatedAt.epochSecond}:${pending.version.updatedAt.nano}",
            request["expectedRevision"],
        )
    }

    @Test
    fun onlyMatchingCompleteResponseCanBeAcknowledged() {
        val pending = ModerationDecisionUnitFixture.pending()
        val request = ModerationBuild80Contract.payload(pending)
        val receipt =
            mapOf<String, Any>(
                "contentType" to request.getValue("contentType"),
                "contentId" to request.getValue("contentId"),
                "operationId" to pending.operationId,
                "moderationStatus" to pending.decision.wire,
                "updatedAt" to "2026-09-09T12:00:00.123Z",
                "replayed" to false,
            )
        ModerationBuild80Contract.requireReceipt(pending, receipt)
        ModerationBuild80Contract.requireReceipt(pending, receipt + ("replayed" to true))
        receipt.keys.forEach { key ->
            assertThrows(ModerationDecisionException::class.java) {
                ModerationBuild80Contract.requireReceipt(pending, receipt - key)
            }
        }
        listOf("contentType", "contentId", "operationId", "moderationStatus", "updatedAt")
            .forEach { key ->
                assertThrows(ModerationDecisionException::class.java) {
                    ModerationBuild80Contract.requireReceipt(
                        pending,
                        receipt + (key to "different"),
                    )
                }
            }
    }
}
