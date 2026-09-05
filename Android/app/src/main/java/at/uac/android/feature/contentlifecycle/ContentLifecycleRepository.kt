package at.uac.android.feature.contentlifecycle

import at.uac.android.feature.organization.OrganizationMutationGate
import at.uac.android.feature.organization.OrganizationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow

interface ContentLifecycleSource {
    suspend fun snapshot(
        target: ContentLifecycleTarget,
        session: OrganizationSession,
    ): ContentLifecycleSnapshot

    fun changes(
        snapshot: ContentLifecycleSnapshot,
        session: OrganizationSession,
    ): Flow<Result<Unit>>

    suspend fun execute(
        intent: ContentLifecycleIntent,
        session: OrganizationSession,
    ): ContentLifecycleReceipt
}

class ContentLifecycleRepository(
    private val source: ContentLifecycleSource,
    private val current: () -> OrganizationSession?,
    private val gate: OrganizationMutationGate,
) {
    private fun capture() =
        (current() ?: ContentLifecycleContract.fail(ContentLifecycleFailure.SIGN_IN)).also {
            if (!it.ready) ContentLifecycleContract.fail(ContentLifecycleFailure.NOT_READY)
        }

    private fun ensure(session: OrganizationSession) {
        if (session != current()) throw CancellationException("Lifecycle session changed")
    }

    private suspend fun load(
        target: ContentLifecycleTarget,
        session: OrganizationSession,
    ): ContentLifecycleSnapshot {
        ensure(session)
        return source.snapshot(target, session).also {
            ensure(session)
            ContentLifecycleContract.validate(it, target, session)
        }
    }

    suspend fun load(target: ContentLifecycleTarget) = load(target, capture())

    fun changes(snapshot: ContentLifecycleSnapshot, session: OrganizationSession) =
        source.changes(snapshot, session)

    suspend fun execute(intent: ContentLifecycleIntent): ContentLifecycleConfirmation {
        val session = capture()
        return gate
            .withSession(session) {
                val before = load(intent.snapshot.target, session)
                if (before.item == null)
                    ContentLifecycleContract.fail(ContentLifecycleFailure.MISSING)
                if (!ContentLifecycleContract.actionable(before, session))
                    ContentLifecycleContract.fail(ContentLifecycleFailure.READ_ONLY)
                ContentLifecycleContract.unchanged(intent.snapshot, before)
                // Exactly one callable. Its awaited Task stays inside the Auth identity mutex.
                val receipt = source.execute(intent, session)
                ensure(session)
                try {
                    val after = load(before.target, session)
                    if (!ContentLifecycleContract.confirmed(before, after, receipt, session))
                        ContentLifecycleContract.fail(ContentLifecycleFailure.UNCONFIRMED)
                    ContentLifecycleConfirmation(after, receipt)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    throw ContentLifecycleException(ContentLifecycleFailure.UNCONFIRMED, error)
                }
            }
            .also { ensure(session) }
    }

    /**
     * Read only. Neither absence nor a cancellation marker authorizes replay of an uncertain
     * cascade.
     */
    suspend fun recover(intent: ContentLifecycleIntent): ContentLifecycleRecovery {
        val session = capture()
        val after = load(intent.snapshot.target, session)
        return ContentLifecycleRecovery(
            after,
            ContentLifecycleContract.observed(intent.snapshot, after, session),
        )
    }
}
