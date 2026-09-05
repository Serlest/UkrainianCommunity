package at.uac.android.feature.accountdeletion

import android.content.Context
import at.uac.android.core.LocalAccountDeletionJournal
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.AuthStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.map

fun AuthSession.accountDeletionScope(): AccountDeletionSession? =
    identity
        ?.takeIf {
            !it.anonymous &&
                !busy &&
                stage in
                    setOf(
                        AuthStage.AUTHENTICATED,
                        AuthStage.VERIFICATION_PENDING,
                        AuthStage.SESSION_UNAVAILABLE,
                    )
        }
        ?.let { AccountDeletionSession(it.uid, revision) }

class AuthAccountDeletionGate(private val auth: AuthStore) : AccountDeletionGate {
    override suspend fun <T> withSession(
        session: AccountDeletionSession,
        action: suspend () -> T,
    ): T =
        try {
            auth.withAccountDeletionSession(session.uid, session.revision, action)
        } catch (error: AuthException) {
            if (error.problem == AuthProblem.SESSION_CHANGED)
                throw CancellationException("Account deletion session changed")
            throw AccountDeletionException(accountDeletionFailure(error), error)
        }
}

/**
 * Host may show a generic completion notice; it must not initiate another sign-out or reload inside
 * the identity gate.
 */
fun localAccountDeletionViewModel(
    context: Context,
    auth: AuthStore,
    onConfirmed: (AccountDeletionSession, AccountDeletionReceipt) -> Unit,
): AccountDeletionViewModel =
    AccountDeletionViewModel(
            localAccountDeletionSource(context),
            LocalAccountDeletionJournal.get(context),
            { auth.state.value.accountDeletionScope() },
            AuthAccountDeletionGate(auth),
            { session, receipt ->
                auth.signOutDeletedIdentity(session.uid, session.revision)
                onConfirmed(session, receipt)
            },
        )
        .also { it.observeSessions(auth.state.map { state -> state.accountDeletionScope() }) }
