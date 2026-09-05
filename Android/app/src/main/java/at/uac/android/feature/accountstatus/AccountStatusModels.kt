package at.uac.android.feature.accountstatus

import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.canAcknowledgeAccountStatus
import java.time.Instant

enum class AccountStatusKind {
    WARNED,
    SUSPENDED,
    BANNED,
    DEACTIVATED,
    RESTORED,
}

/** Raw, lossless displayed-version fence. Display normalization must never change this value. */
data class AccountStatusVersion(
    val uid: String,
    val status: String,
    val blockState: String,
    val updatedAt: Instant,
    val reason: String?,
    val message: String?,
    val expiresAt: Instant?,
) {
    val kind: AccountStatusKind?
        get() =
            restriction(status)
                ?: restriction(blockState)
                ?: when (status) {
                    "warned" -> AccountStatusKind.WARNED
                    "active" -> AccountStatusKind.RESTORED.takeIf { blockState == "active" }
                    else -> null
                }

    private fun restriction(value: String): AccountStatusKind? =
        when (value) {
            "suspendedUntil",
            "temporarilyBanned",
            "blocked" -> AccountStatusKind.SUSPENDED
            "bannedPermanent",
            "permanentlyBanned" -> AccountStatusKind.BANNED
            "deactivated" -> AccountStatusKind.DEACTIVATED
            else -> null
        }

    override fun toString(): String = "AccountStatusVersion(kind=$kind, privateFields=redacted)"

    val requiresSignOut: Boolean
        get() =
            kind in
                setOf(
                    AccountStatusKind.SUSPENDED,
                    AccountStatusKind.BANNED,
                    AccountStatusKind.DEACTIVATED,
                )
}

data class AccountStatusObservation(
    val version: AccountStatusVersion?,
    val acknowledgedAt: Instant?,
) {
    val notice: AccountStatusVersion?
        get() = version?.takeIf {
            it.kind != null && (acknowledgedAt == null || acknowledgedAt < it.updatedAt)
        }

    fun confirms(expected: AccountStatusVersion): Boolean =
        version == expected && acknowledgedAt != null && acknowledgedAt >= expected.updatedAt
}

data class AccountStatusSession(
    val uid: String,
    val revision: Long,
    val observation: AccountStatusObservation,
    val canAcknowledge: Boolean,
    val verified: Boolean,
    val needsMfa: Boolean = false,
    val role: String = "user",
    val totpAuthenticated: Boolean = false,
)

fun AuthSession.accountStatusScope(): AccountStatusSession? {
    val user = identity?.takeUnless { it.anonymous } ?: return null
    val own = profile?.takeIf { it.uid == user.uid } ?: return null
    if (
        busy ||
            mfa.interactive ||
            mfa.unconfirmed ||
            stage !in setOf(AuthStage.AUTHENTICATED, AuthStage.VERIFICATION_PENDING)
    )
        return null
    val version =
        own.statusUpdatedAt?.let {
            AccountStatusVersion(
                user.uid,
                own.accountStatus,
                own.blockState,
                it,
                own.statusReason,
                own.statusMessage,
                own.banExpiresAt,
            )
        }
    return AccountStatusSession(
        user.uid,
        revision,
        AccountStatusObservation(version, own.statusAcknowledgedAt),
        canAcknowledgeAccountStatus(),
        user.emailVerified,
        gate == AuthGate.MFA_REQUIRED,
        own.globalRole,
        totpAuthenticated,
    )
}

enum class AccountStatusFailure {
    DENIED,
    INVALID,
    STALE,
    OFFLINE,
    UNCONFIRMED,
    SIGN_OUT_FAILED,
    UNKNOWN,
}

class AccountStatusException(val failure: AccountStatusFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

enum class AccountStatusReconciliation {
    CONFIRMED,
    NOT_CONFIRMED,
    CHANGED,
}

internal fun statusFailure(error: Throwable): AccountStatusFailure =
    generateSequence(error) { it.cause }
        .filterIsInstance<AccountStatusException>()
        .firstOrNull()
        ?.failure ?: AccountStatusFailure.UNKNOWN

internal fun statusRequire(condition: Boolean, reason: AccountStatusFailure) {
    if (!condition) throw AccountStatusException(reason)
}
