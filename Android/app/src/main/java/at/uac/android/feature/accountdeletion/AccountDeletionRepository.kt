package at.uac.android.feature.accountdeletion

import at.uac.android.core.AccountDeletionJournal
import at.uac.android.core.DeletionJournalEntry
import java.time.Instant
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

class AccountDeletionRepository(
    private val source: AccountDeletionSource,
    private val journal: AccountDeletionJournal,
    private val authority: () -> AccountDeletionSession?,
    private val gate: AccountDeletionGate = DeniedAccountDeletionGate,
    private val clock: () -> Instant = Instant::now,
    private val freshnessWait: AccountDeletionFreshnessWait = AccountDeletionFreshnessWait(),
) {
    private var reconciled: Pair<AccountDeletionSession, Instant>? = null
    private var issuedChallenge: Pair<AccountDeletionSession, AccountDeletionChallenge>? = null

    private fun capture() =
        authority() ?: throw AccountDeletionException(AccountDeletionFailure.SIGN_IN)

    private fun current(session: AccountDeletionSession) {
        if (authority() != session) throw CancellationException("Account deletion identity changed")
    }

    private suspend fun <T> owned(session: AccountDeletionSession, action: suspend () -> T): T {
        current(session)
        return try {
            gate
                .withSession(session) { withContext(NonCancellable) { action() } }
                .also { current(session) }
        } catch (error: Exception) {
            current(session)
            throw error
        }
    }

    suspend fun inspect(): Pair<AccountDeletionPolicy, DeletionJournalEntry?> {
        val session = capture()
        return owned(session) {
            source.policy(session.uid) to checkpoint { journal.pending(session.uid) }
        }
    }

    suspend fun begin(
        password: String,
        attempt: AccountDeletionAttempt,
        onPhase: (AccountDeletionPhase) -> Unit,
        onSubmitted: (Instant) -> Unit,
    ): AccountDeletionStep {
        val session = capture()
        val originalCaller = currentCoroutineContext()
        if (password.isEmpty())
            throw AccountDeletionException(AccountDeletionFailure.PASSWORD_REQUIRED)
        return owned(session) {
            requireReconciledRetry(session)
            issuedChallenge = null
            validatePolicy(source.policy(session.uid))
            checkBeforeSubmission(session, attempt)
            onPhase(AccountDeletionPhase.REAUTHENTICATING)
            val proof =
                try {
                    source.reauthenticate(session.uid, password)
                } catch (challenge: AccountDeletionChallengeRequired) {
                    checkBeforeSubmission(session, attempt)
                    issuedChallenge = session to challenge.challenge
                    return@owned AccountDeletionStep.Challenge(challenge.challenge)
                }
            finish(session, proof, attempt, originalCaller, onPhase, onSubmitted)
        }
    }

    suspend fun completeChallenge(
        challenge: AccountDeletionChallenge,
        factorId: String,
        code: String,
        attempt: AccountDeletionAttempt,
        onPhase: (AccountDeletionPhase) -> Unit,
        onSubmitted: (Instant) -> Unit,
    ): AccountDeletionStep {
        val session = capture()
        val originalCaller = currentCoroutineContext()
        if (issuedChallenge?.first != session || issuedChallenge?.second !== challenge)
            throw AccountDeletionException(AccountDeletionFailure.SIGN_IN)
        if (challenge.factors.none { it.id == factorId } || !Regex("[0-9]{6}").matches(code.trim()))
            throw AccountDeletionException(AccountDeletionFailure.MFA_INVALID)
        return owned(session) {
            requireReconciledRetry(session)
            checkBeforeSubmission(session, attempt)
            onPhase(AccountDeletionPhase.REAUTHENTICATING)
            val proof = challenge.resolve(factorId, code.trim())
            finish(session, proof, attempt, originalCaller, onPhase, onSubmitted)
        }
    }

    private suspend fun finish(
        session: AccountDeletionSession,
        proof: AccountDeletionProof,
        attempt: AccountDeletionAttempt,
        originalCaller: CoroutineContext,
        onPhase: (AccountDeletionPhase) -> Unit,
        onSubmitted: (Instant) -> Unit,
    ): AccountDeletionStep {
        checkBeforeSubmission(session, attempt)
        if (proof.uid != session.uid) throw AccountDeletionException(AccountDeletionFailure.SIGN_IN)
        val now =
            freshnessWait.sampledNow(proof.authenticatedAt, clock(), clock) {
                // SDK tasks already settled; cancellation of the original caller may now stop this
                // pre-dispatch wait even though the enclosing identity gate is NonCancellable.
                originalCaller.ensureActive()
                checkBeforeSubmission(session, attempt)
            }
        requireRecentProof(proof, AccountDeletionFreshnessStage.FIRST_CLOCK_CHECK, now)
        val policy = source.policy(session.uid)
        validatePolicy(policy)
        if (policy.requiresTotp && !proof.totp)
            throw AccountDeletionException(AccountDeletionFailure.MFA_REQUIRED)
        // Recheck freshness after the server preflight, not only before potentially slow reads.
        requireRecentProof(proof, AccountDeletionFreshnessStage.POST_POLICY_CLOCK_CHECK)
        originalCaller.ensureActive()
        checkBeforeSubmission(session, attempt)
        requireReconciledRetry(session)
        val entry = checkpoint { journal.record(session.uid, clock()) }
        issuedChallenge = null
        reconciled = null
        onSubmitted(entry.submittedAt)
        checkBeforeSubmission(session, attempt)
        originalCaller.ensureActive()
        onPhase(AccountDeletionPhase.DELETING)
        // This is the only destructive request. No timeout wrapper, client cascade, or automatic
        // retry.
        val receipt = source.delete(session.uid)
        val cleared = runCatching {
            journal.clearConfirmed(session.uid, entry.submittedAt)
        }
            .getOrDefault(false)
        return AccountDeletionStep.Completed(receipt.copy(journalCleared = cleared))
    }

    private fun requireRecentProof(
        proof: AccountDeletionProof,
        stage: AccountDeletionFreshnessStage,
        now: Instant = clock(),
    ) {
        // Exactly one clock sample for the unchanged decision and its redacted diagnostic.
        if (!proof.recent(now))
            throw AccountDeletionException(
                AccountDeletionFailure.RECENT_AUTH_REQUIRED,
                freshnessDiagnostic =
                    AccountDeletionFreshnessDiagnostic.rejectedClock(
                        stage,
                        proof.authenticatedAt,
                        now,
                    ),
            )
    }

    private fun validatePolicy(policy: AccountDeletionPolicy) {
        if (policy.platformOwner)
            throw AccountDeletionException(AccountDeletionFailure.PLATFORM_OWNER)
        if (policy.ownsOrganization == true)
            throw AccountDeletionException(AccountDeletionFailure.ORGANIZATION_OWNER)
    }

    private fun checkBeforeSubmission(
        session: AccountDeletionSession,
        attempt: AccountDeletionAttempt,
    ) {
        current(session)
        if (attempt.cancellationRequested)
            throw CancellationException("Account deletion cancelled before submission")
    }

    suspend fun reconcile(): Pair<AccountDeletionIdentityStatus, AccountDeletionReceipt?> {
        val session = capture()
        return owned(session) {
            val entry =
                checkpoint { journal.pending(session.uid) }
                    ?: throw AccountDeletionException(AccountDeletionFailure.INVALID)
            val status = source.status(session.uid)
            if (status == AccountDeletionIdentityStatus.ABSENT) {
                reconciled = null
                val cleared = runCatching {
                    journal.clearConfirmed(session.uid, entry.submittedAt)
                }
                    .getOrDefault(false)
                status to
                    AccountDeletionReceipt(
                        clock(),
                        AccountDeletionConfirmation.AUTH_IDENTITY_ABSENT,
                        cleared,
                    )
            } else {
                if (status == AccountDeletionIdentityStatus.PARTIAL)
                    checkpoint { journal.markPartial(session.uid, entry.submittedAt) }
                reconciled = session to entry.submittedAt
                status to null
            }
        }
    }

    private suspend fun requireReconciledRetry(session: AccountDeletionSession) {
        val entry = checkpoint { journal.pending(session.uid) } ?: return
        if (
            reconciled != (session to entry.submittedAt) ||
                clock()
                    .isBefore(
                        entry.submittedAt.plusSeconds(
                            AccountDeletionContract.REQUEST_TIMEOUT_SECONDS
                        )
                    )
        ) {
            throw AccountDeletionException(AccountDeletionFailure.UNCONFIRMED)
        }
    }

    private suspend fun <T> checkpoint(action: suspend () -> T): T =
        try {
            action()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw AccountDeletionException(AccountDeletionFailure.CHECKPOINT, error)
        }
}
