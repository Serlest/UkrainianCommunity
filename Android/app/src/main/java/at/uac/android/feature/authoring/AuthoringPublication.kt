package at.uac.android.feature.authoring

import at.uac.android.feature.browse.Fields
import java.time.Instant
import java.time.temporal.ChronoUnit

enum class AuthoringPublicationMode {
    NOW,
    SCHEDULED,
}

/** Ordinary create scheduling only. This is not the owner's planning/lease workflow. */
object AuthoringPublication {
    const val MINIMUM_DELAY_SECONDS = 300L

    fun initialTime(now: Instant = Instant.now()): Instant =
        now.plusSeconds(3_600).truncatedTo(ChronoUnit.MINUTES)

    fun hasEnoughLeadTime(time: Instant?, now: Instant = Instant.now()): Boolean =
        time != null && time >= now.plusSeconds(MINIMUM_DELAY_SECONDS)

    fun validateDraft(draft: AuthoringDraft, base: AuthoringItem?, now: Instant) {
        if (
            base != null &&
                (draft.publicationMode != AuthoringPublicationMode.NOW || draft.scheduledAt != null)
        )
            AuthoringContract.invalid("schedule")
        if (
            draft.publicationMode == AuthoringPublicationMode.SCHEDULED &&
                !hasEnoughLeadTime(draft.scheduledAt, now)
        )
            AuthoringContract.invalid("schedule")
    }

    /**
     * No wall-clock check here: an expired durable intent must remain readable, never disappear.
     */
    fun validStoredShape(fields: Fields): Boolean =
        if (fields["moderationStatus"] == AuthoringStatus.SCHEDULED.wire)
            fields["scheduledAt"] is Instant
        else "scheduledAt" !in fields

    fun canSend(intent: AuthoringSubmission, now: Instant = Instant.now()): Boolean =
        validStoredShape(intent.fields) &&
            (intent.fields["moderationStatus"] != AuthoringStatus.SCHEDULED.wire ||
                intent.base == null &&
                    hasEnoughLeadTime(intent.fields["scheduledAt"] as? Instant, now))

    fun requireFreshIntent(intent: AuthoringSubmission, now: Instant = Instant.now()) {
        if (!canSend(intent, now)) AuthoringContract.invalid("schedule")
    }
}
