package at.uac.android.feature.applinks

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class PendingAppLink(val destination: AppLinkDestination, val revision: Long)

/** One pending, validated destination. Re-delivery is idempotent across warm/cold starts. */
class AppLinkNavigationViewModel(private val saved: SavedStateHandle) : ViewModel() {
    private val mutable = MutableStateFlow(restored())
    val pending = mutable.asStateFlow()

    fun offer(value: String?): Boolean {
        val destination = AppLinkContract.parse(value) ?: return false
        if (mutable.value?.destination == destination) return true
        val next =
            PendingAppLink(destination, (mutable.value?.revision ?: saved[REVISION] ?: 0L) + 1)
        saved[ROUTE] = destination.route
        saved[ACCESS] = destination.access.name
        saved[REVISION] = next.revision
        mutable.value = next
        return true
    }

    fun consume(expectedRevision: Long) {
        if (mutable.value?.revision != expectedRevision) return
        saved.remove<String>(ROUTE)
        saved.remove<String>(ACCESS)
        mutable.value = null
    }

    private fun restored(): PendingAppLink? {
        val route = saved.get<String>(ROUTE) ?: return null
        val access =
            saved.get<String>(ACCESS)?.let { runCatching { AppLinkAccess.valueOf(it) }.getOrNull() }
                ?: return null
        // Saved state is untrusted too: round-trip through the same narrow external contract.
        val canonical =
            when {
                route == "profile/inbox" -> AppLinkDestination(route, AppLinkAccess.SIGNED_IN)
                route.startsWith("news/") -> AppLinkContract.parse("ukrainiancommunity://$route")
                route.startsWith("events/") -> AppLinkContract.parse("ukrainiancommunity://$route")
                route.startsWith("organizations/") ->
                    AppLinkContract.parse("ukrainiancommunity://$route")
                else -> null
            }
        if (canonical?.access != access) return null
        return PendingAppLink(canonical, saved[REVISION] ?: 0L)
    }

    private companion object {
        const val ROUTE = "app-link-route"
        const val ACCESS = "app-link-access"
        const val REVISION = "app-link-revision"
    }
}
