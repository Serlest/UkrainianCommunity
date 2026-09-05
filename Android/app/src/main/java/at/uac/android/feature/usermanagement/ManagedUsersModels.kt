package at.uac.android.feature.usermanagement

import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.personal.validDocumentId
import java.text.Normalizer
import java.time.Instant
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

enum class ManagedUsersFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    OFFLINE,
    INDEX,
    INVALID,
    MISSING,
    STALE,
    UNKNOWN,
}

class ManagedUsersException(val failure: ManagedUsersFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

data class ManagedUser(
    val id: String,
    val displayName: String,
    val fullName: String,
    val email: String,
    val city: String,
    val region: String,
    val telegram: String,
    val globalRole: String,
    val accountStatus: String,
    val blockState: String,
    val warningCount: Long?,
    val banExpiresAt: Instant?,
    val statusReason: String,
    val createdAt: Instant?,
    val updatedAt: Instant?,
) {
    override fun toString() = "ManagedUser([redacted])"
}

data class ManagedUserSecurity(
    val targetId: String,
    val emailVerified: Boolean,
    val authDisabled: Boolean,
    val creationTime: Instant?,
    val lastSignInTime: Instant?,
    val providerIds: List<String>,
) {
    override fun toString() = "ManagedUserSecurity([redacted])"
}

/** Opaque, memory-only cursor. There is deliberately no serialization or document path API. */
abstract class ManagedUsersCursor
internal constructor(
    internal val owner: ModerationSession,
    internal val consumed: Int,
) {
    final override fun toString() = "ManagedUsersCursor([redacted])"
}

data class ManagedUsersPage(
    val users: List<ManagedUser>,
    val next: ManagedUsersCursor?,
    val consumed: Int,
    val capped: Boolean,
) {
    override fun toString() = "ManagedUsersPage([redacted], capped=$capped)"
}

data class ManagedUsersSearch(
    val users: List<ManagedUser>,
    val totalMatches: Int,
    val unavailable: Int,
) {
    override fun toString() = "ManagedUsersSearch([redacted])"
}

data class ManagedUsersQuery private constructor(val value: String) {
    override fun toString() = "ManagedUsersQuery([redacted])"

    companion object {
        fun from(input: String): ManagedUsersQuery {
            val normalized = ManagedUsersContract.normalizeQuery(input)
            if (normalized.length !in 2..120) ManagedUsersContract.fail(ManagedUsersFailure.INVALID)
            return ManagedUsersQuery(normalized)
        }
    }
}

enum class ManagedUsersFilter {
    ALL,
    ACTIVE,
    WARNED,
    RESTRICTED,
}

object ManagedUsersContract {
    const val PAGE_SIZE = 40
    const val MAX_USERS = 200
    const val SEARCH_LIMIT = 100
    const val MAX_QUERY_INPUT = 240
    private val earliestDate = Instant.parse("0001-01-01T00:00:00Z")
    private val latestDate = Instant.parse("9999-12-31T23:59:59.999999999Z")

    fun fail(failure: ManagedUsersFailure): Nothing = throw ManagedUsersException(failure)

    fun requireSession(session: ModerationSession?) {
        if (session == null) fail(ManagedUsersFailure.SIGN_IN)
        if (!session.ready) fail(ManagedUsersFailure.NOT_READY)
        if (!session.allowed) fail(ManagedUsersFailure.DENIED)
        requireId(session.uid)
    }

    fun requireId(id: String) {
        if (
            !validDocumentId(id) ||
                id != id.trim() ||
                id.length > 128 ||
                id.startsWith("__") && id.endsWith("__")
        )
            fail(ManagedUsersFailure.INVALID)
    }

    fun normalizeQuery(input: String): String =
        Normalizer.normalize(
                input.trim().lowercase(Locale.forLanguageTag("uk-UA")),
                Normalizer.Form.NFKD,
            )
            .replace(Regex("\\p{M}+"), "")
            .replace(Regex("[^\\p{L}\\p{N}]+"), " ")
            .trim()

    fun cursor(session: ModerationSession, cursor: ManagedUsersCursor?) {
        if (
            cursor != null &&
                (cursor.owner != session ||
                    cursor.consumed !in PAGE_SIZE until MAX_USERS ||
                    cursor.consumed % PAGE_SIZE != 0)
        )
            fail(ManagedUsersFailure.STALE)
    }

    fun user(documentId: String, fields: Map<String, Any?>): ManagedUser {
        requireId(documentId)
        // The stored legacy id never redirects the target away from its canonical document path.
        fun text(key: String, maximum: Int = 500): String {
            val value = (fields[key] as? String).orEmpty()
            return if (value.length > maximum) value.take(maximum) + "…" else value
        }
        fun status(key: String, legacy: String): String =
            when {
                !fields.containsKey(key) -> legacy
                fields[key] is String -> text(key).ifBlank { legacy }
                else -> "unknown"
            }
        val legacyBlock =
            when {
                !fields.containsKey("isBlocked") || fields["isBlocked"] == false -> "active"
                fields["isBlocked"] == true -> "suspendedUntil"
                else -> "unknown"
            }
        val block = status("blockState", legacyBlock)
        val legacyAccount =
            when (block) {
                in restrictedStates -> "suspendedUntil"
                "active",
                "warned" -> "active"
                else -> "unknown"
            }
        val warnings =
            (fields["warningCount"] as? Number)?.let { value ->
                value.toLong().takeIf { it >= 0 && value.toDouble() == it.toDouble() }
            }
        return ManagedUser(
            documentId,
            text("displayName").ifBlank { text("fullName") },
            text("fullName"),
            text("email"),
            text("city"),
            text("selectedFederalState"),
            text("telegramUsername"),
            status("globalRole", "user"),
            status("accountStatus", legacyAccount),
            block,
            warnings,
            fields["banExpiresAt"] as? Instant,
            text("statusReason", 2_000),
            fields["createdAt"] as? Instant,
            fields["updatedAt"] as? Instant,
        )
    }

    fun searchIds(data: Any?): Pair<List<String>, Int> {
        val body = data as? Map<*, *> ?: fail(ManagedUsersFailure.INVALID)
        val raw = body["userIds"] as? List<*> ?: fail(ManagedUsersFailure.INVALID)
        if (raw.size > SEARCH_LIMIT) fail(ManagedUsersFailure.INVALID)
        val ids = raw.map { (it as? String ?: fail(ManagedUsersFailure.INVALID)).also(::requireId) }
        if (ids.distinct().size != ids.size) fail(ManagedUsersFailure.INVALID)
        val count = body["totalMatches"] as? Number ?: fail(ManagedUsersFailure.INVALID)
        val total = count.toLong()
        if (
            count.toDouble() != total.toDouble() ||
                total !in ids.size.toLong()..Int.MAX_VALUE.toLong()
        )
            fail(ManagedUsersFailure.INVALID)
        return ids to total.toInt()
    }

    fun security(target: String, data: Any?): ManagedUserSecurity {
        requireId(target)
        val body = data as? Map<*, *> ?: fail(ManagedUsersFailure.INVALID)
        if (body["targetUserId"] != target) fail(ManagedUsersFailure.INVALID)
        fun date(key: String): Instant? {
            val value = body[key] ?: return null
            if (value !is String || value.length > 100) fail(ManagedUsersFailure.INVALID)
            val parsed = runCatching {
                ZonedDateTime.parse(value, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant()
            }
                .recoverCatching { Instant.parse(value) }
                .getOrElse { fail(ManagedUsersFailure.INVALID) }
            if (parsed < earliestDate || parsed > latestDate) fail(ManagedUsersFailure.INVALID)
            return parsed
        }
        val providers = body["providerIds"] as? List<*> ?: fail(ManagedUsersFailure.INVALID)
        if (providers.size > 32) fail(ManagedUsersFailure.INVALID)
        val typed = providers.map {
            (it as? String)?.takeIf { value ->
                value.isNotBlank() && value.length <= 128 && !value.any(Char::isISOControl)
            } ?: fail(ManagedUsersFailure.INVALID)
        }
        if (typed.distinct().size != typed.size) fail(ManagedUsersFailure.INVALID)
        return ManagedUserSecurity(
            target,
            body["emailVerified"] as? Boolean ?: fail(ManagedUsersFailure.INVALID),
            body["authDisabled"] as? Boolean ?: fail(ManagedUsersFailure.INVALID),
            date("creationTime"),
            date("lastSignInTime"),
            typed.sorted(),
        )
    }

    private val restrictedStates =
        setOf(
            "suspendedUntil",
            "blocked",
            "temporarilyBanned",
            "bannedPermanent",
            "permanentlyBanned",
            "deactivated",
        )

    fun matches(user: ManagedUser, filter: ManagedUsersFilter): Boolean =
        when (filter) {
            ManagedUsersFilter.ALL -> true
            ManagedUsersFilter.ACTIVE ->
                user.accountStatus == "active" && user.blockState == "active"
            ManagedUsersFilter.WARNED ->
                user.accountStatus == "warned" || user.blockState == "warned"
            ManagedUsersFilter.RESTRICTED ->
                user.accountStatus in restrictedStates || user.blockState in restrictedStates
        }
}
