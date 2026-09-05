package at.uac.pushprobe

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.text.DateFormat
import java.util.Date

/** Deliberately separate diagnostic UI; it has no route into UAC or external URLs. */
class ProbeActivity : Activity() {
    private val runtime
        get() = ProbeRuntime.get(this)

    private val handler = Handler(Looper.getMainLooper())
    private lateinit var status: TextView
    private lateinit var receipts: TextView
    private lateinit var enable: Button
    private lateinit var disable: Button
    private var awaitingPermission = false
    private var displayedStopScope: ProbeCleanupScope? = null
    private val refresh =
        object : Runnable {
            override fun run() {
                render()
                handler.postDelayed(this, 1_000)
            }
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        awaitingPermission = savedInstanceState?.getBoolean("awaitingPermission") == true
        val column =
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(24.dp(), 28.dp(), 24.dp(), 28.dp())
            }
        fun label(text: String, size: Float) =
            TextView(this).apply {
                this.text = text
                textSize = size
                setTextColor(0xff17243b.toInt())
                setPadding(0, 8.dp(), 0, 12.dp())
                column.addView(this)
            }
        label("UAC Push Test", 28f)
        label(
            "Isolated test project · SDK-phone emulator only\n\nNo UAC login, contacts, personal notifications, analytics or production data. " +
                "Enabling registers this test installation with Firebase for up to one hour. Only generic ‘UAC Test’ messages are displayed. " +
                "The installation identifier stays out of the screen and logs; the test runner can read a private, single-installation target receipt.",
            16f,
        )
        status = label("Not enabled", 16f).apply { contentDescription = "probe-status" }
        enable =
            Button(this).apply {
                setText(R.string.probe_enable)
                contentDescription = "probe-enable"
                setOnClickListener { requestEnable() }
                column.addView(this)
            }
        disable =
            Button(this).apply {
                setText(R.string.probe_disable)
                contentDescription = "probe-disable"
                setOnClickListener {
                    displayedStopScope?.let(runtime::optOut)
                    render()
                }
                column.addView(this)
            }
        label("Safe event receipts", 20f)
        receipts = label("No events", 14f).apply { contentDescription = "probe-receipts" }
        setContentView(
            ScrollView(this).apply {
                isFillViewport = true
                addView(column)
            }
        )
        runtime.tapped(intent)
    }

    override fun onResume() {
        super.onResume()
        handler.post(refresh)
    }

    override fun onPause() {
        handler.removeCallbacks(refresh)
        super.onPause()
    }

    override fun onDestroy() {
        handler.removeCallbacks(refresh)
        super.onDestroy()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("awaitingPermission", awaitingPermission)
        super.onSaveInstanceState(outState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        runtime.tapped(intent)
        render()
    }

    private fun requestEnable() {
        if (!runtime.configurationAllowed() || !runtime.store.healthy) return
        if (
            Build.VERSION.SDK_INT >= 33 &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
        ) {
            awaitingPermission = true
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                NOTIFICATION_PERMISSION,
            )
        } else runtime.optIn()
        render()
    }

    @Deprecated("Platform permission callback is intentional for this minimal separate Activity")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION) return
        val requested = awaitingPermission
        awaitingPermission = false
        if (
            requested &&
                permissions.contentEquals(arrayOf(Manifest.permission.POST_NOTIFICATIONS)) &&
                grantResults.singleOrNull() == PackageManager.PERMISSION_GRANTED
        )
            runtime.optIn()
        render()
    }

    private fun render() {
        if (!::status.isInitialized) return
        runtime.reconcileConsent()
        val state = runtime.store.snapshot()
        displayedStopScope =
            when {
                state.optedIn && state.runId != null ->
                    ProbeCleanupScope(state.generation, state.runId)
                // Empty run cannot match an active state; this scope can only retry
                // the exact inactive generation that was displayed to the user.
                state.cleanupPending && state.generation > 0 ->
                    ProbeCleanupScope(state.generation - 1, "")
                else -> null
            }
        val allowed = runtime.configurationAllowed()
        status.text =
            when {
                !runtime.store.healthy ->
                    "Blocked: local receipt storage is unavailable. Nothing will be displayed."
                !allowed ->
                    "Blocked: this APK requires the exact test SDK configuration and the authorized API37 SDK-phone AVD."
                state.cleanupPending ->
                    "Opted out. Registration cleanup is pending/unconfirmed. Retry cleanup explicitly."
                state.registering ->
                    "Registration is in progress. You can opt out; cleanup waits for the actual operation."
                state.optedIn && state.registrationHash != null ->
                    "Registered for this test run.\nInstallation fingerprint: ${state.registrationHash.take(12)}\n" +
                        "Run: ${state.runId}\nNotifications allowed: ${runtime.notificationsAllowed()}\nNo raw identifier or token is shown."
                !runtime.notificationsAllowed() ->
                    "Off. System notification permission/channel is unavailable. The enable button requests permission only when you choose it."
                else -> "Off. No registration starts until you explicitly enable the test."
            }
        enable.isEnabled =
            allowed &&
                runtime.store.healthy &&
                !state.optedIn &&
                !state.cleanupPending &&
                !state.registering &&
                !awaitingPermission
        disable.isEnabled =
            runtime.store.healthy && (state.optedIn || state.cleanupPending || state.registering)
        val format = DateFormat.getTimeInstance(DateFormat.MEDIUM)
        receipts.text =
            state.receipts
                .takeLast(18)
                .joinToString("\n") {
                    "${format.format(Date(it.at))}  ${it.event.name}${it.probeId?.let { id -> " · ${id.take(8)}" }.orEmpty()}"
                }
                .ifEmpty { "No events" }
        receipts.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
    }

    private fun Int.dp() = (this * resources.displayMetrics.density).toInt()

    companion object {
        private const val NOTIFICATION_PERMISSION = 41
    }
}
