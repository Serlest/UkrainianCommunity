package at.uac.android.feature.dsastatement

import at.uac.android.core.backend.CompiledBackend
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStore
import kotlinx.coroutines.CancellationException

/** Labels bind the projection; actual SDK objects are checked separately by the source. */
val dsaStatementBackendBinding: String
    get() =
        with(CompiledBackend) {
            "$ANDROID_PACKAGE|$FIREBASE_APP_NAME|$PROJECT_ID|$FIREBASE_APPLICATION_ID"
        }

fun AuthSession.dsaStatementScope(): DsaStatementSession? {
    val identity = identity ?: return null
    if (identity.anonymous) return null
    return DsaStatementSession(
        identity.uid,
        revision,
        dsaStatementBackendBinding,
        readyForActions &&
            profile?.active == true &&
            (profile?.privileged != true || (profile.requiresMultiFactorAuth && totpAuthenticated)),
    )
}

class AuthDsaStatementReadGate(private val auth: AuthStore) : DsaStatementReadGate {
    override suspend fun <T> withSession(session: DsaStatementSession, action: suspend () -> T): T {
        if (session.backend != dsaStatementBackendBinding || !session.ready)
            DsaStatementContract.fail(DsaStatementFailure.ACCESS)
        try {
            return auth.withReadySession(session.uid, session.revision) {
                if (auth.state.value.dsaStatementScope() != session)
                    throw CancellationException("Statement account scope changed")
                action()
            }
        } catch (error: AuthException) {
            if (error.problem == AuthProblem.SESSION_CHANGED)
                throw CancellationException("Statement account scope changed")
            DsaStatementContract.fail(DsaStatementFailure.ACCESS)
        }
    }
}

/** Strong existing Android privileged policy, without requiring ordinary authors to be owners. */
object DsaStatementSdkPolicy {
    fun requireProfile(profile: Map<String, Any?>?, secondFactor: Any?) {
        if (
            profile == null ||
                profile["accountStatus"] !in setOf("active", "warned") ||
                profile["blockState"] !in setOf("active", "warned") ||
                profile["globalRole"] !in setOf("user", "admin", "owner")
        )
            DsaStatementContract.fail(DsaStatementFailure.ACCESS)
        if (
            profile["globalRole"] in setOf("admin", "owner") &&
                (profile["requiresMultiFactorAuth"] != true || secondFactor != "totp")
        )
            DsaStatementContract.fail(DsaStatementFailure.ACCESS)
    }
}
