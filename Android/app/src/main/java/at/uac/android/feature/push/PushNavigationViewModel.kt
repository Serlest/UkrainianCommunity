package at.uac.android.feature.push

import android.content.Intent
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import at.uac.android.feature.browse.BrowseNavigation
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class PendingPushTap(
    val ownerUid: String,
    val decision: PushRouteDecision,
    val revision: Long,
)

/** Only explicit notification-tap intents enter navigation; receipt alone never moves the user. */
class PushNavigationViewModel(private val saved: SavedStateHandle) : ViewModel() {
    private val sequence = AtomicLong(saved[REVISION] ?: 0L)
    private val mutable = MutableStateFlow(restored())
    val pending = mutable.asStateFlow()
    private val handled = linkedSetOf<String>()

    fun offer(intent: Intent?, ownerUid: String?): Boolean {
        if (intent?.action != ACTION_TAP || !validUid(ownerUid)) return false
        val data =
            intent.extras
                ?.keySet()
                ?.filter { it in ALLOWED_FIELDS }
                ?.associateWith { intent.getStringExtra(it).orEmpty() } ?: return false
        return offer(data, ownerUid)
    }

    fun offer(data: Map<String, String>, ownerUid: String?): Boolean {
        if (!validUid(ownerUid) || data.keys.any { it !in ALLOWED_FIELDS }) return false
        val decision = PushRouting.route(data) ?: return false
        val id = decision.notificationId ?: return false
        if (id in handled || mutable.value?.decision?.notificationId == id) return true
        val next = PendingPushTap(checkNotNull(ownerUid), decision, sequence.incrementAndGet())
        saved[OWNER] = next.ownerUid
        saved[ROUTE] = next.decision.route
        saved[NOTICE] = id
        saved[REVISION] = next.revision
        mutable.value = next
        return true
    }

    fun consume(expectedRevision: Long) {
        val value = mutable.value?.takeIf { it.revision == expectedRevision } ?: return
        value.decision.notificationId?.let(::remember)
        saved.remove<String>(OWNER)
        saved.remove<String>(ROUTE)
        saved.remove<String>(NOTICE)
        mutable.value = null
    }

    private fun restored(): PendingPushTap? {
        val owner = saved.get<String>(OWNER)?.takeIf(::validUid) ?: return null
        val route = saved.get<String>(ROUTE)?.takeIf(::validRoute) ?: return null
        val notice = saved.get<String>(NOTICE)?.takeIf(::validNotice) ?: return null
        return PendingPushTap(owner, PushRouteDecision(route, notice), sequence.get())
    }

    private fun remember(id: String) {
        handled += id
        while (handled.size > 16) handled.remove(handled.first())
    }

    companion object {
        const val ACTION_TAP = "at.uac.android.PUSH_TAP"
        val ALLOWED_FIELDS =
            setOf(
                "notificationId",
                "type",
                "sourceType",
                "sourceId",
                "actionType",
                "actionTargetId",
                "targetId",
                "targetID",
                "route",
                "routeTargetId",
            )
        private const val OWNER = "push-owner"
        private const val ROUTE = "push-route"
        private const val NOTICE = "push-notice"
        private const val REVISION = "push-revision"

        private fun validUid(value: String?): Boolean =
            value != null && value.isNotBlank() && value.length <= 256 && '/' !in value

        private fun validNotice(value: String): Boolean =
            value.isNotBlank() && value.length <= 512 && !value.any(Char::isISOControl)

        private fun validRoute(value: String): Boolean = runCatching {
            BrowseNavigation.restore().navigate(value)
        }
            .isSuccess
    }
}
