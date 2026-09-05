package at.uac.android.feature.dsaappeal

import at.uac.android.core.backend.CompiledBackend
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStore
import kotlinx.coroutines.CancellationException

val dsaAppealBackendBinding: String
    get() =
        with(CompiledBackend) {
            "$ANDROID_PACKAGE|$FIREBASE_APP_NAME|$PROJECT_ID|$FIREBASE_APPLICATION_ID"
        }

fun AuthSession.dsaAppealScope(): DsaAppealSession? {
    val identity = identity ?: return null
    if (identity.anonymous) return null
    return DsaAppealSession(
        identity.uid,
        revision,
        dsaAppealBackendBinding,
        readyForActions &&
            profile?.active == true &&
            (profile?.privileged != true || (profile.requiresMultiFactorAuth && totpAuthenticated)),
    )
}

class AuthDsaAppealReadGate(private val auth: AuthStore) : DsaAppealReadGate {
    override suspend fun <T> withSession(session: DsaAppealSession, action: suspend () -> T): T {
        if (session.backend != dsaAppealBackendBinding || !session.ready)
            DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
        try {
            return auth.withReadySession(session.uid, session.revision) {
                if (auth.state.value.dsaAppealScope() != session)
                    throw CancellationException("Appeal read account scope changed")
                action()
            }
        } catch (error: AuthException) {
            if (error.problem == AuthProblem.SESSION_CHANGED)
                throw CancellationException("Appeal read account scope changed")
            DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
        }
    }
}

/** Identity policy only; reporter ownership is checked independently by query and contract. */
object DsaAppealSdkPolicy {
    fun requireProfile(profile: Map<String, Any?>?, secondFactor: Any?) {
        if (
            profile == null ||
                profile["accountStatus"] !in setOf("active", "warned") ||
                profile["blockState"] !in setOf("active", "warned") ||
                profile["globalRole"] !in setOf("user", "admin", "owner")
        )
            DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
        if (
            profile["globalRole"] in setOf("admin", "owner") &&
                (profile["requiresMultiFactorAuth"] != true || secondFactor != "totp")
        )
            DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
    }

    fun requireFresh(fromCache: Boolean, pendingWrites: Boolean) {
        if (fromCache || pendingWrites) DsaAppealReviewContract.fail(DsaAppealReviewFailure.STALE)
    }
}
