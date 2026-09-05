package at.uac.android.feature.auth

import at.uac.android.BuildConfig
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

data class AuthLegalReceipt(
    val type: String,
    val version: String,
    val acceptedAtMillis: Long,
    val profileAcceptedAtMillis: Long,
)

interface AuthLegalAcceptor {
    /** Returns only after the callable result and own server profile agree. */
    suspend fun accept(uid: String, document: AuthLegalDocument, language: String): AuthLegalReceipt
}

class LocalAuthLegalAcceptor(
    private val auth: FirebaseAuth,
    private val database: FirebaseFirestore,
    private val functions: CallableGateway,
) : AuthLegalAcceptor {
    init {
        require(auth.app === database.app) { "LOCAL_CALLABLE_MIXED_APPS" }
        functions.requireBoundTo(auth)
    }

    override suspend fun accept(
        uid: String,
        document: AuthLegalDocument,
        language: String,
    ): AuthLegalReceipt {
        fun requireIdentity() {
            val user = auth.currentUser
            if (user?.uid != uid || user.isAnonymous || !user.isEmailVerified) {
                throw AuthException(AuthProblem.SESSION_CHANGED)
            }
        }
        requireIdentity()
        val payload = legalAcceptancePayload(document, language)
        // The caller owns AuthStore's identity mutex until this callable task really
        // finishes. Coroutine cancellation must never release an in-flight write.
        val response =
            try {
                withContext(NonCancellable) {
                    functions
                        .getHttpsCallable("acceptLegalDocument")
                        .withTimeout(20, TimeUnit.SECONDS)
                        .call(payload)
                        .await()
                        .data
                }
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                throw AuthException(legalProblem(error))
            }
        requireIdentity()
        val acceptedAt = decodeLegalAcceptanceResponse(response, document)
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
                throw AuthException(AuthProblem.LEGAL_UNCONFIRMED)
            }
        requireIdentity()
        val prefix = if (document.type == "terms") "acceptedTerms" else "acceptedPrivacy"
        val profileAcceptedAt = snapshot.getTimestamp("${prefix}At")?.toDate()?.time
        if (
            snapshot.metadata.isFromCache ||
                snapshot.metadata.hasPendingWrites() ||
                snapshot.getString("${prefix}Version") != document.version ||
                profileAcceptedAt == null ||
                profileAcceptedAt <= 0L
        ) {
            throw AuthException(AuthProblem.LEGAL_UNCONFIRMED)
        }
        return AuthLegalReceipt(document.type, document.version, acceptedAt, profileAcceptedAt)
    }
}

internal fun legalAcceptancePayload(
    document: AuthLegalDocument,
    language: String,
): Map<String, String> {
    if (document.type !in setOf("terms", "privacy") || document.version.isBlank()) {
        throw AuthException(AuthProblem.INVALID_PROFILE)
    }
    return mapOf(
        "documentType" to document.type,
        "version" to document.version,
        "appVersion" to BuildConfig.VERSION_NAME,
        "locale" to if (language == "uk") "uk" else "de",
        "acceptedFromPlatform" to "android",
    )
}

internal fun decodeLegalAcceptanceResponse(response: Any?, expected: AuthLegalDocument): Long {
    val data = response as? Map<*, *> ?: throw AuthException(AuthProblem.LEGAL_UNCONFIRMED)
    if (data["documentType"] != expected.type || data["version"] != expected.version) {
        throw AuthException(AuthProblem.LEGAL_UNCONFIRMED)
    }
    val acceptedAt =
        (data["acceptedAt"] as? String)?.let {
            runCatching { Instant.parse(it).toEpochMilli() }.getOrNull()
        }
    // An invalid server date must never become a locally fabricated receipt.
    return acceptedAt?.takeIf { it > 0L } ?: throw AuthException(AuthProblem.LEGAL_UNCONFIRMED)
}

private fun legalProblem(error: Throwable): AuthProblem =
    if (error is LocalCallableException) {
        when (error.code) {
            LocalCallableFailure.UNAVAILABLE,
            LocalCallableFailure.DEADLINE_EXCEEDED -> AuthProblem.NETWORK
            LocalCallableFailure.UNAUTHENTICATED -> AuthProblem.SESSION_CHANGED
            LocalCallableFailure.PERMISSION_DENIED -> AuthProblem.PERMISSION_DENIED
            LocalCallableFailure.RESOURCE_EXHAUSTED -> AuthProblem.RATE_LIMITED
            LocalCallableFailure.FAILED_PRECONDITION -> AuthProblem.LEGAL_CHANGED
            LocalCallableFailure.UNCONFIRMED -> AuthProblem.LEGAL_UNCONFIRMED
            else -> AuthProblem.UNKNOWN
        }
    } else authProblem(error)

fun AuthSession.requiredLegalDocuments(): List<AuthLegalDocument> =
    legalDocuments.filter { document ->
        document.requiresAcceptance &&
            document.version !=
                when (document.type) {
                    "terms" -> profile?.acceptedTermsVersion
                    "privacy" -> profile?.acceptedPrivacyVersion
                    else -> null
                }
    }
