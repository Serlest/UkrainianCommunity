package at.uac.android.feature.push

import java.security.MessageDigest

data class PushSession(val uid: String, val revision: Long, val verifiedActive: Boolean)

data class PushGate(val consent: Boolean, val postNotificationsGranted: Boolean) {
    val open: Boolean
        get() = consent && postNotificationsGranted
}

enum class PushFailure {
    SIGN_IN,
    NOT_READY,
    PERMISSION,
    STALE_SESSION,
    CROSS_ACCOUNT,
    INVALID_INSTALLATION,
    INVALID_TOKEN,
    OFFLINE,
    DENIED,
    UNKNOWN,
}

class PushException(val reason: PushFailure, cause: Throwable? = null) :
    Exception(reason.name, cause)

/** A secret wrapper whose diagnostics cannot disclose an FCM registration token. */
class PushToken private constructor(private val raw: String) {
    internal fun value(): String = raw

    internal fun sameValue(other: PushToken): Boolean =
        MessageDigest.isEqual(raw.toByteArray(), other.raw.toByteArray())

    override fun equals(other: Any?): Boolean = other is PushToken && sameValue(other)

    override fun hashCode(): Int = raw.hashCode()

    override fun toString(): String = "PushToken([redacted])"

    companion object {
        fun parse(value: String?): PushToken? {
            val normalized = value?.trim().orEmpty()
            return normalized
                .takeIf { it.length in 16..4_096 && !it.any(Char::isWhitespace) }
                ?.let(::PushToken)
        }
    }
}

data class PushRegistration(
    val documentId: String,
    val installationId: String,
    val token: PushToken,
    val platform: String = "android",
    val registrationType: String = "token",
    val deviceName: String,
    val appVersion: String,
)

data class OwnedPushRegistration(
    val uid: String,
    val registration: PushRegistration,
)

object PushRegistrationContract {
    private val installationPattern = Regex("^[A-Za-z0-9_-]{16,128}$")
    private val safeMetadata = Regex("^[^\\p{Cc}]{0,160}$")

    fun create(
        installationId: String,
        token: String,
        deviceName: String,
        appVersion: String,
        registrationType: String = "token",
    ): PushRegistration {
        val installation = installationId.trim()
        if (!installationPattern.matches(installation))
            throw PushException(PushFailure.INVALID_INSTALLATION)
        val parsedToken = PushToken.parse(token) ?: throw PushException(PushFailure.INVALID_TOKEN)
        if (registrationType !in setOf("token", "fid"))
            throw PushException(PushFailure.INVALID_TOKEN)
        if (registrationType == "fid" && !Regex("^[A-Za-z0-9_-]{22}$").matches(token))
            throw PushException(PushFailure.INVALID_TOKEN)
        if (!safeMetadata.matches(deviceName) || !safeMetadata.matches(appVersion))
            throw PushException(PushFailure.NOT_READY)
        return PushRegistration(
            documentId = stableDocumentId(installation),
            installationId = installation,
            token = parsedToken,
            registrationType = registrationType,
            deviceName = deviceName,
            appVersion = appVersion,
        )
    }

    /** A rotation overwrites one installation document instead of accumulating token documents. */
    fun stableDocumentId(installationId: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest("android-installation:$installationId".toByteArray())
            .joinToString("") { "%02x".format(it) }
}

/** Must be app-private, excluded from backup and never synchronized across devices. */
interface PushOwnershipStore {
    suspend fun load(): OwnedPushRegistration?

    suspend fun save(value: OwnedPushRegistration)

    suspend fun clear(expected: OwnedPushRegistration)
}

interface PushRegistrationBackend {
    /** Implementations must use a server timestamp for createdAt/updatedAt. */
    suspend fun upsert(capturedUid: String, registration: PushRegistration)

    /** Calls deleteNotificationPushRegistration for this exact token only. */
    suspend fun deleteExact(capturedUid: String, registration: PushRegistration)
}

interface PushTokenSource {
    val registrationType: String
        get() = "token"

    suspend fun installationId(): String

    suspend fun token(): String

    suspend fun unregister() {}
}

object PushChannelPolicy {
    const val ID = "uac_updates"
    const val NAME_RESOURCE = "uac_notifications_channel_updates_name"
    const val DESCRIPTION_RESOURCE = "uac_notifications_channel_updates_description"
    const val IMPORTANCE = 3 // NotificationManager.IMPORTANCE_DEFAULT
    const val PRIVATE_LOCK_SCREEN = true
    const val SOUND_ENABLED = true
    const val BADGE_ENABLED = true
}
