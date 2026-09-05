package at.uac.pushprobe

import android.Manifest
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import java.io.File
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

/**
 * No fake Firebase/provider result, shell grant, app-data reset, or send. Root owns the exact AVD.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class ProbeSafetyDeviceTest {
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val context
        get() = instrumentation.targetContext

    private val automation
        get() = instrumentation.uiAutomation

    private val runtime
        get() = ProbeRuntime.get(context)

    private val target
        get() = File(context.noBackupFilesDir, "push-probe/target.json")

    private val permissionPackages =
        setOf("com.google.android.permissioncontroller", "com.android.permissioncontroller")

    @Test
    fun a_noConsentAndActualPermissionDenialNeverInitializeFirebase() {
        assumeTrue(
            "Fresh-install proof requires explicit opt-in; skip is not proof",
            argument("expectFreshPushProbe"),
        )
        requireAvd()
        assertTrue("Root must supply the exact test SDK config", runtime.configurationAllowed())
        assertTrue(runtime.store.healthy)
        assertFalse(
            "Root must provide a fresh probe install, not clear somebody else's data",
            runtime.store.snapshot().everOptedIn,
        )
        assertFalse(notificationsGranted())
        withInspection {
            ActivityScenario.launch(ProbeActivity::class.java).use {
                await("initial activity") { appScrollVisible() }
                assertTrue(
                    "First launch must not create a default Firebase app",
                    FirebaseApp.getApps(context).isEmpty(),
                )
                assertFalse(target.exists())
                clickApp("probe-enable")
                await("actual permission denial control") {
                    permissionButton("permission_deny_button") != null
                }
                click(permissionButton("permission_deny_button")!!, permissionPackages)
                await("permission dialog dismissed") {
                    permissionButton("permission_deny_button") == null &&
                        findApp("probe-enable")?.isEnabled == true
                }
                assertFalse(notificationsGranted())
                assertFalse(runtime.store.snapshot().everOptedIn)
                assertFalse(runtime.store.snapshot().optedIn)
                assertTrue(
                    "Denial must not initialize Firebase/FIS",
                    FirebaseApp.getApps(context).isEmpty(),
                )
                assertFalse(target.exists())
                trace("actual deny retained no-consent/no-default")
            }
        }
    }

    @Test
    fun b_actualRegisterUiAndOptOutWaitForRealUnregister() {
        assumeTrue(
            "Cloud registration requires explicit opt-in; skip is not proof",
            argument("expectPushProbeCloud"),
        )
        requireAvd()
        assertTrue("Root must supply the exact test SDK config", runtime.configurationAllowed())
        assertTrue(runtime.store.healthy)
        val before = runtime.store.snapshot()
        assertFalse(
            "Do not take over root's active installation",
            before.optedIn || before.registering || before.cleanupPending,
        )
        var began = false
        var failure: Throwable? = null
        try {
            withInspection {
                ActivityScenario.launch(ProbeActivity::class.java).use {
                    await("inactive activity") { appScrollVisible() }
                    began = true
                    clickApp("probe-enable")
                    if (!notificationsGranted()) {
                        await("actual permission allow control") {
                            permissionButton("permission_allow_button") != null
                        }
                        click(permissionButton("permission_allow_button")!!, permissionPackages)
                    }
                    await("actual SDK registration", 45_000) {
                        val state = runtime.store.snapshot()
                        state.optedIn &&
                            !state.registering &&
                            state.registrationHash != null &&
                            target.isFile
                    }
                    assertTrue(runtime.store.healthy)
                    val registered = runtime.store.snapshot()
                    assertEquals(before.generation + 1, registered.generation)
                    assertTrue(
                        registered.receipts.any { receipt ->
                            receipt.event == ProbeEvent.REGISTER_ACK
                        }
                    )
                    val descriptor = JSONObject(target.readText())
                    // Boolean checks prevent assertion diagnostics from printing identifiers.
                    assertTrue(
                        "Target project mismatch",
                        descriptor.getString("projectId") == ProbeContract.PROJECT,
                    )
                    assertTrue(
                        "Target app mismatch",
                        descriptor.getString("appId") == ProbeContract.APP,
                    )
                    assertTrue(
                        "Target package mismatch",
                        descriptor.getString("packageName") == ProbeContract.PACKAGE,
                    )
                    assertTrue(
                        "Target generation mismatch",
                        descriptor.getLong("generation") == registered.generation,
                    )
                    assertTrue(
                        "Target run mismatch",
                        descriptor.getString("runId") == registered.runId,
                    )
                    val fid = descriptor.getString("installationId")
                    assertTrue("Invalid installation identifier shape", ProbeContract.validFid(fid))
                    assertTrue(
                        "Target fingerprint mismatch",
                        ProbeContract.hash(fid) == registered.registrationHash,
                    )
                    assertFalse(FirebaseMessaging.getInstance().isAutoInitEnabled)
                    assertFalse(
                        FirebaseMessaging.getInstance().deliveryMetricsExportToBigQueryEnabled()
                    )
                    assertFalse(FirebaseMessaging.getInstance().isNotificationDelegationEnabled)
                    trace("actual register acknowledgement and private target verified")
                    clickApp("probe-disable")
                    await("local opt-out immediately masked") {
                        !runtime.store.snapshot().optedIn && !target.exists()
                    }
                    await("actual SDK unregister", 45_000) {
                        !runtime.store.snapshot().cleanupPending
                    }
                    val stopped = runtime.store.snapshot()
                    assertTrue(
                        stopped.receipts.any { receipt ->
                            receipt.event == ProbeEvent.UNREGISTER_ACK
                        }
                    )
                    assertFalse(stopped.registering)
                    assertNull(stopped.registrationHash)
                    assertNull(stopped.runId)
                    assertFalse(target.exists())
                    assertFalse(FirebaseMessaging.getInstance().isAutoInitEnabled)
                    trace("actual unregister acknowledgement verified")
                }
            }
        } catch (error: Throwable) {
            failure = error
            throw error
        } finally {
            if (began)
                runCatching {
                    runtime.optOut()
                    await("final exact probe cleanup", 45_000) {
                        !runtime.store.snapshot().optedIn &&
                            !runtime.store.snapshot().cleanupPending &&
                            !target.exists()
                    }
                }
                    .onFailure {
                        val cleanup =
                            AssertionError(
                                "Probe registration cleanup is unconfirmed (${it.javaClass.simpleName})"
                            )
                        val primary = failure
                        if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
                    }
        }
    }

    /**
     * Explicit two-phase transport setup: intentionally retains the confirmed target on success.
     */
    @Test
    fun c_prepareSingleSend() {
        assumeTrue(
            "Holding a cloud target requires explicit root opt-in",
            argument("expectPushProbePrepare"),
        )
        requireAvd()
        assertTrue(runtime.configurationAllowed())
        assertTrue(runtime.store.healthy)
        val before = runtime.store.snapshot()
        assertFalse(
            "Do not take over an active registration",
            before.optedIn || before.registering || before.cleanupPending,
        )
        var success = false
        var began = false
        var failure: Throwable? = null
        try {
            withInspection {
                ActivityScenario.launch(ProbeActivity::class.java).use {
                    await("prepare activity") { appScrollVisible() }
                    began = true
                    clickApp("probe-enable")
                    if (!notificationsGranted()) {
                        await("prepare permission allow") {
                            permissionButton("permission_allow_button") != null
                        }
                        click(permissionButton("permission_allow_button")!!, permissionPackages)
                    }
                    await("prepare actual registration", 45_000) {
                        val state = runtime.store.snapshot()
                        state.optedIn &&
                            !state.registering &&
                            state.registrationHash != null &&
                            target.isFile
                    }
                    assertTrue(runtime.store.healthy)
                    val state = runtime.store.snapshot()
                    assertEquals(before.generation + 1, state.generation)
                    assertTrue(
                        state.receipts.any { receipt -> receipt.event == ProbeEvent.REGISTER_ACK }
                    )
                    val descriptor = JSONObject(target.readText())
                    assertTrue(
                        "Wrong target identity",
                        descriptor.getString("projectId") == ProbeContract.PROJECT &&
                            descriptor.getString("projectNumber") == ProbeContract.NUMBER &&
                            descriptor.getString("appId") == ProbeContract.APP &&
                            descriptor.getString("packageName") == ProbeContract.PACKAGE,
                    )
                    assertTrue(
                        "Wrong target scope",
                        descriptor.getString("runId") == state.runId &&
                            descriptor.getLong("generation") == state.generation,
                    )
                    assertTrue(
                        "Wrong target fingerprint",
                        ProbeContract.hash(descriptor.getString("installationId")) ==
                            state.registrationHash,
                    )
                    assertTrue(
                        "Target expired",
                        descriptor.getLong("runExpiresAtEpochMs") > System.currentTimeMillis(),
                    )
                    trace("prepared one actual registration; private descriptor retained for root")
                }
            }
            success = true
        } catch (error: Throwable) {
            failure = error
            throw error
        } finally {
            if (began && !success)
                runCatching {
                    runtime.optOut()
                    await("failed prepare cleanup", 45_000) {
                        !runtime.store.snapshot().cleanupPending && !target.exists()
                    }
                }
                    .onFailure {
                        val cleanup =
                            AssertionError(
                                "Failed prepare cleanup remains unconfirmed (${it.javaClass.simpleName})"
                            )
                        val primary = failure
                        if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
                    }
        }
    }

    /** Does not silently stop a different/newer run that root may have prepared. */
    @Test
    fun d_cleanupSingleSend() {
        assumeTrue(
            "Cloud target cleanup requires explicit root opt-in",
            argument("expectPushProbeCleanup"),
        )
        requireAvd()
        assertTrue(runtime.configurationAllowed())
        assertTrue(runtime.store.healthy)
        val args = InstrumentationRegistry.getArguments()
        val run = args.getString("expectedPushProbeRun").orEmpty()
        val generation =
            args.getString("expectedPushProbeGeneration")?.toLongOrNull()
                ?: error("Exact prepared generation is required")
        require(ProbeContract.validId(run) && generation > 0)
        val expected = ProbeCleanupScope(generation, run)
        fun current() = expected.matches(runtime.store.snapshot())
        check(current()) { "Refusing cleanup of an unrelated or newer test run" }
        var failure: Throwable? = null
        try {
            withInspection {
                ActivityScenario.launch(ProbeActivity::class.java).use {
                    await("cleanup activity") { appScrollVisible() }
                    check(current()) { "Prepared run changed before cleanup" }
                    if (runtime.store.snapshot().optedIn || runtime.store.snapshot().cleanupPending)
                        clickApp("probe-disable")
                    await("cleanup actual unregister", 45_000) {
                        current() &&
                            !runtime.store.snapshot().optedIn &&
                            !runtime.store.snapshot().cleanupPending &&
                            !target.exists()
                    }
                    assertTrue(
                        runtime.store.snapshot().receipts.any { receipt ->
                            receipt.event == ProbeEvent.UNREGISTER_ACK
                        }
                    )
                    trace("exact prepared run cleanup confirmed")
                }
            }
        } catch (error: Throwable) {
            failure = error
            throw error
        } finally {
            if (current())
                runCatching {
                    check(runtime.optOut(expected)) { "Prepared cleanup scope changed" }
                    await("final single-target cleanup", 45_000) {
                        !runtime.store.snapshot().cleanupPending && !target.exists()
                    }
                }
                    .onFailure {
                        val cleanup =
                            AssertionError(
                                "Single-target cleanup remains unconfirmed (${it.javaClass.simpleName})"
                            )
                        val primary = failure
                        if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
                    }
        }
    }

    private fun argument(name: String) =
        InstrumentationRegistry.getArguments().getString(name) == "true"

    private fun notificationsGranted() =
        context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED

    private fun requireAvd() {
        check(
            BuildConfig.DEBUG &&
                context.packageName == ProbeContract.PACKAGE &&
                Build.VERSION.SDK_INT == 37 &&
                Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone")
        )
        val qemu =
            ParcelFileDescriptor.AutoCloseInputStream(
                    automation.executeShellCommand("getprop ro.kernel.qemu")
                )
                .bufferedReader()
                .use { it.readText().trim() }
        check(qemu == "1") { "Physical devices are forbidden for automated permission changes" }
    }

    private fun withInspection(action: () -> Unit) {
        val oldFlags = automation.serviceInfo.flags
        automation.serviceInfo =
            automation.serviceInfo.apply {
                flags =
                    flags or
                        AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                        AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            }
        var failure: Throwable? = null
        try {
            action()
        } catch (error: Throwable) {
            failure = error
            throw error
        } finally {
            runCatching {
                automation.serviceInfo = automation.serviceInfo.apply { flags = oldFlags }
            }
                .onFailure {
                    val cleanup =
                        AssertionError(
                            "Accessibility inspection cleanup failed (${it.javaClass.simpleName})"
                        )
                    val primary = failure
                    if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
                }
        }
    }

    private fun findApp(description: String) =
        nodes(setOf(ProbeContract.PACKAGE)).firstOrNull {
            it.contentDescription?.toString() == description
        }

    private fun appScrollVisible() =
        nodes(setOf(ProbeContract.PACKAGE)).any {
            it.className?.toString() == "android.widget.ScrollView"
        }

    private fun permissionButton(id: String) =
        nodes(permissionPackages).firstOrNull {
            it.viewIdResourceName?.substringAfterLast('/') == id
        }

    private fun clickApp(description: String) {
        repeat(8) {
            val node = findApp(description)
            if (node != null) {
                click(node, setOf(ProbeContract.PACKAGE))
                return
            }
            val scroll =
                nodes(setOf(ProbeContract.PACKAGE)).firstOrNull {
                    it.className?.toString() == "android.widget.ScrollView"
                } ?: error("Expected exact probe control: $description")
            check(scroll.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)) {
                "Expected probe control is not reachable: $description"
            }
            Thread.sleep(150)
        }
        error("Expected probe control is not reachable: $description")
    }

    private fun click(node: AccessibilityNodeInfo, allowed: Set<String>) {
        var current: AccessibilityNodeInfo? = node
        repeat(6) {
            val candidate = current ?: error("No clickable expected control")
            check(candidate.packageName?.toString() in allowed)
            if (candidate.isClickable && candidate.isEnabled) {
                assertTrue(
                    "Expected UI action rejected",
                    candidate.performAction(AccessibilityNodeInfo.ACTION_CLICK),
                )
                return
            }
            current = candidate.parent
        }
        error("No clickable expected control")
    }

    private fun nodes(packages: Set<String>): List<AccessibilityNodeInfo> {
        automation.clearCache()
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
        val found = mutableListOf<AccessibilityNodeInfo>()
        fun walk(node: AccessibilityNodeInfo, depth: Int) {
            if (depth > 30 || node.packageName?.toString() !in packages) return
            if (node.isVisibleToUser) found += node
            for (index in 0 until node.childCount) node.getChild(index)?.let { walk(it, depth + 1) }
        }
        roots.forEach { walk(it, 0) }
        return found
    }

    private fun await(stage: String, timeout: Long = 15_000, predicate: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + timeout
        while (SystemClock.elapsedRealtime() < deadline) {
            if (predicate()) return
            Thread.sleep(100)
        }
        trace("timeout: $stage")
        error("Timed out at $stage; see only safe event receipts")
    }

    private fun trace(stage: String) {
        val state = runtime.store.snapshot()
        println(
            "push-probe-test: $stage; healthy=${runtime.store.healthy}; consent=${state.optedIn}; pending=${state.registering}; cleanup=${state.cleanupPending}; events=${state.receipts.map { it.event.name }}"
        )
    }
}
