package at.uac.android.feature.inbox

import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.AuthStore
import kotlinx.coroutines.CancellationException

fun AuthSession.inboxScope(): InboxSession? {
    val user = identity ?: return null
    if (
        user.anonymous ||
            busy ||
            stage !in setOf(AuthStage.AUTHENTICATED, AuthStage.VERIFICATION_PENDING)
    )
        return null
    return InboxSession(user.uid, revision, canEditPreferences = readyForActions)
}

class AuthInboxMutationGate(private val auth: AuthStore) : InboxMutationGate {
    override suspend fun <T> withSession(
        session: InboxSession,
        preferences: Boolean,
        operation: suspend () -> T,
    ): T =
        try {
            if (preferences) auth.withReadySession(session.uid, session.revision, operation)
            else auth.withInboxSession(session.uid, session.revision, operation)
        } catch (error: AuthException) {
            if (error.problem == AuthProblem.SESSION_CHANGED)
                throw CancellationException("Account scope changed")
            throw InboxException(
                if (error.problem == AuthProblem.PERMISSION_DENIED) InboxFailure.DENIED
                else InboxFailure.UNKNOWN,
                error,
            )
        }
}
