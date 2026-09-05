package at.uac.android.feature.accountdeletion

import android.content.Context
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthMfaChallenge
import at.uac.android.feature.auth.AuthMfaChallengeRequired
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.firebaseAuthOperation
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.FirebaseTooManyRequestsException
import com.google.firebase.auth.EmailAuthProvider
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

fun localAccountDeletionSource(context: Context): AccountDeletionSource =
    FirebaseAccountDeletionSource(
        AppBackend.auth(context),
        AppBackend.firestore(context),
        AppBackend.callables(context),
    )

/**
 * The only deletion is the actual callable. There are no client profile, Storage, cascade or Auth
 * deletes here.
 */
class FirebaseAccountDeletionSource(
    private val auth: FirebaseAuth,
    private val db: FirebaseFirestore,
    private val functions: CallableGateway,
) : AccountDeletionSource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
    }

    private fun identity(uid: String): FirebaseUser {
        val user =
            auth.currentUser ?: throw AccountDeletionException(AccountDeletionFailure.SIGN_IN)
        if (user.uid != uid || user.isAnonymous)
            throw AccountDeletionException(AccountDeletionFailure.SIGN_IN)
        if (user.email?.endsWith(".invalid", ignoreCase = true) != true)
            throw AccountDeletionException(AccountDeletionFailure.LOCAL_ONLY)
        AccountDeletionSession(
            uid,
            0,
        ) // Exact document-ID validation, never a caller-supplied path.
        return user
    }

    private suspend fun <T> read(action: suspend () -> T): T =
        try {
            withTimeout(15_000) { action() }
        } catch (error: TimeoutCancellationException) {
            throw AccountDeletionException(AccountDeletionFailure.OFFLINE, error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw AccountDeletionException(accountDeletionFailure(error), error)
        }

    override suspend fun policy(uid: String): AccountDeletionPolicy = read {
        val user = identity(uid)
        val profile = db.document("users/$uid").get(Source.SERVER).await()
        val role = profile.getString("globalRole") ?: "user"
        val requiresTotp =
            profile.getBoolean("requiresMultiFactorAuth") == true && role in setOf("owner", "admin")
        val active =
            (profile.getString("accountStatus") ?: "active") in setOf("active", "warned") &&
                (profile.getString("blockState") ?: "active") in setOf("active", "warned")
        val owned =
            if (profile.exists() && user.isEmailVerified && active) {
                try {
                    !db.collection("organizations")
                        .whereEqualTo("ownerId", uid)
                        .limit(1)
                        .get(Source.SERVER)
                        .await()
                        .isEmpty
                } catch (error: FirebaseFirestoreException) {
                    if (error.code != FirebaseFirestoreException.Code.PERMISSION_DENIED) throw error
                    null // The callable performs the authoritative owner check, including
                    // restricted/MFA/partial accounts.
                }
            } else null
        identity(uid)
        AccountDeletionPolicy(
            role == "owner",
            requiresTotp,
            owned,
            !profile.exists(),
            profile.getString("deletionState") == "inProgress",
        )
    }

    override suspend fun reauthenticate(uid: String, password: String): AccountDeletionProof {
        if (password.isEmpty())
            throw AccountDeletionException(AccountDeletionFailure.PASSWORD_REQUIRED)
        try {
            // Unlike the general security-settings backend, account deletion does not require
            // verified/active status.
            val user = identity(uid)
            firebaseAuthOperation(auth) {
                user.reauthenticate(EmailAuthProvider.getCredential(user.email!!, password)).await()
            }
            return proof(uid)
        } catch (error: AuthMfaChallengeRequired) {
            throw AccountDeletionChallengeRequired(DeletionTotpChallenge(uid, error.challenge))
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw reauthenticationFailure(error)
        }
    }

    private suspend fun proof(uid: String): AccountDeletionProof {
        val token = identity(uid).getIdToken(true).await()
        identity(uid)
        val numeric =
            token.claims["auth_time"] as? Number
                ?: throw invalidProof(AccountDeletionFreshnessReason.MISSING_OR_NON_NUMERIC)
        val seconds = numeric.toLong()
        if (seconds <= 0 || numeric.toDouble() != seconds.toDouble())
            throw invalidProof(AccountDeletionFreshnessReason.INVALID_INTEGER)
        val totp = (token.claims["firebase"] as? Map<*, *>)?.get("sign_in_second_factor") == "totp"
        return AccountDeletionProof(uid, Instant.ofEpochSecond(seconds), totp)
    }

    private fun invalidProof(reason: AccountDeletionFreshnessReason) =
        AccountDeletionException(
            AccountDeletionFailure.RECENT_AUTH_REQUIRED,
            freshnessDiagnostic =
                AccountDeletionFreshnessDiagnostic(
                    AccountDeletionFreshnessStage.CLAIM_PARSE,
                    reason,
                ),
        )

    private fun reauthenticationFailure(error: Throwable): AccountDeletionException {
        val failure = accountDeletionFailure(error)
        return AccountDeletionException(
            failure,
            error,
            if (failure == AccountDeletionFailure.RECENT_AUTH_REQUIRED)
                error.accountDeletionFreshnessDiagnostic()
                    ?: AccountDeletionFreshnessDiagnostic(
                        AccountDeletionFreshnessStage.SDK_REAUTH,
                        AccountDeletionFreshnessReason.SDK_REJECTED,
                    )
            else null,
        )
    }

    private inner class DeletionTotpChallenge(
        private val uid: String,
        private val challenge: AuthMfaChallenge,
    ) : AccountDeletionChallenge {
        override val factors = challenge.factors.map { AccountDeletionFactor(it.id, it.name) }

        override suspend fun resolve(factorId: String, code: String): AccountDeletionProof {
            identity(uid)
            try {
                val resolved = challenge.resolve(factorId, code)
                if (resolved.uid != uid)
                    throw AccountDeletionException(AccountDeletionFailure.SIGN_IN)
                return proof(uid)
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                throw reauthenticationFailure(error)
            }
        }

        override fun toString() = "AccountDeletionTotpChallenge([redacted])"
    }

    override suspend fun delete(uid: String): AccountDeletionReceipt {
        identity(uid)
        return try {
            AccountDeletionContract.receipt(
                functions
                    .getHttpsCallable("deleteOwnAccount")
                    .withTimeout(AccountDeletionContract.REQUEST_TIMEOUT_SECONDS, TimeUnit.SECONDS)
                    .call(emptyMap<String, Any>())
                    .await()
                    .data
            )
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            val failure = accountDeletionFailure(error, submitted = true)
            throw AccountDeletionException(
                failure,
                error,
                if (failure == AccountDeletionFailure.RECENT_AUTH_REQUIRED)
                    AccountDeletionFreshnessDiagnostic(
                        AccountDeletionFreshnessStage.CALLABLE,
                        AccountDeletionFreshnessReason.SERVER_REJECTED,
                    )
                else null,
            )
        }
    }

    override suspend fun status(uid: String): AccountDeletionIdentityStatus {
        val user = identity(uid)
        try {
            user.reload().await()
        } catch (error: FirebaseAuthException) {
            // Expired/revoked tokens and disabled accounts are NOT evidence of deletion.
            if (
                error.errorCode == "ERROR_USER_NOT_FOUND" &&
                    auth.currentUser?.uid.let { it == null || it == uid }
            )
                return AccountDeletionIdentityStatus.ABSENT
            throw AccountDeletionException(accountDeletionFailure(error), error)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw AccountDeletionException(accountDeletionFailure(error), error)
        }
        return read {
            identity(uid)
            val profile = db.document("users/$uid").get(Source.SERVER).await()
            identity(uid)
            if (!profile.exists() || profile.getString("deletionState") == "inProgress")
                AccountDeletionIdentityStatus.PARTIAL
            else AccountDeletionIdentityStatus.PRESENT
        }
    }
}

fun accountDeletionFailure(error: Throwable, submitted: Boolean = false): AccountDeletionFailure =
    when (error) {
        is AccountDeletionException -> error.failure
        is LocalCallableException ->
            when (error.code.name) {
                "UNAUTHENTICATED" -> AccountDeletionFailure.RECENT_AUTH_REQUIRED
                "PERMISSION_DENIED" -> AccountDeletionFailure.DENIED
                "FAILED_PRECONDITION" -> AccountDeletionFailure.PRECONDITION
                "RESOURCE_EXHAUSTED" -> AccountDeletionFailure.RATE_LIMITED
                "UNAVAILABLE",
                "DEADLINE_EXCEEDED" -> AccountDeletionFailure.OFFLINE
                else -> AccountDeletionFailure.UNCONFIRMED
            }
        is AuthException ->
            when (error.problem) {
                AuthProblem.PASSWORD_REQUIRED -> AccountDeletionFailure.PASSWORD_REQUIRED
                AuthProblem.INVALID_CREDENTIALS,
                AuthProblem.INVALID_EMAIL -> AccountDeletionFailure.INVALID_CREDENTIALS
                AuthProblem.NETWORK -> AccountDeletionFailure.OFFLINE
                AuthProblem.RATE_LIMITED -> AccountDeletionFailure.RATE_LIMITED
                AuthProblem.MFA_CODE_INVALID,
                AuthProblem.CODE_INVALID,
                AuthProblem.CODE_EXPIRED,
                AuthProblem.MFA_EXPIRED -> AccountDeletionFailure.MFA_INVALID
                AuthProblem.MFA_UNSUPPORTED -> AccountDeletionFailure.MFA_UNSUPPORTED
                AuthProblem.SECOND_FACTOR_REQUIRED -> AccountDeletionFailure.MFA_REQUIRED
                AuthProblem.RECENT_LOGIN_REQUIRED -> AccountDeletionFailure.RECENT_AUTH_REQUIRED
                AuthProblem.SESSION_CHANGED -> AccountDeletionFailure.SIGN_IN
                else -> AccountDeletionFailure.DENIED
            }
        is FirebaseAuthException ->
            when (error.errorCode) {
                "ERROR_WRONG_PASSWORD",
                "ERROR_INVALID_CREDENTIAL",
                "ERROR_INVALID_LOGIN_CREDENTIALS",
                "ERROR_USER_NOT_FOUND" -> AccountDeletionFailure.INVALID_CREDENTIALS
                "ERROR_USER_TOKEN_EXPIRED",
                "ERROR_INVALID_USER_TOKEN" -> AccountDeletionFailure.SIGN_IN
                else -> AccountDeletionFailure.DENIED
            }
        is FirebaseNetworkException -> AccountDeletionFailure.OFFLINE
        is FirebaseTooManyRequestsException -> AccountDeletionFailure.RATE_LIMITED
        is FirebaseFirestoreException ->
            when (error.code) {
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> AccountDeletionFailure.OFFLINE
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                FirebaseFirestoreException.Code.UNAUTHENTICATED -> AccountDeletionFailure.DENIED
                else -> AccountDeletionFailure.INVALID
            }
        else ->
            if (submitted) AccountDeletionFailure.UNCONFIRMED else AccountDeletionFailure.INVALID
    }
