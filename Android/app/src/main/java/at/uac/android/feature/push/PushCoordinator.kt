package at.uac.android.feature.push

import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class PushReconcileResult(
    val registered: Boolean,
    val changed: Boolean,
    val failure: PushFailure? = null,
)

/**
 * Minimal lifecycle controller. Call reconcile only after loading the user's persisted push
 * consent; call beforeLogout before FirebaseAuth.signOut(). All mutations are serialized.
 */
class PushCoordinator(
    private val backend: PushRegistrationBackend,
    private val ownership: PushOwnershipStore,
    private val tokens: PushTokenSource,
    private val currentSession: () -> PushSession?,
    private val deviceName: () -> String,
    private val appVersion: () -> String,
) {
    private val lock = Mutex()
    private val closed = AtomicBoolean(false)

    suspend fun reconcile(captured: PushSession, gate: PushGate): PushReconcileResult =
        lock.withLock {
            if (closed.get()) return PushReconcileResult(false, false, PushFailure.NOT_READY)
            currentFailure(captured)?.let {
                return PushReconcileResult(false, false, it)
            }
            val previous = ownership.load()
            if (previous != null && previous.uid != captured.uid)
                return PushReconcileResult(false, false, PushFailure.CROSS_ACCOUNT)
            if (!gate.open) {
                if (previous == null) {
                    return try {
                        tokens.unregister()
                        PushReconcileResult(false, false, PushFailure.PERMISSION)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        PushReconcileResult(false, false, PushFailure.UNKNOWN)
                    }
                }
                return delete(captured, previous, PushFailure.PERMISSION)
            }
            if (!captured.verifiedActive)
                return PushReconcileResult(false, false, PushFailure.NOT_READY)

            try {
                // FIS/FCM identifiers are not requested before both user and OS gates open.
                val registration =
                    PushRegistrationContract.create(
                        tokens.installationId(),
                        tokens.token(),
                        deviceName(),
                        appVersion(),
                        tokens.registrationType,
                    )
                currentFailure(captured)?.let {
                    return PushReconcileResult(false, false, it)
                }
                if (previous?.registration == registration) return PushReconcileResult(true, false)
                backend.upsert(captured.uid, registration)
                currentFailure(captured)?.let {
                    return PushReconcileResult(false, false, it)
                }
                ownership.save(OwnedPushRegistration(captured.uid, registration))
                PushReconcileResult(true, true)
            } catch (error: CancellationException) {
                throw error
            } catch (error: PushException) {
                PushReconcileResult(false, false, error.reason)
            } catch (_: Exception) {
                PushReconcileResult(false, false, PushFailure.UNKNOWN)
            }
        }

    /** Deletes only this installation's captured registration; it never enumerates user devices. */
    suspend fun beforeLogout(captured: PushSession): PushReconcileResult = lock.withLock {
        if (closed.get()) return PushReconcileResult(false, false, PushFailure.NOT_READY)
        currentFailure(captured)?.let {
            return PushReconcileResult(false, false, it)
        }
        val previous = ownership.load() ?: return PushReconcileResult(false, false)
        if (previous.uid != captured.uid)
            return PushReconcileResult(false, false, PushFailure.CROSS_ACCOUNT)
        delete(captured, previous, null)
    }

    /** AuthStore has revoked UI readiness, but native Auth must still own this exact UID. */
    suspend fun beforeExplicitSignOut(
        capturedUid: String,
        stillNativeOwner: () -> Boolean,
    ): PushReconcileResult = lock.withLock {
        if (closed.get() || !stillNativeOwner())
            return PushReconcileResult(false, false, PushFailure.CROSS_ACCOUNT)
        val previous = ownership.load() ?: return PushReconcileResult(false, false)
        if (previous.uid != capturedUid)
            return PushReconcileResult(false, false, PushFailure.CROSS_ACCOUNT)
        try {
            tokens.unregister()
            if (!stillNativeOwner())
                return PushReconcileResult(false, false, PushFailure.CROSS_ACCOUNT)
            backend.deleteExact(capturedUid, previous.registration)
            if (!stillNativeOwner())
                return PushReconcileResult(false, false, PushFailure.CROSS_ACCOUNT)
            ownership.clear(previous)
            PushReconcileResult(false, true)
        } catch (error: CancellationException) {
            throw error
        } catch (error: PushException) {
            PushReconcileResult(false, false, error.reason)
        } catch (_: Exception) {
            PushReconcileResult(false, false, PushFailure.UNKNOWN)
        }
    }

    fun close() {
        closed.set(true)
    }

    private suspend fun delete(
        captured: PushSession,
        previous: OwnedPushRegistration,
        successFailure: PushFailure?,
    ): PushReconcileResult =
        try {
            currentFailure(captured)?.let {
                return PushReconcileResult(false, false, it)
            }
            tokens.unregister()
            backend.deleteExact(captured.uid, previous.registration)
            currentFailure(captured)?.let {
                return PushReconcileResult(false, false, it)
            }
            ownership.clear(previous)
            PushReconcileResult(false, true, successFailure)
        } catch (error: CancellationException) {
            throw error
        } catch (error: PushException) {
            PushReconcileResult(false, false, error.reason)
        } catch (_: Exception) {
            // Preserve ownership locally so an exact retry remains possible.
            PushReconcileResult(false, false, PushFailure.UNKNOWN)
        }

    private fun currentFailure(captured: PushSession): PushFailure? {
        val live = currentSession() ?: return PushFailure.SIGN_IN
        return when {
            live.uid != captured.uid -> PushFailure.CROSS_ACCOUNT
            live != captured -> PushFailure.STALE_SESSION
            else -> null
        }
    }
}
