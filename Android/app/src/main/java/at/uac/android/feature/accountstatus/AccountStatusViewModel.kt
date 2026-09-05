package at.uac.android.feature.accountstatus

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import java.nio.ByteBuffer
import java.security.MessageDigest
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

data class AccountStatusState(
    val session: AccountStatusSession? = null,
    val notice: AccountStatusVersion? = null,
    val visible: Boolean = false,
    val busy: Boolean = false,
    val pending: AccountStatusVersion? = null,
    val failure: AccountStatusFailure? = null,
)

class AccountStatusViewModel(
    private val repository: AccountStatusRepository,
    private val currentSession: () -> AccountStatusSession?,
    private val signOut: suspend (AccountStatusSession) -> Boolean,
    private val refreshSession: () -> Unit = {},
) : ViewModel() {
    private val mutable = MutableStateFlow(AccountStatusState())
    val state: StateFlow<AccountStatusState> = mutable
    private var watch: Job? = null
    private var operation: Job? = null
    private var ticket = 0L

    private data class Escape(val uid: String, val digest: List<Byte>)

    private var escaped: Escape? = null
    // Only a lossless version digest survives a same-user transient cleared profile. Raw notice
    // fields are restored exclusively from the next fresh profile, never retained while hidden.
    private var pendingMarker: Escape? = null

    fun observeAuthSessions(sessions: Flow<AuthSession>) {
        watch?.cancel()
        watch = viewModelScope.launch { sessions.collect(::bindAuthSession) }
    }

    fun bindAuthSession(session: AuthSession) {
        val retainedUid =
            session.identity
                ?.takeUnless { it.anonymous }
                ?.uid
                ?.takeIf { session.stage != AuthStage.GUEST }
        bindSession(session.accountStatusScope(), retainedUid)
    }

    fun observeSessions(sessions: Flow<AccountStatusSession?>) {
        watch?.cancel()
        watch = viewModelScope.launch { sessions.collect { bindSession(it) } }
    }

    fun bindSession(session: AccountStatusSession?, retainedUid: String? = session?.uid) {
        val old = mutable.value
        if (escaped?.uid != retainedUid) escaped = null
        if (pendingMarker?.uid != retainedUid) pendingMarker = null
        if (old.session == session) return
        val sameIdentity =
            old.session?.uid == session?.uid && old.session?.revision == session?.revision
        val sameVersion = old.session?.observation?.version == session?.observation?.version
        if (!sameIdentity || !sameVersion) {
            ticket++
            operation?.cancel()
        }
        val candidate = session?.observation?.notice
        if (session != null && (candidate == null || pendingMarker?.digest != candidate.digest()))
            pendingMarker = null
        if (
            session != null &&
                (session.canAcknowledge ||
                    candidate == null ||
                    escaped?.digest != candidate.digest())
        )
            escaped = null
        val notice = candidate?.takeUnless { escaped == Escape(it.uid, it.digest()) }
        mutable.value =
            AccountStatusState(
                session,
                notice,
                old.visible,
                old.busy && sameIdentity && sameVersion,
                notice?.takeIf { pendingMarker == Escape(it.uid, it.digest()) },
                old.failure?.takeIf { sameIdentity && sameVersion && notice != null },
            )
    }

    fun setVisible(value: Boolean) {
        mutable.value = mutable.value.copy(visible = value)
    }

    private fun current(session: AccountStatusSession, expected: AccountStatusVersion): Boolean {
        val actual = currentSession() ?: return false
        return actual.uid == session.uid &&
            actual.revision == session.revision &&
            actual.observation.version == expected &&
            mutable.value.session?.uid == session.uid &&
            mutable.value.session?.revision == session.revision
    }

    fun acknowledge() {
        val captured = mutable.value
        val session = captured.session ?: return
        val expected = captured.notice ?: return
        if (
            !captured.visible ||
                captured.busy ||
                captured.pending != null ||
                captured.failure == AccountStatusFailure.STALE ||
                !session.canAcknowledge ||
                !current(session, expected) ||
                expected.requiresSignOut
        )
            return
        val owner = ++ticket
        mutable.value = captured.copy(busy = true, failure = null)
        operation = viewModelScope.launch {
            try {
                repository.acknowledge(
                    session,
                    expected,
                    onDispatch = {
                        // This runs synchronously before the real Task starts. A later cancellation
                        // may prevent delivery of its result, so an exact pending marker must exist
                        // before any write can settle. A late callback must not revive an old UID.
                        statusRequire(
                            ticket == owner && current(session, expected) && mutable.value.visible,
                            AccountStatusFailure.STALE,
                        )
                        pendingMarker = Escape(expected.uid, expected.digest())
                        mutable.value = mutable.value.copy(pending = expected)
                    },
                ) {
                    current(session, expected) &&
                        mutable.value.visible &&
                        mutable.value.notice == expected &&
                        ticket == owner &&
                        currentSession()?.canAcknowledge == true
                }
                if (ticket == owner && current(session, expected)) {
                    pendingMarker = null
                    mutable.value =
                        mutable.value.copy(
                            notice = null,
                            busy = false,
                            pending = null,
                            failure = null,
                        )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (ticket == owner && current(session, expected)) {
                    val failure = statusFailure(error)
                    pendingMarker =
                        if (failure == AccountStatusFailure.UNCONFIRMED)
                            Escape(expected.uid, expected.digest())
                        else null
                    mutable.value =
                        mutable.value.copy(
                            busy = false,
                            failure = failure,
                            pending =
                                expected.takeIf { failure == AccountStatusFailure.UNCONFIRMED },
                        )
                }
            } finally {
                if (ticket == owner) mutable.value = mutable.value.copy(busy = false)
            }
        }
    }

    fun reconcile() {
        val captured = mutable.value
        val session = captured.session ?: return
        val expected = captured.pending ?: captured.notice ?: return
        if (!captured.visible || captured.busy || !current(session, expected)) return
        val owner = ++ticket
        mutable.value = captured.copy(busy = true, failure = null)
        operation = viewModelScope.launch {
            try {
                val result = repository.reconcile(session, expected)
                if (ticket != owner || !current(session, expected)) return@launch
                pendingMarker = null
                mutable.value =
                    when (result) {
                        AccountStatusReconciliation.CONFIRMED ->
                            mutable.value.copy(notice = null, pending = null, busy = false)
                        AccountStatusReconciliation.NOT_CONFIRMED ->
                            mutable.value.copy(pending = null, busy = false, failure = null)
                        AccountStatusReconciliation.CHANGED ->
                            mutable.value.copy(
                                pending = null,
                                busy = false,
                                failure = AccountStatusFailure.STALE,
                            )
                    }
                if (result == AccountStatusReconciliation.CHANGED) refreshSession()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (ticket == owner && current(session, expected))
                    mutable.value = mutable.value.copy(busy = false, failure = statusFailure(error))
            } finally {
                if (ticket == owner) mutable.value = mutable.value.copy(busy = false)
            }
        }
    }

    fun requestSignOut() {
        val captured = mutable.value
        val session = captured.session ?: return
        val expected = captured.notice ?: return
        if (!captured.visible || captured.busy || !current(session, expected)) return
        val owner = ++ticket
        mutable.value = captured.copy(busy = true, failure = null)
        operation = viewModelScope.launch {
            try {
                val completed = signOut(session)
                if (ticket == owner && current(session, expected))
                    mutable.value =
                        mutable.value.copy(
                            busy = false,
                            notice = if (completed) null else expected,
                            failure = if (completed) null else AccountStatusFailure.SIGN_OUT_FAILED,
                        )
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                if (ticket == owner && current(session, expected))
                    mutable.value =
                        mutable.value.copy(
                            busy = false,
                            failure = AccountStatusFailure.SIGN_OUT_FAILED,
                        )
            } finally {
                if (ticket == owner) mutable.value = mutable.value.copy(busy = false)
            }
        }
    }

    /** Escape only to verification/MFA; does not acknowledge or persist a dismissal. */
    fun escapeForAuthentication(): Boolean {
        val value = mutable.value
        val session = value.session ?: return false
        val expected = value.notice ?: return false
        if (
            !value.visible ||
                value.busy ||
                session.canAcknowledge ||
                expected.requiresSignOut ||
                !current(session, expected)
        )
            return false
        escaped = Escape(expected.uid, expected.digest())
        mutable.value = value.copy(notice = null)
        return true
    }
}

/** Memory-only remediation marker; no reason/message survives a temporary cleared Auth profile. */
private fun AccountStatusVersion.digest(): List<Byte> {
    val digest = MessageDigest.getInstance("SHA-256")
    for (value in
        listOf(
            uid,
            status,
            blockState,
            updatedAt.toString(),
            reason,
            message,
            expiresAt?.toString(),
        )) {
        if (value == null) digest.update(0.toByte())
        else {
            digest.update(1.toByte())
            val bytes = value.toByteArray(Charsets.UTF_8)
            digest.update(ByteBuffer.allocate(4).putInt(bytes.size).array())
            digest.update(bytes)
        }
    }
    return digest.digest().toList()
}
