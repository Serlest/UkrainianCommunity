package at.uac.android.feature.safety

import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.AuthStore
import kotlinx.coroutines.CancellationException

fun AuthSession.safetyScope(): SafetySession? {
    val identity = identity ?: return null
    if (stage == AuthStage.GUEST || identity.anonymous) return null
    val ready = readyForActions && profile?.active == true
    val access =
        when {
            ready -> SafetyAccess.READY
            stage == AuthStage.VERIFICATION_PENDING || !identity.emailVerified ->
                SafetyAccess.VERIFY_EMAIL
            gate == AuthGate.RESTRICTED || profile?.active == false -> SafetyAccess.RESTRICTED
            gate in setOf(AuthGate.LEGAL_REQUIRED, AuthGate.LEGAL_UNAVAILABLE) -> SafetyAccess.LEGAL
            gate == AuthGate.MFA_REQUIRED -> SafetyAccess.MFA
            else -> SafetyAccess.UNAVAILABLE
        }
    return SafetySession(identity.uid, revision, ready, access)
}

class AuthSafetyMutationGate(private val auth: AuthStore) : SafetyMutationGate {
    override suspend fun <T> withSession(session: SafetySession, operation: suspend () -> T): T =
        try {
            auth.withReadySession(session.uid, session.revision, operation)
        } catch (error: AuthException) {
            if (error.problem == AuthProblem.SESSION_CHANGED)
                throw CancellationException("Safety account scope changed")
            throw SafetyException(SafetyFailure.NOT_READY, error)
        }
}

fun SafetyState.forSession(authority: SafetySession?): SafetyState =
    if (session == authority) this else SafetyState(session = authority)
