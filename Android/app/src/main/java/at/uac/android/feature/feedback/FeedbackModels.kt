package at.uac.android.feature.feedback

import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.map
import at.uac.android.feature.browse.string
import java.time.Duration
import java.time.Instant

data class FeedbackSession(
    val uid: String,
    val revision: Long,
    val ready: Boolean,
    val canManage: Boolean,
    val displayName: String,
)

enum class FeedbackAudience {
    OWN,
    MANAGEMENT,
}

enum class FeedbackType(val wire: String) {
    QUESTION("question"),
    SUGGESTION("suggestion"),
    BUG("bug"),
    REPORT("report"),
}

enum class FeedbackStatus(val wire: String) {
    OPEN("open"),
    ANSWERED("answered"),
    REVIEWED("reviewed"),
    ARCHIVED("archived"),
    CLOSED("closed"),
    UNKNOWN("");

    val closed
        get() = this in setOf(ARCHIVED, CLOSED, UNKNOWN)
}

enum class FeedbackFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    MISSING,
    CLOSED,
    INVALID,
    CONFLICT,
    OFFLINE,
    UNCONFIRMED,
    UNKNOWN,
}

class FeedbackException(val failure: FeedbackFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

fun feedbackId(value: String): Boolean =
    value.isNotBlank() &&
        value == value.trim() &&
        value.length <= 512 &&
        value.toByteArray(Charsets.UTF_8).size <= 1_500 &&
        value !in setOf(".", "..") &&
        '/' !in value &&
        value.none(Char::isISOControl)

data class FeedbackDraft(val type: FeedbackType = FeedbackType.QUESTION, val message: String = "") {
    fun normalized() = copy(message = message.trim())

    fun valid() = message.trim().length in 1..2_000
}

data class FeedbackCursor(val createdAt: Instant, val id: String)

data class FeedbackRawPage(
    val rows: List<RawDocument>,
    val next: FeedbackCursor?,
    val hasMore: Boolean,
)

data class FeedbackPage(
    val items: List<FeedbackItem>,
    val next: FeedbackCursor?,
    val hasMore: Boolean,
    val invalid: Int = 0,
)

data class FeedbackConversation(
    val item: FeedbackItem,
    val messages: List<FeedbackMessage>,
    val invalid: Int = 0,
    val limited: Boolean = false,
)

data class FeedbackItem(
    val id: String,
    val uid: String,
    val name: String,
    val type: FeedbackType?,
    val subject: String?,
    val message: String,
    val status: FeedbackStatus,
    val createdAt: Instant,
    val updatedAt: Instant,
    val preview: String,
    val unreadForUser: Boolean,
    val unreadForOwner: Boolean,
    val ownerReply: String?,
    val repliedAt: Instant?,
    val repliedBy: String?,
    val caseNumber: String?,
    val hasDsaCase: Boolean,
    val lastMessageAt: Instant? = null,
    val caseContext: FeedbackCaseContext? = null,
)

data class FeedbackMessage(
    val id: String,
    val feedbackId: String,
    val senderId: String,
    val name: String,
    val owner: Boolean,
    val text: String,
    val createdAt: Instant,
    val system: Boolean = false,
    val legacy: Boolean = false,
)

object FeedbackContract {
    private fun invalid(): Nothing = throw FeedbackException(FeedbackFailure.INVALID)

    private fun date(value: Any?): Instant = value as? Instant ?: invalid()

    private fun optionalDate(f: Fields, key: String): Instant? = f[key]?.let(::date)

    private fun text(value: Any?, maximum: Int = 65_536): String =
        (value as? String ?: invalid()).also {
            if (it.length > maximum) invalid()
        }

    private fun optionalText(f: Fields, key: String): String? = f[key]?.let { text(it) }

    private fun optionalFlag(f: Fields, key: String): Boolean =
        f[key]?.let { it as? Boolean ?: invalid() } ?: false

    fun item(row: RawDocument): FeedbackItem =
        with(row.fields) {
            if (!feedbackId(row.id) || (this["id"] != null && this["id"] != row.id)) invalid()
            val uid = text(this["userId"], 128).also { if (!feedbackId(it)) invalid() }
            val created = date(this["createdAt"])
            val body = text(this["message"])
            val state = text(this["status"], 80)
            val type = text(this["type"], 80)
            val dsa = map("dsaCase")
            FeedbackItem(
                row.id,
                uid,
                text(this["userDisplayName"], 1_000),
                FeedbackType.entries.find { it.wire == type },
                optionalText(this, "subject"),
                body,
                FeedbackStatus.entries.find { it.wire == state } ?: FeedbackStatus.UNKNOWN,
                created,
                optionalDate(this, "updatedAt") ?: created,
                optionalText(this, "lastMessageText") ?: body,
                optionalFlag(this, "unreadForUser"),
                optionalFlag(this, "unreadForOwner"),
                optionalText(this, "ownerReply"),
                optionalDate(this, "repliedAt"),
                optionalText(this, "repliedByUserId"),
                dsa.string("caseNumber").takeIf(String::isNotBlank),
                this["dsaCase"] != null,
                optionalDate(this, "lastMessageAt"),
                FeedbackCaseContextContract.decode(this["dsaCase"]),
            )
        }

    fun message(row: RawDocument, parent: String): FeedbackMessage =
        with(row.fields) {
            if (
                !feedbackId(row.id) ||
                    (this["id"] != null && this["id"] != row.id) ||
                    (this["feedbackId"] != null && this["feedbackId"] != parent)
            )
                invalid()
            val role = text(this["senderRole"], 20)
            if (role !in setOf("user", "owner")) invalid()
            val system = optionalFlag(this, "isSystem")
            // submitDsaAppeal creates user-role system messages on the server. Preserve that
            // marker without promoting the sender to support; write/receipt checks stay separate.
            FeedbackMessage(
                row.id,
                parent,
                text(this["senderId"], 128),
                text(this["senderDisplayName"], 1_000),
                role == "owner",
                text(this["text"]),
                date(this["createdAt"]),
                system,
            )
        }

    fun merge(item: FeedbackItem, stored: List<FeedbackMessage>): List<FeedbackMessage> {
        val messages = stored.toMutableList()
        if (
            stored.none {
                !it.owner &&
                    it.senderId == item.uid &&
                    it.text == item.message &&
                    Duration.between(item.createdAt, it.createdAt).abs() < Duration.ofSeconds(2)
            }
        ) {
            messages +=
                FeedbackMessage(
                    "legacy-initial:${item.id}",
                    item.id,
                    item.uid,
                    item.name,
                    false,
                    item.message,
                    item.createdAt,
                    legacy = true,
                )
        }
        if (
            stored.none { it.owner } && !item.ownerReply.isNullOrBlank() && item.repliedAt != null
        ) {
            messages +=
                FeedbackMessage(
                    "legacy-owner:${item.id}",
                    item.id,
                    item.repliedBy.orEmpty(),
                    "",
                    true,
                    item.ownerReply,
                    item.repliedAt,
                    legacy = true,
                )
        }
        return messages
            .distinctBy { it.legacy to it.id }
            .sortedWith(compareBy<FeedbackMessage> { it.createdAt }.thenBy { it.id })
    }

    fun creation(
        id: String,
        session: FeedbackSession,
        draft: FeedbackDraft,
        timestamp: Any,
    ): Fields {
        if (!feedbackId(id) || !draft.valid()) invalid()
        return mapOf(
            "id" to id,
            "userId" to session.uid,
            "userDisplayName" to session.displayName,
            "type" to draft.type.wire,
            "message" to draft.message,
            "status" to "open",
            "createdAt" to timestamp,
            "updatedAt" to timestamp,
            "lastMessageText" to draft.message,
            "lastMessageAt" to timestamp,
            "lastMessageByUserId" to session.uid,
            "lastMessageByRole" to "user",
            "unreadForOwner" to true,
            "unreadForUser" to false,
        )
    }

    fun matches(item: FeedbackItem, session: FeedbackSession, draft: FeedbackDraft) =
        item.uid == session.uid && item.type == draft.type && item.message == draft.message
}

data class FeedbackState(
    val session: FeedbackSession? = null,
    val audience: FeedbackAudience = FeedbackAudience.OWN,
    val selectedId: String? = null,
    val page: FeedbackPage? = null,
    val conversation: FeedbackConversation? = null,
    val loading: Boolean = false,
    val error: FeedbackFailure? = null,
    val draft: FeedbackDraft = FeedbackDraft(),
    val reply: String = "",
    val pending: Boolean = false,
    val actionError: FeedbackFailure? = null,
    val confirmedId: String? = null,
    val createRetryPending: Boolean = false,
    val replyRetryPending: Boolean = false,
    val inbox: FeedbackInboxOptions = FeedbackInboxOptions(),
    val inboxQueryRejected: Boolean = false,
)
