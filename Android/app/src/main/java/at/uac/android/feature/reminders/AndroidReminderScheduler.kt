package at.uac.android.feature.reminders

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import at.uac.android.core.LocalEnvironment
import java.time.Instant

object ReminderIntents {
    const val ALARM = "at.uac.android.local.EVENT_REMINDER_ALARM"
    const val TAP = "at.uac.android.local.EVENT_REMINDER_TAP"
    const val CHANNEL = "uac_event_reminders"
    private const val EPOCH = "reminder_epoch"
    private const val TOKEN = "reminder_ticket"

    fun request(intent: Intent): ReminderTapRequest? {
        if (intent.action !in setOf(ALARM, TAP)) return null
        val epoch = intent.getStringExtra(EPOCH) ?: return null
        val token = intent.getStringExtra(TOKEN) ?: return null
        return if (reminderOpaque(epoch) && reminderOpaque(token)) ReminderTapRequest(epoch, token)
        else null
    }

    internal fun extras(intent: Intent, ticket: ReminderTicket): Intent =
        intent.putExtra(EPOCH, ticket.epoch).putExtra(TOKEN, ticket.token)
}

class AndroidReminderScheduler(private val context: Context) : ReminderScheduler {
    private val alarms = context.getSystemService(AlarmManager::class.java)

    private fun base() =
        Intent(context, ReminderReceiver::class.java).setAction(ReminderIntents.ALARM)

    override fun requestNext(ticket: ReminderTicket, now: Instant) {
        require(reminderOpaque(ticket.epoch) && reminderOpaque(ticket.token))
        val pending =
            PendingIntent.getBroadcast(
                context,
                1_515,
                ReminderIntents.extras(base(), ticket),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        try {
            alarms.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                maxOf(ticket.fireAt, now.plusSeconds(1)).toEpochMilli(),
                pending,
            )
        } catch (_: Exception) {
            throw ReminderException(ReminderFailure.SYSTEM)
        }
    }

    override fun cancelOwned() {
        val pending =
            PendingIntent.getBroadcast(
                context,
                1_515,
                base(),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
            ) ?: return
        alarms.cancel(pending)
        pending.cancel()
    }
}

/**
 * Generic public and private payloads; event names, venues, account identifiers and URLs never
 * enter a notification.
 */
class AndroidReminderNotifications(private val context: Context) : ReminderNotificationSink {
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val compat = NotificationManagerCompat.from(context)

    private fun ukrainian(): Boolean {
        val saved = runCatching {
            context
                .getSharedPreferences("uac-local", Context.MODE_PRIVATE)
                .getString("language", null)
        }
            .getOrNull()
        return reminderLanguage(saved, context.resources.configuration.locales[0]?.language) == "uk"
    }

    fun ensureChannel() {
        manager.createNotificationChannel(
            NotificationChannel(
                    ReminderIntents.CHANNEL,
                    if (ukrainian()) "Нагадування про події" else "Veranstaltungserinnerungen",
                    NotificationManager.IMPORTANCE_DEFAULT,
                )
                .apply {
                    description =
                        if (ukrainian()) "Локальні нагадування UAC" else "Lokale UAC-Erinnerungen"
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                }
        )
    }

    override fun permission(): ReminderPermission {
        if (
            Build.VERSION.SDK_INT >= 33 &&
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.POST_NOTIFICATIONS,
                ) != PackageManager.PERMISSION_GRANTED
        )
            return ReminderPermission.APP_DENIED
        if (!compat.areNotificationsEnabled()) return ReminderPermission.APP_DENIED
        return if (
            manager.getNotificationChannel(ReminderIntents.CHANNEL)?.importance ==
                NotificationManager.IMPORTANCE_NONE
        )
            ReminderPermission.CHANNEL_DENIED
        else ReminderPermission.ALLOWED
    }

    override fun postGeneric(receipt: ConfirmedReminder) {
        if (
            receipt.ticket.state != ReminderTicketState.CLAIMED ||
                permission() != ReminderPermission.ALLOWED
        )
            throw ReminderException(ReminderFailure.SUPPRESSED)
        ensureChannel()
        val launch =
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: throw ReminderException(ReminderFailure.SYSTEM)
        launch.action = ReminderIntents.TAP
        launch.data =
            Uri.Builder()
                .scheme("uac-local-reminder")
                .authority("claimed")
                .appendPath(receipt.ticket.token)
                .build()
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        ReminderIntents.extras(launch, receipt.ticket)
        val pending =
            PendingIntent.getActivity(
                context,
                1_516,
                launch,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        val title =
            if (receipt.ticket.localTest) {
                if (ukrainian()) "UAC · Локальна перевірка" else "UAC · Lokaler Test"
            } else if (ukrainian()) "UAC · Нагадування про подію"
            else "UAC · Veranstaltungserinnerung"
        val body =
            if (ukrainian()) "Відкрийте UAC, щоб перевірити актуальні дані."
            else "UAC öffnen, um aktuelle Angaben zu prüfen."
        val appInfo =
            context.packageManager.getApplicationInfo(
                context.packageName,
                PackageManager.GET_META_DATA,
            )
        val icon =
            appInfo.metaData?.getInt("at.uac.android.REMINDER_ICON", 0)?.takeIf { it != 0 }
                ?: android.R.drawable.ic_dialog_info
        val public =
            NotificationCompat.Builder(context, ReminderIntents.CHANNEL)
                .setSmallIcon(icon)
                .setContentTitle("UAC")
                .setContentText(if (ukrainian()) "Нагадування" else "Erinnerung")
                .build()
        val notification =
            NotificationCompat.Builder(context, ReminderIntents.CHANNEL)
                .setSmallIcon(icon)
                .setContentTitle(title)
                .setContentText(body)
                .setContentIntent(pending)
                .setAutoCancel(true)
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setPublicVersion(public)
                .setOnlyAlertOnce(true)
                .setTimeoutAfter(
                    maxOf(
                        1,
                        receipt.ticket.occurrence.end.toEpochMilli() - System.currentTimeMillis(),
                    )
                )
                .build()
        // The permission and ownership are checked immediately before this call by ReminderDelivery
        // on Main.
        try {
            manager.notify("uac-reminder:${receipt.ticket.token}", 1_517, notification)
        } catch (_: SecurityException) {
            throw ReminderException(ReminderFailure.SUPPRESSED)
        }
    }

    override fun cancelOwned() {
        manager.activeNotifications
            .filter { it.tag?.startsWith("uac-reminder:") == true && it.id == 1_517 }
            .forEach { manager.cancel(it.tag, it.id) }
    }
}

internal fun requireReminderEnvironment(context: Context) {
    LocalEnvironment.requireSafe()
    require(context.applicationContext.packageName == "at.uac.android.local")
}

internal fun reminderLanguage(saved: String?, device: String?): String =
    when (saved) {
        "de",
        "uk" -> saved
        else -> if (device == "uk") "uk" else "de"
    }
