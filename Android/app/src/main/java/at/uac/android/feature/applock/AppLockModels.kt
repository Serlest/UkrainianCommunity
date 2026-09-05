package at.uac.android.feature.applock

import android.content.Context
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.personal.validDocumentId
import java.security.MessageDigest

data class AppLockSession(val uid: String, val revision: Long)

fun AuthSession.appLockSession(): AppLockSession? =
    identity?.takeUnless { it.anonymous }?.let { AppLockSession(it.uid, revision) }

enum class AppLockProblem {
    UNAVAILABLE,
    FAILED,
    LOCKED_OUT,
    STORAGE,
    BUSY,
    SIGN_OUT,
}

class AppLockException(val reason: AppLockProblem) : Exception(reason.name)

enum class AppLockResult {
    ACCEPTED,
    REJECTED,
    CANCELLED,
    UNAVAILABLE,
    LOCKED_OUT,
    ERROR,
}

data class AppLockAvailability(
    val strongBiometric: Boolean = false,
    val deviceCredential: Boolean = false,
) {
    val available: Boolean
        get() = strongBiometric || deviceCredential
}

enum class AppLockPromptPolicy {
    STRONG_OR_CREDENTIAL,
    STRONG_WITH_LEGACY_CREDENTIAL,
    STRONG_ONLY,
    LEGACY_CREDENTIAL,
    UNAVAILABLE,
}

fun appLockPromptPolicy(sdk: Int, availability: AppLockAvailability): AppLockPromptPolicy =
    when {
        sdk < 26 || !availability.available -> AppLockPromptPolicy.UNAVAILABLE
        sdk >= 30 -> AppLockPromptPolicy.STRONG_OR_CREDENTIAL
        availability.strongBiometric && availability.deviceCredential ->
            AppLockPromptPolicy.STRONG_WITH_LEGACY_CREDENTIAL
        availability.strongBiometric -> AppLockPromptPolicy.STRONG_ONLY
        else -> AppLockPromptPolicy.LEGACY_CREDENTIAL
    }

/** This is not a Firebase token, credential, or permission grant. */
class AppLockAttempt
internal constructor(internal val session: AppLockSession, internal val generation: Long) {
    override fun toString(): String = "AppLockAttempt([redacted])"
}

interface AppLockAuthenticating {
    fun availability(): AppLockAvailability

    suspend fun authenticate(attempt: AppLockAttempt, language: String): AppLockResult

    fun cancel(attempt: AppLockAttempt)
}

interface AppLockPreferences {
    fun enabled(uid: String): Boolean

    fun setEnabled(uid: String, enabled: Boolean)
}

fun appLockPreferenceKey(uid: String): String {
    require(validDocumentId(uid))
    val digest = MessageDigest.getInstance("SHA-256").digest(uid.toByteArray(Charsets.UTF_8))
    return "appLock.enabledAccounts.v1." +
        digest.joinToString("") { "%02x".format(it.toInt() and 0xff) }
}

/** Only a hashed-UID boolean is stored. No biometric, password, or Firebase session data. */
class DeviceAppLockPreferences(context: Context) : AppLockPreferences {
    private val preferences =
        context.applicationContext.getSharedPreferences("uac-device-lock", Context.MODE_PRIVATE)
    private val unconfirmed = mutableSetOf<String>()

    override fun enabled(uid: String): Boolean =
        try {
            val key = appLockPreferenceKey(uid)
            if (key in unconfirmed) throw AppLockException(AppLockProblem.STORAGE)
            preferences.getBoolean(key, false)
        } catch (_: Exception) {
            throw AppLockException(AppLockProblem.STORAGE)
        }

    override fun setEnabled(uid: String, enabled: Boolean) {
        val key = appLockPreferenceKey(uid)
        val confirmed =
            try {
                preferences.edit().putBoolean(key, enabled).commit()
            } catch (_: Exception) {
                false
            }
        if (!confirmed) {
            // commit(false) may still have changed SharedPreferences' in-memory value.
            unconfirmed.add(key)
            throw AppLockException(AppLockProblem.STORAGE)
        }
        unconfirmed.remove(key)
    }
}

data class AppLockState(
    val session: AppLockSession? = null,
    val enabled: Boolean = false,
    val unlocked: Boolean = false,
    val authenticating: Boolean = false,
    val foreground: Boolean = false,
    val availability: AppLockAvailability = AppLockAvailability(),
    val error: AppLockProblem? = null,
) {
    val locked: Boolean
        get() = session != null && enabled && !unlocked

    val needsPrivacyShield: Boolean
        get() = session != null && (enabled || authenticating)

    val blocksInteraction: Boolean
        get() = locked || authenticating || !foreground && needsPrivacyShield

    val canRoute: Boolean
        get() = foreground && !blocksInteraction

    /** Unknown account/revision must be covered until its local preference has been read. */
    fun forSession(authority: AppLockSession?): AppLockState =
        if (session == authority) this
        else AppLockState(session = authority, enabled = authority != null, foreground = foreground)
}
