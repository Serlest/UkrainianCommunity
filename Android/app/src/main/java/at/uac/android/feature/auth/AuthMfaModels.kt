package at.uac.android.feature.auth

import java.net.URI

data class AuthTotpFactor(val id: String, val name: String, val enrolledAtEpochSeconds: Long = 0)

/** Sensitive, memory-only presentation. Never serialize this or log its fields. */
class AuthTotpSetup(
    val sharedKey: String,
    val otpAuthUri: String,
    val deadlineMillis: Long,
    val digits: Int = 6,
    val intervalSeconds: Int = 30,
) {
    override fun toString() = "AuthTotpSetup([redacted])"
}

data class AuthMfaState(
    val factors: List<AuthTotpFactor> = emptyList(),
    val loaded: Boolean = false,
    val challenge: Boolean = false,
    val setup: AuthTotpSetup? = null,
    val unconfirmed: Boolean = false,
) {
    val interactive: Boolean
        get() = challenge || setup != null
}

/** SDK resolver and session stay opaque and application-scoped, never in a Bundle. */
interface AuthMfaChallenge {
    val factors: List<AuthTotpFactor>

    suspend fun resolve(factorId: String, code: String): AuthIdentity
}

class AuthMfaChallengeRequired(val challenge: AuthMfaChallenge) :
    Exception("MFA challenge required")

interface AuthTotpEnrollment {
    val setup: AuthTotpSetup

    suspend fun complete(code: String)
}

interface AuthSecurityBackend {
    suspend fun factors(uid: String): List<AuthTotpFactor>

    suspend fun reauthenticate(uid: String, password: String)

    suspend fun beginEnrollment(uid: String): AuthTotpEnrollment

    suspend fun unenroll(uid: String, factorId: String)
}

interface AuthMfaActivator {
    suspend fun activate(uid: String)
}

internal fun totpCode(value: String, digits: Int = 6): String {
    val code = value.trim().replace(" ", "")
    if (digits !in 6..8 || code.length != digits || code.any { it !in '0'..'9' }) {
        throw AuthException(AuthProblem.MFA_CODE_INVALID)
    }
    return code
}

internal fun safeOtpAuthUri(value: String): Boolean = runCatching {
    val uri = URI(value)
    value.length <= 4096 &&
        uri.scheme == "otpauth" &&
        uri.host == "totp" &&
        uri.userInfo == null &&
        uri.port == -1 &&
        uri.fragment == null &&
        !uri.rawPath.isNullOrBlank()
}
    .getOrDefault(false)

internal fun canRemoveTotp(
    profile: AuthProfile,
    factors: List<AuthTotpFactor>,
    factorId: String,
): Boolean =
    factors.any { it.id == factorId } &&
        !(profile.privileged && profile.requiresMultiFactorAuth && factors.size <= 1)
