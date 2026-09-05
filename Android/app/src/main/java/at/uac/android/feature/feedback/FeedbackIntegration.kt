package at.uac.android.feature.feedback

import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.AuthStore
import kotlinx.coroutines.CancellationException

fun AuthSession.feedbackScope(): FeedbackSession? {
    val identity = identity ?: return null
    if (
        identity.anonymous ||
            busy ||
            stage !in setOf(AuthStage.AUTHENTICATED, AuthStage.VERIFICATION_PENDING)
    )
        return null
    return FeedbackSession(
        identity.uid,
        revision,
        readyForActions,
        readyForActions && profile?.privileged == true,
        profile?.displayName.orEmpty(),
    )
}

fun FeedbackState.forSession(authority: FeedbackSession?): FeedbackState =
    if (session == authority) this else FeedbackState(session = authority)

class AuthFeedbackMutationGate(private val auth: AuthStore) : FeedbackMutationGate {
    override suspend fun <T> withSession(session: FeedbackSession, operation: suspend () -> T): T =
        try {
            auth.withReadySession(session.uid, session.revision, operation)
        } catch (error: AuthException) {
            if (error.problem == AuthProblem.SESSION_CHANGED)
                throw CancellationException("Feedback account scope changed")
            throw FeedbackException(FeedbackFailure.NOT_READY, error)
        }
}
