package at.uac.android.feature.profilemedia

import at.uac.android.core.LocalStorage
import at.uac.android.feature.personal.DirectPersonalMutationGate
import at.uac.android.feature.personal.PersonalException
import at.uac.android.feature.personal.PersonalFailure
import at.uac.android.feature.personal.PersonalMutationGate
import at.uac.android.feature.personal.PersonalProfile
import at.uac.android.feature.personal.PersonalSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException

class ProfileMediaRepository(
    private val source: ProfileMediaSource,
    private val session: () -> PersonalSession?,
    private val gate: PersonalMutationGate = DirectPersonalMutationGate,
) {
    suspend fun save(
        photo: PreparedAvatar,
        operation: AvatarOperation,
        onPhase: (ProfileMediaPhase) -> Unit,
        onProgress: (Float) -> Unit,
    ): PersonalProfile {
        val captured = session() ?: throw ProfileMediaException(ProfileMediaFailure.SIGN_IN)
        if (!captured.ready) throw ProfileMediaException(ProfileMediaFailure.NOT_READY)
        profileAvatarPath(captured.uid)
        fun current() {
            if (session() != captured) throw CancellationException("Account scope changed")
        }
        current()
        operation.check()
        try {
            // Never nest PersonalRepository/another identity gate or time out a still-running SDK
            // write.
            val confirmed =
                gate.withSession(captured) {
                    current()
                    operation.check()
                    onPhase(ProfileMediaPhase.UPLOADING)
                    val url = source.upload(captured.uid, photo, operation, onProgress)
                    current()
                    operation.check()
                    if (!LocalStorage.urlMatches(url, profileAvatarPath(captured.uid)))
                        throw ProfileMediaException(ProfileMediaFailure.INVALID)
                    onPhase(ProfileMediaPhase.COMMITTING)
                    source
                        .saveAvatar(captured.uid, url) { session() == captured }
                        .also {
                            if (it.uid != captured.uid || it.draft.avatarUrl != url)
                                throw ProfileMediaException(ProfileMediaFailure.UNCONFIRMED)
                        }
                }
            current()
            return confirmed
        } catch (error: Exception) {
            current()
            when (error) {
                is TimeoutCancellationException ->
                    throw ProfileMediaException(ProfileMediaFailure.OFFLINE, error)
                is CancellationException -> throw error
                is ProfileMediaException -> throw error
                is PersonalException ->
                    throw ProfileMediaException(
                        when (error.reason) {
                            PersonalFailure.SIGN_IN -> ProfileMediaFailure.SIGN_IN
                            PersonalFailure.NOT_READY -> ProfileMediaFailure.NOT_READY
                            PersonalFailure.DENIED -> ProfileMediaFailure.DENIED
                            PersonalFailure.OFFLINE -> ProfileMediaFailure.OFFLINE
                            PersonalFailure.INVALID -> ProfileMediaFailure.INVALID
                            else -> ProfileMediaFailure.UNCONFIRMED
                        },
                        error,
                    )
                else -> throw ProfileMediaException(ProfileMediaFailure.UNCONFIRMED, error)
            }
        }
    }
}
