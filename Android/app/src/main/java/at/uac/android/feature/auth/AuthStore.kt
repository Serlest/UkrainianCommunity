package at.uac.android.feature.auth

import at.uac.android.core.AccountDeletionJournal
import at.uac.android.core.DeletionJournalCodec
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Application-scoped session owner. UI lifetimes never cancel a Firebase session transition. */
class AuthStore(
    private val backend: AuthBackend,
    private val profiles: AuthProfiles,
    private val scope: CoroutineScope =
        CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
    private val legalAcceptor: AuthLegalAcceptor? = null,
    private val mfaActivator: AuthMfaActivator? = null,
    private val deletionJournal: AccountDeletionJournal? = null,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val mutable = MutableStateFlow(AuthSession())
    val state: StateFlow<AuthSession> = mutable.asStateFlow()
    private val sessionMutex = Mutex()
    private var generation = 0L
    private var profileWatch: Job? = null
    private var legalWatch: Job? = null
    private var pendingRegistration: Pair<String, AuthRegistration>? = null
    private var pendingMfa: PendingMfa? = null
    private var pendingEnrollment: Pair<String, AuthTotpEnrollment>? = null
    private val foregroundPolicy = AuthForegroundPolicy()
    private val localUnlockPolicy = AuthLocalUnlockPolicy()

    private enum class MfaPurpose {
        SIGN_IN,
        VERIFY,
        ENROLL,
        REMOVE,
    }

    private class PendingMfa(
        val challenge: AuthMfaChallenge,
        val purpose: MfaPurpose,
        val email: String,
        val uid: String? = null,
        val factorId: String? = null,
    )

    fun restore() = transition(AuthStage.RESTORING) { revision -> restoreLocked(revision) }

    // Foreground refresh must not destroy a resolver while the person is reading
    // their authenticator app. Explicit cancel/logout still clears it immediately.
    fun refresh(): Job =
        if (state.value.mfa.interactive || state.value.mfa.unconfirmed) scope.launch {}
        else restore()

    /** Call immediately before this session launches its own system photo picker. */
    fun beginExternalPicker(uid: String, revision: Long): AuthExternalPickerToken? {
        val session = state.value
        if (
            !session.readyForActions ||
                session.identity?.uid != uid ||
                backend.current?.uid != uid ||
                generation != revision ||
                session.revision != revision
        )
            return null
        return foregroundPolicy.begin(uid, revision)
    }

    fun finishExternalPicker(token: AuthExternalPickerToken) = foregroundPolicy.finish(token)

    fun cancelExternalPicker(token: AuthExternalPickerToken) = foregroundPolicy.cancel(token)

    fun onHostPause() {
        foregroundPolicy.onHostPause()
        localUnlockPolicy.onHostPause()
    }

    /** Only the native adapter calls this immediately before its own Keyguard launch. */
    fun beginLocalUnlock(uid: String, revision: Long): AuthLocalUnlockToken? {
        if (!currentLocalUnlockIdentity(uid, revision)) return null
        return localUnlockPolicy.begin(uid, revision)
    }

    fun finishLocalUnlock(token: AuthLocalUnlockToken) = localUnlockPolicy.finish(token)

    fun cancelLocalUnlock(token: AuthLocalUnlockToken) = localUnlockPolicy.cancel(token)

    private fun currentLocalUnlockIdentity(uid: String?, revision: Long): Boolean {
        val session = state.value
        return uid != null &&
            generation == revision &&
            session.revision == revision &&
            session.identity?.uid == uid &&
            !session.identity.anonymous &&
            backend.current?.uid == uid &&
            backend.current?.anonymous == false &&
            !session.busy &&
            session.stage in
                setOf(
                    AuthStage.AUTHENTICATED,
                    AuthStage.VERIFICATION_PENDING,
                    AuthStage.SESSION_UNAVAILABLE,
                )
    }

    fun onForeground(): Job? {
        val session = state.value
        if (
            localUnlockPolicy.consumeResume(
                session.identity?.uid,
                session.revision,
                currentLocalUnlockIdentity(session.identity?.uid, session.revision),
            )
        )
            return null
        if (
            foregroundPolicy.consumeResume(
                session.identity?.uid,
                session.revision,
                session.readyForActions && backend.current?.uid == session.identity?.uid,
            )
        )
            return null
        if (session.busy || session.identity == null) return null
        return refresh()
    }

    fun signIn(email: String, password: String): Job? {
        val problem =
            AuthValidation.email(email)
                ?: if (password.isEmpty()) AuthProblem.PASSWORD_REQUIRED else null
        if (problem != null) {
            report(problem)
            return null
        }
        return transition(AuthStage.AUTHENTICATING) { revision ->
            backend.signOut()
            requireCurrent(revision)
            pendingRegistration = null
            val identity =
                try {
                    backend.signIn(email.trim(), password)
                } catch (error: AuthMfaChallengeRequired) {
                    showMfaChallenge(
                        revision,
                        PendingMfa(error.challenge, MfaPurpose.SIGN_IN, email.trim()),
                    )
                    return@transition
                }
            requireCurrent(revision, identity.uid)
            restoreLocked(revision)
            issueLocalPasswordProof(revision, identity.uid)
        }
    }

    fun register(
        draft: AuthRegistration,
        password: String,
        repeated: String,
        language: String,
    ): Job? {
        AuthValidation.registration(draft, password, repeated)?.let {
            report(it)
            return null
        }
        if (state.value.busy) return null
        return transition(AuthStage.AUTHENTICATING) { revision ->
            backend.signOut()
            requireCurrent(revision)
            val identity =
                try {
                    backend.create(draft.email, password, draft.displayName)
                } catch (error: Exception) {
                    // Auth may have created its identity before a display-name update
                    // failed. Preserve the non-secret draft for explicit recovery.
                    if (generation == revision)
                        backend.current?.let { pendingRegistration = it.uid to draft }
                    throw error
                }
            if (generation != revision) {
                // Creation is not cancellable. If superseded before any profile was
                // written, remove only the new identity while still owning the mutex.
                if (backend.current?.uid == identity.uid) backend.deleteCreatedUser(identity.uid)
                return@transition
            }
            requireCurrent(revision, identity.uid)
            pendingRegistration = identity.uid to draft
            try {
                profiles.create(identity.uid, draft)
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                // A timed-out write is not proof it failed. Read back before cleanup.
                try {
                    profiles.fetch(identity.uid)
                } catch (readError: Exception) {
                    if (readError is CancellationException) throw readError
                    if (authProblem(readError) == AuthProblem.PROFILE_MISSING) {
                        backend.deleteCreatedUser(identity.uid)
                        pendingRegistration = null
                    }
                    throw error
                }
            }
            requireCurrent(revision, identity.uid)
            pendingRegistration = null
            clearMfaHandles()
            mutable.value =
                AuthSession(AuthStage.VERIFICATION_PENDING, identity, revision = revision)
            try {
                backend.sendVerification(language)
                requireCurrent(revision, identity.uid)
                mutable.value =
                    mutable.value.copy(
                        notice = AuthNotice.VERIFICATION_SENT,
                        resendAfterMillis = clock() + 60_000,
                    )
            } catch (error: Exception) {
                requireCurrent(revision, identity.uid)
                mutable.value = mutable.value.copy(error = authProblem(error))
            }
        }
    }

    fun retryUnavailable(): Job =
        transition(AuthStage.RESTORING) { revision ->
            val pending = pendingRegistration
            if (pending != null && backend.current?.uid == pending.first) {
                try {
                    profiles.fetch(pending.first)
                } catch (error: AuthException) {
                    if (error.problem != AuthProblem.PROFILE_MISSING) throw error
                    profiles.create(pending.first, pending.second)
                }
                requireCurrent(revision, pending.first)
                pendingRegistration = null
            }
            restoreLocked(revision)
        }

    fun signOut(): Job =
        transition(AuthStage.AUTHENTICATING) { revision ->
            backend.signOut()
            requireCurrent(revision)
            pendingRegistration = null
            mutable.value = AuthSession(AuthStage.GUEST, revision = revision)
        }

    fun resendVerification(language: String): Job? {
        if (state.value.busy || state.value.stage != AuthStage.VERIFICATION_PENDING) return null
        if (clock() < state.value.resendAfterMillis) {
            report(AuthProblem.RATE_LIMITED)
            return null
        }
        return auxiliary { revision ->
            val user = backend.reload()
            requireCurrent(revision, user.uid)
            if (user.emailVerified) {
                restoreLocked(revision)
                return@auxiliary
            }
            backend.sendVerification(language)
            requireCurrent(revision, user.uid)
            mutable.value =
                mutable.value.copy(
                    notice = AuthNotice.VERIFICATION_SENT,
                    resendAfterMillis = clock() + 60_000,
                )
        }
    }

    fun checkVerification(): Job =
        transition(AuthStage.AUTHENTICATING) { revision ->
            restoreLocked(revision)
            if (state.value.stage == AuthStage.VERIFICATION_PENDING)
                report(AuthProblem.VERIFICATION_PENDING)
        }

    fun applyVerificationCode(value: String): Job? {
        val code =
            try {
                LocalAuthActionCode.parse(value, "verifyEmail")
            } catch (error: AuthException) {
                report(error.problem)
                return null
            }
        return auxiliary { revision ->
            backend.verifyEmailCode(code)
            requireCurrent(revision)
            restoreLocked(revision)
            mutable.value = mutable.value.copy(notice = AuthNotice.EMAIL_VERIFIED)
        }
    }

    fun sendPasswordReset(email: String, language: String): Job? {
        AuthValidation.email(email)?.let {
            report(it)
            return null
        }
        return auxiliary { revision ->
            try {
                backend.sendPasswordReset(email.trim(), language)
            } catch (error: AuthException) {
                // Do not expose whether an address exists, even with enumeration protection off.
                if (error.problem != AuthProblem.INVALID_CREDENTIALS) throw error
            }
            requireCurrent(revision)
            mutable.value = mutable.value.copy(notice = AuthNotice.RESET_SENT)
        }
    }

    fun confirmPasswordReset(value: String, password: String, repeated: String): Job? {
        val problem =
            AuthValidation.password(password)
                ?: if (password != repeated) AuthProblem.PASSWORD_MISMATCH else null
        if (problem != null) {
            report(problem)
            return null
        }
        val code =
            try {
                LocalAuthActionCode.parse(value, "resetPassword")
            } catch (error: AuthException) {
                report(error.problem)
                return null
            }
        return auxiliary { revision ->
            backend.resetPasswordCode(code, password)
            requireCurrent(revision)
            // Reset revokes prior credentials. Never retain an apparently-ready app session.
            backend.signOut()
            requireCurrent(revision)
            profileWatch?.cancel()
            legalWatch?.cancel()
            pendingRegistration = null
            clearMfaHandles()
            mutable.value =
                AuthSession(
                    AuthStage.GUEST,
                    revision = revision,
                    notice = AuthNotice.PASSWORD_CHANGED,
                )
        }
    }

    fun clearMessage() {
        mutable.value = mutable.value.copy(error = null, notice = null)
    }

    fun loadMfa(): Job? {
        val identity = securityIdentity() ?: return null
        return auxiliary { revision ->
            securityProfile(revision, identity)
            val factors = security().factors(identity.uid)
            requireCurrent(revision, identity.uid)
            restoreLocked(revision)
            mutable.value =
                state.value.copy(mfa = AuthMfaState(factors, loaded = true), busy = true)
        }
    }

    fun beginTotpEnrollment(password: String): Job? = reauthenticateMfa(password, MfaPurpose.ENROLL)

    fun verifyMfaSignIn(password: String): Job? = reauthenticateMfa(password, MfaPurpose.VERIFY)

    fun removeTotpFactor(factorId: String, password: String): Job? =
        reauthenticateMfa(password, MfaPurpose.REMOVE, factorId)

    private fun reauthenticateMfa(
        password: String,
        purpose: MfaPurpose,
        factorId: String? = null,
    ): Job? {
        val identity = securityIdentity() ?: return null
        if (password.isEmpty()) {
            report(AuthProblem.PASSWORD_REQUIRED)
            return null
        }
        if (state.value.mfa.unconfirmed) {
            report(AuthProblem.MFA_UNCONFIRMED)
            return null
        }
        return auxiliary { revision ->
            try {
                val profile = securityProfile(revision, identity)
                val factors = security().factors(identity.uid)
                requireCurrent(revision, identity.uid)
                if (purpose == MfaPurpose.ENROLL && factors.isNotEmpty())
                    throw AuthException(AuthProblem.MFA_ALREADY_ENROLLED)
                if (
                    purpose == MfaPurpose.REMOVE &&
                        !canRemoveTotp(profile, factors, factorId.orEmpty())
                ) {
                    throw AuthException(
                        if (factors.any { it.id == factorId }) AuthProblem.MFA_LAST_FACTOR
                        else AuthProblem.MFA_UNSUPPORTED
                    )
                }
                try {
                    security().reauthenticate(identity.uid, password)
                } catch (error: AuthMfaChallengeRequired) {
                    showMfaChallenge(
                        revision,
                        PendingMfa(
                            error.challenge,
                            purpose,
                            identity.email,
                            identity.uid,
                            factorId,
                        ),
                    )
                    return@auxiliary
                }
                requireCurrent(revision, identity.uid)
                continueMfaAction(revision, identity, purpose, factorId)
            } catch (error: Exception) {
                handleMfaFailure(revision, error)
            }
        }
    }

    fun completeMfaChallenge(factorId: String, value: String): Job? {
        val pending = pendingMfa ?: return null
        if (state.value.stage != AuthStage.MFA_CHALLENGE || state.value.busy) return null
        val code =
            try {
                totpCode(value)
            } catch (error: AuthException) {
                report(error.problem)
                return null
            }
        if (pending.challenge.factors.none { it.id == factorId }) {
            report(AuthProblem.MFA_UNSUPPORTED)
            return null
        }
        return auxiliary { revision ->
            requireCurrent(revision, pending.uid)
            // A wrong code or recoverable network error keeps the same resolver.
            val identity = pending.challenge.resolve(factorId, code)
            requireCurrent(revision)
            pendingMfa = null
            if (
                backend.current?.uid != identity.uid ||
                    identity.anonymous ||
                    !identity.emailVerified ||
                    !identity.email.equals(pending.email, true) ||
                    (pending.uid != null && pending.uid != identity.uid)
            ) {
                backend.signOut()
                requireCurrent(revision)
                reconcile(AuthProblem.SESSION_CHANGED, revision)
                return@auxiliary
            }
            try {
                if (!backend.refreshToken()) {
                    // A consumed resolver without its required proof is not an
                    // ordinary recoverable profile outage. Do not let a later
                    // regular-user restore accidentally bypass the MFA refusal.
                    backend.signOut()
                    requireCurrent(revision)
                    reconcile(AuthProblem.MFA_UNCONFIRMED, revision)
                    return@auxiliary
                }
                requireCurrent(revision, identity.uid)
                restoreLocked(revision)
                mutable.value = state.value.copy(busy = true)
                continueMfaAction(revision, identity, pending.purpose, pending.factorId)
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                requireCurrent(revision, identity.uid)
                // The SDK resolver has already been consumed. Do not show a retry
                // button for it or claim readiness without the refreshed token.
                if (state.value.stage == AuthStage.MFA_CHALLENGE)
                    reconcile(authProblem(error), revision)
                else handleMfaFailure(revision, error)
            }
        }
    }

    fun completeTotpEnrollment(value: String): Job? {
        val pending = pendingEnrollment ?: return null
        val identity = state.value.identity ?: return null
        if (
            state.value.busy ||
                identity.uid != pending.first ||
                state.value.stage != AuthStage.AUTHENTICATED
        )
            return null
        val code =
            try {
                totpCode(value, pending.second.setup.digits)
            } catch (error: AuthException) {
                report(error.problem)
                return null
            }
        return auxiliary { revision ->
            var committed = false
            try {
                securityProfile(revision, identity)
                if (clock() >= pending.second.setup.deadlineMillis) {
                    clearMfaHandles()
                    mutable.value = state.value.copy(mfa = AuthMfaState())
                    throw AuthException(AuthProblem.MFA_EXPIRED)
                }
                pending.second.complete(code)
                committed = true
                requireCurrent(revision, identity.uid)
                pendingEnrollment = null
                val factors = security().factors(identity.uid)
                requireCurrent(revision, identity.uid)
                if (factors.isEmpty()) throw AuthException(AuthProblem.MFA_UNCONFIRMED)
                restoreLocked(revision)
                mutable.value =
                    state.value.copy(
                        mfa = AuthMfaState(factors, loaded = true),
                        notice = AuthNotice.MFA_ENROLLED,
                        busy = true,
                    )
            } catch (error: Exception) {
                handleMfaFailure(revision, if (committed) unconfirmedMfa(error) else error)
            }
        }
    }

    fun cancelMfa(): Job = if (pendingMfa?.purpose == MfaPurpose.SIGN_IN) signOut() else restore()

    fun activateMfaProtection(): Job? {
        val identity = securityIdentity() ?: return null
        val activator =
            mfaActivator
                ?: run {
                    report(AuthProblem.OPERATION_DISABLED)
                    return null
                }
        if (state.value.mfa.unconfirmed) {
            report(AuthProblem.MFA_UNCONFIRMED)
            return null
        }
        return auxiliary { revision ->
            var committed = false
            try {
                val profile = securityProfile(revision, identity)
                if (!profile.privileged) throw AuthException(AuthProblem.PERMISSION_DENIED)
                if (!backend.refreshToken()) throw AuthException(AuthProblem.SECOND_FACTOR_REQUIRED)
                requireCurrent(revision, identity.uid)
                activator.activate(identity.uid)
                committed = true
                requireCurrent(revision, identity.uid)
                restoreLocked(revision)
                if (
                    state.value.profile?.requiresMultiFactorAuth != true ||
                        !state.value.totpAuthenticated
                ) {
                    throw AuthException(AuthProblem.MFA_UNCONFIRMED)
                }
                mutable.value = state.value.copy(notice = AuthNotice.MFA_ACTIVATED, busy = true)
            } catch (error: Exception) {
                handleMfaFailure(revision, if (committed) unconfirmedMfa(error) else error)
            }
        }
    }

    private suspend fun continueMfaAction(
        revision: Long,
        identity: AuthIdentity,
        purpose: MfaPurpose,
        factorId: String?,
    ) {
        when (purpose) {
            MfaPurpose.SIGN_IN,
            MfaPurpose.VERIFY -> {
                if (!backend.refreshToken()) throw AuthException(AuthProblem.SECOND_FACTOR_REQUIRED)
                requireCurrent(revision, identity.uid)
                restoreLocked(revision)
                mutable.value = state.value.copy(notice = AuthNotice.MFA_VERIFIED, busy = true)
                if (purpose == MfaPurpose.SIGN_IN) issueLocalPasswordProof(revision, identity.uid)
            }
            MfaPurpose.ENROLL -> {
                securityProfile(revision, identity)
                val enrollment = security().beginEnrollment(identity.uid)
                requireCurrent(revision, identity.uid)
                pendingEnrollment = identity.uid to enrollment
                mutable.value =
                    state.value.copy(
                        mfa = AuthMfaState(loaded = true, setup = enrollment.setup),
                        busy = true,
                    )
            }
            MfaPurpose.REMOVE -> {
                val profile = securityProfile(revision, identity)
                val factors = security().factors(identity.uid)
                requireCurrent(revision, identity.uid)
                if (!canRemoveTotp(profile, factors, factorId.orEmpty()))
                    throw AuthException(AuthProblem.MFA_LAST_FACTOR)
                security().unenroll(identity.uid, factorId.orEmpty())
                requireCurrent(revision, identity.uid)
                try {
                    val remaining = security().factors(identity.uid)
                    requireCurrent(revision, identity.uid)
                    if (remaining.any { it.id == factorId })
                        throw AuthException(AuthProblem.MFA_UNCONFIRMED)
                    restoreLocked(revision)
                    mutable.value =
                        state.value.copy(
                            mfa = AuthMfaState(remaining, loaded = true),
                            notice = AuthNotice.MFA_REMOVED,
                            busy = true,
                        )
                } catch (error: Exception) {
                    throw unconfirmedMfa(error)
                }
            }
        }
    }

    private fun securityIdentity(): AuthIdentity? {
        val session = state.value
        return session.identity?.takeIf {
            !session.busy &&
                session.stage == AuthStage.AUTHENTICATED &&
                it.emailVerified &&
                !it.anonymous &&
                session.profile?.active == true &&
                !session.mfa.interactive
        }
    }

    private fun issueLocalPasswordProof(revision: Long, uid: String) {
        requireCurrent(revision, uid)
        val session = state.value
        if (
            session.identity?.uid == uid &&
                !session.identity.anonymous &&
                session.stage in setOf(AuthStage.AUTHENTICATED, AuthStage.VERIFICATION_PENDING)
        ) {
            mutable.value = session.copy(localPasswordProof = AuthPasswordProof(uid, revision))
        }
    }

    private fun security(): AuthSecurityBackend =
        backend.security ?: throw AuthException(AuthProblem.OPERATION_DISABLED)

    private suspend fun securityProfile(revision: Long, identity: AuthIdentity): AuthProfile {
        requireCurrent(revision, identity.uid)
        val profile = profiles.fetch(identity.uid)
        requireCurrent(revision, identity.uid)
        if (profile.uid != identity.uid || !profile.email.equals(identity.email, true))
            throw AuthException(AuthProblem.INVALID_PROFILE)
        mutable.value =
            state.value.copy(
                profile = profile,
                gate = gateFor(profile, state.value.totpAuthenticated, state.value.legalDocuments),
            )
        if (!identity.emailVerified || !profile.active) {
            clearMfaHandles()
            mutable.value = state.value.copy(mfa = AuthMfaState())
            throw AuthException(AuthProblem.PERMISSION_DENIED)
        }
        return profile
    }

    private fun showMfaChallenge(revision: Long, pending: PendingMfa) {
        requireCurrent(revision, pending.uid)
        if (pending.challenge.factors.isEmpty()) throw AuthException(AuthProblem.MFA_UNSUPPORTED)
        profileWatch?.cancel()
        legalWatch?.cancel()
        pendingMfa = pending
        pendingEnrollment = null
        mutable.value =
            AuthSession(
                AuthStage.MFA_CHALLENGE,
                backend.current,
                revision = revision,
                mfa = AuthMfaState(pending.challenge.factors, challenge = true),
                busy = true,
            )
    }

    private suspend fun handleMfaFailure(revision: Long, error: Exception) {
        if (error is CancellationException) throw error
        requireCurrent(revision)
        val problem = authProblem(error)
        if (problem == AuthProblem.SESSION_CHANGED) {
            clearMfaHandles()
            backend.signOut()
            requireCurrent(revision)
            reconcile(problem, revision)
        } else {
            if (problem == AuthProblem.MFA_UNCONFIRMED) {
                clearMfaHandles()
                mutable.value = state.value.copy(mfa = AuthMfaState(unconfirmed = true))
            }
            throw error
        }
    }

    private fun clearMfaHandles() {
        pendingMfa = null
        pendingEnrollment = null
    }

    private fun unconfirmedMfa(error: Exception): Exception =
        if (error is CancellationException || authProblem(error) == AuthProblem.SESSION_CHANGED)
            error
        else AuthException(AuthProblem.MFA_UNCONFIRMED)

    fun acceptLegalDocuments(versions: Map<String, String>, language: String): Job? {
        val session = state.value
        val identity = session.identity ?: return null
        if (
            session.busy ||
                session.mfa.interactive ||
                session.stage != AuthStage.AUTHENTICATED ||
                !identity.emailVerified ||
                session.profile?.active != true ||
                session.gate != AuthGate.LEGAL_REQUIRED
        )
            return null
        val expected = session.requiredLegalDocuments().associate { it.type to it.version }
        if (expected.isEmpty() || versions != expected) {
            report(AuthProblem.CONSENT_REQUIRED)
            return null
        }
        val acceptor =
            legalAcceptor
                ?: run {
                    report(AuthProblem.OPERATION_DISABLED)
                    return null
                }
        return auxiliary { revision ->
            requireCurrent(revision, identity.uid)
            try {
                // Always read before retrying an uncertain request. A previous
                // commit must not be replayed just because its response was lost.
                refreshLegalState(revision, identity)
                val current = state.value
                if (
                    versions.any { (type, version) ->
                        current.legalDocuments.none { it.type == type && it.version == version }
                    }
                ) {
                    throw AuthException(AuthProblem.LEGAL_CHANGED)
                }
                for (document in current.requiredLegalDocuments()) {
                    requireCurrent(revision, identity.uid)
                    if (
                        state.value.profile?.active != true ||
                            state.value.gate == AuthGate.MFA_REQUIRED
                    ) {
                        throw AuthException(AuthProblem.PERMISSION_DENIED)
                    }
                    if (versions[document.type] != document.version)
                        throw AuthException(AuthProblem.LEGAL_CHANGED)
                    val receipt = acceptor.accept(identity.uid, document, language)
                    requireCurrent(revision, identity.uid)
                    if (
                        receipt.type != document.type ||
                            receipt.version != document.version ||
                            receipt.acceptedAtMillis <= 0L ||
                            receipt.profileAcceptedAtMillis <= 0L
                    ) {
                        throw AuthException(AuthProblem.LEGAL_UNCONFIRMED)
                    }
                    mutable.value =
                        state.value.copy(
                            legalReceipts =
                                state.value.legalReceipts.filterNot { it.type == receipt.type } +
                                    receipt
                        )
                    refreshLegalState(revision, identity)
                }
                requireCurrent(revision, identity.uid)
                if (state.value.requiredLegalDocuments().isNotEmpty())
                    throw AuthException(AuthProblem.LEGAL_CHANGED)
                mutable.value = state.value.copy(notice = AuthNotice.LEGAL_ACCEPTED)
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                requireCurrent(revision, identity.uid)
                // Preserve confirmed partial receipts, but recover actual server
                // state before exposing another acceptance action.
                runCatching { refreshLegalState(revision, identity) }
                    .onFailure {
                        requireCurrent(revision, identity.uid)
                        mutable.value =
                            state.value.copy(
                                gate = AuthGate.LEGAL_UNAVAILABLE,
                                legalDocuments = emptyList(),
                            )
                    }
                if (state.value.gate == AuthGate.READY) {
                    mutable.value =
                        state.value.copy(
                            gate = AuthGate.LEGAL_UNAVAILABLE,
                            legalDocuments = emptyList(),
                        )
                }
                throw error
            }
        }
    }

    private suspend fun refreshLegalState(revision: Long, identity: AuthIdentity) {
        val profile = profiles.fetch(identity.uid)
        requireCurrent(revision, identity.uid)
        if (
            profile.uid != identity.uid || !profile.email.equals(identity.email, ignoreCase = true)
        ) {
            throw AuthException(AuthProblem.INVALID_PROFILE)
        }
        val documents = profiles.legalDocuments()
        requireCurrent(revision, identity.uid)
        mutable.value =
            state.value.copy(
                profile = profile,
                legalDocuments = documents,
                gate = gateFor(profile, state.value.totpAuthenticated, documents),
            )
    }

    /**
     * Keep Firebase identity fixed until an authorized mutation really completes. A newer
     * transition clears UI immediately but waits here before changing Auth. Callers must await the
     * actual SDK task, not start a detached/deferred write.
     */
    suspend fun <T> withReadySession(uid: String, revision: Long, action: suspend () -> T): T =
        sessionMutex.withLock {
            requireCurrent(revision, uid)
            if (!state.value.readyForActions || state.value.profile?.uid != uid)
                throw AuthException(AuthProblem.PERMISSION_DENIED)
            val outcome = runCatching { withContext(NonCancellable) { action() } }
            // Hold the identity until the SDK settles, then honor the cancelled
            // consumer before exposing a late result/error or checking its old scope.
            currentCoroutineContext().ensureActive()
            val result = outcome.getOrThrow()
            requireCurrent(revision, uid)
            if (!state.value.readyForActions) throw AuthException(AuthProblem.PERMISSION_DENIED)
            result
        }

    /**
     * Only an exact own status acknowledgement. Legal consent is deliberately independent, but
     * verified/active identity and this app's existing privileged TOTP activation policy remain
     * required. The caller must await the real transaction and may write only statusAcknowledgedAt.
     */
    suspend fun <T> withStatusAcknowledgementSession(
        uid: String,
        revision: Long,
        action: suspend () -> T,
    ): T = sessionMutex.withLock {
        fun requireStatusIdentity() {
            requireCurrent(revision, uid)
            val actual = backend.current
            if (
                actual?.uid != uid ||
                    actual.anonymous ||
                    !actual.emailVerified ||
                    !state.value.permitsStatusAcknowledgement(uid, revision)
            )
                throw AuthException(AuthProblem.PERMISSION_DENIED)
        }
        requireStatusIdentity()
        val outcome = runCatching { withContext(NonCancellable) { action() } }
        currentCoroutineContext().ensureActive()
        val result = outcome.getOrThrow()
        requireStatusIdentity()
        result
    }

    /**
     * Narrow self-inbox gate: legal or account restrictions must not hide notices explaining those
     * restrictions. This is not permission for general mutations.
     */
    suspend fun <T> withInboxSession(uid: String, revision: Long, action: suspend () -> T): T =
        sessionMutex.withLock {
            fun requireInboxIdentity() {
                requireCurrent(revision, uid)
                val session = state.value
                if (
                    session.busy ||
                        session.identity?.uid != uid ||
                        session.identity.anonymous ||
                        session.stage !in
                            setOf(AuthStage.AUTHENTICATED, AuthStage.VERIFICATION_PENDING)
                ) {
                    throw AuthException(AuthProblem.PERMISSION_DENIED)
                }
            }
            requireInboxIdentity()
            val outcome = runCatching { withContext(NonCancellable) { action() } }
            currentCoroutineContext().ensureActive()
            val result = outcome.getOrThrow()
            requireInboxIdentity()
            result
        }

    /**
     * Only the self-deletion workflow: blocked/unverified/partially deleted users retain this
     * right. It is not a gate for profile, content or other mutations. A successful Auth absence
     * check may itself clear Firebase's current user.
     */
    suspend fun <T> withAccountDeletionSession(
        uid: String,
        revision: Long,
        action: suspend () -> T,
    ): T = sessionMutex.withLock {
        requireDeletionIdentity(uid, revision, allowAbsentBackend = false)
        val outcome = runCatching { withContext(NonCancellable) { action() } }
        // Cancellation never detaches the SDK call or releases identity early.
        // Once it really settles, restore the caller's cancellation before an
        // obsolete error/result can escape into a cancelled UI parent scope.
        currentCoroutineContext().ensureActive()
        val result = outcome.getOrThrow()
        requireDeletionIdentity(uid, revision, allowAbsentBackend = true)
        result
    }

    /** Finalize confirmed deletion only for its original account and generation. */
    fun signOutDeletedIdentity(uid: String, revision: Long): Job? {
        if (
            runCatching { requireDeletionIdentity(uid, revision, allowAbsentBackend = true) }
                .isFailure
        )
            return null
        return scope.launch {
            sessionMutex.withLock {
                // Do not start a transition before acquiring the lock: a queued old
                // deletion completion must never invalidate a newer login's UI.
                if (
                    runCatching {
                        requireDeletionIdentity(uid, revision, allowAbsentBackend = true)
                    }
                        .isFailure
                )
                    return@withLock
                generation++
                val next = generation
                foregroundPolicy.invalidate()
                localUnlockPolicy.invalidate()
                clearMfaHandles()
                profileWatch?.cancel()
                legalWatch?.cancel()
                mutable.value =
                    AuthSession(
                        AuthStage.AUTHENTICATING,
                        state.value.identity,
                        revision = next,
                        busy = true,
                    )
                try {
                    if (backend.current?.uid == uid)
                        withContext(NonCancellable) { backend.signOut() }
                    requireCurrent(next)
                    pendingRegistration = null
                    mutable.value = AuthSession(AuthStage.GUEST, revision = next)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (generation == next) reconcile(authProblem(error), next)
                } finally {
                    if (generation == next) mutable.value = state.value.copy(busy = false)
                }
            }
        }
    }

    private fun requireDeletionIdentity(uid: String, revision: Long, allowAbsentBackend: Boolean) {
        val session = state.value
        val backendUid = backend.current?.uid
        if (
            generation != revision ||
                session.revision != revision ||
                session.identity?.uid != uid ||
                (backendUid != uid && (!allowAbsentBackend || backendUid != null))
        ) {
            throw AuthException(AuthProblem.SESSION_CHANGED)
        }
        if (
            session.busy ||
                session.identity.anonymous ||
                backend.current?.anonymous == true ||
                session.stage !in
                    setOf(
                        AuthStage.AUTHENTICATED,
                        AuthStage.VERIFICATION_PENDING,
                        AuthStage.SESSION_UNAVAILABLE,
                    )
        ) {
            throw AuthException(AuthProblem.PERMISSION_DENIED)
        }
    }

    private suspend fun restoreLocked(revision: Long) {
        requireCurrent(revision)
        val previous = backend.current
        if (previous == null || previous.anonymous) {
            if (previous != null) backend.signOut()
            requireCurrent(revision)
            mutable.value = AuthSession(AuthStage.GUEST, revision = revision)
            return
        }
        val identity = backend.reload()
        requireCurrent(revision, previous.uid)
        if (!identity.emailVerified) {
            mutable.value =
                AuthSession(
                    AuthStage.VERIFICATION_PENDING,
                    identity,
                    revision = revision,
                    resendAfterMillis = state.value.resendAfterMillis,
                )
            return
        }
        val totp = backend.refreshToken()
        requireCurrent(revision, identity.uid)
        val profile =
            try {
                profiles.fetch(identity.uid)
            } catch (error: AuthException) {
                if (error.problem == AuthProblem.PROFILE_MISSING && pendingRegistration == null) {
                    val pending = deletionJournal?.pending(identity.uid)
                    requireCurrent(revision, identity.uid)
                    if (pending != null) {
                        if (pending.accountHash != DeletionJournalCodec.accountHash(identity.uid)) {
                            throw AuthException(AuthProblem.INVALID_PROFILE)
                        }
                        // Durable local intent is recovery context, not authorization.
                        // Do not reconstruct the profile or run legal/role/MFA writes.
                        mutable.value =
                            AuthSession(
                                AuthStage.SESSION_UNAVAILABLE,
                                identity,
                                revision = revision,
                                gate = AuthGate.RESTRICTED,
                                error = AuthProblem.PROFILE_MISSING,
                                deletionRecovery = true,
                            )
                        return
                    }
                    backend.signOut()
                    requireCurrent(revision)
                }
                throw error
            }
        requireCurrent(revision, identity.uid)
        if (
            profile.uid != identity.uid || !profile.email.equals(identity.email, ignoreCase = true)
        ) {
            throw AuthException(AuthProblem.INVALID_PROFILE)
        }
        val docs =
            try {
                profiles.legalDocuments()
            } catch (error: Exception) {
                if (error is CancellationException) throw error
                null
            }
        requireCurrent(revision, identity.uid)
        mutable.value =
            AuthSession(
                AuthStage.AUTHENTICATED,
                identity,
                profile,
                revision,
                gateFor(profile, totp, docs),
                docs.orEmpty(),
                totpAuthenticated = totp,
            )
        watchProfile(revision, identity, totp)
        watchLegalVersions(revision, identity)
        if (profile.active && (!profile.privileged || (profile.requiresMultiFactorAuth && totp))) {
            // This projection has no private email or account metadata. Failure is recoverable.
            try {
                profiles.ensurePublicProfile(profile)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                /* Retry on the next verified session refresh. */
            }
        }
        requireCurrent(revision, identity.uid)
    }

    private fun watchProfile(revision: Long, identity: AuthIdentity, totp: Boolean) {
        profileWatch?.cancel()
        profileWatch = scope.launch {
            profiles.observe(identity.uid).collect { result ->
                if (
                    generation != revision ||
                        backend.current?.uid != identity.uid ||
                        state.value.stage != AuthStage.AUTHENTICATED
                )
                    return@collect
                val profile = result.getOrNull()
                if (
                    profile == null ||
                        profile.uid != identity.uid ||
                        !profile.email.equals(identity.email, ignoreCase = true)
                ) {
                    mutable.value =
                        AuthSession(
                            AuthStage.SESSION_UNAVAILABLE,
                            identity,
                            revision = revision,
                            error =
                                result.exceptionOrNull()?.let(::authProblem)
                                    ?: AuthProblem.INVALID_PROFILE,
                        )
                } else {
                    if (!profile.active) clearMfaHandles()
                    mutable.value =
                        mutable.value.copy(
                            profile = profile,
                            gate = gateFor(profile, totp, state.value.legalDocuments),
                            mfa = if (profile.active) state.value.mfa else AuthMfaState(),
                        )
                }
            }
        }
    }

    private fun watchLegalVersions(revision: Long, identity: AuthIdentity) {
        legalWatch?.cancel()
        var observedVersions =
            state.value.legalDocuments
                .associate { it.type to it.version }
                .takeIf { it.isNotEmpty() }
        var pointerFailed = false
        legalWatch = scope.launch {
            profiles.observeLegalVersions().collect { result ->
                if (
                    generation != revision ||
                        backend.current?.uid != identity.uid ||
                        state.value.stage != AuthStage.AUTHENTICATED
                )
                    return@collect
                val versions = result.getOrNull()
                if (versions == null || versions.keys != setOf("terms", "privacy")) {
                    pointerFailed = true
                    val profile = state.value.profile ?: return@collect
                    mutable.value =
                        state.value.copy(
                            legalDocuments = emptyList(),
                            gate = gateFor(profile, state.value.totpAuthenticated, null),
                        )
                } else {
                    val changed = observedVersions?.let { it != versions } ?: false
                    observedVersions = versions
                    if (changed || pointerFailed) {
                        // Revoke old readiness synchronously. A new server read must
                        // finish before the app can accept or act under a new version.
                        refresh()
                    }
                    // A valid pointer with an unreadable body must not cause an
                    // endless restore/listen loop. Explicit retry remains available.
                    pointerFailed = false
                }
            }
        }
    }

    private fun transition(stage: AuthStage, action: suspend (Long) -> Unit): Job {
        generation += 1
        val revision = generation
        foregroundPolicy.invalidate()
        localUnlockPolicy.invalidate()
        clearMfaHandles()
        profileWatch?.cancel()
        legalWatch?.cancel()
        // Clear protected data synchronously, before the old backend operation can return.
        mutable.value =
            AuthSession(
                stage,
                backend.current,
                revision = revision,
                busy = true,
                resendAfterMillis = state.value.resendAfterMillis,
            )
        return scope.launch {
            sessionMutex.withLock {
                if (revision != generation) return@withLock
                try {
                    action(revision)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (revision == generation) reconcile(authProblem(error), revision)
                } finally {
                    if (revision == generation) mutable.value = mutable.value.copy(busy = false)
                }
            }
        }
    }

    private fun auxiliary(action: suspend (Long) -> Unit): Job? {
        if (state.value.busy) return null
        val revision = generation
        mutable.value = mutable.value.copy(busy = true, error = null, notice = null)
        return scope.launch {
            sessionMutex.withLock {
                if (revision != generation) return@withLock
                try {
                    action(revision)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (revision == generation) report(authProblem(error))
                } finally {
                    if (revision == generation) mutable.value = mutable.value.copy(busy = false)
                }
            }
        }
    }

    private fun reconcile(problem: AuthProblem, revision: Long) {
        val identity = backend.current
        mutable.value =
            if (identity == null || identity.anonymous)
                AuthSession(AuthStage.GUEST, revision = revision, error = problem)
            else
                AuthSession(
                    AuthStage.SESSION_UNAVAILABLE,
                    identity,
                    revision = revision,
                    error = problem,
                )
    }

    private fun report(problem: AuthProblem) {
        mutable.value = mutable.value.copy(error = problem, notice = null)
    }

    private fun requireCurrent(revision: Long, uid: String? = null) {
        if (generation != revision || (uid != null && backend.current?.uid != uid))
            throw AuthException(AuthProblem.SESSION_CHANGED)
    }
}

fun gateFor(profile: AuthProfile, totp: Boolean, documents: List<AuthLegalDocument>?): AuthGate =
    when {
        !profile.active -> AuthGate.RESTRICTED
        profile.privileged && (!profile.requiresMultiFactorAuth || !totp) -> AuthGate.MFA_REQUIRED
        documents == null || documents.map { it.type }.toSet() != setOf("terms", "privacy") ->
            AuthGate.LEGAL_UNAVAILABLE
        documents.any {
            it.requiresAcceptance &&
                it.version !=
                    when (it.type) {
                        "terms" -> profile.acceptedTermsVersion
                        "privacy" -> profile.acceptedPrivacyVersion
                        else -> null
                    }
        } -> AuthGate.LEGAL_REQUIRED
        else -> AuthGate.READY
    }
