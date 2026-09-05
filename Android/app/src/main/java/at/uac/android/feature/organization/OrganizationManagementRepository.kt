package at.uac.android.feature.organization

import at.uac.android.feature.browse.Fields
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow

interface OrganizationManagementSource {
    suspend fun organization(id: String, session: OrganizationSession): OrganizationRecord?

    suspend fun subscribers(
        id: String,
        after: OrganizationSubscriberCursor?,
        session: OrganizationSession,
    ): OrganizationSubscriberPage

    suspend fun profiles(
        ids: List<String>,
        session: OrganizationSession,
    ): List<OrganizationPublicMember>

    fun changes(id: String, session: OrganizationSession): Flow<Result<Unit>>

    suspend fun update(base: OrganizationRecord, fields: Fields, session: OrganizationSession)

    suspend fun logo(
        base: OrganizationRecord,
        jpeg: ByteArray,
        session: OrganizationSession,
    ): OrganizationRecord

    suspend fun role(
        base: OrganizationRecord,
        intent: OrganizationRoleIntent,
        session: OrganizationSession,
    ): Any?
}

class OrganizationManagementRepository(
    private val source: OrganizationManagementSource,
    private val current: () -> OrganizationSession?,
    private val gate: OrganizationMutationGate,
) {
    private fun capture(): OrganizationSession =
        (current() ?: fail(OrganizationManagementFailure.SIGN_IN)).also {
            if (!it.ready) fail(OrganizationManagementFailure.NOT_READY)
        }

    private fun ensure(session: OrganizationSession) {
        if (session != current())
            throw CancellationException("Organization management session changed")
    }

    private suspend fun fresh(id: String, session: OrganizationSession): OrganizationRecord {
        if (!OrganizationContract.id(id)) fail(OrganizationManagementFailure.INVALID)
        ensure(session)
        val record =
            source.organization(id, session).also { ensure(session) }
                ?: fail(OrganizationManagementFailure.MISSING)
        if (record.id != id) fail(OrganizationManagementFailure.INVALID)
        val canonical = OrganizationManagementContract.requireApproved(record, session)
        if (canonical.authority == OrganizationAuthority.NONE)
            fail(OrganizationManagementFailure.DENIED)
        return canonical
    }

    private fun unchanged(base: OrganizationRecord, actual: OrganizationRecord) {
        if (
            base.id != actual.id ||
                base.updatedAt != actual.updatedAt ||
                base.fields != actual.fields
        )
            fail(OrganizationManagementFailure.STALE)
    }

    suspend fun load(
        id: String,
        previous: OrganizationManagementSnapshot? = null,
    ): OrganizationManagementSnapshot {
        val session = capture()
        val organization = fresh(id, session)
        if (previous != null) unchanged(previous.organization, organization)
        val page = source.subscribers(id, previous?.next, session).also { ensure(session) }
        if (previous != null && previous.next == null) fail(OrganizationManagementFailure.INVALID)
        if (page.next != null && page.next == previous?.next)
            fail(OrganizationManagementFailure.INVALID)
        val subscriberIds =
            (previous?.subscriberIds.orEmpty() + page.items.map { it.userId }).distinct()
        val teamIds = OrganizationManagementContract.teamIds(organization)
        val cached = previous?.members.orEmpty().map { it.profile }.associateBy { it.id }
        val ids =
            (teamIds.take(OrganizationManagementContract.MAX_TEAM_PROFILES) + subscriberIds)
                .distinct()
        val fetched =
            source.profiles(ids.filterNot(cached::containsKey), session).also { ensure(session) }
        if (fetched.any { it.id !in ids }) fail(OrganizationManagementFailure.INVALID)
        unchanged(organization, fresh(id, session))
        return OrganizationManagementSnapshot(
            organization,
            OrganizationManagementContract.members(
                organization,
                subscriberIds,
                cached.values.toList() + fetched,
            ),
            subscriberIds,
            page.next,
            teamIds.size > OrganizationManagementContract.MAX_TEAM_PROFILES,
        )
    }

    fun changes(id: String, session: OrganizationSession): Flow<Result<Unit>> {
        if (!OrganizationContract.id(id)) fail(OrganizationManagementFailure.INVALID)
        return source.changes(id, session)
    }

    suspend fun save(
        base: OrganizationRecord,
        draft: OrganizationInformationDraft,
        jpeg: ByteArray?,
    ): OrganizationInformationResult {
        val session = capture()
        if (!OrganizationManagementContract.canEdit(base, session))
            fail(OrganizationManagementFailure.DENIED)
        val fields = OrganizationManagementContract.informationFields(draft, base)
        return gate
            .withSession(session) {
                ensure(session)
                val before = fresh(base.id, session)
                if (!OrganizationManagementContract.canEdit(before, session))
                    fail(OrganizationManagementFailure.DENIED)
                unchanged(base, before)
                if (fields.any { (key, value) -> before.fields[key] != value })
                    source.update(before, fields, session)
                ensure(session)
                val confirmed = fresh(base.id, session)
                if (fields.any { (key, value) -> confirmed.fields[key] != value })
                    fail(OrganizationManagementFailure.UNCONFIRMED)
                if (jpeg == null) OrganizationInformationResult(confirmed)
                else
                    try {
                        OrganizationInformationResult(
                            source.logo(confirmed, jpeg, session).also { ensure(session) }
                        )
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        ensure(session)
                        OrganizationInformationResult(confirmed, logoIncomplete = true)
                    }
            }
            .also { ensure(session) }
    }

    suspend fun apply(
        base: OrganizationRecord,
        intent: OrganizationRoleIntent,
    ): OrganizationRecord {
        val session = capture()
        OrganizationManagementContract.requireIntent(base, intent, session)
        return gate
            .withSession(session) {
                ensure(session)
                val before = fresh(base.id, session)
                OrganizationManagementContract.requireIntent(before, intent, session)
                // A recovered desired state must not generate another audit/notification receipt.
                if (
                    OrganizationManagementContract.role(before, intent.targetId) ==
                        OrganizationManagementContract.desired(intent)
                )
                    return@withSession before
                unchanged(base, before)
                if (
                    OrganizationManagementContract.role(before, intent.targetId) !=
                        intent.previousRole
                )
                    fail(OrganizationManagementFailure.STALE)
                val response = source.role(before, intent, session).also { ensure(session) }
                try {
                    val receipt = OrganizationManagementContract.receipt(response, before, intent)
                    val after = fresh(base.id, session)
                    OrganizationManagementContract.verifyRole(after, intent, receipt)
                    after
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    throw OrganizationManagementException(
                        OrganizationManagementFailure.UNCONFIRMED,
                        error,
                    )
                }
            }
            .also { ensure(session) }
    }

    private fun fail(failure: OrganizationManagementFailure): Nothing =
        OrganizationManagementContract.fail(failure)
}
