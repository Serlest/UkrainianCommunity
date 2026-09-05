package at.uac.android.feature.attendees

import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.fold
import at.uac.android.feature.browse.string
import at.uac.android.feature.community.communityId
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.personal.validDocumentId
import at.uac.android.feature.personal.validProfileAvatar
import java.text.Collator
import java.time.Instant
import java.util.Locale

data class AttendeesSession(
    val uid: String,
    val revision: Long,
    val ready: Boolean,
    val globalRole: String,
) {
    override fun toString() = "AttendeesSession([redacted], revision=$revision, ready=$ready)"
}

fun AuthSession.attendeesScope(): AttendeesSession? =
    identity
        ?.takeUnless { it.anonymous }
        ?.let {
            AttendeesSession(
                it.uid,
                revision,
                readyForActions && profile?.uid == it.uid,
                profile?.globalRole.orEmpty(),
            )
        }

enum class AttendeesFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    INVALID,
    MISSING,
    NOT_APPLICABLE,
    OFFLINE,
    INDEX,
    UNKNOWN,
}

class AttendeesException(val failure: AttendeesFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

enum class AttendeesSort {
    OLDEST,
    NEWEST,
    NAME_ASCENDING,
    NAME_DESCENDING,
}

data class AttendeesEvent(
    val id: String,
    val organizationId: String?,
    val title: String,
    val ukrainianTitle: String,
    val capacity: Long?,
    val registeredCount: Long,
) {
    fun title(language: String) = if (language == "uk") ukrainianTitle else title
}

data class Attendee(
    val id: String,
    val userId: String,
    val registeredAt: Instant?,
    val displayName: String?,
    val avatarUrl: String?,
) {
    override fun toString() = "Attendee([redacted], dated=${registeredAt != null})"
}

data class AttendeesCursor(val eventId: String, val documentId: String)

data class AttendeesRawPage(val rows: List<RawDocument>, val next: String?)

data class AttendeesAccessCheck(
    val event: AttendeesEvent?,
    val organizationId: String?,
    val failure: AttendeesFailure?,
)

data class AttendeesPage(
    val event: AttendeesEvent,
    val people: List<Attendee>,
    val next: AttendeesCursor?,
    val invalid: Int = 0,
    val session: AttendeesSession? = null,
)

object AttendeesContract {
    const val PAGE_SIZE = 25

    fun eventId(value: String) = communityId(value)

    fun userId(value: String) = communityId(value, 128)

    private fun fail(reason: AttendeesFailure): Nothing = throw AttendeesException(reason)

    /** Matches build 65's UI authority; Rules are broader for unassigned platform admins. */
    fun authorize(
        event: RawDocument,
        organization: RawDocument?,
        session: AttendeesSession,
    ): AttendeesEvent {
        if (!session.ready) fail(AttendeesFailure.NOT_READY)
        if (
            !userId(session.uid) ||
                !eventId(event.id) ||
                event.fields["id"]?.let { it != event.id } == true
        )
            fail(AttendeesFailure.INVALID)
        val organizationId = (event.fields["organizationId"] as? String)?.takeIf(String::isNotBlank)
        val organizationEvent =
            event.fields["sourceType"] == "organization" && organizationId != null
        if (organizationEvent && !OrganizationContract.id(organizationId))
            fail(AttendeesFailure.INVALID)
        if (session.globalRole != "owner") {
            if (
                !organizationEvent ||
                    organization == null ||
                    organization.id != organizationId ||
                    !OrganizationContract.id(organization.id)
            )
                fail(AttendeesFailure.DENIED)
            val data = organization.fields
            if (organization.id == "ukrainian-community" || data["isSystemManaged"] == true)
                fail(AttendeesFailure.DENIED)
            val member =
                data["ownerId"] == session.uid ||
                    (data["adminIds"] as? List<*>)?.contains(session.uid) == true ||
                    (data["moderatorIds"] as? List<*>)?.contains(session.uid) == true
            if (!member) fail(AttendeesFailure.DENIED)
        }
        val count = nonnegativeInteger(event.fields["registeredCount"]) ?: 0
        if (event.fields["requiresRegistration"] != true && count == 0L)
            fail(AttendeesFailure.NOT_APPLICABLE)
        val content = Content(ContentKind.EVENTS, event.id, event.fields)
        return AttendeesEvent(
            event.id,
            organizationId.takeIf { organizationEvent },
            content.title("de").take(300),
            content.title("uk").take(300),
            nonnegativeInteger(event.fields["capacity"])?.takeIf { it > 0 },
            count,
        )
    }

    private fun nonnegativeInteger(value: Any?): Long? {
        if (value == null) return null
        val number = value as? Number ?: fail(AttendeesFailure.INVALID)
        val decimal = number.toDouble()
        val integer = number.toLong()
        if (!decimal.isFinite() || integer < 0 || decimal != integer.toDouble())
            fail(AttendeesFailure.INVALID)
        return integer
    }

    /**
     * Firestore document identifiers are ordered by UTF-8 bytes, not the JVM's UTF-16 code units.
     */
    fun compareDocumentIds(left: String, right: String): Int {
        val a = left.toByteArray(Charsets.UTF_8)
        val b = right.toByteArray(Charsets.UTF_8)
        for (index in 0 until minOf(a.size, b.size)) {
            val result = (a[index].toInt() and 255).compareTo(b[index].toInt() and 255)
            if (result != 0) return result
        }
        return a.size.compareTo(b.size)
    }

    fun row(value: RawDocument, eventId: String): Attendee? {
        val uid = value.fields["userId"] as? String ?: return null
        if (
            !userId(uid) ||
                value.fields["eventId"] != eventId ||
                !validDocumentId(value.id) ||
                value.id != "event_${eventId}_$uid" ||
                value.fields["id"]?.let { it != value.id } == true
        )
            return null
        return Attendee(
            value.id,
            uid,
            value.fields["registeredAt"] as? Instant ?: value.fields["createdAt"] as? Instant,
            null,
            null,
        )
    }

    fun withProfile(person: Attendee, profile: RawDocument?): Attendee {
        if (
            profile == null ||
                profile.id != person.userId ||
                profile.fields["id"]?.let { it != person.userId } == true
        )
            return person
        val name =
            profile.fields.string("displayName").takeIf(String::isNotEmpty)?.take(160)
                ?: return person
        val avatar =
            profile.fields.string("avatarURL").takeIf {
                it.isNotEmpty() && validProfileAvatar(it, person.userId)
            }
        // Never hydrate email, biography, phone, location, account status, or other private-user
        // fields.
        return person.copy(displayName = name, avatarUrl = avatar)
    }

    fun visible(
        people: List<Attendee>,
        search: String,
        sort: AttendeesSort,
        language: String,
    ): List<Attendee> {
        val selected = people.filter {
            fold(it.displayName.orEmpty()).contains(fold(search.trim()))
        }
        val names =
            Collator.getInstance(Locale.forLanguageTag(if (language == "uk") "uk" else "de"))
        val comparator =
            Comparator<Attendee> { a, b ->
                val result =
                    when (sort) {
                        AttendeesSort.OLDEST ->
                            compareValues(
                                a.registeredAt ?: Instant.MAX,
                                b.registeredAt ?: Instant.MAX,
                            )
                        AttendeesSort.NEWEST ->
                            compareValues(
                                b.registeredAt ?: Instant.MIN,
                                a.registeredAt ?: Instant.MIN,
                            )
                        AttendeesSort.NAME_ASCENDING ->
                            names.compare(a.displayName.orEmpty(), b.displayName.orEmpty())
                        AttendeesSort.NAME_DESCENDING ->
                            names.compare(b.displayName.orEmpty(), a.displayName.orEmpty())
                    }
                result.takeIf { it != 0 } ?: a.userId.compareTo(b.userId)
            }
        return selected.sortedWith(comparator)
    }
}
