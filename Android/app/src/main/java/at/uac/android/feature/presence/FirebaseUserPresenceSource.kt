package at.uac.android.feature.presence

import android.content.Context
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.feature.moderation.ModerationSession
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.auth.FirebaseAuth
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

fun localUserPresenceSource(context: Context): UserPresenceSource =
    FirebaseUserPresenceSource(AppBackend.auth(context), AppBackend.callables(context))

class FirebaseUserPresenceSource(
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
    private val monotonicNanos: () -> Long = System::nanoTime,
) : UserPresenceSource {
    init {
        functions.requireBoundTo(auth)
    }

    override suspend fun update(value: UserPresenceUpdate) {
        UserPresenceContract.validate(value)
        if (auth.currentUser?.uid != value.userId) return
        try {
            val result =
                functions
                    .getHttpsCallable("updateUserPresence")
                    .withTimeout(15, TimeUnit.SECONDS)
                    .call(
                        mapOf(
                            "userId" to value.userId,
                            "sessionId" to value.sessionId,
                            "sequence" to value.sequence,
                            "active" to value.active,
                        )
                    )
                    .await()
            if (auth.currentUser?.uid != value.userId) return
            UserPresenceContract.acknowledgement(result.data)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw PresenceException(presenceFailure(error), error)
        }
    }

    override suspend fun managed(
        session: ModerationSession,
        targetUserId: String,
    ): ManagedUserPresence {
        if (auth.currentUser?.uid != session.uid || !session.allowed)
            throw PresenceException(PresenceFailure.DENIED)
        val started = monotonicNanos()
        try {
            val response =
                functions
                    .getHttpsCallable("getManagedUserPresence")
                    .withTimeout(15, TimeUnit.SECONDS)
                    .call(mapOf("targetUserId" to targetUserId))
                    .await()
            if (auth.currentUser?.uid != session.uid)
                throw CancellationException("Presence identity changed")
            return UserPresenceContract.snapshot(targetUserId, response.data, started)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw PresenceException(presenceFailure(error), error)
        }
    }
}

fun presenceFailure(error: Throwable): PresenceFailure =
    when (error) {
        is PresenceException -> error.failure
        is FirebaseNetworkException,
        is IOException -> PresenceFailure.OFFLINE
        is LocalCallableException ->
            when (error.code) {
                LocalCallableFailure.UNAUTHENTICATED -> PresenceFailure.SIGN_IN
                LocalCallableFailure.PERMISSION_DENIED -> PresenceFailure.DENIED
                LocalCallableFailure.FAILED_PRECONDITION -> PresenceFailure.NOT_READY
                LocalCallableFailure.NOT_FOUND -> PresenceFailure.MISSING
                LocalCallableFailure.INVALID_ARGUMENT,
                LocalCallableFailure.DATA_LOSS -> PresenceFailure.INVALID
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableFailure.DEADLINE_EXCEEDED -> PresenceFailure.OFFLINE
                else -> PresenceFailure.UNKNOWN
            }
        else -> PresenceFailure.UNKNOWN
    }
