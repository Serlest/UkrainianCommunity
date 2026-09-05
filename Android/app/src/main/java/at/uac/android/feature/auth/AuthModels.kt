package at.uac.android.feature.auth

import java.net.URI
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.time.Instant

enum class AuthStage {
    RESTORING,
    AUTHENTICATING,
    GUEST,
    VERIFICATION_PENDING,
    MFA_CHALLENGE,
    AUTHENTICATED,
    SESSION_UNAVAILABLE,
}

enum class AuthGate {
    READY,
    RESTRICTED,
    MFA_REQUIRED,
    LEGAL_REQUIRED,
    LEGAL_UNAVAILABLE,
}

enum class AuthProblem {
    INVALID_EMAIL,
    PASSWORD_REQUIRED,
    WEAK_PASSWORD,
    PASSWORD_MISMATCH,
    NAME_REQUIRED,
    REGION_REQUIRED,
    CONSENT_REQUIRED,
    INVALID_TELEGRAM,
    INVALID_CREDENTIALS,
    EMAIL_EXISTS,
    NETWORK,
    RATE_LIMITED,
    DISABLED,
    OPERATION_DISABLED,
    PROFILE_MISSING,
    INVALID_PROFILE,
    PERMISSION_DENIED,
    SESSION_CHANGED,
    VERIFICATION_PENDING,
    CODE_INVALID,
    CODE_EXPIRED,
    SECOND_FACTOR_REQUIRED,
    LOCAL_ONLY,
    LEGAL_CHANGED,
    LEGAL_UNCONFIRMED,
    MFA_CODE_INVALID,
    MFA_EXPIRED,
    MFA_UNSUPPORTED,
    MFA_ALREADY_ENROLLED,
    MFA_LAST_FACTOR,
    MFA_UNCONFIRMED,
    RECENT_LOGIN_REQUIRED,
    UNKNOWN,
}

enum class AuthNotice {
    VERIFICATION_SENT,
    RESET_SENT,
    PASSWORD_CHANGED,
    EMAIL_VERIFIED,
    LEGAL_ACCEPTED,
    MFA_ENROLLED,
    MFA_REMOVED,
    MFA_VERIFIED,
    MFA_ACTIVATED,
}

class AuthException(val problem: AuthProblem) : Exception(problem.name)

data class AuthIdentity(
    val uid: String,
    val email: String,
    val emailVerified: Boolean,
    val anonymous: Boolean = false,
)

data class AuthProfile(
    val uid: String,
    val email: String,
    val displayName: String,
    val fullName: String = displayName,
    val city: String = "",
    val bio: String = "",
    val telegramUsername: String? = null,
    val region: String = "",
    val avatarUrl: String? = null,
    val globalRole: String = "user",
    val accountStatus: String = "active",
    val blockState: String = "active",
    val requiresMultiFactorAuth: Boolean = false,
    val acceptedTermsVersion: String? = null,
    val acceptedPrivacyVersion: String? = null,
    val statusReason: String? = null,
    val statusMessage: String? = null,
    val statusUpdatedAt: Instant? = null,
    val statusAcknowledgedAt: Instant? = null,
    val banExpiresAt: Instant? = null,
) {
    val active: Boolean
        get() =
            accountStatus in setOf("active", "warned") && blockState in setOf("active", "warned")

    val privileged: Boolean
        get() = globalRole in setOf("owner", "admin")
}

data class AuthLegalDocument(
    val type: String,
    val version: String,
    val requiresAcceptance: Boolean,
    val titles: Map<String, String>,
    val texts: Map<String, String>,
) {
    fun title(language: String): String = titles[language] ?: titles["de"] ?: type

    fun text(language: String): String = texts[language] ?: texts["de"] ?: ""
}

data class AuthSession(
    val stage: AuthStage = AuthStage.RESTORING,
    val identity: AuthIdentity? = null,
    val profile: AuthProfile? = null,
    val revision: Long = 0,
    val gate: AuthGate = AuthGate.READY,
    val legalDocuments: List<AuthLegalDocument> = emptyList(),
    val busy: Boolean = false,
    val error: AuthProblem? = null,
    val notice: AuthNotice? = null,
    val resendAfterMillis: Long = 0,
    val totpAuthenticated: Boolean = false,
    val legalReceipts: List<AuthLegalReceipt> = emptyList(),
    val mfa: AuthMfaState = AuthMfaState(),
    val localPasswordProof: AuthPasswordProof? = null,
    val deletionRecovery: Boolean = false,
) {
    val readyForActions: Boolean
        get() =
            stage == AuthStage.AUTHENTICATED &&
                identity?.emailVerified == true &&
                identity.uid == profile?.uid &&
                gate == AuthGate.READY &&
                !busy &&
                !mfa.interactive &&
                !mfa.unconfirmed
}

/** Only the one-field own status acknowledgement; not a grant for other account actions. */
fun AuthSession.canAcknowledgeAccountStatus(): Boolean =
    identity?.uid?.let { permitsStatusAcknowledgement(it, revision) } == true

/** Exact-scope part is also rechecked inside the serialized AuthStore gate. */
internal fun AuthSession.permitsStatusAcknowledgement(uid: String, revision: Long): Boolean =
    this.revision == revision &&
        stage == AuthStage.AUTHENTICATED &&
        identity?.uid == uid &&
        !identity.anonymous &&
        identity.emailVerified &&
        profile?.uid == uid &&
        profile.active &&
        gate in setOf(AuthGate.READY, AuthGate.LEGAL_REQUIRED, AuthGate.LEGAL_UNAVAILABLE) &&
        (!profile.privileged || (profile.requiresMultiFactorAuth && totpAuthenticated)) &&
        !busy &&
        !mfa.interactive &&
        !mfa.unconfirmed

data class AuthRegistration(
    val email: String,
    val displayName: String,
    val region: String,
    val telegramUsername: String = "",
    val acceptedTerms: Boolean = false,
    val acceptedPrivacy: Boolean = false,
    val minimumAgeConfirmed: Boolean = false,
    val analyticsOptIn: Boolean = false,
    val termsVersion: String = TERMS_VERSION,
    val privacyVersion: String = PRIVACY_VERSION,
) {
    companion object {
        const val TERMS_VERSION = "2026.10"
        const val PRIVACY_VERSION = "2026.12"
        const val MINIMUM_AGE_VERSION = "14+"
    }
}

object AuthValidation {
    private val emailPattern = Regex("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")
    val regions =
        setOf(
            "burgenland",
            "kaernten",
            "niederoesterreich",
            "oberoesterreich",
            "salzburg",
            "steiermark",
            "tirol",
            "vorarlberg",
            "wien",
        )

    fun email(value: String): AuthProblem? =
        if (value.trim().length <= 254 && emailPattern.matches(value.trim())) null
        else AuthProblem.INVALID_EMAIL

    fun password(value: String): AuthProblem? =
        when {
            value.isEmpty() -> AuthProblem.PASSWORD_REQUIRED
            value.codePointCount(0, value.length) !in 10..128 -> AuthProblem.WEAK_PASSWORD
            else -> null
        }

    fun registration(draft: AuthRegistration, password: String, repeated: String): AuthProblem? =
        email(draft.email)
            ?: password(password)
            ?: when {
                password != repeated -> AuthProblem.PASSWORD_MISMATCH
                draft.displayName.trim().length !in 1..160 -> AuthProblem.NAME_REQUIRED
                draft.region !in regions -> AuthProblem.REGION_REQUIRED
                !draft.acceptedTerms || !draft.acceptedPrivacy || !draft.minimumAgeConfirmed ->
                    AuthProblem.CONSENT_REQUIRED
                draft.telegramUsername.trim().removePrefix("@").let {
                    it.isNotEmpty() && !Regex("[A-Za-z0-9_]{5,32}").matches(it)
                } -> AuthProblem.INVALID_TELEGRAM
                draft.termsVersion.isBlank() || draft.privacyVersion.isBlank() ->
                    AuthProblem.CONSENT_REQUIRED
                else -> null
            }
}

/** Only pasted local action links or opaque codes are accepted in this isolated build. */
object LocalAuthActionCode {
    fun parse(value: String, expectedMode: String): String {
        val trimmed = value.trim()
        if (Regex("[A-Za-z0-9_-]{4,2048}").matches(trimmed)) return trimmed
        val uri =
            try {
                URI(trimmed)
            } catch (_: Exception) {
                throw AuthException(AuthProblem.CODE_INVALID)
            }
        if (
            uri.scheme != "http" ||
                uri.host !in setOf("127.0.0.1", "localhost", "10.0.2.2") ||
                uri.port != 9098 ||
                uri.userInfo != null ||
                uri.fragment != null
        )
            throw AuthException(AuthProblem.CODE_INVALID)
        val values =
            uri.rawQuery.orEmpty().split('&').mapNotNull { part ->
                val pair = part.split('=', limit = 2)
                if (pair.size == 2)
                    pair[0] to URLDecoder.decode(pair[1], StandardCharsets.UTF_8.name())
                else null
            }
        if (
            values.count { it.first == "oobCode" } != 1 ||
                values.count { it.first == "mode" } != 1 ||
                values.firstOrNull { it.first == "mode" }?.second != expectedMode
        )
            throw AuthException(AuthProblem.CODE_INVALID)
        return values
            .first { it.first == "oobCode" }
            .second
            .takeIf { Regex("[A-Za-z0-9_-]{4,2048}").matches(it) }
            ?: throw AuthException(AuthProblem.CODE_INVALID)
    }
}
