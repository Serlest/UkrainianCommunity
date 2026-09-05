package at.uac.android.feature.inbox

import java.time.Instant

/** Navigation is authorized at the moment of use, not when a dialog was composed. */
sealed interface InboxNavigationTarget {
    data class Route(val path: String, val publicContent: Boolean = false) : InboxNavigationTarget

    data class External(val url: String) : InboxNavigationTarget
}

fun resolveInboxNavigation(
    notice: InboxNotice,
    destination: InboxDestination,
    capturedSession: InboxSession?,
    currentSession: InboxSession?,
    canManageFeedback: Boolean,
    now: Instant,
): InboxNavigationTarget? {
    if (
        capturedSession == null ||
            capturedSession != currentSession ||
            notice.uid != capturedSession.uid ||
            notice.destination(now) != destination ||
            !availableInboxDestination(destination)
    )
        return null
    return when (destination.kind) {
        InboxDestinationKind.NEWS,
        InboxDestinationKind.EVENT,
        InboxDestinationKind.ORGANIZATION -> {
            val collection =
                when (destination.kind) {
                    InboxDestinationKind.NEWS -> "news"
                    InboxDestinationKind.EVENT -> "events"
                    else -> "organizations"
                }
            destination.target?.let {
                InboxNavigationTarget.Route("$collection/$it", publicContent = true)
            }
        }
        InboxDestinationKind.PROFILE -> InboxNavigationTarget.Route("profile")
        InboxDestinationKind.DSA_STATEMENT ->
            destination.target?.let {
                InboxNavigationTarget.Route("profile/dsa-statement/$it")
            }
        InboxDestinationKind.LEGAL -> InboxNavigationTarget.Route("profile/legal")
        InboxDestinationKind.ORGANIZATION_REQUEST ->
            InboxNavigationTarget.Route(
                destination.target?.let { "profile/organizations/$it" } ?: "profile/organizations"
            )
        InboxDestinationKind.FEEDBACK -> {
            val management = notice.kind == InboxKind.FEEDBACK_SUBMITTED && canManageFeedback
            val base = "profile/${if (management) "support" else "feedback"}"
            InboxNavigationTarget.Route(destination.target?.let { "$base/$it" } ?: base)
        }
        InboxDestinationKind.URL -> destination.target?.let { InboxNavigationTarget.External(it) }
        else -> null
    }
}
