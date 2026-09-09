package at.uac.android.feature.push

import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/** Small application-layer bridge; permission prompting and UI stay with the host screen. */
class PushController(
    private val coordinator: PushCoordinator,
    private val session: () -> PushSession?,
    private val gate: () -> PushGate,
    /** Present/refresh only; navigate to the decision.route after explicit user interaction. */
    private val deliver: (PushRouteDecision) -> Unit,
    private val scope: CoroutineScope,
    private val syncInbox: (Int) -> Unit = {},
    private val openAnnouncement: (String) -> Unit = {},
    private val confirmAnnouncementChallenge: (String) -> Unit = {},
) : PushRuntimeDelegate {
    private val closed = AtomicBoolean(false)
    private val started = AtomicBoolean(false)

    fun start(): Job? {
        if (closed.get()) return null
        if (started.compareAndSet(false, true)) PushRuntime.install(this)
        return refresh()
    }

    /** Call after Auth READY, consent changes, or POST_NOTIFICATIONS result changes. */
    fun refresh(): Job? {
        if (closed.get()) return null
        val captured = session() ?: return null
        val capturedGate = gate()
        return scope.launch { coordinator.reconcile(captured, capturedGate) }
    }

    /**
     * Must finish before FirebaseAuth.signOut(); failure lets the caller postpone logout or retry.
     */
    suspend fun beforeLogout(captured: PushSession): PushReconcileResult =
        if (closed.get()) PushReconcileResult(false, false, PushFailure.NOT_READY)
        else coordinator.beforeLogout(captured)

    override fun tokenRotated() {
        refresh()
    }

    override fun route(decision: PushRouteDecision): Boolean {
        val current = session()
        val allowed = !closed.get() && current?.verifiedActive == true && gate().open
        if (allowed) deliver(decision)
        return allowed
    }

    override fun inboxSync(unreadCount: Int): Boolean {
        val current = session()
        val allowed =
            !closed.get() &&
                current?.verifiedActive == true &&
                gate().open &&
                unreadCount in 0..1_000_000
        if (allowed) syncInbox(unreadCount)
        return allowed
    }

    override fun announcement(id: String): Boolean {
        if (closed.get() || !AnnouncementPushContract.id(id)) return false
        openAnnouncement(id)
        return true
    }

    override fun announcementChallenge(value: String): Boolean {
        if (closed.get() || !AnnouncementPushContract.challenge(value)) return false
        confirmAnnouncementChallenge(value)
        return true
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        if (started.get()) PushRuntime.uninstall(this)
        coordinator.close()
    }
}

private object AnnouncementPushContract {
    fun id(value: String) = Regex("[A-Za-z0-9_-]{1,128}").matches(value)

    fun challenge(value: String) = Regex("[a-f0-9]{64}").matches(value)
}
