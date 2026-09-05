package at.uac.android.feature.attendees

import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.personal.validDocumentId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow

interface AttendeesSource {
    suspend fun event(id: String, session: AttendeesSession): RawDocument

    suspend fun organization(id: String, session: AttendeesSession): RawDocument?

    suspend fun registrations(
        id: String,
        after: String?,
        session: AttendeesSession,
    ): AttendeesRawPage

    suspend fun profiles(ids: List<String>, session: AttendeesSession): List<RawDocument>

    fun accessChanges(
        id: String,
        organizationId: String?,
        session: AttendeesSession,
    ): Flow<Result<Unit>>

    fun changes(id: String, organizationId: String?, session: AttendeesSession): Flow<Result<Unit>>
}

class AttendeesRepository(
    private val source: AttendeesSource,
    private val authority: () -> AttendeesSession?,
) {
    private fun current(session: AttendeesSession) {
        if (authority() != session) throw CancellationException("Attendee account changed")
    }

    private suspend fun documents(
        id: String,
        session: AttendeesSession,
    ): Pair<RawDocument, RawDocument?> {
        current(session)
        val event = source.event(id, session)
        if (event.id != id) throw AttendeesException(AttendeesFailure.INVALID)
        current(session)
        val organizationId = (event.fields["organizationId"] as? String)?.takeIf(String::isNotBlank)
        // The platform owner is authorized by the authoritative session, not by a client
        // organization override.
        val organization =
            if (
                session.globalRole != "owner" &&
                    event.fields["sourceType"] == "organization" &&
                    organizationId != null
            )
                source.organization(organizationId, session)
            else null
        current(session)
        return event to organization
    }

    private suspend fun target(id: String, session: AttendeesSession): AttendeesEvent {
        val (event, organization) = documents(id, session)
        return AttendeesContract.authorize(event, organization, session)
    }

    /**
     * Only event and organization documents; deciding whether to offer the entry point never reads
     * attendees.
     */
    suspend fun access(id: String): AttendeesEvent {
        val check = inspectAccess(id)
        return check.event ?: throw AttendeesException(check.failure ?: AttendeesFailure.DENIED)
    }

    /**
     * A denied public-role check still supplies the public organization watch target, so gaining a
     * role can revalidate.
     */
    suspend fun inspectAccess(id: String): AttendeesAccessCheck {
        val session = authority() ?: throw AttendeesException(AttendeesFailure.SIGN_IN)
        if (!session.ready) throw AttendeesException(AttendeesFailure.NOT_READY)
        if (!AttendeesContract.eventId(id)) throw AttendeesException(AttendeesFailure.INVALID)
        val (event, organization) = documents(id, session)
        val orgId =
            (event.fields["organizationId"] as? String)?.takeIf {
                event.fields["sourceType"] == "organization" &&
                    at.uac.android.feature.organization.OrganizationContract.id(it)
            }
        val check =
            try {
                AttendeesAccessCheck(
                    AttendeesContract.authorize(event, organization, session),
                    orgId,
                    null,
                )
            } catch (error: AttendeesException) {
                if (
                    error.failure !in
                        setOf(AttendeesFailure.DENIED, AttendeesFailure.NOT_APPLICABLE)
                )
                    throw error
                AttendeesAccessCheck(null, orgId, error.failure)
            }
        current(session)
        return check
    }

    suspend fun load(id: String, previous: AttendeesPage? = null): AttendeesPage {
        val session = authority() ?: throw AttendeesException(AttendeesFailure.SIGN_IN)
        if (!session.ready) throw AttendeesException(AttendeesFailure.NOT_READY)
        if (
            !AttendeesContract.eventId(id) ||
                previous?.event?.id?.let { it != id } == true ||
                previous?.next?.eventId?.let { it != id } == true ||
                previous != null && (previous.next == null || previous.session != session) ||
                previous?.next?.documentId?.let { !validDocumentId(it) } == true
        )
            throw AttendeesException(AttendeesFailure.INVALID)
        target(id, session)
        val raw = source.registrations(id, previous?.next?.documentId, session)
        current(session)
        val identifiers = raw.rows.map { it.id }
        if (
            raw.rows.size > AttendeesContract.PAGE_SIZE ||
                identifiers.any { !validDocumentId(it) } ||
                identifiers.zipWithNext().any { (left, right) ->
                    AttendeesContract.compareDocumentIds(left, right) >= 0
                } ||
                previous?.next?.documentId?.let { after ->
                    identifiers.any { AttendeesContract.compareDocumentIds(it, after) <= 0 }
                } == true ||
                raw.next?.let { next ->
                    raw.rows.size != AttendeesContract.PAGE_SIZE || identifiers.lastOrNull() != next
                } == true
        )
            throw AttendeesException(AttendeesFailure.INVALID)
        val valid = raw.rows.mapNotNull { AttendeesContract.row(it, id) }
        val requested = valid.map { it.userId }.distinct()
        val joined = source.profiles(requested, session)
        if (
            joined.any { it.id !in requested } ||
                joined.map { it.id }.distinct().size != joined.size
        )
            throw AttendeesException(AttendeesFailure.INVALID)
        val profiles = joined.associateBy { it.id }
        current(session)
        val people = valid.map { AttendeesContract.withProfile(it, profiles[it.userId]) }
        // Re-check current event/role after the join; an old permission snapshot cannot publish a
        // private page.
        val fresh = target(id, session)
        current(session)
        return AttendeesPage(
            fresh,
            (previous?.people.orEmpty() + people).distinctBy { it.userId },
            raw.next?.let { AttendeesCursor(id, it) },
            (previous?.invalid ?: 0) + raw.rows.size - valid.size,
            session,
        )
    }
}
