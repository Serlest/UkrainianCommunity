package at.uac.pushprobe

import android.Manifest
import android.annotation.SuppressLint
import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.installations.FirebaseInstallations
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.util.UUID
import java.util.concurrent.Executors

class ProbeApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        ProbeRuntime.get(this).restore()
    }
}

/** This process can initialize only the fixed test app, after durable explicit consent. */
class ProbeRuntime private constructor(private val context: Context) {
    val store = ProbeStore(context)
    private val executor = Executors.newSingleThreadExecutor()
    private val notifications = context.getSystemService(NotificationManager::class.java)
    @Volatile private var configurationFailed = false
    @Volatile private var unregisterQueued = false

    fun configurationAllowed() =
        ProbeContract.configurationAllowed(
            ProbeContract.PROJECT,
            ProbeContract.NUMBER,
            ProbeContract.APP,
            context.packageName,
            BuildConfig.DEBUG,
            BuildConfig.TEST_API_KEY,
        ) &&
            Build.VERSION.SDK_INT == 37 &&
            Build.HARDWARE in setOf("ranchu", "goldfish") &&
            Build.MODEL.startsWith("sdk_gphone") &&
            !configurationFailed

    fun notificationsAllowed(): Boolean =
        (Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED) &&
            NotificationManagerCompat.from(context).areNotificationsEnabled() &&
            (notifications.getNotificationChannel(ProbeContract.CHANNEL)?.importance
                ?: NotificationManager.IMPORTANCE_DEFAULT) != NotificationManager.IMPORTANCE_NONE

    fun restore() {
        if (!store.healthy) return
        val before = store.snapshot()
        if (!before.everOptedIn)
            return // No default app, FIS, or registration on first launch/denial.
        if (!configurationAllowed()) return
        // An interrupted register has an uncertain outcome. Do not repeat it or
        // fabricate a target. A visible opt-out/retry is required before enabling.
        if (before.registering)
            runCatching {
                store.update {
                    it.optOut(System.currentTimeMillis())
                        .event(ProbeEvent.REGISTER_FAILED, System.currentTimeMillis())
                }
                store.clearTarget()
            }
        runCatching { messaging() }.onFailure { configurationFailed = true }
        reconcileConsent()
        if (store.snapshot().cleanupPending) enqueueUnregister()
    }

    fun optIn() {
        if (!store.healthy || !configurationAllowed() || !notificationsAllowed()) return
        val before = store.snapshot()
        if (before.optedIn || before.cleanupPending || before.registering) return
        val captured =
            runCatching {
                store.update {
                    it.optIn(System.currentTimeMillis(), UUID.randomUUID().toString())
                }
            }
                .getOrNull() ?: return
        createChannel()
        executor.execute {
            try {
                if (store.snapshot().generation != captured.generation || !store.snapshot().optedIn)
                    return@execute
                val sdk = messaging()
                Tasks.await(sdk.setNotificationDelegationEnabled(false))
                // Never detach/retry this actual SDK operation on UI destruction.
                Tasks.await(sdk.register())
                val fid = Tasks.await(FirebaseInstallations.getInstance().id)
                if (!notificationsAllowed()) {
                    optOut(ProbeCleanupScope(captured.generation, captured.runId.orEmpty()))
                    return@execute
                }
                store.acknowledgeRegistration(captured.generation, fid, System.currentTimeMillis())
            } catch (_: Exception) {
                runCatching {
                    store.update {
                        if (it.generation != captured.generation) it
                        else
                            it.optOut(System.currentTimeMillis())
                                .event(ProbeEvent.REGISTER_FAILED, System.currentTimeMillis())
                    }
                    store.clearTarget()
                }
                // Failure may be ambiguous. Keep cleanupPending and require the
                // user's explicit opt-out retry, rather than repeat registration.
            }
        }
    }

    fun optOut(expected: ProbeCleanupScope? = null): Boolean {
        if (!store.healthy) {
            if (expected == null) notifications.cancelAll()
            return false
        }
        // This separate package owns only its own probe notifications. A scoped
        // runner cleanup must not clear a newer run between check and cancellation.
        val stopped = runCatching {
            store.stop(expected, System.currentTimeMillis()) { notifications.cancelAll() }
        }
            .getOrDefault(false)
        if (!stopped) return false
        enqueueUnregister()
        return true
    }

    fun reconcileConsent() {
        val state = store.snapshot()
        if (
            state.optedIn &&
                (!notificationsAllowed() || System.currentTimeMillis() >= state.runExpiresAt)
        )
            optOut(ProbeCleanupScope(state.generation, state.runId.orEmpty()))
    }

    @Synchronized
    private fun enqueueUnregister() {
        if (
            unregisterQueued ||
                !store.healthy ||
                !store.snapshot().cleanupPending ||
                !configurationAllowed()
        )
            return
        unregisterQueued = true
        val generation = store.snapshot().generation
        executor.execute {
            try {
                val sdk = messaging()
                Tasks.await(sdk.unregister())
                store.update {
                    it.unregistrationAcknowledged(generation, System.currentTimeMillis())
                }
            } catch (_: Exception) {
                runCatching {
                    store.update {
                        it.event(ProbeEvent.UNREGISTER_FAILED, System.currentTimeMillis())
                    }
                }
            } finally {
                unregisterQueued = false
            }
        }
    }

    fun registrationCallback(fid: String, registered: Boolean) {
        if (!store.healthy || !ProbeContract.validFid(fid)) return
        runCatching {
            store.update {
                val current =
                    registered &&
                        it.optedIn &&
                        (it.registering || it.registrationHash == ProbeContract.hash(fid))
                it.event(
                    if (!registered) ProbeEvent.UNREGISTER_CALLBACK
                    else if (current) ProbeEvent.REGISTER_CALLBACK else ProbeEvent.CALLBACK_IGNORED,
                    System.currentTimeMillis(),
                )
            }
        }
        if (registered && !store.snapshot().optedIn && store.snapshot().cleanupPending)
            enqueueUnregister()
    }

    fun received(message: RemoteMessage) {
        if (!configurationAllowed() || !store.healthy) return
        reconcileConsent()
        runCatching {
            store.receive(
                message.data,
                message.from,
                message.notification != null,
                ::notificationsAllowed,
                System.currentTimeMillis(),
                ::display,
            )
        }
    }

    fun deletedMessages() {
        if (store.healthy)
            runCatching {
                store.update { it.event(ProbeEvent.DELETED_MESSAGES, System.currentTimeMillis()) }
            }
    }

    fun tapped(intent: Intent?) {
        val uri = intent?.data ?: return
        if (intent.action != ACTION_OPEN || uri.scheme != "uac-push-probe" || uri.host != "receipt")
            return
        val id = uri.lastPathSegment ?: return
        if (!ProbeContract.validId(id)) return
        runCatching {
            store.update {
                if (
                    it.optedIn &&
                        System.currentTimeMillis() < it.runExpiresAt &&
                        id in it.seen &&
                        intent.getStringExtra("runId") == it.runId
                )
                    it.event(ProbeEvent.TAPPED, System.currentTimeMillis(), id)
                else it
            }
        }
    }

    @Synchronized
    private fun messaging(): FirebaseMessaging {
        check(configurationAllowed() && store.healthy && store.snapshot().everOptedIn)
        val apps = FirebaseApp.getApps(context)
        check(
            apps.all {
                it.name == FirebaseApp.DEFAULT_APP_NAME &&
                    it.options.projectId == ProbeContract.PROJECT &&
                    it.options.applicationId == ProbeContract.APP &&
                    it.options.gcmSenderId == ProbeContract.NUMBER &&
                    it.options.apiKey == BuildConfig.TEST_API_KEY
            }
        )
        val app =
            apps.singleOrNull()
                ?: FirebaseApp.initializeApp(
                    context,
                    FirebaseOptions.Builder()
                        .setProjectId(ProbeContract.PROJECT)
                        .setApplicationId(ProbeContract.APP)
                        .setGcmSenderId(ProbeContract.NUMBER)
                        .setApiKey(BuildConfig.TEST_API_KEY)
                        .build(),
                )
        val collectionOverride: Boolean? =
            false // Nullable overload replaces the deprecated primitive overload.
        app.setDataCollectionDefaultEnabled(collectionOverride)
        return FirebaseMessaging.getInstance().also {
            it.isAutoInitEnabled = false
            it.setDeliveryMetricsExportToBigQuery(false)
        }
    }

    private fun createChannel() {
        notifications.createNotificationChannel(
            NotificationChannel(
                    ProbeContract.CHANNEL,
                    "UAC synthetic delivery test",
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
                .apply {
                    description =
                        "Only generic synthetic test messages; no UAC accounts or private content."
                    lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
                    setShowBadge(false)
                }
        )
    }

    @Suppress(
        "MissingPermission"
    ) // Checked immediately in the serialized display gate; revocation is caught.
    private fun display(message: ProbeMessage) {
        createChannel()
        val intent =
            Intent(context, ProbeActivity::class.java)
                .setAction(ACTION_OPEN)
                .setData("uac-push-probe://receipt/${message.probeId}".toUri())
                .putExtra("runId", message.runId)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending =
            PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        val notification =
            NotificationCompat.Builder(context, ProbeContract.CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_probe)
                .setContentTitle("UAC Test")
                .setContentText("Synthetic notification delivery test.")
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setAutoCancel(true)
                .setOnlyAlertOnce(true)
                .setTimeoutAfter((message.expiresAt - System.currentTimeMillis()).coerceAtLeast(1))
                .setContentIntent(pending)
                .build()
        notifications.notify("probe-${message.probeId}", 1, notification)
    }

    companion object {
        const val ACTION_OPEN = "at.uac.pushprobe.OPEN_RECEIPT"
        @SuppressLint(
            "StaticFieldLeak"
        ) // The private constructor receives applicationContext only, never Activity.
        @Volatile
        private var instance: ProbeRuntime? = null

        fun get(context: Context): ProbeRuntime =
            instance
                ?: synchronized(this) {
                    instance ?: ProbeRuntime(context.applicationContext).also { instance = it }
                }
    }
}

@SuppressLint(
    "MissingFirebaseInstanceTokenRefresh"
) // Messaging25.1 FID mode replaces deprecated onNewToken with these two callbacks.
class ProbeMessagingService : FirebaseMessagingService() {
    override fun onRegistered(installationId: String) {
        ProbeRuntime.get(this).registrationCallback(installationId, true)
    }

    override fun onUnregistered(installationId: String) {
        ProbeRuntime.get(this).registrationCallback(installationId, false)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        ProbeRuntime.get(this).received(message)
    }

    override fun onDeletedMessages() {
        ProbeRuntime.get(this).deletedMessages()
    }
}
