package at.uac.android.feature.authoring

import at.uac.android.feature.authoring.recovery.AuthoringRecoveryScope
import at.uac.android.feature.authoring.recovery.AuthoringRecoveryStore
import at.uac.android.feature.authoring.recovery.MemoryAuthoringRecoveryStore
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.OrganizationMutationGate
import at.uac.android.feature.organization.OrganizationRecord
import at.uac.android.feature.organization.OrganizationSession
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow

interface AuthoringSource {
    suspend fun organization(id: String, session: OrganizationSession): OrganizationRecord?

    suspend fun page(
        organizationId: String,
        kind: ContentKind,
        status: AuthoringStatus,
        after: AuthoringCursor?,
        session: OrganizationSession,
    ): AuthoringPage

    suspend fun find(
        organizationId: String,
        kind: ContentKind,
        id: String,
        session: OrganizationSession,
    ): AuthoringItem?

    fun changes(
        organizationId: String,
        kind: ContentKind,
        status: AuthoringStatus,
        session: OrganizationSession,
        target: AuthoringItem? = null,
    ): Flow<Result<Unit>>

    suspend fun commit(
        submission: AuthoringSubmission,
        organization: OrganizationRecord,
        session: OrganizationSession,
    )
}

class AuthoringRepository(
    private val source: AuthoringSource,
    private val current: () -> OrganizationSession?,
    private val gate: OrganizationMutationGate,
    private val recoveryStore: AuthoringRecoveryStore = MemoryAuthoringRecoveryStore(),
    private val now: () -> Instant = Instant::now,
) {
    private fun capture(): OrganizationSession =
        (current() ?: AuthoringContract.fail(AuthoringFailure.SIGN_IN)).also {
            if (!it.ready) AuthoringContract.fail(AuthoringFailure.NOT_READY)
        }

    private fun ensure(session: OrganizationSession) {
        if (session != current()) throw CancellationException("Authoring session changed")
    }

    private suspend fun organization(id: String, session: OrganizationSession): OrganizationRecord {
        if (!AuthoringContract.id(id)) AuthoringContract.invalid()
        ensure(session)
        val actual =
            source.organization(id, session).also { ensure(session) }
                ?: AuthoringContract.fail(AuthoringFailure.MISSING)
        if (actual.id != id) AuthoringContract.invalid()
        return AuthoringContract.authority(actual, session)
    }

    suspend fun load(
        id: String,
        kind: ContentKind,
        status: AuthoringStatus,
        previous: AuthoringHub? = null,
    ): AuthoringHub {
        val session = capture()
        val org = organization(id, session)
        if (
            kind !in AuthoringContract.kinds ||
                previous != null &&
                    (previous.kind != kind ||
                        previous.status != status ||
                        previous.organization.id != id ||
                        previous.page.next == null)
        )
            AuthoringContract.invalid()
        val page =
            source.page(id, kind, status, previous?.page?.next, session).also { ensure(session) }
        if (
            page.items.any { it.organizationId != id || it.kind != kind || it.status != status } ||
                page.next != null && page.next == previous?.page?.next
        )
            AuthoringContract.invalid()
        val latest = organization(id, session)
        if (org.fields != latest.fields) AuthoringContract.fail(AuthoringFailure.STALE)
        val old = previous?.page?.items.orEmpty()
        if ((old + page.items).map { it.id }.distinct().size != old.size + page.items.size)
            AuthoringContract.fail(AuthoringFailure.STALE)
        return AuthoringHub(latest, kind, status, page.copy(items = old + page.items))
    }

    suspend fun open(
        id: String,
        kind: ContentKind,
        contentId: String,
    ): Pair<OrganizationRecord, AuthoringItem> {
        val session = capture()
        val org = organization(id, session)
        val item =
            source.find(id, kind, contentId, session).also { ensure(session) }
                ?: AuthoringContract.fail(AuthoringFailure.MISSING)
        if (item.id != contentId || item.kind != kind || item.organizationId != id)
            AuthoringContract.invalid()
        if (!item.editable) AuthoringContract.fail(AuthoringFailure.DENIED)
        if (organization(id, session).fields != org.fields)
            AuthoringContract.fail(AuthoringFailure.STALE)
        return org to item
    }

    fun changes(
        id: String,
        kind: ContentKind,
        status: AuthoringStatus,
        session: OrganizationSession,
        target: AuthoringItem? = null,
    ): Flow<Result<Unit>> = source.changes(id, kind, status, session, target)

    suspend fun submit(submission: AuthoringSubmission): AuthoringItem {
        val session = capture()
        return gate
            .withSession(session) {
                ensure(session)
                val org = organization(submission.organizationId, session)
                val scope = AuthoringRecoveryScope(session.uid, org.id, submission.kind)
                // The pending copy is immutable and cannot be replaced by a freshly generated UUID.
                if (submission.base == null)
                    recoveryStore.load(scope)?.pending?.let { stored ->
                        if (stored != submission)
                            throw at.uac.android.feature.authoring.recovery
                                .AuthoringRecoveryException(
                                    at.uac.android.feature.authoring.recovery
                                        .AuthoringRecoveryFailure
                                        .PENDING_CONFLICT
                                )
                    }
                ensure(session)
                val existing =
                    source.find(org.id, submission.kind, submission.id, session).also {
                        ensure(session)
                    }
                if (existing != null && AuthoringContract.matches(submission, existing)) {
                    if (submission.base == null)
                        recoveryStore.confirmCreation(scope, submission, existing)
                    ensure(session)
                    return@withSession existing
                }
                if (submission.base == null) {
                    if (existing != null) AuthoringContract.fail(AuthoringFailure.STALE)
                } else {
                    if (existing == null) AuthoringContract.fail(AuthoringFailure.MISSING)
                    if (!existing.editable) AuthoringContract.fail(AuthoringFailure.DENIED)
                    AuthoringContract.unchanged(submission.base, existing)
                }
                // Durable encrypted read-back is inside the same identity gate and precedes every
                // create SDK call.
                // Match above remains recoverable after its chosen time; absence never silently
                // retimes it.
                AuthoringPublication.requireFreshIntent(submission, now())
                val durable =
                    if (submission.base == null) recoveryStore.prepareCreation(scope, submission)
                    else submission
                ensure(session)
                AuthoringPublication.requireFreshIntent(durable, now())
                source.commit(durable, org, session)
                ensure(session)
                try {
                    val confirmed =
                        source.find(org.id, submission.kind, submission.id, session).also {
                            ensure(session)
                        } ?: AuthoringContract.fail(AuthoringFailure.UNCONFIRMED)
                    if (!AuthoringContract.matches(submission, confirmed))
                        AuthoringContract.fail(AuthoringFailure.UNCONFIRMED)
                    if (submission.base == null)
                        recoveryStore.confirmCreation(scope, submission, confirmed)
                    ensure(session)
                    confirmed
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    throw AuthoringException(AuthoringFailure.UNCONFIRMED, cause = error)
                }
            }
            .also { ensure(session) }
    }

    /**
     * Read only: absence is not a reason to auto-resend. The UI asks for a new explicit decision.
     */
    suspend fun recover(submission: AuthoringSubmission): AuthoringItem? {
        val session = capture()
        return gate.withSession(session) {
            organization(submission.organizationId, session)
            val actual =
                source
                    .find(submission.organizationId, submission.kind, submission.id, session)
                    .also { ensure(session) }
            if (
                submission.base == null &&
                    actual != null &&
                    AuthoringContract.matches(submission, actual)
            )
                recoveryStore.confirmCreation(
                    AuthoringRecoveryScope(session.uid, submission.organizationId, submission.kind),
                    submission,
                    actual,
                )
            ensure(session)
            actual
        }
    }
}
