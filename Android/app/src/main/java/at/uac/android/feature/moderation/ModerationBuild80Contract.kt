package at.uac.android.feature.moderation

import java.time.Instant

/** Exact callable contract deployed with iOS 1.1 (80). */
internal object ModerationBuild80Contract {
    fun payload(pending: ModerationPending): Map<String, String> {
        pending.version.validate()
        val time = pending.version.updatedAt
        return mapOf(
            "contentType" to
                if (pending.version.target.kind == ModerationKind.NEWS) "news" else "event",
            "contentId" to pending.version.target.id,
            "decision" to pending.decision.wire,
            "operationId" to pending.operationId,
            "expectedRevision" to "${time.epochSecond}:${time.nano}",
        )
    }

    fun requireReceipt(pending: ModerationPending, response: Any?) {
        val fields = response as? Map<*, *> ?: invalid()
        val request = payload(pending)
        if (
            fields["contentType"] != request["contentType"] ||
                fields["contentId"] != request["contentId"] ||
                fields["operationId"] != pending.operationId ||
                fields["moderationStatus"] != pending.decision.wire ||
                fields["replayed"] !is Boolean ||
                runCatching { Instant.parse(fields["updatedAt"] as? String) }.getOrNull() == null
        )
            invalid()
    }

    fun confirmsCurrentOperation(
        pending: ModerationPending,
        uid: String,
        fields: Map<String, Any?>,
    ): Boolean =
        pending.phase != ModerationDecisionPhase.PREPARED &&
            pending.accountHash == ModerationDecisionContract.accountHash(uid) &&
            fields["moderationOperationId"] == pending.operationId &&
            fields["moderatedByUserId"] == uid &&
            fields["moderationStatus"] == pending.decision.wire &&
            ModerationReviewVersion.instant(fields["moderatedAt"]) != null &&
            runCatching {
                    ModerationReviewVersion.hash(
                        pending.version.target,
                        fields.filterKeys {
                            it !in
                                setOf("moderationOperationId", "moderatedByUserId", "moderatedAt")
                        },
                        true,
                    )
                }
                .getOrNull() == pending.version.preservedHash

    private fun invalid(): Nothing =
        ModerationDecisionContract.fail(ModerationDecisionFailure.UNCONFIRMED)
}
