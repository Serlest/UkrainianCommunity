package at.uac.android.feature.auth

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.firebase.FirebaseException
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.FirebaseTooManyRequestsException
import com.google.firebase.Timestamp
import com.google.firebase.auth.ActionCodeResult
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseAuthException
import com.google.firebase.auth.UserProfileChangeRequest
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.MetadataChanges
import com.google.firebase.firestore.Source
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

interface AuthBackend {
    val current: AuthIdentity?
    val security: AuthSecurityBackend?
        get() = null

    suspend fun signIn(email: String, password: String): AuthIdentity

    suspend fun create(email: String, password: String, displayName: String): AuthIdentity

    suspend fun reload(): AuthIdentity

    suspend fun refreshToken(): Boolean

    suspend fun signOut()

    suspend fun deleteCreatedUser(uid: String)

    suspend fun sendVerification(language: String)

    suspend fun sendPasswordReset(email: String, language: String)

    suspend fun verifyEmailCode(code: String)

    suspend fun resetPasswordCode(code: String, password: String)
}

interface AuthProfiles {
    suspend fun create(uid: String, draft: AuthRegistration)

    suspend fun fetch(uid: String): AuthProfile

    suspend fun legalDocuments(): List<AuthLegalDocument>

    suspend fun ensurePublicProfile(profile: AuthProfile)

    fun observe(uid: String): Flow<Result<AuthProfile>>

    fun observeLegalVersions(): Flow<Result<Map<String, String>>> = emptyFlow()
}

class FirebaseAuthBackend(private val auth: FirebaseAuth) : AuthBackend {
    override val security: AuthSecurityBackend = FirebaseAuthSecurityBackend(auth)
    override val current: AuthIdentity?
        get() =
            auth.currentUser?.let {
                AuthIdentity(it.uid, it.email.orEmpty(), it.isEmailVerified, it.isAnonymous)
            }

    private fun requireSyntheticEmail(email: String) {
        if (!email.trim().endsWith(".invalid", ignoreCase = true))
            throw AuthException(AuthProblem.LOCAL_ONLY)
    }

    // Firebase mutations keep running after coroutine cancellation. Await their real
    // completion while the store owns its mutex, so a later login cannot race them.
    private suspend fun <T> operation(action: suspend () -> T): T =
        firebaseAuthOperation(auth, action)

    override suspend fun signIn(email: String, password: String): AuthIdentity = operation {
        requireSyntheticEmail(email)
        auth.signInWithEmailAndPassword(email.trim(), password).await()
        current ?: throw AuthException(AuthProblem.SESSION_CHANGED)
    }

    override suspend fun create(
        email: String,
        password: String,
        displayName: String,
    ): AuthIdentity = operation {
        requireSyntheticEmail(email)
        val user =
            auth.createUserWithEmailAndPassword(email.trim(), password).await().user
                ?: throw AuthException(AuthProblem.SESSION_CHANGED)
        user
            .updateProfile(
                UserProfileChangeRequest.Builder().setDisplayName(displayName.trim()).build()
            )
            .await()
        current ?: throw AuthException(AuthProblem.SESSION_CHANGED)
    }

    override suspend fun reload(): AuthIdentity = operation {
        val user = auth.currentUser ?: throw AuthException(AuthProblem.SESSION_CHANGED)
        user.reload().await()
        current ?: throw AuthException(AuthProblem.SESSION_CHANGED)
    }

    override suspend fun refreshToken(): Boolean = operation {
        val user = auth.currentUser ?: throw AuthException(AuthProblem.SESSION_CHANGED)
        val token = user.getIdToken(true).await()
        val firebase = token.claims["firebase"] as? Map<*, *>
        firebase?.get("sign_in_second_factor") == "totp"
    }

    override suspend fun signOut() = operation { auth.signOut() }

    override suspend fun deleteCreatedUser(uid: String) = operation {
        val user = auth.currentUser ?: throw AuthException(AuthProblem.SESSION_CHANGED)
        if (user.uid != uid) throw AuthException(AuthProblem.SESSION_CHANGED)
        user.delete().await()
        Unit
    }

    override suspend fun sendVerification(language: String) = operation {
        auth.setLanguageCode(if (language == "uk") "uk" else "de")
        val user = auth.currentUser ?: throw AuthException(AuthProblem.SESSION_CHANGED)
        user.sendEmailVerification().await()
        Unit
    }

    override suspend fun sendPasswordReset(email: String, language: String) = operation {
        requireSyntheticEmail(email)
        auth.setLanguageCode(if (language == "uk") "uk" else "de")
        auth.sendPasswordResetEmail(email.trim()).await()
        Unit
    }

    override suspend fun verifyEmailCode(code: String) = operation {
        val info = auth.checkActionCode(code).await()
        val expected = current ?: throw AuthException(AuthProblem.SESSION_CHANGED)
        if (
            info.operation != ActionCodeResult.VERIFY_EMAIL ||
                !info.info?.email.equals(expected.email, ignoreCase = true)
        ) {
            throw AuthException(AuthProblem.CODE_INVALID)
        }
        auth.applyActionCode(code).await()
        Unit
    }

    override suspend fun resetPasswordCode(code: String, password: String) = operation {
        val email = auth.verifyPasswordResetCode(code).await()
        requireSyntheticEmail(email)
        auth.confirmPasswordReset(code, password).await()
        Unit
    }
}

class FirestoreAuthProfiles(private val database: FirebaseFirestore) : AuthProfiles {
    init {
        FirebaseBackendGuard.requireFirestore(database)
    }

    private suspend fun <T> write(action: suspend () -> T): T =
        withContext(NonCancellable) {
            try {
                action()
            } catch (error: Exception) {
                throw AuthException(authProblem(error))
            }
        }

    private suspend fun <T> read(action: suspend () -> T): T =
        try {
            withTimeout(12_000) { action() }
        } catch (error: kotlinx.coroutines.TimeoutCancellationException) {
            throw AuthException(AuthProblem.NETWORK)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw AuthException(authProblem(error))
        }

    override suspend fun create(uid: String, draft: AuthRegistration) {
        val reference = database.collection("users").document(uid)
        // Transactions fail offline: no queued private registration write may be
        // replayed later under a different account. Existing profiles are never overwritten.
        write {
            database
                .runTransaction { transaction ->
                    if (transaction.get(reference).exists())
                        throw AuthException(AuthProblem.EMAIL_EXISTS)
                    transaction.set(
                        reference,
                        registeredProfileFields(uid, draft, FieldValue.serverTimestamp()),
                    )
                }
                .await()
        }
    }

    override suspend fun fetch(uid: String): AuthProfile = read {
        val data =
            database.collection("users").document(uid).get(Source.SERVER).await().data
                ?: throw AuthException(AuthProblem.PROFILE_MISSING)
        decodeProfile(uid, data)
    }

    override suspend fun legalDocuments(): List<AuthLegalDocument> = read {
        listOf("terms", "privacy").map { type ->
            val reference = database.collection("legalDocuments").document(type)
            val version =
                reference.get(Source.SERVER).await().getString("activeVersion")?.takeIf {
                    it.isNotBlank()
                } ?: throw AuthException(AuthProblem.INVALID_PROFILE)
            val data =
                reference.collection("versions").document(version).get(Source.SERVER).await().data
                    ?: throw AuthException(AuthProblem.INVALID_PROFILE)
            decodeLegal(type, version, data)
        }
    }

    override suspend fun ensurePublicProfile(profile: AuthProfile) {
        // Recovery is optional for login, but it is still transaction-only and own-UID.
        val reference = database.collection("publicProfiles").document(profile.uid)
        val fields =
            mutableMapOf<String, Any>(
                "id" to profile.uid,
                "displayName" to profile.displayName,
                "city" to profile.city,
                "updatedAt" to FieldValue.serverTimestamp(),
            )
        profile.avatarUrl?.let { fields["avatarURL"] = it }
        profile.region.takeIf { it in AuthValidation.regions }?.let { fields["federalState"] = it }
        write {
            database
                .runTransaction { transaction ->
                    val existing = transaction.get(reference).data
                    if (
                        existing?.get("displayName") != profile.displayName ||
                            existing["city"] != profile.city ||
                            existing["avatarURL"] != profile.avatarUrl ||
                            existing["federalState"] != profile.region.takeIf { it.isNotEmpty() }
                    ) {
                        transaction.set(reference, fields)
                    }
                }
                .await()
        }
    }

    override fun observe(uid: String): Flow<Result<AuthProfile>> = callbackFlow {
        val registration =
            database.collection("users").document(uid).addSnapshotListener(
                MetadataChanges.INCLUDE
            ) { snapshot, error ->
                if (error != null) trySend(Result.failure(AuthException(authProblem(error))))
                else if (
                    snapshot != null &&
                        !snapshot.metadata.isFromCache &&
                        !snapshot.metadata.hasPendingWrites()
                ) {
                    trySend(
                        runCatching {
                            decodeProfile(
                                uid,
                                snapshot.data ?: throw AuthException(AuthProblem.PROFILE_MISSING),
                            )
                        }
                    )
                }
            }
        awaitClose { registration.remove() }
    }

    override fun observeLegalVersions(): Flow<Result<Map<String, String>>> = callbackFlow {
        val versions = mutableMapOf<String, String>()
        val listeners =
            listOf("terms", "privacy").map { type ->
                database.collection("legalDocuments").document(type).addSnapshotListener(
                    MetadataChanges.INCLUDE
                ) { snapshot, error ->
                    if (error != null) {
                        synchronized(versions) { versions.remove(type) }
                        trySend(Result.failure(AuthException(authProblem(error))))
                    } else if (
                        snapshot != null &&
                            !snapshot.metadata.isFromCache &&
                            !snapshot.metadata.hasPendingWrites()
                    ) {
                        val version =
                            snapshot.getString("activeVersion")?.takeIf { it.isNotBlank() }
                        if (version == null || snapshot.getString("status") != "published") {
                            synchronized(versions) { versions.remove(type) }
                            trySend(Result.failure(AuthException(AuthProblem.INVALID_PROFILE)))
                        } else
                            synchronized(versions) {
                                versions[type] = version
                                if (versions.size == 2) trySend(Result.success(versions.toMap()))
                            }
                    }
                }
            }
        awaitClose { listeners.forEach { it.remove() } }
    }
}

fun registeredProfileFields(
    uid: String,
    draft: AuthRegistration,
    timestamp: Any,
): Map<String, Any?> =
    mapOf(
        "id" to uid,
        "fullName" to draft.displayName.trim(),
        "displayName" to draft.displayName.trim(),
        "city" to "",
        "email" to draft.email.trim(),
        "bio" to "",
        "telegramUsername" to draft.telegramUsername.trim().removePrefix("@").ifEmpty { null },
        "isBlocked" to false,
        "blockState" to "active",
        "globalRole" to "user",
        "selectedFederalState" to draft.region,
        "accountStatus" to "active",
        "warningCount" to 0,
        "communityMemberships" to emptyList<Any>(),
        "acceptedTermsAt" to timestamp,
        "acceptedPrivacyAt" to timestamp,
        "acceptedTermsVersion" to draft.termsVersion,
        "acceptedPrivacyVersion" to draft.privacyVersion,
        "termsVersion" to draft.termsVersion,
        "privacyVersion" to draft.privacyVersion,
        "minimumAgeConfirmedAt" to timestamp,
        "minimumAgeVersion" to AuthRegistration.MINIMUM_AGE_VERSION,
        "createdAt" to timestamp,
        "updatedAt" to timestamp,
    )

fun decodeProfile(uid: String, data: Map<String, Any?>): AuthProfile {
    // The document path is authoritative; older iOS profiles may omit a duplicated id.
    if (data["id"] != null && data["id"] != uid) throw AuthException(AuthProblem.INVALID_PROFILE)
    val email = data["email"] as? String ?: throw AuthException(AuthProblem.INVALID_PROFILE)
    val name =
        (data["displayName"] as? String)?.takeIf { it.isNotBlank() }
            ?: (data["fullName"] as? String)?.takeIf { it.isNotBlank() }
            ?: throw AuthException(AuthProblem.INVALID_PROFILE)
    fun optionalStatusText(key: String): String? {
        val value = data[key] ?: return null
        // Keep the exact reviewed text. Trimming or truncation could acknowledge unseen changes.
        return value as? String ?: throw AuthException(AuthProblem.INVALID_PROFILE)
    }
    fun optionalStatusTime(key: String): Instant? {
        val value = data[key] ?: return null
        val timestamp = value as? Timestamp ?: throw AuthException(AuthProblem.INVALID_PROFILE)
        return Instant.ofEpochSecond(timestamp.seconds, timestamp.nanoseconds.toLong())
    }
    fun authorityStatus(key: String, legacy: () -> String): String {
        if (!data.containsKey(key)) return legacy()
        // Missing legacy fields may default; a present malformed value never becomes active.
        return data[key] as? String ?: throw AuthException(AuthProblem.INVALID_PROFILE)
    }
    val blockState =
        authorityStatus("blockState") {
            when {
                !data.containsKey("isBlocked") -> "active"
                data["isBlocked"] == true -> "suspendedUntil"
                data["isBlocked"] == false -> "active"
                else -> throw AuthException(AuthProblem.INVALID_PROFILE)
            }
        }
    return AuthProfile(
        uid,
        email,
        name,
        data["fullName"] as? String ?: name,
        data["city"] as? String ?: "",
        data["bio"] as? String ?: "",
        data["telegramUsername"] as? String,
        data["selectedFederalState"] as? String ?: "",
        data["avatarURL"] as? String,
        (data["globalRole"] as? String)?.takeIf { it in setOf("owner", "admin") } ?: "user",
        authorityStatus("accountStatus") { "active" },
        blockState,
        data["requiresMultiFactorAuth"] == true,
        data["acceptedTermsVersion"] as? String ?: data["termsVersion"] as? String,
        data["acceptedPrivacyVersion"] as? String ?: data["privacyVersion"] as? String,
        optionalStatusText("statusReason"),
        optionalStatusText("statusMessage"),
        optionalStatusTime("statusUpdatedAt"),
        optionalStatusTime("statusAcknowledgedAt"),
        optionalStatusTime("banExpiresAt"),
    )
}

fun decodeLegal(type: String, version: String, data: Map<String, Any?>): AuthLegalDocument {
    if (data["status"] != "published" || (data["version"] != null && data["version"] != version)) {
        throw AuthException(AuthProblem.INVALID_PROFILE)
    }
    val locales = data["locales"] as? Map<*, *> ?: throw AuthException(AuthProblem.INVALID_PROFILE)
    val titles = mutableMapOf<String, String>()
    val texts = mutableMapOf<String, String>()
    for (locale in listOf("uk", "de")) {
        val content = locales[locale] as? Map<*, *> ?: continue
        val title = content["title"] as? String ?: continue
        val body =
            (content["contentText"] as? String)?.takeIf(String::isNotBlank)
                ?: (content["contentMarkdown"] as? String)?.takeIf(String::isNotBlank)
                ?: continue
        if (title.isNotBlank() && body.isNotBlank()) {
            titles[locale] = title
            texts[locale] = body
        }
    }
    if (texts.isEmpty()) throw AuthException(AuthProblem.INVALID_PROFILE)
    return AuthLegalDocument(
        type,
        version,
        data["requiresAcceptance"] as? Boolean ?: true,
        titles,
        texts,
    )
}

fun authProblem(error: Throwable): AuthProblem =
    when (error) {
        is AuthException -> error.problem
        is FirebaseNetworkException,
        is kotlinx.coroutines.TimeoutCancellationException -> AuthProblem.NETWORK
        is FirebaseTooManyRequestsException -> AuthProblem.RATE_LIMITED
        is FirebaseAuthException ->
            when (error.errorCode) {
                "ERROR_INVALID_EMAIL" -> AuthProblem.INVALID_EMAIL
                "ERROR_WRONG_PASSWORD",
                "ERROR_USER_NOT_FOUND",
                "ERROR_INVALID_CREDENTIAL",
                "ERROR_INVALID_LOGIN_CREDENTIALS" -> AuthProblem.INVALID_CREDENTIALS
                "ERROR_EMAIL_ALREADY_IN_USE" -> AuthProblem.EMAIL_EXISTS
                "ERROR_WEAK_PASSWORD" -> AuthProblem.WEAK_PASSWORD
                "ERROR_USER_DISABLED" -> AuthProblem.DISABLED
                "ERROR_OPERATION_NOT_ALLOWED" -> AuthProblem.OPERATION_DISABLED
                "ERROR_TOO_MANY_REQUESTS" -> AuthProblem.RATE_LIMITED
                "ERROR_EXPIRED_ACTION_CODE" -> AuthProblem.CODE_EXPIRED
                "ERROR_INVALID_ACTION_CODE" -> AuthProblem.CODE_INVALID
                "ERROR_SECOND_FACTOR_REQUIRED" -> AuthProblem.SECOND_FACTOR_REQUIRED
                "ERROR_INVALID_VERIFICATION_CODE",
                "ERROR_MISSING_VERIFICATION_CODE" -> AuthProblem.MFA_CODE_INVALID
                "ERROR_INVALID_MFA_SESSION",
                "ERROR_MISSING_MFA_SESSION",
                "ERROR_SESSION_EXPIRED" -> AuthProblem.MFA_EXPIRED
                "ERROR_SECOND_FACTOR_ALREADY_ENROLLED",
                "ERROR_MAXIMUM_SECOND_FACTOR_COUNT_EXCEEDED" -> AuthProblem.MFA_ALREADY_ENROLLED
                "ERROR_UNSUPPORTED_FIRST_FACTOR",
                "ERROR_MFA_ENROLLMENT_NOT_FOUND" -> AuthProblem.MFA_UNSUPPORTED
                "ERROR_UNVERIFIED_EMAIL" -> AuthProblem.VERIFICATION_PENDING
                "ERROR_REQUIRES_RECENT_LOGIN" -> AuthProblem.RECENT_LOGIN_REQUIRED
                "ERROR_USER_TOKEN_EXPIRED",
                "ERROR_INVALID_USER_TOKEN" -> AuthProblem.SESSION_CHANGED
                else -> AuthProblem.UNKNOWN
            }
        is FirebaseFirestoreException ->
            when (error.code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED -> AuthProblem.PERMISSION_DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> AuthProblem.NETWORK
                FirebaseFirestoreException.Code.UNAUTHENTICATED -> AuthProblem.SESSION_CHANGED
                else -> (error.cause as? AuthException)?.problem ?: AuthProblem.UNKNOWN
            }
        // Auth 24.2.0 loses the transport cause for emulator connection refusal and
        // returns a plain FirebaseException, without an error code. Keep this fallback
        // exact and demo-host-only: arbitrary internal errors are not network failures.
        is FirebaseException ->
            if (isLocalAuthConnectionRefusal(error.javaClass, error.message)) {
                AuthProblem.NETWORK
            } else AuthProblem.UNKNOWN
        else -> AuthProblem.UNKNOWN
    }

internal fun isLocalAuthConnectionRefusal(errorType: Class<*>, message: String?): Boolean =
    errorType == FirebaseException::class.java &&
        message ==
            "An internal error has occurred. [ Failed to connect to /${LocalEnvironment.HOST}:${LocalEnvironment.AUTH_PORT} ]"

object LocalAuthSession {
    @Volatile private var instance: AuthStore? = null

    @Synchronized
    fun get(context: Context): AuthStore =
        instance
            ?: AuthStore(
                    FirebaseAuthBackend(AppBackend.auth(context.applicationContext)),
                    FirestoreAuthProfiles(AppBackend.firestore(context.applicationContext)),
                    legalAcceptor =
                        LocalAuthLegalAcceptor(
                            AppBackend.auth(context.applicationContext),
                            AppBackend.firestore(context.applicationContext),
                            AppBackend.callables(context.applicationContext),
                        ),
                    mfaActivator =
                        LocalAuthMfaActivator(
                            AppBackend.auth(context.applicationContext),
                            AppBackend.firestore(context.applicationContext),
                            AppBackend.callables(context.applicationContext),
                        ),
                    deletionJournal =
                        at.uac.android.core.LocalAccountDeletionJournal.get(
                            context.applicationContext
                        ),
                )
                .also {
                    instance = it
                    it.restore()
                }
}
