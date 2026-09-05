package at.uac.android.feature.profilemedia

import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import at.uac.android.feature.personal.PersonalProfile
import at.uac.android.feature.personal.PersonalSession
import at.uac.android.feature.personal.validDocumentId
import java.util.concurrent.atomic.AtomicBoolean

enum class ProfileMediaFailure {
    SIGN_IN,
    NOT_READY,
    INVALID,
    TOO_LARGE,
    UNSUPPORTED,
    UNREADABLE,
    DENIED,
    OFFLINE,
    UNCONFIRMED,
    CANCELLED,
}

class ProfileMediaException(val reason: ProfileMediaFailure, cause: Throwable? = null) :
    Exception(reason.name, cause)

enum class ProfileMediaPhase {
    IDLE,
    UPLOADING,
    COMMITTING,
}

/**
 * Byte content is never included in a state/debug string or persisted across accounts/process
 * death.
 */
class PreparedAvatar(val jpeg: ByteArray) {
    init {
        require(LocalImagePreparation.validJpeg(jpeg, LocalImagePolicy.AVATAR))
    }

    override fun toString(): String = "PreparedAvatar(${jpeg.size} bytes)"
}

data class ProfileMediaState(
    val session: PersonalSession? = null,
    val selection: PreparedAvatar? = null,
    val preparing: Boolean = false,
    val pickerOpen: Boolean = false,
    val phase: ProfileMediaPhase = ProfileMediaPhase.IDLE,
    val progress: Float? = null,
    val cancelRequested: Boolean = false,
    val confirmed: PersonalProfile? = null,
    val confirmationDelivered: Boolean = false,
    val error: ProfileMediaFailure? = null,
) {
    val busy: Boolean
        get() = pickerOpen || preparing || phase != ProfileMediaPhase.IDLE

    fun forSession(value: PersonalSession?): ProfileMediaState =
        if (session == value) this else ProfileMediaState(session = value)
}

fun profileAvatarPath(uid: String): String {
    if (!validDocumentId(uid)) throw ProfileMediaException(ProfileMediaFailure.INVALID)
    return "profileImages/$uid/avatar.jpg"
}

/** Cancel is explicit, while the auth lock still waits for the actual Storage task to settle. */
class AvatarOperation {
    private val cancelled = AtomicBoolean()
    private var cancelUpload: (() -> Unit)? = null

    @Synchronized
    fun attachCancel(action: (() -> Unit)?) {
        cancelUpload = action
        if (cancelled.get()) action?.invoke()
    }

    @Synchronized
    fun cancel() {
        cancelled.set(true)
        cancelUpload?.invoke()
    }

    fun check() {
        if (cancelled.get()) throw ProfileMediaException(ProfileMediaFailure.CANCELLED)
    }
}

interface ProfileMediaSource {
    suspend fun upload(
        uid: String,
        photo: PreparedAvatar,
        operation: AvatarOperation,
        onProgress: (Float) -> Unit,
    ): String

    suspend fun saveAvatar(uid: String, url: String, stillCurrent: () -> Boolean): PersonalProfile
}

fun interface ProfilePhotoPreparation {
    suspend fun prepare(contentUri: String): PreparedAvatar
}
