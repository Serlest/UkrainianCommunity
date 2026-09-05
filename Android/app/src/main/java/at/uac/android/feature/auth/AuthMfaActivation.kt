package at.uac.android.feature.auth

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.CallableGateway
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

class LocalAuthMfaActivator(
    private val auth: FirebaseAuth,
    private val database: FirebaseFirestore,
    private val functions: CallableGateway,
) : AuthMfaActivator {
    init {
        require(auth.app === database.app) { "LOCAL_CALLABLE_MIXED_APPS" }
        functions.requireBoundTo(auth)
    }

    override suspend fun activate(uid: String) {
        fun requireIdentity() {
            val user = auth.currentUser
            if (user?.uid != uid || user.isAnonymous || !user.isEmailVerified)
                throw AuthException(AuthProblem.SESSION_CHANGED)
        }
        requireIdentity()
        val response =
            try {
                withContext(NonCancellable) {
                    functions
                        .getHttpsCallable("activatePrivilegedMFAProtection")
                        .withTimeout(20, TimeUnit.SECONDS)
                        .call(emptyMap<String, Any>())
                        .await()
                        .data
                }
            } catch (error: LocalCallableException) {
                throw AuthException(
                    when (error.code) {
                        LocalCallableFailure.FAILED_PRECONDITION ->
                            AuthProblem.SECOND_FACTOR_REQUIRED
                        LocalCallableFailure.PERMISSION_DENIED -> AuthProblem.PERMISSION_DENIED
                        LocalCallableFailure.UNAUTHENTICATED -> AuthProblem.SESSION_CHANGED
                        LocalCallableFailure.RESOURCE_EXHAUSTED -> AuthProblem.RATE_LIMITED
                        else -> AuthProblem.MFA_UNCONFIRMED
                    }
                )
            }
        requireIdentity()
        requireMfaActivationResponse(response)
        val snapshot =
            try {
                withTimeout(12_000) {
                    database.collection("users").document(uid).get(Source.SERVER).await()
                }
            } catch (error: Exception) {
                if (
                    error is CancellationException &&
                        error !is kotlinx.coroutines.TimeoutCancellationException
                )
                    throw error
                throw AuthException(AuthProblem.MFA_UNCONFIRMED)
            }
        requireIdentity()
        if (
            snapshot.metadata.isFromCache ||
                snapshot.metadata.hasPendingWrites() ||
                snapshot.getBoolean("requiresMultiFactorAuth") != true ||
                snapshot.getString("multiFactorAuthRequiredMethod") != "totp" ||
                (snapshot.getTimestamp("multiFactorAuthRequiredAt")?.toDate()?.time ?: 0) <= 0
        ) {
            throw AuthException(AuthProblem.MFA_UNCONFIRMED)
        }
    }
}

internal fun requireMfaActivationResponse(value: Any?) {
    val data = value as? Map<*, *>
    val activatedAt =
        (data?.get("activatedAt") as? String)?.let {
            runCatching { Instant.parse(it).toEpochMilli() }.getOrNull()
        }
    if (data?.get("required") != true || activatedAt == null || activatedAt <= 0) {
        throw AuthException(AuthProblem.MFA_UNCONFIRMED)
    }
}
