package at.uac.android.feature.reminders

import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.browse.Content
import at.uac.android.feature.inbox.InboxPreferences
import java.security.MessageDigest
import java.time.Instant

data class ReminderSession(val uid: String, val revision: Long, val ready: Boolean)

fun AuthSession.reminderSession(): ReminderSession? =
    identity
        ?.takeUnless { it.anonymous }
        ?.let {
            ReminderSession(it.uid, revision, readyForActions)
        }

enum class ReminderFailure {
    NOT_READY,
    STALE,
    INVALID,
    LIMIT,
    OFFLINE,
    STORAGE,
    SYSTEM,
    EXPIRED,
    SUPPRESSED,
}

class ReminderException(val failure: ReminderFailure) : Exception(failure.name)

enum class ReminderPermission {
    ALLOWED,
    APP_DENIED,
    CHANNEL_DENIED,
}

enum class ReminderStage {
    IDLE,
    CHECKING,
    SCHEDULED,
    DISABLED,
    FAILED,
}

data class ReminderState(
    val stage: ReminderStage = ReminderStage.IDLE,
    val permission: ReminderPermission = ReminderPermission.APP_DENIED,
    val scheduled: Int = 0,
    val error: ReminderFailure? = null,
    val localTestRequested: Boolean = false,
    val session: ReminderSession? = null,
) {
    /**
     * A delayed collector/bind may never render a former account's count, error or test receipt.
     */
    fun forSession(current: ReminderSession?): ReminderState =
        if (current?.ready == true && session == current) this
        else ReminderState(permission = permission, session = current)
}

data class ReminderOccurrence(val id: String, val start: Instant, val end: Instant)

data class ReminderCandidate(
    val eventId: String,
    val occurrence: ReminderOccurrence,
    val fireAt: Instant,
)

data class ReminderSnapshot(
    val session: ReminderSession,
    val preferences: InboxPreferences,
    val candidates: List<ReminderCandidate>,
    val complete: Boolean,
    val confirmedAt: Instant,
)

enum class ReminderTicketState {
    PENDING,
    CLAIMED,
    SUPPRESSED,
}

data class ReminderTicket(
    val token: String,
    val owner: String,
    val epoch: String,
    val eventId: String,
    val occurrence: ReminderOccurrence,
    val fireAt: Instant,
    val localTest: Boolean = false,
    val state: ReminderTicketState = ReminderTicketState.PENDING,
) {
    val key: String
        get() =
            reminderHash(listOf(owner, eventId, occurrence.start.toString(), localTest.toString()))

    fun due(now: Instant): Boolean = now >= fireAt && now < occurrence.end
}

data class ReminderReceipt(val key: String, val retainUntil: Instant)

data class ReminderPlan(
    val owner: String? = null,
    val epoch: String? = null,
    val tickets: List<ReminderTicket> = emptyList(),
    val receipts: List<ReminderReceipt> = emptyList(),
)

data class ReminderTapRequest(val epoch: String, val token: String)

data class ConfirmedReminder(
    val ticket: ReminderTicket,
    val content: Content?,
    val checkedAt: Instant,
)

sealed interface ReminderTapOutcome {
    data class Event(val content: Content) : ReminderTapOutcome

    data object LocalTest : ReminderTapOutcome
}

interface ReminderSource {
    fun currentOwner(): String?

    suspend fun snapshot(session: ReminderSession, current: () -> Boolean): ReminderSnapshot

    suspend fun verify(ticket: ReminderTicket, current: () -> Boolean): ConfirmedReminder
}

interface ReminderScheduler {
    fun requestNext(ticket: ReminderTicket, now: Instant)

    fun cancelOwned()
}

interface ReminderNotificationSink {
    fun permission(): ReminderPermission

    fun postGeneric(receipt: ConfirmedReminder)

    fun cancelOwned()
}

internal const val REMINDER_MAX_EVENTS = 200
internal const val REMINDER_MAX_RECEIPTS = 1_000
internal const val REMINDER_BUDGET_MS = 7_000L

internal fun reminderId(value: String): Boolean =
    value.isNotBlank() &&
        value.length <= 256 &&
        value !in setOf(".", "..") &&
        '/' !in value &&
        value.none(Char::isISOControl)

internal fun reminderOpaque(value: String): Boolean = Regex("[a-f0-9-]{36}").matches(value)

internal fun reminderHash(parts: List<String>): String =
    MessageDigest.getInstance("SHA-256")
        .digest(parts.joinToString("|") { "${it.length}:$it" }.toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }

fun reminderOwner(uid: String): String =
    reminderHash(listOf("demo-uac-android", "at.uac.android.local", uid))
