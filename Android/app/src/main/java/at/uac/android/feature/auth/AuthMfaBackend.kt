package at.uac.android.feature.auth

import com.google.firebase.auth.EmailAuthProvider
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthMultiFactorException
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.MultiFactorInfo
import com.google.firebase.auth.MultiFactorResolver
import com.google.firebase.auth.TotpMultiFactorGenerator
import com.google.firebase.auth.TotpSecret
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

/** Await real SDK completion before releasing AuthStore's identity mutex. */
internal suspend fun <T> firebaseAuthOperation(auth: FirebaseAuth, action: suspend () -> T): T =
    withContext(NonCancellable) {
        try {
            action()
        } catch (error: AuthMfaChallengeRequired) {
            throw error
        } catch (error: FirebaseAuthMultiFactorException) {
            throw AuthMfaChallengeRequired(FirebaseTotpChallenge(auth, error.resolver))
        } catch (error: Exception) {
            throw AuthException(authProblem(error))
        }
    }

private fun requireSecurityUser(auth: FirebaseAuth, uid: String): FirebaseUser {
    val user = auth.currentUser
    if (user?.uid != uid || user.isAnonymous) throw AuthException(AuthProblem.SESSION_CHANGED)
    if (!user.isEmailVerified) throw AuthException(AuthProblem.VERIFICATION_PENDING)
    return user
}

private fun List<MultiFactorInfo>.totpFactors(): List<AuthTotpFactor> = filter {
    it.factorId == TotpMultiFactorGenerator.FACTOR_ID && it.uid.isNotBlank()
}
    .map {
        AuthTotpFactor(
            it.uid,
            it.displayName?.takeIf(String::isNotBlank) ?: "Authenticator",
            it.enrollmentTimestamp,
        )
    }

private class FirebaseTotpChallenge(
    private val auth: FirebaseAuth,
    private val resolver: MultiFactorResolver,
) : AuthMfaChallenge {
    override val factors = resolver.hints.totpFactors()

    init {
        if (resolver.firebaseAuth !== auth) throw AuthException(AuthProblem.SESSION_CHANGED)
        if (factors.isEmpty()) throw AuthException(AuthProblem.MFA_UNSUPPORTED)
    }

    override suspend fun resolve(factorId: String, code: String): AuthIdentity =
        firebaseAuthOperation(auth) {
            if (factors.none { it.id == factorId }) throw AuthException(AuthProblem.MFA_UNSUPPORTED)
            val assertion = TotpMultiFactorGenerator.getAssertionForSignIn(factorId, totpCode(code))
            val user =
                resolver.resolveSignIn(assertion).await().user
                    ?: throw AuthException(AuthProblem.SESSION_CHANGED)
            AuthIdentity(user.uid, user.email.orEmpty(), user.isEmailVerified, user.isAnonymous)
        }

    override fun toString() = "FirebaseTotpChallenge([redacted])"
}

class FirebaseAuthSecurityBackend(private val auth: FirebaseAuth) : AuthSecurityBackend {
    override suspend fun factors(uid: String): List<AuthTotpFactor> =
        firebaseAuthOperation(auth) {
            val user = requireSecurityUser(auth, uid)
            user.reload().await()
            requireSecurityUser(auth, uid).multiFactor.enrolledFactors.totpFactors()
        }

    override suspend fun reauthenticate(uid: String, password: String) =
        firebaseAuthOperation(auth) {
            if (password.isEmpty()) throw AuthException(AuthProblem.PASSWORD_REQUIRED)
            val user = requireSecurityUser(auth, uid)
            val email = user.email ?: throw AuthException(AuthProblem.INVALID_PROFILE)
            user.reauthenticate(EmailAuthProvider.getCredential(email, password)).await()
            requireSecurityUser(auth, uid)
            Unit
        }

    override suspend fun beginEnrollment(uid: String): AuthTotpEnrollment =
        firebaseAuthOperation(auth) {
            val user = requireSecurityUser(auth, uid)
            user.reload().await()
            if (
                requireSecurityUser(auth, uid)
                    .multiFactor
                    .enrolledFactors
                    .totpFactors()
                    .isNotEmpty()
            ) {
                throw AuthException(AuthProblem.MFA_ALREADY_ENROLLED)
            }
            val session = user.multiFactor.session.await()
            requireSecurityUser(auth, uid)
            val secret = TotpMultiFactorGenerator.generateSecret(session).await()
            requireSecurityUser(auth, uid)
            FirebaseTotpEnrollment(auth, uid, user.email.orEmpty(), secret)
        }

    override suspend fun unenroll(uid: String, factorId: String) =
        firebaseAuthOperation(auth) {
            val user = requireSecurityUser(auth, uid)
            user.reload().await()
            if (
                requireSecurityUser(auth, uid).multiFactor.enrolledFactors.totpFactors().none {
                    it.id == factorId
                }
            ) {
                throw AuthException(AuthProblem.MFA_UNSUPPORTED)
            }
            try {
                user.multiFactor.unenroll(factorId).await()
            } catch (error: Exception) {
                throw AuthException(mfaMutationProblem(error))
            }
            try {
                user.reload().await()
                if (
                    requireSecurityUser(auth, uid).multiFactor.enrolledFactors.any {
                        it.uid == factorId
                    }
                ) {
                    throw AuthException(AuthProblem.MFA_UNCONFIRMED)
                }
            } catch (error: Exception) {
                throw AuthException(mfaMutationProblem(error, readBack = true))
            }
        }
}

private class FirebaseTotpEnrollment(
    private val auth: FirebaseAuth,
    private val uid: String,
    email: String,
    private val secret: TotpSecret,
) : AuthTotpEnrollment {
    override val setup: AuthTotpSetup

    init {
        val deadline = secret.enrollmentCompletionDeadline
        val uri = secret.generateQrCodeUrl(email, "UAC")
        if (
            deadline <= 0 ||
                deadline > Long.MAX_VALUE / 1000 ||
                secret.codeLength !in 6..8 ||
                secret.codeIntervalSeconds <= 0 ||
                secret.sharedSecretKey.isBlank() ||
                !safeOtpAuthUri(uri)
        ) {
            throw AuthException(AuthProblem.MFA_UNCONFIRMED)
        }
        setup =
            AuthTotpSetup(
                secret.sharedSecretKey,
                uri,
                deadline * 1000,
                secret.codeLength,
                secret.codeIntervalSeconds,
            )
    }

    override suspend fun complete(code: String) =
        firebaseAuthOperation(auth) {
            val user = requireSecurityUser(auth, uid)
            val assertion =
                TotpMultiFactorGenerator.getAssertionForEnrollment(
                    secret,
                    totpCode(code, setup.digits),
                )
            try {
                user.multiFactor.enroll(assertion, "UAC Authenticator").await()
            } catch (error: Exception) {
                throw AuthException(mfaMutationProblem(error))
            }
            try {
                user.reload().await()
                if (
                    requireSecurityUser(auth, uid)
                        .multiFactor
                        .enrolledFactors
                        .totpFactors()
                        .isEmpty()
                ) {
                    throw AuthException(AuthProblem.MFA_UNCONFIRMED)
                }
            } catch (error: Exception) {
                throw AuthException(mfaMutationProblem(error, readBack = true))
            }
        }

    override fun toString() = "FirebaseTotpEnrollment([redacted])"
}

private fun mfaMutationProblem(error: Throwable, readBack: Boolean = false): AuthProblem {
    val problem = authProblem(error)
    return when {
        problem == AuthProblem.SESSION_CHANGED -> problem
        readBack || problem in setOf(AuthProblem.NETWORK, AuthProblem.UNKNOWN) ->
            AuthProblem.MFA_UNCONFIRMED
        else -> problem
    }
}
