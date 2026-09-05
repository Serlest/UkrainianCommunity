package at.uac.android.feature.accountstatus

import at.uac.android.feature.auth.AuthStore
import kotlinx.coroutines.CancellationException

interface AccountStatusSource {
    suspend fun read(session: AccountStatusSession): AccountStatusObservation

    suspend fun acknowledge(
        session: AccountStatusSession,
        expected: AccountStatusVersion,
        canDispatch: () -> Boolean,
        onDispatch: () -> Unit,
    )
}

interface AccountStatusMutationGate {
    suspend fun <T> withSession(session: AccountStatusSession, action: suspend () -> T): T
}

interface AccountStatusReadGate {
    suspend fun <T> withReadSession(session: AccountStatusSession, action: suspend () -> T): T
}

class AuthAccountStatusGate(private val auth: AuthStore) :
    AccountStatusMutationGate, AccountStatusReadGate {
    override suspend fun <T> withSession(
        session: AccountStatusSession,
        action: suspend () -> T,
    ): T = auth.withStatusAcknowledgementSession(session.uid, session.revision, action)

    override suspend fun <T> withReadSession(
        session: AccountStatusSession,
        action: suspend () -> T,
    ): T = auth.withInboxSession(session.uid, session.revision, action)
}

class AccountStatusRepository(
    private val source: AccountStatusSource,
    private val gate: AccountStatusMutationGate,
    private val readGate: AccountStatusReadGate,
) {
    suspend fun acknowledge(
        session: AccountStatusSession,
        expected: AccountStatusVersion,
        onDispatch: () -> Unit = {},
        canDispatch: () -> Boolean,
    ): AccountStatusObservation {
        statusRequire(
            session.canAcknowledge && session.uid == expected.uid,
            AccountStatusFailure.DENIED,
        )
        statusRequire(session.observation.notice == expected, AccountStatusFailure.STALE)
        return gate.withSession(session) {
            var dispatched = false
            try {
                source.acknowledge(session, expected, canDispatch) {
                    dispatched = true
                    onDispatch()
                }
                val observed = source.read(session)
                statusRequire(observed.version == expected, AccountStatusFailure.STALE)
                statusRequire(observed.confirms(expected), AccountStatusFailure.UNCONFIRMED)
                observed
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                val failure = statusFailure(error)
                if (
                    failure in
                        setOf(
                            AccountStatusFailure.STALE,
                            AccountStatusFailure.DENIED,
                            AccountStatusFailure.INVALID,
                        )
                )
                    throw error
                throw AccountStatusException(
                    if (dispatched) AccountStatusFailure.UNCONFIRMED else failure,
                    error,
                )
            }
        }
    }

    /** Read only. A failed/unknown acknowledgement is never resent by this method. */
    suspend fun reconcile(
        session: AccountStatusSession,
        expected: AccountStatusVersion,
    ): AccountStatusReconciliation {
        statusRequire(session.uid == expected.uid, AccountStatusFailure.DENIED)
        val observed = readGate.withReadSession(session) { source.read(session) }
        return when {
            observed.confirms(expected) -> AccountStatusReconciliation.CONFIRMED
            observed.version != expected -> AccountStatusReconciliation.CHANGED
            else -> AccountStatusReconciliation.NOT_CONFIRMED
        }
    }
}
