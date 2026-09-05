package at.uac.android.feature.platformrolemanagement

import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant

/** Platform App Admin only. Neither owner transfer nor organization roles belong here. */
enum class PlatformRoleAction(val callable: String, val previousRole: String, val newRole: String) {
    ASSIGN("assignAppAdmin", "user", "admin"),
    REMOVE("removeAppAdmin", "admin", "user"),
}

enum class PlatformRoleFailure {
    ACCESS,
    INVALID,
    STALE,
    JOURNAL,
    PENDING,
    OFFLINE,
    UNCONFIRMED,
}

class PlatformRoleException(val failure: PlatformRoleFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

/** Memory-only policy projection, NOT a raw version or authorization to dispatch. */
data class PlatformRoleTarget(val targetId: String, val role: String, val usableProfile: Boolean) {
    override fun toString() = "PlatformRoleTarget([redacted])"
}

/** Advisory target metadata; a future SDK source must fetch it fresh for assignment only. */
data class PlatformRoleTargetAuth(
    val targetId: String,
    val emailVerified: Boolean,
    val disabled: Boolean,
) {
    override fun toString() = "PlatformRoleTargetAuth([redacted])"
}

/** Parsed actual response only; not a durable operation receipt or a Firestore commit version. */
data class PlatformRoleResponse(
    val targetId: String,
    val previousRole: String,
    val newRole: String,
    val wireTime: Instant,
) {
    override fun toString() = "PlatformRoleResponse([redacted])"
}

/**
 * Pure local policy/wire contract. This object never dispatches or grants SDK authorization.
 * Presentation readiness never replaces actual SDK identity, profile, activated MFA and TOTP.
 */
object PlatformRoleContract {
    private val minimumTime = Instant.parse("0001-01-01T00:00:00Z")
    private val maximumTime = Instant.parse("9999-12-31T23:59:59.999Z")

    fun fail(value: PlatformRoleFailure): Nothing = throw PlatformRoleException(value)

    fun id(value: String): Boolean =
        value.length in 1..128 &&
            value !in setOf(".", "..") &&
            !(value.startsWith("__") && value.endsWith("__")) &&
            value.none { it == '/' || it.isISOControl() } &&
            value.trim(::serverWhitespace) == value &&
            validUnicode(value)

    /** Matches platformRoleManagement.ts, including unknown/legacy roles normalizing to user. */
    fun normalizedRole(value: Any?): String =
        when (value) {
            "owner" -> "owner"
            "admin" -> "admin"
            else -> "user"
        }

    fun target(targetId: String, fields: Map<String, Any?>): PlatformRoleTarget {
        if (!id(targetId)) fail(PlatformRoleFailure.INVALID)
        // Canonical document path is authority. Stored id/contacts never redirect the target.
        val active = setOf("active", "warned")
        return PlatformRoleTarget(
            targetId,
            normalizedRole(fields["globalRole"]),
            (fields["accountStatus"] ?: "active") in active &&
                (fields["blockState"] ?: "active") in active,
        )
    }

    fun targetAuth(targetId: String, data: Any?): PlatformRoleTargetAuth {
        if (!id(targetId)) fail(PlatformRoleFailure.INVALID)
        val map = data as? Map<*, *> ?: fail(PlatformRoleFailure.INVALID)
        if (map["targetUserId"] != targetId) fail(PlatformRoleFailure.INVALID)
        return PlatformRoleTargetAuth(
            targetId,
            map["emailVerified"] as? Boolean ?: fail(PlatformRoleFailure.INVALID),
            map["authDisabled"] as? Boolean ?: fail(PlatformRoleFailure.INVALID),
        )
    }

    fun requireSession(session: ModerationSession) {
        if (!session.ready || session.role != "owner" || !id(session.uid))
            fail(PlatformRoleFailure.ACCESS)
    }

    fun requireTarget(
        session: ModerationSession,
        target: PlatformRoleTarget,
        action: PlatformRoleAction,
        auth: PlatformRoleTargetAuth?,
    ) {
        requireTargetRole(session, target, action)
        // Removal intentionally does NOT depend on target Auth existence/metadata/usability.
        if (
            action == PlatformRoleAction.ASSIGN &&
                (!target.usableProfile ||
                    auth == null ||
                    auth.targetId != target.targetId ||
                    !auth.emailVerified ||
                    auth.disabled)
        )
            fail(PlatformRoleFailure.STALE)
    }

    /** Pure role veto before any assignment-only metadata lookup. */
    fun requireTargetRole(
        session: ModerationSession,
        target: PlatformRoleTarget,
        action: PlatformRoleAction,
    ) {
        requireSession(session)
        if (!id(target.targetId) || target.role !in setOf("owner", "admin", "user"))
            fail(PlatformRoleFailure.INVALID)
        if (session.uid == target.targetId || target.role == "owner")
            fail(PlatformRoleFailure.ACCESS)
        if (target.role != action.previousRole) fail(PlatformRoleFailure.STALE)
    }

    fun normalizeReason(value: String): String {
        if (value.length > LocalCallableProtocol.MAX_REQUEST_BYTES || !validUnicode(value))
            fail(PlatformRoleFailure.INVALID)
        val result = value.trim(::serverWhitespace)
        if (result.isEmpty() || result.any { it.isISOControl() && it !in "\n\r\t" })
            fail(PlatformRoleFailure.INVALID)
        return result
    }

    /** Exact existing request. No invented expectedVersion/operationId/idempotency fields. */
    fun payload(targetId: String, reason: String): Map<String, String> {
        if (!id(targetId)) fail(PlatformRoleFailure.INVALID)
        val result = mapOf("targetUserId" to targetId, "reason" to normalizeReason(reason))
        try {
            LocalCallableProtocol.request(result)
        } catch (error: Exception) {
            throw PlatformRoleException(PlatformRoleFailure.INVALID, error)
        }
        return result
    }

    /** Only actual successful awaited call data, never an error or a matching profile/audit. */
    fun response(targetId: String, action: PlatformRoleAction, data: Any?): PlatformRoleResponse {
        if (!id(targetId)) fail(PlatformRoleFailure.INVALID)
        val map = data as? Map<*, *> ?: fail(PlatformRoleFailure.UNCONFIRMED)
        if (
            map.keys != setOf("targetUserId", "previousGlobalRole", "newGlobalRole", "updatedAt") ||
                map["targetUserId"] != targetId ||
                map["previousGlobalRole"] != action.previousRole ||
                map["newGlobalRole"] != action.newRole
        )
            fail(PlatformRoleFailure.UNCONFIRMED)
        val text = map["updatedAt"] as? String ?: fail(PlatformRoleFailure.UNCONFIRMED)
        val time =
            text.takeIf { it.length <= 40 }?.let { runCatching { Instant.parse(it) }.getOrNull() }
                ?: fail(PlatformRoleFailure.UNCONFIRMED)
        if (time !in minimumTime..maximumTime || time.nano % 1_000_000 != 0)
            fail(PlatformRoleFailure.UNCONFIRMED)
        return PlatformRoleResponse(targetId, action.previousRole, action.newRole, time)
    }

    private fun serverWhitespace(value: Char): Boolean =
        value in " \t\n\r\u000B\u000C\u00A0\u1680\u2028\u2029\u202F\u205F\u3000\uFEFF" ||
            value in '\u2000'..'\u200A'

    private fun validUnicode(value: String): Boolean {
        var index = 0
        while (index < value.length) {
            val character = value[index++]
            if (character.isHighSurrogate()) {
                if (index >= value.length || !value[index++].isLowSurrogate()) return false
            } else if (character.isLowSurrogate()) return false
        }
        return true
    }
}
