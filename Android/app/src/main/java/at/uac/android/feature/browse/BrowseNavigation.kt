package at.uac.android.feature.browse

import at.uac.android.feature.community.communityId
import at.uac.android.feature.dsastatement.DsaStatementContract
import at.uac.android.feature.feedback.feedbackId
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.personal.validDocumentId

/** Build 65 has four independent navigation stacks. News belongs to Home. */
enum class PrimaryTab(val route: String) {
    HOME("home"),
    EVENTS("events"),
    ORGANIZATIONS("organizations"),
    PROFILE("profile");

    companion object {
        fun forRoute(route: String): PrimaryTab =
            entries.firstOrNull {
                it != HOME && route.substringBefore('/').substringBefore(':') == it.route
            } ?: HOME
    }
}

@ConsistentCopyVisibility
data class BrowseNavigation
private constructor(
    val selected: PrimaryTab,
    val stacks: Map<PrimaryTab, List<String>>,
) {
    val stack: List<String>
        get() = stacks.getValue(selected)

    val route: String
        get() = stack.last()

    val canBack: Boolean
        get() = stack.size > 1

    fun navigate(route: String, replace: Boolean = false): BrowseNavigation {
        require(validRoute(route))
        if (route == this.route && !replace) return this
        val destination = if (replace) PrimaryTab.forRoute(route) else selected
        val next = if (replace) listOf(route) else (stack + route).takeLast(MAX_DEPTH)
        return copy(selected = destination, stacks = stacks + (destination to next))
    }

    /** A repeated tab tap returns to its root; switching tabs restores its own destination. */
    fun select(tab: PrimaryTab): BrowseNavigation =
        if (tab == selected) {
            copy(stacks = stacks + (tab to listOf(tab.route)))
        } else copy(selected = tab)

    fun back(): BrowseNavigation =
        if (!canBack) this else copy(stacks = stacks + (selected to stack.dropLast(1)))

    /**
     * Account destinations can be nested in any tab; their following public targets share that
     * history.
     */
    fun scrubPrivateDestinations(restoreGuestAuthentication: Boolean = false): BrowseNavigation =
        copy(
            stacks =
                stacks.mapValues { (tab, routes) ->
                    if (tab == PrimaryTab.PROFILE) {
                        // Restore only the public authentication prefix, never a suffix reached
                        // through private history.
                        if (restoreGuestAuthentication)
                            routes
                                .takeWhile { it == "profile" || it in guestAuthenticationRoutes }
                                .ifEmpty { listOf(tab.route) }
                        else listOf(tab.route)
                    } else
                        routes
                            .takeWhile {
                                it != "settings" && it != "profile" && !it.startsWith("profile/")
                            }
                            .ifEmpty { listOf(tab.route) }
                }
        )

    companion object {
        private const val MAX_DEPTH = 16
        private val guestAuthenticationRoutes =
            setOf("profile/login", "profile/register", "profile/reset")
        private val accountRoots =
            setOf(
                "profile",
                "profile/login",
                "profile/register",
                "profile/reset",
                "profile/edit",
                "profile/saved",
                "profile/subscriptions",
                "profile/feedback",
                "profile/support",
                "profile/inbox",
                "profile/inbox-settings",
                "profile/legal",
                "profile/blocked",
                "profile/organizations",
                "profile/registrations",
                "profile/recent",
                "profile/history",
                "profile/delete",
                "profile/deleted",
                "profile/moderation",
                "profile/users",
                "profile/organization-review",
            )

        private fun validRoute(route: String): Boolean {
            if (route.isBlank() || route.length > 2_048 || route.any(Char::isISOControl))
                return false
            if (
                route in accountRoots ||
                    route in setOf("home", "news", "events", "organizations", "settings")
            )
                return true
            val parts = route.split('/')
            if (parts.size == 1) {
                val section = route.substringBefore(':')
                return section in setOf("news", "events") &&
                    ':' in route &&
                    OrganizationContract.id(route.substringAfter(':'))
            }
            return when {
                parts.size == 2 && parts[0] in setOf("news", "events") -> validDocumentId(parts[1])
                parts.size == 2 && parts[0] == "organizations" -> OrganizationContract.id(parts[1])
                parts.size == 3 &&
                    parts[0] == "profile" &&
                    parts[1] in setOf("feedback", "support") -> feedbackId(parts[2])
                parts.size == 3 && parts.take(2) == listOf("profile", "attendees") ->
                    communityId(parts[2])
                parts.size == 3 &&
                    parts[0] == "profile" &&
                    parts[1] in setOf("dsa-statement", "dsa-review") ->
                    DsaStatementContract.validId(parts[2])
                parts.size == 3 && parts.take(2) == listOf("profile", "subscribers") ->
                    OrganizationContract.id(parts[2])
                parts.size == 3 && parts.take(2) == listOf("profile", "organization-review") ->
                    OrganizationContract.id(parts[2])
                parts.size == 3 && parts.take(2) == listOf("profile", "organizations") ->
                    OrganizationContract.id(parts[2])
                parts.size == 4 &&
                    parts.take(2) == listOf("profile", "organizations") &&
                    parts[2] in setOf("manage", "gallery") -> OrganizationContract.id(parts[3])
                parts.size == 5 && parts.take(3) == listOf("profile", "organizations", "author") ->
                    OrganizationContract.id(parts[3]) && parts[4] in setOf("news", "events")
                parts.size == 6 &&
                    parts.take(2) == listOf("profile", "organizations") &&
                    parts[2] in setOf("cover", "lifecycle") ->
                    OrganizationContract.id(parts[3]) &&
                        parts[4] in setOf("news", "events") &&
                        OrganizationContract.id(parts[5])
                else -> false
            }
        }

        private fun restoreStack(tab: PrimaryTab, routes: List<String>): List<String> {
            if (routes.isEmpty() || routes.any { !validRoute(it) }) return listOf(tab.route)
            // A route is not proof of a completed destructive operation after process recreation.
            return routes.takeLast(MAX_DEPTH).map { if (it == "profile/deleted") "profile" else it }
        }

        fun restore(
            selectedRoute: String? = null,
            stored: Map<PrimaryTab, List<String>> = emptyMap(),
            legacy: List<String> = emptyList(),
        ): BrowseNavigation {
            val selected =
                PrimaryTab.entries.firstOrNull { it.route == selectedRoute }
                    ?: legacy.firstOrNull()?.takeIf(::validRoute)?.let(PrimaryTab::forRoute)
                    ?: PrimaryTab.HOME
            val stacks =
                PrimaryTab.entries.associateWith { tab ->
                    restoreStack(tab, stored[tab] ?: legacy.takeIf { tab == selected }.orEmpty())
                }
            return BrowseNavigation(selected, stacks)
        }
    }
}
