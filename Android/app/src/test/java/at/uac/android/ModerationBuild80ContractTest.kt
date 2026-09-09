package at.uac.android

import at.uac.android.feature.moderation.*
import org.junit.Assert.*
import org.junit.Test

class ModerationBuild80ContractTest {
    @Test
    fun lostResponseNeedsExactActorOperationAndPreservedContent() {
        val pending = ModerationDecisionUnitFixture.pending(ModerationDecisionPhase.DISPATCHED)
        val uid = ModerationDecisionUnitFixture.actor.uid
        val fields =
            ModerationDecisionUnitFixture.fields() +
                mapOf(
                    "moderationOperationId" to pending.operationId,
                    "moderatedByUserId" to uid,
                    "moderatedAt" to ModerationDecisionUnitFixture.time.plusSeconds(1),
                    "moderationStatus" to "approved",
                )
        assertTrue(ModerationBuild80Contract.confirmsCurrentOperation(pending, uid, fields))
        for (key in
            listOf(
                "moderationOperationId",
                "moderatedByUserId",
                "moderatedAt",
                "moderationStatus",
                "body",
            )) assertFalse(
            ModerationBuild80Contract.confirmsCurrentOperation(
                pending,
                uid,
                fields + (key to "different"),
            )
        )
        assertFalse(
            ModerationBuild80Contract.confirmsCurrentOperation(
                pending.copy(phase = ModerationDecisionPhase.PREPARED),
                uid,
                fields,
            )
        )
    }

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
