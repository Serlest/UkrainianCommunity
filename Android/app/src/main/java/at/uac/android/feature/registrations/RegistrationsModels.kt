package at.uac.android.feature.registrations

import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.time
import at.uac.android.feature.personal.PersonalFailure
import at.uac.android.feature.personal.PersonalSession
import java.time.Instant
import java.time.ZoneId

enum class RegistrationSegment {
    ALL,
    UPCOMING,
    PAST,
}

data class RegistrationsPage(
    val items: List<Content>,
    val next: String?,
    val hasMore: Boolean,
    val unavailable: Int,
)

data class RegistrationsState(
    val session: PersonalSession? = null,
    val items: List<Content> = emptyList(),
    val loading: Boolean = false,
    val loaded: Boolean = false,
    val next: String? = null,
    val hasMore: Boolean = false,
    val unavailable: Int = 0,
    val error: PersonalFailure? = null,
    val segment: RegistrationSegment = RegistrationSegment.UPCOMING,
) {
    fun forSession(current: PersonalSession?): RegistrationsState =
        if (session == current) this else RegistrationsState(session = current)

    fun visibleTo(visible: (Content) -> Boolean): RegistrationsState =
        copy(items = items.filter(visible))
}

/** Matches build 65: an event earlier today is still in the upcoming/today group. */
fun registrationEvents(
    items: List<Content>,
    segment: RegistrationSegment,
    now: Instant = Instant.now(),
    zone: ZoneId = ZoneId.systemDefault(),
): List<Content> {
    val today = now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
    val upcoming =
        items
            .filter { it.fields.time("endDate")?.let { end -> end >= today } == true }
            .sortedWith(compareBy<Content> { it.fields.time("startDate") }.thenBy { it.id })
    val past =
        items
            .filter { it.fields.time("endDate")?.let { end -> end < today } == true }
            .sortedWith(compareByDescending<Content> { it.fields.time("endDate") }.thenBy { it.id })
    return when (segment) {
        RegistrationSegment.ALL -> upcoming + past
        RegistrationSegment.UPCOMING -> upcoming
        RegistrationSegment.PAST -> past
    }
}
