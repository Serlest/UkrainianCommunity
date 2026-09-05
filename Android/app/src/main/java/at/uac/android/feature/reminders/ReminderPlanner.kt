package at.uac.android.feature.reminders

import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.string
import at.uac.android.feature.browse.time
import at.uac.android.feature.inbox.InboxPreferences
import java.time.Instant
import java.time.temporal.ChronoUnit

/**
 * Build 65 picks the first scheduled occurrence that has not ended, including one already underway.
 */
object ReminderPlanner {
    val leadChoices = listOf(15, 30, 60, 120, 1_440)

    fun nearest(content: Content, now: Instant): ReminderOccurrence? {
        if (
            content.kind != ContentKind.EVENTS ||
                !reminderId(content.id) ||
                content.fields.string("moderationStatus") != "approved" ||
                content.fields.string("sourceType") != "organization" ||
                content.fields.string("cancellationState") == "cancelled"
        )
            return null
        val raw = content.fields["occurrences"]
        if (raw != null && raw !is List<*>) throw ReminderException(ReminderFailure.INVALID)
        if (raw is List<*> && raw.size > 366) throw ReminderException(ReminderFailure.LIMIT)
        val valid =
            raw.orEmpty()
                .mapNotNull { value ->
                    val fields =
                        value as? Map<*, *> ?: throw ReminderException(ReminderFailure.INVALID)
                    val start =
                        fields["startDate"] as? Instant
                            ?: throw ReminderException(ReminderFailure.INVALID)
                    val end =
                        fields["endDate"] as? Instant
                            ?: throw ReminderException(ReminderFailure.INVALID)
                    val id =
                        fields["id"] as? String ?: throw ReminderException(ReminderFailure.INVALID)
                    val status = fields["status"] as? String ?: "scheduled"
                    if (!reminderId(id) || status !in setOf("scheduled", "cancelled"))
                        throw ReminderException(ReminderFailure.INVALID)
                    if (end < start) null else ReminderOccurrence(id, start, end) to status
                }
                .sortedBy { it.first.start }
        val occurrences = valid.ifEmpty {
            val start = content.fields.time("startDate") ?: return null
            val end = content.fields.time("endDate") ?: return null
            if (end < start) return null
            listOf(ReminderOccurrence("legacy", start, end) to "scheduled")
        }
        return occurrences
            .firstOrNull { (occurrence, status) -> status == "scheduled" && occurrence.end >= now }
            ?.first
    }

    fun candidate(
        content: Content,
        preferences: InboxPreferences,
        now: Instant,
    ): ReminderCandidate? {
        if (!preferences.valid()) throw ReminderException(ReminderFailure.INVALID)
        if (!preferences.notificationsEnabled || !preferences.eventRemindersEnabled) return null
        val occurrence = nearest(content, now) ?: return null
        val fire =
            occurrence.start
                .minusSeconds(preferences.reminderLeadMinutes.toLong() * 60)
                .truncatedTo(ChronoUnit.MINUTES)
        return if (fire > now) ReminderCandidate(content.id, occurrence, fire) else null
    }

    fun matches(
        ticket: ReminderTicket,
        content: Content,
        preferences: InboxPreferences,
        now: Instant,
    ): Boolean {
        if (
            !preferences.valid() ||
                !preferences.notificationsEnabled ||
                !preferences.eventRemindersEnabled ||
                !ticket.due(now)
        )
            return false
        val occurrence = nearest(content, now) ?: return false
        return ticket.eventId == content.id &&
            ticket.occurrence == occurrence &&
            ticket.fireAt ==
                occurrence.start
                    .minusSeconds(preferences.reminderLeadMinutes.toLong() * 60)
                    .truncatedTo(ChronoUnit.MINUTES)
    }
}
