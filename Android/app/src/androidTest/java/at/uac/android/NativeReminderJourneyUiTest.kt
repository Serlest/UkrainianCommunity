package at.uac.android

import android.Manifest
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.Notification
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleCallback
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.community.CommunityContract
import at.uac.android.feature.inbox.FirestoreInboxSource
import at.uac.android.feature.inbox.InboxPreferences
import at.uac.android.feature.reminders.*
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real inexact alarm and SystemUI drawer. No clock changes, shell broadcasts, exact-alarm grants or
 * fake receipts.
 */
@RunWith(AndroidJUnit4::class)
class NativeReminderJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val context
        get() = instrumentation.targetContext

    private val automation
        get() = instrumentation.uiAutomation

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val runtime
        get() = LocalReminders.get(context)

    private val manager
        get() = context.getSystemService(NotificationManager::class.java)

    private val password = "Synthetic-native-reminder-Only1!"
    private val permissionPackages =
        setOf("com.google.android.permissioncontroller", "com.android.permissioncontroller")

    @Test
    fun actualPermissionInexactAlarmBackgroundDrawerAndFreshEventTap() {
        assumeTrue(
            "Native local reminders require explicit opt-in; skipped is not delivery proof",
            InstrumentationRegistry.getArguments().getString("expectLocalReminders") == "true",
        )
        AccountDeletionFixtures.requireLocalAvd()
        assertTrue(
            "Local Auth/Firestore/Functions must be explicitly enabled",
            AccountDeletionFixtures.online(),
        )
        if (InstrumentationRegistry.getArguments().getString("expectNotificationPrompt") == "true")
            assertFalse(
                "Root must prepare only this AVD package's notification permission",
                granted(),
            )
        val originalFlags = automation.serviceInfo.flags
        automation.serviceInfo =
            automation.serviceInfo.apply {
                flags =
                    flags or
                        AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                        AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            }
        val suffix = UUID.randomUUID().toString()
        val email = "native-reminder-$suffix@example.invalid"
        val eventId = "native-reminder-$suffix"
        val organizationId = "native-reminder-org-$suffix"
        val paths = mutableListOf<String>()
        var originalLaunchIntent: Intent? = null
        var identity: AuthIdentity? = null
        var failure: Throwable? = null
        var stage = "setup"
        fun milestone(next: String) {
            stage = next
            trace(stage, eventId)
        }
        try {
            compose.runOnIdle { originalLaunchIntent = Intent(compose.activity.intent) }
            milestone("setup_started")
            runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
            compose.runOnIdle {
                browse.preference("mode", "emulator")
                browse.preference("language", "de")
                browse.navigate("profile", true)
            }
            runBlocking {
                val fixtures = LocalEmulatorFixtures(context)
                fixtures.seedLegal()
                val backend = FirebaseAuthBackend(LocalFirebase.auth(context))
                val created =
                    backend.create(email, password, "Synthetic reminder journey").also {
                        identity = it
                    }
                paths +=
                    listOf(
                        "users/${created.uid}",
                        "publicProfiles/${created.uid}",
                        "users/${created.uid}/notificationPreferences/settings",
                        "events/$eventId",
                        "organizations/$organizationId",
                        "registrations/${CommunityContract.registrationId(eventId, created.uid)}",
                        "users/${created.uid}/recentViews/event_$eventId",
                        "users/${created.uid}/eventViews/$eventId",
                    )
                FirestoreAuthProfiles(LocalFirebase.firestore(context))
                    .create(
                        created.uid,
                        AuthRegistration(
                            email,
                            "Synthetic reminder journey",
                            "wien",
                            "",
                            true,
                            true,
                            true,
                        ),
                    )
                backend.sendVerification("de")
                backend.verifyEmailCode(fixtures.verificationCode(email))
                backend.reload()
                backend.refreshToken()
                backend.signOut()
            }
            compose.openGuestLogin()
            compose.onNodeWithTag("auth-email").performScrollTo().performTextReplacement(email)
            compose
                .onNodeWithTag("auth-password")
                .performScrollTo()
                .performTextReplacement(password)
            compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
            compose.waitUntil(20_000) {
                auth.state.value.readyForActions && auth.state.value.identity?.uid == identity!!.uid
            }
            milestone("actual_login_ready")
            val fireAt = Instant.now().truncatedTo(ChronoUnit.MINUTES).plusSeconds(120)
            runBlocking {
                val fixtures = LocalEmulatorFixtures(context)
                val created = identity!!
                val now = Instant.now()
                fixtures.seed(
                    "organizations/$organizationId",
                    mapOf(
                        "id" to organizationId,
                        "name" to "Synthetic reminder organization",
                        "description" to "Synthetic",
                        "city" to "Wien",
                        "moderationStatus" to "approved",
                        "createdAt" to now,
                        "updatedAt" to now,
                    ),
                )
                fixtures.seed(
                    "events/$eventId",
                    mapOf(
                        "id" to eventId,
                        "sourceType" to "organization",
                        "organizationId" to organizationId,
                        "moderationStatus" to "approved",
                        "title" to "Synthetic private event title",
                        "summary" to "Synthetic event",
                        "details" to "Synthetic private venue",
                        "createdAt" to now,
                        "updatedAt" to now,
                        "startDate" to fireAt,
                        "endDate" to fireAt.plusSeconds(3_600),
                    ),
                )
                val markerId = CommunityContract.registrationId(eventId, created.uid)
                fixtures.seed(
                    "registrations/$markerId",
                    mapOf(
                        "id" to markerId,
                        "eventId" to eventId,
                        "userId" to created.uid,
                        "registeredAt" to now,
                    ),
                )
                // A pre-existing synthetic consent/registration is setup, not claimed as UI
                // signup/consent proof.
                FirestoreInboxSource(LocalFirebase.firestore(context)).savePreferences(
                    created.uid,
                    InboxPreferences(true, true, 0),
                ) {
                    LocalFirebase.auth(context).currentUser?.uid == created.uid
                }
            }
            compose.runOnIdle { browse.navigate("profile/inbox-settings") }
            compose.waitUntil(15_000) { browse.state.value.route == "profile/inbox-settings" }
            milestone("permission_check")
            if (!granted()) {
                field("reminders-permission-request").performClick()
                awaitNative("notification allow control") { permissionButton() != null }
                milestone("actual_permission_control_visible")
                click(permissionButton()!!, permissionPackages)
                awaitNative("actual notification grant") { granted() }
            }
            milestone("actual_permission_granted")
            field("reminders-retry").performClick()
            compose.waitUntil(25_000) {
                runtime.controller.state.value.stage == ReminderStage.SCHEDULED &&
                    runtime.controller.state.value.scheduled == 1
            }
            milestone("schedule_confirmed")
            assertTrue("The fixture must still have a future trigger", Instant.now() < fireAt)
            assertTrue(ownNotifications().isEmpty())
            assertTrue(automation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME))
            milestone("background_waiting_for_alarm")
            awaitNative("real system alarm notification", 180_000) { ownNotifications().size == 1 }
            milestone("actual_notification_posted")
            val posted = ownNotifications().single()
            assertTrue(
                "Inexact alarms must not fire before the requested minute",
                Instant.now() >= fireAt,
            )
            assertEquals(ReminderIntents.CHANNEL, posted.notification.channelId)
            assertEquals(Notification.CATEGORY_REMINDER, posted.notification.category)
            assertEquals(Notification.VISIBILITY_PRIVATE, posted.notification.visibility)
            assertEquals(
                "UAC · Veranstaltungserinnerung",
                posted.notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            )
            val text =
                posted.notification.extras
                    .getCharSequence(Notification.EXTRA_TEXT)
                    ?.toString()
                    .orEmpty()
            assertFalse(text.contains("Synthetic private"))
            assertFalse(text.contains(email))
            assertNotNull(posted.notification.publicVersion)
            assertTrue(
                automation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS)
            )
            milestone("drawer_opening")
            awaitNative("generic SystemUI reminder row") { notificationRow() != null }
            milestone("actual_drawer_row_visible")
            click(notificationRow()!!, setOf("com.android.systemui"))
            milestone("actual_drawer_row_clicked")
            compose.waitUntil(25_000) {
                auth.state.value.readyForActions &&
                    browse.state.value.route == "events/$eventId" &&
                    browse.state.value.data.detail?.id == eventId &&
                    !browse.state.value.data.loading
            }
            milestone("fresh_navigation_matched")
            assertEquals(identity!!.uid, auth.state.value.identity?.uid)
            assertEquals(
                "Synthetic private event title",
                browse.state.value.data.detail!!.title("de"),
            )
            compose.onNodeWithTag("back").performClick()
            milestone("detail_back_completed")
            runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
            compose.waitUntil(15_000) { auth.state.value.stage == AuthStage.GUEST }
            assertTrue(ownNotifications().isEmpty())
            milestone("body_complete")
        } catch (error: Throwable) {
            failure = error
            trace(stage, eventId, error)
            throw error
        } finally {
            fun cleanup(step: String, action: () -> Unit) {
                try {
                    action()
                } catch (error: Throwable) {
                    trace("cleanup_$step", eventId, error)
                    val previous = failure
                    if (previous == null) failure = error else previous.addSuppressed(error)
                }
            }
            // A generic BACK can finish the guest MainActivity and mask the body result in
            // ActivityScenario teardown.
            // Synthetic cleanup does not need to dismiss or navigate the current system/application
            // surface.
            cleanup("sign_out") {
                runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
            }
            cleanup("owned_identity") {
                runBlocking {
                    val owned = identity ?: return@runBlocking
                    val backend = FirebaseAuthBackend(LocalFirebase.auth(context))
                    backend.signIn(email, password).also { check(it.uid == owned.uid) }
                    backend.deleteCreatedUser(owned.uid)
                    backend.signOut()
                }
            }
            for (path in paths.asReversed()) cleanup("owned_document") {
                runBlocking(Dispatchers.IO) {
                    AuthEmulatorFixtures.adminRequest(
                        8088,
                        AuthEmulatorFixtures.documentPath(path),
                        "DELETE",
                    )
                }
            }
            cleanup("accessibility_flags") {
                automation.serviceInfo = automation.serviceInfo.apply { flags = originalFlags }
            }
            cleanup("scenario_host") { finishScenarioHost(checkNotNull(originalLaunchIntent)) }
            trace(if (failure == null) "cleanup_complete" else "cleanup_after_failure", eventId)
            failure?.let { throw it }
        }
    }

    /**
     * ActivityScenario 1.7 filters lifecycle callbacks by the original Intent action/data, not just
     * the Activity. Main correctly replaces its Intent in onNewIntent after a genuine notification
     * tap. Restore the test's launch identity only after all product assertions and synthetic
     * cleanup, then observe real destruction. No lifecycle event is fabricated and normal
     * ActivityScenario.close remains mandatory and unsuppressed.
     */
    private fun finishScenarioHost(original: Intent) {
        val scenario = compose.activityRule.scenario
        val monitor = ActivityLifecycleMonitorRegistry.getInstance()
        val destroyed = AtomicBoolean(false)
        var observer: ActivityLifecycleCallback? = null
        try {
            scenario.onActivity { tracked ->
                check(
                    tracked.componentName.className == MainActivity::class.java.name &&
                        tracked.packageName == context.packageName
                )
                val resumed =
                    monitor.getActivitiesInStage(Stage.RESUMED).filterIsInstance<MainActivity>()
                check(resumed.isEmpty() || resumed.singleOrNull() === tracked) {
                    "A different Main host must not be silently closed"
                }
                System.out.println(
                    "NativeReminderTrace cleanupHostSame=${resumed.singleOrNull() === tracked} " +
                        "cleanupLaunchFilterChanged=${!original.filterEquals(tracked.intent)}"
                )
                observer =
                    ActivityLifecycleCallback { activity, stage ->
                            if (activity === tracked && stage == Stage.DESTROYED)
                                destroyed.set(true)
                        }
                        .also(monitor::addLifecycleCallback)
                tracked.intent = Intent(original)
                tracked.finish()
            }
            awaitNative("actual tracked Main destruction") { destroyed.get() }
            assertEquals(
                "Scenario must observe the real terminal lifecycle",
                Lifecycle.State.DESTROYED,
                scenario.state,
            )
            scenario.close()
            System.out.println(
                "NativeReminderTrace actualHostDestroyed=true scenarioCloseCompleted=true"
            )
        } finally {
            observer?.let { callback ->
                instrumentation.runOnMainSync { monitor.removeLifecycleCallback(callback) }
            }
        }
    }

    /**
     * Diagnostics are structural only: never print fixture IDs, content, identity, intent extras or
     * exception messages.
     */
    private fun trace(stage: String, expectedEventId: String, failure: Throwable? = null) {
        runCatching {
            var mainResumed: Boolean? = null
            var componentMatches: Boolean? = null
            var navigationMatches: Boolean? = null
            runCatching {
                instrumentation.runOnMainSync {
                    val activities =
                        ActivityLifecycleMonitorRegistry.getInstance()
                            .getActivitiesInStage(Stage.RESUMED)
                    val currentMain = activities.filterIsInstance<MainActivity>().singleOrNull()
                    mainResumed = currentMain != null
                    componentMatches =
                        currentMain?.componentName?.let {
                            it.packageName == context.packageName &&
                                it.className == MainActivity::class.java.name
                        } ?: false
                    navigationMatches =
                        currentMain?.let {
                            val state =
                                ViewModelProvider(it)[BrowseViewModel::class.java].state.value
                            state.route == "events/$expectedEventId" &&
                                state.data.detail?.id == expectedEventId &&
                                !state.data.loading
                        } ?: false
                }
            }
            val permission = runCatching { granted() }.getOrNull()
            val scheduled = runCatching { runtime.controller.state.value.scheduled }.getOrNull()
            val posted = runCatching { ownNotifications().size }.getOrNull()
            val rowVisible = runCatching { notificationRow() != null }.getOrNull()
            val ready = runCatching { auth.state.value.readyForActions }.getOrNull()
            System.out.println(
                "NativeReminderTrace stage=$stage permissionGranted=$permission scheduledCount=$scheduled " +
                    "postedCount=$posted drawerRow=$rowVisible mainResumed=$mainResumed currentComponentMatches=$componentMatches " +
                    "authReady=$ready navigationMatched=$navigationMatches"
            )
            failure?.let {
                val frames =
                    it.stackTrace.take(8).joinToString(" <- ") { frame ->
                        "${frame.className.substringAfterLast('.')}.${frame.methodName}:${frame.lineNumber}"
                    }
                System.out.println(
                    "NativeReminderTrace primaryStage=$stage exceptionType=${it.javaClass.simpleName} " +
                        "causeType=${it.cause?.javaClass?.simpleName ?: "none"} frames=$frames"
                )
            }
        }
    }

    private fun granted() =
        context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun ownNotifications() =
        manager.activeNotifications.filter { it.tag?.startsWith("uac-reminder:") == true }

    private fun field(tag: String): SemanticsNodeInteraction {
        compose.onNodeWithTag("inbox-preferences").performScrollToNode(hasTestTag(tag))
        return compose.onNodeWithTag(tag).performScrollTo()
    }

    private fun nodes(): List<AccessibilityNodeInfo> {
        val result = mutableListOf<AccessibilityNodeInfo>()
        fun visit(node: AccessibilityNodeInfo) {
            result += node
            repeat(node.childCount) { node.getChild(it)?.let(::visit) }
        }
        automation.windows.mapNotNull { it.root }.forEach(::visit)
        return result
    }

    private fun permissionButton() =
        nodes().firstOrNull {
            it.packageName?.toString() in permissionPackages &&
                it.viewIdResourceName?.substringAfterLast('/') == "permission_allow_button" &&
                it.isVisibleToUser &&
                it.isEnabled
        }

    private fun notificationRow() =
        nodes().firstOrNull {
            it.packageName?.toString() == "com.android.systemui" &&
                it.text?.toString() == "UAC · Veranstaltungserinnerung" &&
                it.isVisibleToUser
        }

    private fun click(node: AccessibilityNodeInfo, packages: Set<String>) {
        var target: AccessibilityNodeInfo? = node
        repeat(8) {
            val current = target ?: return@repeat
            check(current.packageName?.toString() in packages)
            if (current.isClickable && current.isEnabled && current.isVisibleToUser) {
                check(current.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                return
            }
            target = current.parent
        }
        error("No scoped native click action")
    }

    private fun awaitNative(stage: String, timeout: Long = 15_000, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < deadline) {
            if (predicate()) return
            SystemClock.sleep(100)
        }
        throw AssertionError("Native reminder stage timed out: $stage")
    }
}
