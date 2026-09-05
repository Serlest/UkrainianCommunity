package at.uac.android.feature.accountdeletion

import java.time.Duration
import java.time.Instant
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Deliberately independent of legal, verified, active and profile gates: the server supports
 * partial-deletion recovery.
 */
data class AccountDeletionSession(val uid: String, val revision: Long) {
    init {
        require(
            uid.isNotBlank() &&
                uid.length <= 128 &&
                uid == uid.trim() &&
                uid !in setOf(".", "..") &&
                '/' !in uid &&
                uid.none(Char::isISOControl)
        )
    }

    override fun toString() = "AccountDeletionSession([redacted], revision=$revision)"
}

enum class AccountDeletionFailure {
    SIGN_IN,
    LOCAL_ONLY,
    PASSWORD_REQUIRED,
    INVALID_CREDENTIALS,
    RECENT_AUTH_REQUIRED,
    PLATFORM_OWNER,
    ORGANIZATION_OWNER,
    MFA_REQUIRED,
    MFA_INVALID,
    MFA_UNSUPPORTED,
    DENIED,
    PRECONDITION,
    OFFLINE,
    RATE_LIMITED,
    INVALID,
    CHECKPOINT,
    UNCONFIRMED,
}

class AccountDeletionException(
    val failure: AccountDeletionFailure,
    cause: Throwable? = null,
    val freshnessDiagnostic: AccountDeletionFreshnessDiagnostic? = null,
) : Exception(failure.name, cause)

enum class AccountDeletionFreshnessStage {
    SDK_REAUTH,
    CLAIM_PARSE,
    FIRST_CLOCK_CHECK,
    POST_POLICY_CLOCK_CHECK,
    CALLABLE,
}

enum class AccountDeletionFreshnessReason {
    SDK_REJECTED,
    MISSING_OR_NON_NUMERIC,
    INVALID_INTEGER,
    FUTURE,
    EXPIRED,
    WAIT_LIMIT_REACHED,
    SERVER_REJECTED,
}

/** Memory-only failure metadata. No identity, claim, wall-clock timestamp or credential. */
data class AccountDeletionFreshnessDiagnostic(
    val stage: AccountDeletionFreshnessStage,
    val reason: AccountDeletionFreshnessReason,
    /** Signed proof age, saturated at +/-24 hours. Sub-ms FUTURE can have ageMillis == 0. */
    val ageMillis: Long? = null,
) {
    companion object {
        internal const val MAX_AGE_MILLIS = 86_400_000L

        internal fun rejectedClock(
            stage: AccountDeletionFreshnessStage,
            authenticatedAt: Instant,
            sampledNow: Instant,
        ): AccountDeletionFreshnessDiagnostic {
            val future = authenticatedAt.isAfter(sampledNow)
            val age = runCatching {
                Duration.between(authenticatedAt, sampledNow).toMillis()
            }
                .getOrElse { if (future) Long.MIN_VALUE else Long.MAX_VALUE }
                .coerceIn(-MAX_AGE_MILLIS, MAX_AGE_MILLIS)
            return AccountDeletionFreshnessDiagnostic(
                stage,
                if (future) AccountDeletionFreshnessReason.FUTURE
                else AccountDeletionFreshnessReason.EXPIRED,
                age,
            )
        }
    }
}

/** Preserve typed metadata through existing exception wrappers without exposing their messages. */
internal fun Throwable.accountDeletionFreshnessDiagnostic(): AccountDeletionFreshnessDiagnostic? {
    var current: Throwable? = this
    repeat(8) {
        val failure = current as? AccountDeletionException
        if (failure?.failure == AccountDeletionFailure.RECENT_AUTH_REQUIRED) {
            failure.freshnessDiagnostic?.let {
                return it
            }
        }
        current = current?.cause
    }
    return null
}

/**
 * Null ownership is not a client authorization. The unchanged callable always checks owned
 * organizations before deleting anything.
 */
data class AccountDeletionPolicy(
    val platformOwner: Boolean,
    val requiresTotp: Boolean,
    val ownsOrganization: Boolean?,
    val profileMissing: Boolean = false,
    val deletionInProgress: Boolean = false,
)

data class AccountDeletionProof(val uid: String, val authenticatedAt: Instant, val totp: Boolean) {
    override fun toString() = "AccountDeletionProof([redacted])"

    fun recent(now: Instant): Boolean =
        !authenticatedAt.isAfter(now) && authenticatedAt.plusSeconds(240).isAfter(now)
}

data class AccountDeletionFactor(val id: String, val label: String)

interface AccountDeletionChallenge {
    val factors: List<AccountDeletionFactor>

    suspend fun resolve(factorId: String, code: String): AccountDeletionProof
}

class AccountDeletionChallengeRequired(val challenge: AccountDeletionChallenge) :
    Exception("Account deletion requires a real second factor")

enum class AccountDeletionConfirmation {
    SERVER_RECEIPT,
    AUTH_IDENTITY_ABSENT,
}

data class AccountDeletionReceipt(
    val confirmedAt: Instant,
    val confirmation: AccountDeletionConfirmation,
    val journalCleared: Boolean = true,
)

enum class AccountDeletionIdentityStatus {
    ABSENT,
    PRESENT,
    PARTIAL,
}

interface AccountDeletionSource {
    suspend fun policy(uid: String): AccountDeletionPolicy

    suspend fun reauthenticate(uid: String, password: String): AccountDeletionProof

    suspend fun delete(uid: String): AccountDeletionReceipt

    suspend fun status(uid: String): AccountDeletionIdentityStatus
}

sealed interface AccountDeletionStep {
    data class Challenge(val value: AccountDeletionChallenge) : AccountDeletionStep

    data class Completed(val receipt: AccountDeletionReceipt) : AccountDeletionStep
}

/**
 * Must hold the application's real Auth identity mutex until every SDK/HTTP task has actually
 * settled.
 */
interface AccountDeletionGate {
    suspend fun <T> withSession(session: AccountDeletionSession, action: suspend () -> T): T
}

object DeniedAccountDeletionGate : AccountDeletionGate {
    override suspend fun <T> withSession(
        session: AccountDeletionSession,
        action: suspend () -> T,
    ): T = throw AccountDeletionException(AccountDeletionFailure.SIGN_IN)
}

class AccountDeletionAttempt {
    private val cancelled = AtomicBoolean(false)

    fun cancelBeforeSubmission() {
        cancelled.set(true)
    }

    val cancellationRequested
        get() = cancelled.get()
}

enum class AccountDeletionPhase {
    IDLE,
    CHECKING,
    REAUTHENTICATING,
    MFA,
    DELETING,
    RECONCILING,
}

data class AccountDeletionState(
    val session: AccountDeletionSession? = null,
    val phase: AccountDeletionPhase = AccountDeletionPhase.IDLE,
    val policy: AccountDeletionPolicy? = null,
    val factors: List<AccountDeletionFactor> = emptyList(),
    val error: AccountDeletionFailure? = null,
    val submittedAt: Instant? = null,
    val status: AccountDeletionIdentityStatus? = null,
    val retryAllowed: Boolean = false,
    val receipt: AccountDeletionReceipt? = null,
    val cancelRequested: Boolean = false,
    val freshnessDiagnostic: AccountDeletionFreshnessDiagnostic? = null,
) {
    val busy
        get() = phase !in setOf(AccountDeletionPhase.IDLE, AccountDeletionPhase.MFA)

    val unresolved
        get() = submittedAt != null && receipt == null

    fun forSession(authority: AccountDeletionSession?): AccountDeletionState =
        if (session == authority) this else AccountDeletionState(session = authority)
}

object AccountDeletionContract {
    const val REQUEST_TIMEOUT_SECONDS = 300L

    fun receipt(value: Any?): AccountDeletionReceipt {
        val fields = value as? Map<*, *> ?: invalid()
        if (fields["status"] != "deleted") invalid()
        val date =
            (fields["completedAt"] as? String)?.let {
                runCatching { Instant.parse(it) }.getOrNull()
            } ?: invalid()
        if (date.epochSecond <= 0) invalid()
        return AccountDeletionReceipt(date, AccountDeletionConfirmation.SERVER_RECEIPT)
    }

    private fun invalid(): Nothing =
        throw AccountDeletionException(AccountDeletionFailure.UNCONFIRMED)
}
