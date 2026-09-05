package at.uac.android.feature.reminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import at.uac.android.feature.auth.AuthSession
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/**
 * Fixed CPU-only lease. Acquisition occurs before onReceive returns; close is idempotent on every
 * exit.
 */
class ReminderWakeGuard(private val acquire: () -> Unit, private val release: () -> Unit) :
    AutoCloseable {
    private var held = false

    fun acquire(): Boolean =
        if (held) false
        else
            try {
                acquire.invoke()
                held = true
                true
            } catch (_: Exception) {
                false
            }

    override fun close() {
        if (held) {
            held = false
            runCatching(release)
        }
    }
}

suspend fun finishReminderReceiver(lease: ReminderWakeGuard, action: suspend () -> Unit) {
    try {
        withTimeout(REMINDER_BUDGET_MS) { action() }
    } finally {
        lease.close()
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in SYSTEM_ACTIONS && intent.action != ReminderIntents.ALARM) return
        val request =
            if (intent.action == ReminderIntents.ALARM) ReminderIntents.request(intent) ?: return
            else null
        if (runCatching { requireReminderEnvironment(context) }.isFailure) return
        val lease =
            try {
                val wake =
                    context
                        .getSystemService(PowerManager::class.java)
                        .newWakeLock(
                            PowerManager.PARTIAL_WAKE_LOCK,
                            "uac:localReminderVerification",
                        )
                        .apply { setReferenceCounted(false) }
                ReminderWakeGuard({ wake.acquire(8_000) }, { if (wake.isHeld) wake.release() })
            } catch (_: Exception) {
                return
            }
        if (!lease.acquire()) return
        val pending =
            try {
                goAsync()
            } catch (_: Exception) {
                lease.close()
                return
            }
        worker.launch {
            try {
                finishReminderReceiver(lease) {
                    val runtime = LocalReminders.get(context.applicationContext)
                    if (request == null) runtime.delivery.reschedule()
                    else runtime.delivery.receive(request)
                }
            } catch (_: Exception) {
                // No provider messages/tokens/content in logs. Failed/expired proofs never display
                // or retry a notification.
            } finally {
                lease.close()
                pending.finish()
            }
        }
    }

    companion object {
        private val worker = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        private val SYSTEM_ACTIONS =
            setOf(
                Intent.ACTION_BOOT_COMPLETED,
                Intent.ACTION_TIME_CHANGED,
                Intent.ACTION_TIMEZONE_CHANGED,
                Intent.ACTION_MY_PACKAGE_REPLACED,
            )
    }
}

class LocalReminderRuntime internal constructor(context: Context) {
    private val application = context.applicationContext
    val authority = ReminderAuthority()
    private val source = localReminderSource(application)
    private val ledger =
        fileReminderLedger(File(application.noBackupFilesDir, "event-reminders-v1"))
    private val scheduler = AndroidReminderScheduler(application)
    private val sink = AndroidReminderNotifications(application)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val controller = ReminderController(source, ledger, scheduler, sink, authority, scope)
    val delivery = ReminderDelivery(source, ledger, scheduler, sink, authority)

    /**
     * Attach the retained AuthStore's StateFlow getter, never an Activity or cached Compose state.
     */
    fun attachAuth(supplier: () -> AuthSession) = authority.attachAuth(supplier)

    fun ensureChannel() = sink.ensureChannel()
}

object LocalReminders {
    @Volatile private var instance: LocalReminderRuntime? = null

    fun get(context: Context): LocalReminderRuntime {
        requireReminderEnvironment(context)
        return instance
            ?: synchronized(this) {
                instance ?: LocalReminderRuntime(context).also { instance = it }
            }
    }
}
