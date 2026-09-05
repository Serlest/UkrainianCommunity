package at.uac.android

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.View
import android.view.WindowManager
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
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.applock.*
import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.personal.PersonalViewModel
import at.uac.android.feature.personal.personalScope
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real system confirmation, not a fake authenticator. The runner/root owns the AVD's temporary
 * synthetic PIN setup and restoration; this test never sets one.
 */
@RunWith(AndroidJUnit4::class)
class NativeAppLockJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val automation
        get() = instrumentation.uiAutomation

    private val context
        get() = instrumentation.targetContext

    private val store
        get() = LocalAuthSession.get(context)

    private lateinit var lock: AppLockViewModel
    private lateinit var browse: BrowseViewModel
    private lateinit var personal: PersonalViewModel
    private val password = "Synthetic-native-lock-journey-1!"
    private val nativePackages = setOf("com.android.systemui", "com.android.settings")
    private val pinFieldIds = setOf("pinEntry", "pin_entry", "password_entry", "lockPassword")

    @Test
    fun actualSystemPinCancellationEnableBackgroundUnlockAndDisable() {
        assumeTrue(
            "Explicit opt-in required; skipped is not native authentication proof",
            InstrumentationRegistry.getArguments().getString("expectLocalDeviceLock") == "true",
        )
        requireAvd()
        assertEquals(
            "This journey requires the local backend",
            "true",
            InstrumentationRegistry.getArguments().getString("expectEmulator"),
        )
        assertTrue(
            "Root must prepare the synthetic AVD PIN before this test",
            (context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager).isDeviceSecure,
        )
        val originalAccessibilityFlags = automation.serviceInfo.flags
        val originalLaunchIntent = Intent(compose.activity.intent)
        configureInspection()
        var account: AuthIdentity? = null
        var primaryFailure: Throwable? = null
        val email = "native-lock-${UUID.randomUUID()}@example.invalid"
        try {
            runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
            cleanupPreviousMarker()
            compose.runOnIdle {
                lock = ViewModelProvider(compose.activity)[AppLockViewModel::class.java]
                browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
                personal = ViewModelProvider(compose.activity)[PersonalViewModel::class.java]
                assertTrue(
                    "No injected authenticator is allowed",
                    lock.authentication is SystemAppLockAuthenticator,
                )
                browse.preference("mode", "emulator")
                browse.preference("language", "de")
                browse.navigate("profile", true)
            }
            val owned =
                prepare(email) {
                    account = it
                    marker.writeText(
                        JSONObject()
                            .put("version", 1)
                            .put("uid", it.uid)
                            .put("email", email)
                            .toString()
                    )
                }
            compose.openGuestLogin()
            field("auth-email").performTextReplacement(email)
            field("auth-password").performTextReplacement(password)
            field("auth-login-submit").performClick()
            await("signed in") {
                store.state.value.readyForActions &&
                    lock.state.value.session == store.state.value.appLockSession()
            }
            assertEquals(owned.uid, store.state.value.identity?.uid)
            assertFalse(DeviceAppLockPreferences(context).enabled(owned.uid))
            assertFalse(lock.state.value.enabled)

            val beforeCancel = store.state.value.revision
            field("app-lock-toggle").assertIsOff().performClick()
            awaitPinSurface("enable-cancel")
            trace("native cancel prompt observed")
            nativeBack()
            await("cancel returned") {
                !lock.state.value.authenticating &&
                    store.state.value.readyForActions &&
                    lock.state.value.foreground
            }
            assertFalse(
                "Cancel must not persist protection",
                DeviceAppLockPreferences(context).enabled(owned.uid),
            )
            assertEquals(
                "A native confirmation round trip must not replace the session",
                beforeCancel,
                store.state.value.revision,
            )
            field("app-lock-toggle").assertIsOff()

            val beforeEnable = store.state.value.revision
            field("app-lock-toggle").performClick()
            awaitPinSurface("enable")
            enterSyntheticPin()
            await("enabled by native result") {
                lock.state.value.enabled &&
                    lock.state.value.unlocked &&
                    !lock.state.value.authenticating
            }
            assertEquals(
                "Native enable must preserve exact Auth revision",
                beforeEnable,
                store.state.value.revision,
            )
            assertTrue(DeviceAppLockPreferences(context).enabled(owned.uid))
            field("app-lock-toggle").assertIsOn()
            trace("enabled by real system result")

            field("account-open-edit").performClick()
            awaitCompose("profile loaded") {
                personal.state.value.profile?.uid == owned.uid &&
                    !personal.state.value.profileLoading
            }
            val draft = "Synthetic draft survives local lock"
            field("profile-display-name").performTextReplacement(draft)
            // HOME is an actual user background transition; no state injection or
            // scenario lifecycle shortcut may pretend that the shield appeared.
            key(KeyEvent.KEYCODE_HOME)
            await("background protection") {
                !lock.state.value.foreground && lock.state.value.locked
            }
            instrumentation.runOnMainSync {
                val window = compose.activity.window
                val flags =
                    WindowManager.LayoutParams.FLAG_SECURE or
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                assertEquals(flags, window.attributes.flags and flags)
                assertEquals(
                    View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS,
                    window.decorView.importantForAccessibility,
                )
            }
            trace("background shield active")
            context.startActivity(
                Intent(context, MainActivity::class.java)
                    .addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
            )
            await("foreground remains locked") {
                lock.state.value.foreground &&
                    lock.state.value.locked &&
                    !store.state.value.busy &&
                    lock.state.value.session == store.state.value.appLockSession()
            }
            assertFalse(lock.state.value.canRoute)
            assertFalse(
                "No automatic prompt after ordinary background",
                lock.state.value.authenticating,
            )
            assertEquals(owned.uid, store.state.value.identity?.uid)
            assertPrivateContentNotAccessible(email, draft)
            compose.onNodeWithTag("app-lock-unlock").performScrollTo().assertIsDisplayed()
            val beforeUnlock = store.state.value.revision
            compose.onNodeWithTag("app-lock-unlock").performClick()
            awaitPinSurface("unlock")
            enterSyntheticPin()
            await("unlocked by native result") {
                !lock.state.value.locked &&
                    !lock.state.value.authenticating &&
                    lock.state.value.canRoute
            }
            assertEquals(
                "Native unlock must preserve exact Auth revision",
                beforeUnlock,
                store.state.value.revision,
            )
            awaitCompose("profile available after unlock") {
                personal.state.value.profile?.uid == owned.uid &&
                    !personal.state.value.profileLoading
            }
            field("profile-display-name").assertTextContains(draft)
            trace("native unlock retained editor")

            compose.onNodeWithTag("back").performClick()
            await("account route") { browse.state.value.route == "profile" }
            val beforeDisable = store.state.value.revision
            field("app-lock-toggle").assertIsOn().performClick()
            awaitPinSurface("disable")
            enterSyntheticPin()
            await("disabled by native result") {
                !lock.state.value.enabled && !lock.state.value.authenticating
            }
            assertEquals(
                "Native disable must preserve exact Auth revision",
                beforeDisable,
                store.state.value.revision,
            )
            assertFalse(DeviceAppLockPreferences(context).enabled(owned.uid))
            field("app-lock-toggle").assertIsOff()
            trace("disabled by real system result")
        } catch (error: Throwable) {
            if (::lock.isInitialized) trace("failure")
            val failure =
                AssertionError(
                    "Native local-lock journey failed. ${runCatching { stateDiagnostic() }.getOrDefault("State unavailable")}; System controls: ${runCatching { nativeDiagnostic() }.getOrDefault("unavailable")}",
                    error,
                )
            primaryFailure = failure
            throw failure
        } finally {
            // Dismiss only the specifically observed native confirmation, never
            // arbitrary app or system screens. Every cleanup step is independent
            // and may not mask the original failure or prevent account cleanup.
            val failures = mutableListOf<Throwable>()
            fun clean(step: String, action: () -> Unit) {
                runCatching(action).onFailure {
                    failures += AssertionError("Cleanup $step failed (${it.javaClass.simpleName})")
                }
            }
            clean("native prompt") { if (pinSurfacePresent()) nativeBack() }
            clean("pending local request") {
                if (::lock.isInitialized)
                    instrumentation.runOnMainSync { lock.cancelAuthentication() }
            }
            clean("Auth session") {
                runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
            }
            val accountFailures =
                account?.let { owned -> cleanupAccount(owned.uid, email) }.orEmpty()
            failures += accountFailures
            clean("accessibility flags") {
                automation.serviceInfo =
                    automation.serviceInfo.apply { flags = originalAccessibilityFlags }
            }
            if (account != null && accountFailures.isEmpty())
                clean("private fixture marker") { check(!marker.exists() || marker.delete()) }
            clean("tracked scenario host") { finishScenarioHost(originalLaunchIntent) }
            if (failures.isNotEmpty()) {
                val failure =
                    primaryFailure
                        ?: AssertionError(
                            "Native journey cleanup is incomplete; exact fixture marker retained"
                        )
                failures.forEach(failure::addSuppressed)
                if (primaryFailure == null) throw failure
            }
        }
    }

    private fun finishScenarioHost(original: Intent) {
        // The real foreground intent changed in onNewIntent. ActivityScenario 1.7 filters
        // lifecycle events by launch action/data; restore only this test identity AFTER all
        // product assertions and fixture cleanup, then require actual, observed destruction.
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
                check(resumed.isEmpty() || resumed.singleOrNull() === tracked)
                println(
                    "native-lock: cleanup launch filter changed=${!original.filterEquals(tracked.intent)}"
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
            await("actual tracked Main destruction") { destroyed.get() }
            assertEquals(Lifecycle.State.DESTROYED, scenario.state)
            scenario.close()
        } finally {
            observer?.let { callback ->
                instrumentation.runOnMainSync { monitor.removeLifecycleCallback(callback) }
            }
        }
    }

    private fun prepare(email: String, onCreated: (AuthIdentity) -> Unit): AuthIdentity =
        runBlocking {
            LocalEmulatorFixtures(context).seedLegal()
            val backend = FirebaseAuthBackend(LocalFirebase.auth(context))
            val identity = backend.create(email, password, "Native Lock Demo")
            onCreated(identity)
            FirestoreAuthProfiles(LocalFirebase.firestore(context))
                .create(
                    identity.uid,
                    AuthRegistration(
                        email,
                        "Native Lock Demo",
                        "wien",
                        acceptedTerms = true,
                        acceptedPrivacy = true,
                        minimumAgeConfirmed = true,
                    ),
                )
            backend.sendVerification("de")
            backend.verifyEmailCode(LocalEmulatorFixtures(context).verificationCode(email))
            backend.reload()
            backend.refreshToken()
            backend.signOut()
            identity
        }

    private fun requireAvd() {
        LocalEnvironment.requireSafe()
        check(context.packageName == "at.uac.android.local")
        check(
            (Build.VERSION.SDK_INT == 37 &&
                Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone")) || isExplicitApi26CompatibilityAvd()
        ) {
            "Native PIN automation requires the API37 SDK-phone AVD or explicit exact API26 compatibility opt-in"
        }
        val qemu =
            ParcelFileDescriptor.AutoCloseInputStream(
                    automation.executeShellCommand("getprop ro.kernel.qemu")
                )
                .bufferedReader()
                .use { it.readText().trim() }
        check(qemu == "1") { "Physical devices are forbidden for this test" }
    }

    private fun configureInspection() {
        automation.serviceInfo =
            automation.serviceInfo.apply {
                flags =
                    (flags or
                        AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                        AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS) and
                        AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS.inv()
            }
    }

    private fun field(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun awaitCompose(stage: String, condition: () -> Boolean) {
        // Navigation composes the editor and starts its LaunchedEffect. A plain
        // wall-clock sleep does not advance the Compose test clock, so it cannot
        // wait for that effect to launch the actual profile read.
        try {
            compose.waitUntil(timeoutMillis = 20_000, condition = condition)
            trace(stage)
        } catch (error: ComposeTimeoutException) {
            throw AssertionError(
                "Timed out at $stage; ${stateDiagnostic()}; ${nativeDiagnostic()}",
                error,
            )
        }
    }

    private fun await(stage: String, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20_000
        while (SystemClock.elapsedRealtime() < deadline) {
            if (condition()) {
                trace(stage)
                return
            }
            Thread.sleep(100)
        }
        error("Timed out at $stage; ${stateDiagnostic()}; ${nativeDiagnostic()}")
    }

    private fun stateDiagnostic(): String {
        val state = lock.state.value
        val auth = store.state.value
        val profile = personal.state.value
        val route =
            browse.state.value.route.takeIf { it in setOf("profile", "profile/edit") } ?: "other"
        return "auth=${auth.stage}; revision=${auth.revision}; ready=${auth.readyForActions}; enabled=${state.enabled}; unlocked=${state.unlocked}; foreground=${state.foreground}; pending=${state.authenticating}; error=${state.error}; route=$route; personalScopeCurrent=${profile.session == auth.personalScope()}; profileLoading=${profile.profileLoading}; profileError=${profile.profileError}; profilePresent=${profile.profile != null}"
    }

    private fun trace(stage: String) = println("native-lock: $stage; ${stateDiagnostic()}")

    private fun nodes(packages: Set<String>): List<AccessibilityNodeInfo> {
        // UiAutomation.clearCache is API34+. API26 still offers node.refresh(), so the
        // legacy credential path can verify current system nodes without a hidden API.
        if (Build.VERSION.SDK_INT >= 34) automation.clearCache()
        val roots =
            automation.windows
                .mapNotNull { it.root }
                .filter { it.packageName?.toString() in packages }
                .ifEmpty {
                    listOfNotNull(
                        automation.rootInActiveWindow?.takeIf {
                            it.packageName?.toString() in packages
                        }
                    )
                }
        val result = mutableListOf<AccessibilityNodeInfo>()
        fun walk(node: AccessibilityNodeInfo, depth: Int) {
            if (depth > 30 || node.packageName?.toString() !in packages) return
            if (Build.VERSION.SDK_INT < 34 && !node.refresh()) return
            if (node.isVisibleToUser) result += node
            for (index in 0 until node.childCount) node.getChild(index)?.let { walk(it, depth + 1) }
        }
        roots.forEach { walk(it, 0) }
        return result
    }

    private fun AccessibilityNodeInfo.id() = viewIdResourceName?.substringAfterLast('/')

    private fun pinSurfacePresent() =
        nodes(nativePackages).any { it.id() in pinFieldIds || it.id() == "key_enter" }

    private fun awaitPinSurface(stage: String) {
        await("native $stage surface") { pinSurfacePresent() }
        assertTrue(
            "Only an actual pending SDK request may enter device credentials",
            lock.state.value.authenticating,
        )
    }

    private fun clickable(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var current: AccessibilityNodeInfo? = node
        repeat(6) {
            val candidate = current ?: return null
            if (candidate.packageName?.toString() !in nativePackages) return null
            if (candidate.isClickable && candidate.isEnabled) return candidate
            current = candidate.parent
        }
        return null
    }

    private fun enterSyntheticPin() {
        requireAvd()
        check(pinSurfacePresent()) { "No verified SystemUI/Settings credential surface" }
        val captured = lock.state.value.session ?: error("No local confirmation session")
        fun requirePendingSession() {
            check(
                lock.state.value.authenticating &&
                    lock.state.value.session == captured &&
                    store.state.value.appLockSession() == captured
            ) {
                "Native confirmation scope changed"
            }
        }
        // This public synthetic test PIN is prepared by root only on this AVD.
        for (digit in "482716") {
            requirePendingSession()
            val native = nodes(nativePackages)
            val keyNode = native.firstOrNull { it.id() == "key$digit" }
            val target = keyNode?.let(::clickable)
            if (target != null) {
                requireFocusedNativeWindow(target)
                assertTrue(target.performAction(AccessibilityNodeInfo.ACTION_CLICK))
            } else {
                val legacy = native.singleOrNull { it.id() in pinFieldIds }
                val input =
                    legacy
                        ?: focusedComposePinInput(native)
                        ?: error("Exact native PIN input/pad missing; ${nativeDiagnostic()}")
                requireFocusedNativeWindow(input)
                if (legacy != null && !input.isFocused) {
                    assertTrue(
                        "Native PIN field rejected focus",
                        input.performAction(AccessibilityNodeInfo.ACTION_FOCUS),
                    )
                    check(
                        nodes(nativePackages).any {
                            it.id() in pinFieldIds && it.windowId == input.windowId && it.isFocused
                        }
                    ) {
                        "Native PIN input is not focused"
                    }
                }
                requirePendingSession()
                key(KeyEvent.KEYCODE_0 + digit.digitToInt())
            }
            Thread.sleep(80)
        }
        if (!lock.state.value.authenticating) {
            // Some system PIN panels auto-submit after the last digit. Never
            // send an extra ENTER into the app which has just regained focus.
            // The caller still requires the actual expected adapter result and
            // persisted preference; terminal rejection/cancellation cannot pass.
            check(
                lock.state.value.session == captured &&
                    store.state.value.appLockSession() == captured
            ) {
                "Native confirmation scope changed before terminal result"
            }
            return
        }
        requirePendingSession()
        val submit =
            nodes(nativePackages)
                .firstOrNull { it.id() in setOf("key_enter", "button_confirm") }
                ?.let(::clickable)
        if (submit != null) {
            requireFocusedNativeWindow(submit)
            assertTrue(submit.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        } else {
            val native = nodes(nativePackages)
            val input =
                native.singleOrNull { it.id() in pinFieldIds && it.isFocused }
                    ?: focusedComposePinInput(native)
                    ?: error("No verified native PIN input for submit")
            requireFocusedNativeWindow(input)
            key(KeyEvent.KEYCODE_ENTER)
        }
    }

    /** API37 SystemUI uses a focused Compose View, not EditText/pinEntry. */
    private fun focusedComposePinInput(
        native: List<AccessibilityNodeInfo>
    ): AccessibilityNodeInfo? {
        val systemUi = "com.android.systemui"
        val focused = native.filter { node ->
            node.packageName?.toString() == systemUi &&
                node.className?.toString() == "android.view.View" &&
                node.isEnabled &&
                node.isFocused &&
                node.isVisibleToUser
        }
        return focused.singleOrNull { node ->
            val ancestorIds = mutableSetOf<String>()
            var ancestor: AccessibilityNodeInfo? = node
            repeat(20) {
                val current = ancestor ?: return@repeat
                if (
                    current.packageName?.toString() != systemUi || current.windowId != node.windowId
                ) {
                    ancestor = null
                } else {
                    current.id()?.let(ancestorIds::add)
                    ancestor = current.parent
                }
            }
            setOf("cred_pin_pad", "compose_credential_view").all { it in ancestorIds } &&
                native.any {
                    it.packageName?.toString() == systemUi &&
                        it.windowId == node.windowId &&
                        it.id() == "key_enter" &&
                        it.isEnabled
                }
        }
    }

    private fun requireFocusedNativeWindow(node: AccessibilityNodeInfo) {
        val packageName = node.packageName?.toString()
        check(packageName in nativePackages && node.isVisibleToUser && node.isEnabled)
        val window = automation.windows.singleOrNull { it.id == node.windowId }
        check(
            window?.isFocused == true &&
                window.root?.packageName?.toString() == packageName &&
                automation.rootInActiveWindow?.packageName?.toString() == packageName
        ) {
            "Refusing synthetic key outside the focused native credential window"
        }
    }

    private fun nativeBack() {
        check(pinSurfacePresent()) { "Refusing BACK outside the verified credential surface" }
        assertTrue(
            "System BACK dispatch was not accepted",
            automation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK),
        )
    }

    private fun key(code: Int) {
        if (code == KeyEvent.KEYCODE_HOME) {
            assertTrue(
                "System HOME dispatch was not accepted",
                automation.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME),
            )
            return
        }
        val down = SystemClock.uptimeMillis()
        fun event(action: Int) =
            KeyEvent(
                down,
                SystemClock.uptimeMillis(),
                action,
                code,
                0,
                0,
                KeyCharacterMap.VIRTUAL_KEYBOARD,
                0,
                0,
                InputDevice.SOURCE_KEYBOARD,
            )
        assertTrue(
            "Native key DOWN dispatch was not accepted",
            automation.injectInputEvent(event(KeyEvent.ACTION_DOWN), true),
        )
        assertTrue(
            "Native key UP dispatch was not accepted",
            automation.injectInputEvent(event(KeyEvent.ACTION_UP), true),
        )
    }

    private val marker
        get() = File(context.noBackupFilesDir, "native-lock-journey-fixture.json")

    private fun cleanupPreviousMarker() {
        if (!marker.exists()) return
        val prior = JSONObject(marker.readText())
        check(prior.getInt("version") == 1)
        val uid = prior.getString("uid")
        val email = prior.getString("email")
        check(uid.matches(Regex("[A-Za-z0-9_-]{1,128}")))
        val suffix = email.removePrefix("native-lock-").removeSuffix("@example.invalid")
        check(email == "native-lock-${UUID.fromString(suffix)}@example.invalid")
        val failures = cleanupAccount(uid, email)
        if (failures.isNotEmpty())
            throw AssertionError("Prior exact native test fixture needs cleanup").also { error ->
                failures.forEach(error::addSuppressed)
            }
        check(marker.delete())
    }

    private fun cleanupAccount(uid: String, email: String): List<Throwable> {
        val failures = mutableListOf<Throwable>()
        fun clean(step: String, action: () -> Unit) {
            runCatching(action).onFailure {
                failures += AssertionError("Synthetic $step failed (${it.javaClass.simpleName})")
            }
        }
        val backend = FirebaseAuthBackend(LocalFirebase.auth(context))
        clean("identity cleanup") {
            runBlocking {
                val current = backend.signIn(email, password)
                check(current.uid == uid)
                backend.deleteCreatedUser(uid)
            }
        }
        listOf("users/$uid", "publicProfiles/$uid").forEach { path ->
            clean("profile cleanup") {
                runBlocking(Dispatchers.IO) {
                    AuthEmulatorFixtures.adminRequest(
                        8088,
                        AuthEmulatorFixtures.documentPath(path),
                        "DELETE",
                    )
                }
            }
        }
        clean("backend sign-out") { runBlocking { backend.signOut() } }
        clean("own device preference") {
            // Cleanup is not counted as successful UI/system disable evidence.
            assertTrue(
                context
                    .getSharedPreferences("uac-device-lock", Context.MODE_PRIVATE)
                    .edit()
                    .remove(appLockPreferenceKey(uid))
                    .commit()
            )
        }
        return failures
    }

    private fun assertPrivateContentNotAccessible(email: String, draft: String) {
        val exposed =
            nodes(setOf(context.packageName)).any { node ->
                node.text?.toString()?.let { email in it || draft in it } == true ||
                    node.contentDescription?.toString()?.let { email in it || draft in it } == true
            }
        assertFalse("Locked native windows must hide private accessibility content", exposed)
    }

    private fun nativeDiagnostic(): String =
        nodes(nativePackages)
            .map {
                "${it.packageName}:${it.id() ?: "no-id"}:${it.className}:enabled=${it.isEnabled}:focused=${it.isFocused}"
            }
            .distinct()
            .take(35)
            .joinToString(" | ")
}
