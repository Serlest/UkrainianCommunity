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

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        if (started.get()) PushRuntime.uninstall(this)
        coordinator.close()
    }
}
