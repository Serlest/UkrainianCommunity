package at.uac.android.feature.push

import at.uac.android.feature.browse.BrowseNavigation
import at.uac.android.feature.inbox.InboxDestination
import at.uac.android.feature.inbox.InboxDestinationKind
import at.uac.android.feature.inbox.InboxRoutes

data class PushRouteDecision(val route: String, val notificationId: String?)

/** Converts untrusted FCM data only through the existing inbox and BrowseNavigation allowlists. */
object PushRouting {
    private const val MAX_FIELDS = 32
    private const val MAX_KEY = 80
    private const val MAX_VALUE = 2_048

    fun inboxSync(data: Map<String, String>): Int? {
        if (data["type"] != "inboxSync" || data.keys.any { it !in setOf("type", "unreadCount") })
            return null
        return data["unreadCount"]?.toIntOrNull()?.takeIf { it in 0..1_000_000 }
    }

    fun route(data: Map<String, String>): PushRouteDecision? {
        if (
            data.size > MAX_FIELDS ||
                data.any { (key, value) ->
                    key.isBlank() ||
                        key.length > MAX_KEY ||
                        value.length > MAX_VALUE ||
                        key.any(Char::isISOControl) ||
                        value.any(Char::isISOControl)
                }
        )
            return null
        val destination = InboxRoutes.fromPush(data) ?: return null
        val route = browseRoute(destination) ?: return null
        if (runCatching { BrowseNavigation.restore().navigate(route) }.isFailure) return null
        val notificationId = data["notificationId"]?.takeIf(::validId)
        return PushRouteDecision(route, notificationId)
    }

    private fun browseRoute(destination: InboxDestination): String? =
        when (destination.kind) {
            InboxDestinationKind.NEWS -> destination.target?.let { "news/$it" }
            InboxDestinationKind.EVENT -> destination.target?.let { "events/$it" }
            InboxDestinationKind.ORGANIZATION -> destination.target?.let { "organizations/$it" }
            InboxDestinationKind.ORGANIZATION_REQUEST ->
                destination.target?.let { "profile/organization-review/$it" }
            InboxDestinationKind.FEEDBACK ->
                destination.target?.let { "profile/feedback/$it" } ?: "profile/feedback"
            InboxDestinationKind.DSA_STATEMENT ->
                destination.target?.let { "profile/dsa-statement/$it" }
            InboxDestinationKind.LEGAL -> "profile/legal"
            InboxDestinationKind.PROFILE -> "profile"
            InboxDestinationKind.ANNOUNCEMENT -> "profile/inbox"
            // URL opening has a separate external-intent policy. Content planning has no current
            // BrowseNavigation route, so both fail closed here.
            InboxDestinationKind.URL,
            InboxDestinationKind.CONTENT_PLANNING -> null
        }

    private fun validId(value: String): Boolean =
        value.isNotBlank() && value.length <= 512 && !value.any(Char::isISOControl)
}
