package at.uac.android.feature.push

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import at.uac.android.MainActivity
import at.uac.android.R
import at.uac.android.feature.announcements.AnnouncementPushInbox
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.util.concurrent.atomic.AtomicReference

interface PushRuntimeDelegate {
    /**
     * Resolve FirebaseMessaging.getToken() inside the gated coordinator; do not persist this value.
     */
    fun tokenRotated()

    fun route(decision: PushRouteDecision): Boolean

    fun inboxSync(unreadCount: Int): Boolean

    fun announcement(id: String): Boolean = false

    fun announcementChallenge(value: String): Boolean = false
}

/** Process-only bridge. An absent owner deliberately drops events instead of guessing a session. */
object PushRuntime {
    private val delegate = AtomicReference<PushRuntimeDelegate?>()

    fun install(value: PushRuntimeDelegate) {
        check(delegate.compareAndSet(null, value)) { "PUSH_RUNTIME_ALREADY_INSTALLED" }
    }

    fun uninstall(value: PushRuntimeDelegate) {
        delegate.compareAndSet(value, null)
    }

    internal fun tokenRotated() {
        delegate.get()?.tokenRotated()
    }

    internal fun route(decision: PushRouteDecision): Boolean =
        delegate.get()?.route(decision) == true

    internal fun inboxSync(unreadCount: Int): Boolean =
        delegate.get()?.inboxSync(unreadCount) == true

    internal fun announcement(id: String): Boolean = delegate.get()?.announcement(id) == true

    internal fun announcementChallenge(value: String): Boolean =
        delegate.get()?.announcementChallenge(value) == true
}

class UacFirebaseMessagingService : FirebaseMessagingService() {
    override fun onCreate() {
        super.onCreate()
        PushNotificationChannel.ensure(this)
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onNewToken(token: String) {
        // Legacy SDK callback: validate shape only and resolve the current identifier after gates.
        if (PushToken.parse(token) != null) PushRuntime.tokenRotated()
    }

    override fun onRegistered(installationId: String) {
        // Never log, store or forward the raw callback identifier. The gated source resolves
        // current FCM state after checking consent, POST_NOTIFICATIONS and the captured session.
        if (PushToken.parse(installationId) != null) PushRuntime.tokenRotated()
    }

    override fun onMessageReceived(message: RemoteMessage) {
        message.data["announcementChallenge"]
            ?.takeIf { Regex("[a-f0-9]{64}").matches(it) }
            ?.let {
                if (!PushRuntime.announcementChallenge(it)) {
                    AnnouncementPushInbox.putChallenge(this, it)
                }
                return
            }
        message.data["announcementId"]
            ?.takeIf { Regex("[A-Za-z0-9_-]{1,128}").matches(it) }
            ?.let {
                if (!PushRuntime.announcement(it)) {
                    AnnouncementPushInbox.putId(this, it)
                }
                showAnnouncement(message, it)
                return
            }
        // Both foreground notification messages and data messages pass through the same allowlists.
        PushRouting.inboxSync(message.data)?.let {
            PushRuntime.inboxSync(it)
            return
        }
        val decision = PushRouting.route(message.data) ?: return
        if (PushRuntime.route(decision)) show(message, decision)
    }

    private fun showAnnouncement(message: RemoteMessage, id: String) {
        val tap =
            Intent(this, MainActivity::class.java)
                .setAction(PushNavigationViewModel.ACTION_TAP)
                .setPackage(packageName)
                .putExtra("announcementId", id)
        val pending =
            PendingIntent.getActivity(
                this,
                id.hashCode(),
                tap,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val notification =
            Notification.Builder(this, PushChannelPolicy.ID)
                .setSmallIcon(R.drawable.ic_notification_uac)
                .setContentTitle(message.notification?.title?.take(160) ?: "UAC")
                .setContentText(message.notification?.body?.take(512) ?: return)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setAutoCancel(true)
                .setContentIntent(pending)
                .build()
        getSystemService(NotificationManager::class.java)?.notify(id, 2, notification)
    }

    private fun show(message: RemoteMessage, decision: PushRouteDecision) {
        val id = decision.notificationId ?: return
        val tap =
            Intent(this, MainActivity::class.java)
                .setAction(PushNavigationViewModel.ACTION_TAP)
                .setPackage(packageName)
                .apply {
                    message.data
                        .filterKeys { it in PushNavigationViewModel.ALLOWED_FIELDS }
                        .forEach { (key, value) -> putExtra(key, value) }
                }
        val requestCode = id.hashCode()
        val pending =
            PendingIntent.getActivity(
                this,
                requestCode,
                tap,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val title =
            message.notification?.title?.take(160)
                ?: getString(R.string.uac_notifications_channel_updates_name)
        val body = message.notification?.body?.take(512) ?: return
        val notification =
            Notification.Builder(this, PushChannelPolicy.ID)
                .setSmallIcon(R.drawable.ic_notification_uac)
                .setContentTitle(title)
                .setContentText(body)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setAutoCancel(true)
                .setContentIntent(pending)
                .build()
        getSystemService(NotificationManager::class.java)?.notify(id, 1, notification)
    }
}

object PushNotificationChannel {
    fun ensure(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val channel =
            NotificationChannel(
                    PushChannelPolicy.ID,
                    context.getString(R.string.uac_notifications_channel_updates_name),
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
                .apply {
                    description =
                        context.getString(R.string.uac_notifications_channel_updates_description)
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                    enableVibration(true)
                    setShowBadge(PushChannelPolicy.BADGE_ENABLED)
                }
        manager.createNotificationChannel(channel)
    }
}
