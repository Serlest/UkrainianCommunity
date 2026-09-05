package at.uac.android

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.view.InputDevice
import android.view.KeyCharacterMap
import android.view.KeyEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import org.junit.Assert.*

/** AVD-only synthetic gallery fixture. Never chooses the first photo from the general library. */
internal object PhotoPickerFixtures {
    data class Fixture(
        val uri: Uri,
        val album: String,
        val png: ByteArray,
        val documentToken: String? = null,
    )

    private const val PICKER_PACKAGE = "com.google.android.photopicker"
    private const val DOCUMENTS_AUTHORITY = "at.uac.android.local.test.photo_documents"
    private val SEED_URI = Uri.parse("content://at.uac.android.local.test.photo_fixture_seed")
    private val DOCUMENTS_PACKAGES =
        setOf("com.android.documentsui", "com.google.android.documentsui")
    private val created = mutableMapOf<String, String>()
    @Volatile private var compatibilityFixtureEnabled = false

    private fun requireLocalAvd(context: Context) {
        LocalEnvironment.requireSafe()
        check(context.applicationContext.packageName == "at.uac.android.local")
        check(
            (Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone")) || isExplicitApi26CompatibilityAvd()
        ) {
            "Synthetic gallery mutations are allowed only on the named local SDK-phone emulator family, never physical devices."
        }
    }

    fun create(context: Context, prefix: String): Fixture {
        requireLocalAvd(context)
        val compatibility = isExplicitApi26CompatibilityAvd()
        check(Build.VERSION.SDK_INT >= 29 || compatibility) {
            "Only scoped-storage SDK AVDs or the explicit API26 compatibility AVD are supported."
        }
        require(prefix.matches(Regex("[a-zA-Z0-9-]{1,24}")))
        val album = "$prefix-${UUID.randomUUID().toString().take(8)}"
        val bitmap = Bitmap.createBitmap(240, 160, Bitmap.Config.ARGB_8888)
        val png =
            try {
                Canvas(bitmap).apply {
                    drawColor(Color.rgb(18, 62, 126))
                    drawRect(
                        40f,
                        20f,
                        200f,
                        140f,
                        Paint().apply { color = Color.rgb(255, 213, 46) },
                    )
                    drawCircle(120f, 80f, 32f, Paint().apply { color = Color.rgb(43, 125, 72) })
                }
                ByteArrayOutputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                    it.toByteArray()
                }
            } finally {
                bitmap.recycle()
            }
        if (compatibility) return createCompatibility(context, album, png)
        val values =
            ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, "$album.png")
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/$album")
                put(MediaStore.Images.Media.DATE_TAKEN, System.currentTimeMillis())
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        val uri =
            context.contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: error("Could not create the scoped synthetic gallery image")
        try {
            context.contentResolver.openOutputStream(uri)!!.use { it.write(png) }
            assertEquals(
                "Exactly our gallery row must be published before opening the picker",
                1,
                context.contentResolver.update(
                    uri,
                    ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) },
                    null,
                    null,
                ),
            )
            synchronized(created) { created[uri.toString()] = album }
            return Fixture(uri, album, png)
        } catch (error: Exception) {
            context.contentResolver.delete(uri, null, null)
            throw error
        }
    }

    fun delete(context: Context, fixture: Fixture) {
        requireLocalAvd(context)
        check(synchronized(created) { created[fixture.uri.toString()] == fixture.album }) {
            "Only this process's own synthetic gallery fixture can be removed"
        }
        if (fixture.documentToken != null) {
            val result = fixtureCall(context, "clear", fixture)
            assertTrue("Exactly our registered document was removed", result.getBoolean("removed"))
            assertFalse("The test document is absent after cleanup", result.getBoolean("present"))
            assertFalse(
                "Independent read-back confirms deletion",
                fixtureCall(context, "inspect", fixture).getBoolean("present"),
            )
            synchronized(created) { created.remove(fixture.uri.toString()) }
            compatibilityFixtureEnabled = false
            return
        }
        assertEquals(
            "Only our inserted gallery row is deleted",
            1,
            context.contentResolver.delete(fixture.uri, null, null),
        )
        synchronized(created) { created.remove(fixture.uri.toString()) }
    }

    fun selectOnlyPhoto(fixture: Fixture) {
        check(synchronized(created) { created[fixture.uri.toString()] == fixture.album }) {
            "Only this process's registered synthetic photo may be selected"
        }
        if (fixture.documentToken != null) {
            check(isExplicitApi26CompatibilityAvd() && compatibilityFixtureEnabled)
            // API26 uses the actual ACTION_OPEN_DOCUMENT fallback, not a direct test URI callback.
            // AOSP android-8.0.0_r1 DocumentsUI exposes this toolbar accessibility label.
            val initial = awaitNodes {
                it.text?.toString() == "${fixture.album}.png" ||
                    (it.text?.toString() == "UAC synthetic" && clickableAncestor(it) != null) ||
                    it.contentDescription?.toString() == "Show roots"
            }
            if (initial.none { it.text?.toString() == "${fixture.album}.png" }) {
                if (
                    initial.none {
                        it.text?.toString() == "UAC synthetic" && clickableAncestor(it) != null
                    }
                ) {
                    tapLabel("Show roots")
                }
                val root = awaitNodes {
                    it.text?.toString() == "UAC synthetic" && clickableAncestor(it) != null
                }
                assertEquals("Exactly the test-only synthetic root is selected", 1, root.size)
                clickDocumentNode(root.single(), "synthetic-root", fixture)
            }
            val exact = awaitNodes { it.text?.toString() == "${fixture.album}.png" }
            assertEquals(
                "The own synthetic root contains exactly the selected fixture name",
                1,
                exact.size,
            )
            clickDocumentNode(exact.single(), "exact-fixture-file", fixture)
            return
        }
        tapLabel("Collections")
        tapLabel("From this device")
        tapLabel(fixture.album)
        val photos = awaitNodes {
            it.contentDescription?.toString()?.startsWith("Photo taken on ") == true
        }
        assertEquals(
            "The explicitly selected synthetic album must contain exactly one photo",
            1,
            photos.size,
        )
        clickAncestor(photos.single())
        // API 37 keeps the single selection in a separate floating window until Done is confirmed.
        // This exact control was verified on the AVD; selecting the thumbnail is not an Activity
        // result.
        tapLabel("Done")
    }

    /** Read-only diagnostics for the exact process-owned fixture, never the general gallery. */
    fun publishedState(context: Context, fixture: Fixture): String {
        requireLocalAvd(context)
        check(synchronized(created) { created[fixture.uri.toString()] == fixture.album })
        if (fixture.documentToken != null) {
            val result = fixtureCall(context, "inspect", fixture)
            return "compatibility=true,present=${result.getBoolean("present")}"
        }
        check(Build.VERSION.SDK_INT >= 29)
        val columns =
            arrayOf(
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.MIME_TYPE,
                MediaStore.Images.Media.IS_PENDING,
                MediaStore.Images.Media.SIZE,
                MediaStore.Images.Media.WIDTH,
                MediaStore.Images.Media.HEIGHT,
                MediaStore.Images.Media.RELATIVE_PATH,
            )
        return context.contentResolver.query(fixture.uri, columns, null, null, null)?.use { row ->
            if (!row.moveToFirst()) "present=false"
            else
                "present=true,nameMatches=${row.getString(0) == "${fixture.album}.png"}," +
                    "png=${row.getString(1) == "image/png"},pending=${row.getInt(2)}," +
                    "bytes=${row.getLong(3)},width=${row.getInt(4)},height=${row.getInt(5)}," +
                    "albumMatches=${row.getString(6).orEmpty().trimEnd('/') == "Pictures/${fixture.album}"}"
        } ?: "query-unavailable"
    }

    fun pickerVisible(): Boolean =
        InstrumentationRegistry.getInstrumentation()
            .uiAutomation
            .rootInActiveWindow
            ?.packageName
            ?.toString() in pickerPackages()

    /** A cached active-root package alone can precede the picker's actual focused window. */
    fun focusedPickerWindow(): Boolean {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        requireLocalAvd(instrumentation.targetContext)
        pickerRoots() // Existing public cache refresh / interactive-window retrieval policy.
        return instrumentation.uiAutomation.windows.any { window ->
            window.type == AccessibilityWindowInfo.TYPE_APPLICATION &&
                window.isActive &&
                window.isFocused &&
                window.root?.let {
                    it.packageName?.toString() in pickerPackages() && it.isVisibleToUser
                } == true
        }
    }

    /** One native Back press, no retry or result injection; also waits for window animations. */
    fun cancelFocusedPickerOnce() {
        check(focusedPickerWindow()) {
            "Only the focused, allowlisted native picker can receive Back"
        }
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val downTime = SystemClock.uptimeMillis()
        for (action in listOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            val event =
                KeyEvent(
                    downTime,
                    SystemClock.uptimeMillis(),
                    action,
                    KeyEvent.KEYCODE_BACK,
                    0,
                    0,
                    KeyCharacterMap.VIRTUAL_KEYBOARD,
                    0,
                    0,
                    InputDevice.SOURCE_KEYBOARD,
                )
            // Public UiAutomation contract synchronizes window-container animations/surfaces.
            // https://developer.android.com/reference/android/app/UiAutomation#injectInputEvent(android.view.InputEvent,%20boolean)
            check(automation.injectInputEvent(event, true)) {
                "Native Back event was not accepted"
            }
        }
    }

    private fun createCompatibility(context: Context, album: String, png: ByteArray): Fixture {
        check(isExplicitApi26CompatibilityAvd())
        val token = UUID.randomUUID().toString()
        val uri = DocumentsContract.buildDocumentUri(DOCUMENTS_AUTHORITY, "${token}_$album")
        val fixture = Fixture(uri, album, png, token)
        synchronized(created) { created[uri.toString()] = album }
        try {
            val result = fixtureCall(context, "seed", fixture)
            assertTrue("The test-only document was seeded", result.getBoolean("present"))
            assertArrayEquals(
                "Provider's bounded cache read-back matches the exact PNG",
                png,
                result.getByteArray("png"),
            )
            val readBack = fixtureCall(context, "inspect", fixture)
            assertTrue(readBack.getBoolean("present"))
            assertArrayEquals(png, readBack.getByteArray("png"))
            compatibilityFixtureEnabled = true
            return fixture
        } catch (failure: Throwable) {
            try {
                val cleared = fixtureCall(context, "clear", fixture)
                check(!cleared.getBoolean("present"))
                synchronized(created) { created.remove(uri.toString()) }
            } catch (cleanup: Throwable) {
                failure.addSuppressed(
                    IllegalStateException(
                        "Synthetic fixture cleanup pending: ${token}_$album.png",
                        cleanup,
                    )
                )
            }
            throw failure
        }
    }

    private fun fixtureCall(context: Context, method: String, fixture: Fixture): Bundle {
        requireLocalAvd(context)
        check(isExplicitApi26CompatibilityAvd())
        val provider = context.packageManager.resolveContentProvider(SEED_URI.authority!!, 0)
        check(provider?.packageName == "at.uac.android.local.test") {
            "Expected test-only seed provider is unavailable"
        }
        val extras =
            Bundle().apply {
                putString("token", checkNotNull(fixture.documentToken))
                putString("album", fixture.album)
                putBoolean("explicitApi26", true)
                if (method == "seed") putByteArray("png", fixture.png)
            }
        return checkNotNull(context.contentResolver.call(SEED_URI, method, null, extras))
    }

    internal fun pickerPackages(): Set<String> =
        // Visibility/cancellation is read-only and also needed before any fixture was seeded.
        // Selection and mutation retain their separate registered-fixture + active-lease gates.
        if (isExplicitApi26CompatibilityAvd()) DOCUMENTS_PACKAGES else setOf(PICKER_PACKAGE)

    /**
     * Test diagnostics only: never inspects app fields, account identifiers, or a different native
     * app.
     */
    fun diagnosticState(): String {
        val roots = pickerRoots()
        if (roots.isEmpty()) return "native-picker=false"
        val ownNames = synchronized(created) { created.values.map { "$it.png" }.toSet() }
        fun safeLabel(value: CharSequence?): String? {
            val text = value?.toString() ?: return null
            if (Build.VERSION.SDK_INT == 26) {
                return if (
                    text in ownNames ||
                        text in
                            setOf(
                                "UAC synthetic",
                                "Show roots",
                                "Hide roots",
                                "Open from",
                                "Select",
                            )
                )
                    text
                else "<system-label>"
            }
            return if (text.startsWith("Photo taken on ")) "<photo>" else text.take(100)
        }
        return buildString {
                fun walk(node: AccessibilityNodeInfo, depth: Int) {
                    run {
                        appendLine(
                            "${" ".repeat(depth)}${node.className} text=${safeLabel(node.text)} desc=${safeLabel(node.contentDescription)} visible=${node.isVisibleToUser} clickable=${node.isClickable} enabled=${node.isEnabled} selected=${node.isSelected}"
                        )
                    }
                    if (depth < 20)
                        for (index in 0 until node.childCount) node.getChild(index)?.let {
                            walk(it, depth + 1)
                        }
                }
                roots.forEach { walk(it, 0) }
            }
            .take(16_000)
    }

    private fun tapLabel(label: String) {
        val values = awaitNodes {
            it.text?.toString() == label || it.contentDescription?.toString() == label
        }
        if (values.any { it.isSelected }) return
        // A header can repeat the album name; prefer a clickable ancestor over a static title.
        val clickable =
            values.firstOrNull { clickableAncestor(it) != null }
                ?: error("No clickable picker item: $label")
        clickAncestor(clickable)
    }

    private fun awaitNodes(
        predicate: (AccessibilityNodeInfo) -> Boolean
    ): List<AccessibilityNodeInfo> {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        while (SystemClock.elapsedRealtime() < deadline) {
            val roots = pickerRoots()
            if (roots.isNotEmpty()) {
                val result = mutableListOf<AccessibilityNodeInfo>()
                fun walk(node: AccessibilityNodeInfo) {
                    if (Build.VERSION.SDK_INT < 34 && !node.refresh()) return
                    if (node.isVisibleToUser && predicate(node)) result += node
                    for (index in 0 until node.childCount) node.getChild(index)?.let(::walk)
                }
                roots.forEach(::walk)
                if (result.isNotEmpty()) return result
            }
            Thread.sleep(100)
        }
        error("Expected item not found in the verified system Photo Picker\n${diagnosticState()}")
    }

    private fun pickerRoots(): List<AccessibilityNodeInfo> {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        // clearCache is public only from API34; older public node.refresh() is used while walking.
        if (Build.VERSION.SDK_INT >= 34) automation.clearCache()
        val service = automation.serviceInfo
        val required =
            AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
        if (service.flags and required != required) {
            service.flags = service.flags or required
            automation.serviceInfo = service
        }
        return automation.windows
            .mapNotNull { it.root }
            .filter { it.packageName?.toString() in pickerPackages() }
            .ifEmpty {
                listOfNotNull(
                    automation.rootInActiveWindow?.takeIf {
                        it.packageName?.toString() in pickerPackages()
                    }
                )
            }
    }

    private fun clickableAncestor(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var current: AccessibilityNodeInfo? = node
        repeat(6) {
            if (current?.isClickable == true && current.isEnabled) return current
            current = current?.parent
        }
        return null
    }

    private fun clickAncestor(node: AccessibilityNodeInfo) {
        val target = clickableAncestor(node) ?: error("Picker item cannot be selected")
        assertTrue(
            "System picker accepted the explicit selection",
            target.performAction(AccessibilityNodeInfo.ACTION_CLICK),
        )
        Thread.sleep(200)
    }

    internal fun documentClickAllowed(
        packageName: String?,
        visible: Boolean,
        enabled: Boolean,
        actionIds: Collection<Int>,
    ): Boolean =
        packageName in DOCUMENTS_PACKAGES &&
            visible &&
            enabled &&
            AccessibilityNodeInfo.ACTION_CLICK in actionIds

    private fun documentClickAncestor(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var current: AccessibilityNodeInfo? = node
        repeat(6) {
            val item = current ?: return null
            if (item.packageName?.toString() !in DOCUMENTS_PACKAGES) return null
            if (
                documentClickAllowed(
                    item.packageName?.toString(),
                    item.isVisibleToUser,
                    item.isEnabled,
                    item.actionList.map { it.id },
                )
            )
                return item
            current = item.parent
        }
        return null
    }

    /** One advertised API26 native action; failure evidence is recorded before caller cleanup. */
    private fun clickDocumentNode(node: AccessibilityNodeInfo, stage: String, fixture: Fixture) {
        try {
            check(isExplicitApi26CompatibilityAvd() && compatibilityFixtureEnabled)
            check(synchronized(created) { created[fixture.uri.toString()] == fixture.album })
            // Actual32 proved DocumentsUI advertises ACTION_CLICK on the exact file row while its
            // isClickable flag is false. Do not invent a coordinate tap or inject a result URI.
            val target =
                documentClickAncestor(node)
                    ?: error("Exact DocumentsUI item has no enabled, visible advertised click")
            assertTrue(
                "DocumentsUI accepted the single advertised native click",
                target.performAction(AccessibilityNodeInfo.ACTION_CLICK),
            )
            Thread.sleep(200)
        } catch (failure: Throwable) {
            // This does not retry a click, refresh before a successful action, or choose an
            // ancestor
            // beyond the existing limit. It records the failing branch for the next diagnosis.
            val evidence = runCatching {
                check(isExplicitApi26CompatibilityAvd())
                fun ancestors(): String {
                    val rows = mutableListOf<String>()
                    var current: AccessibilityNodeInfo? = node
                    while (current != null && rows.size < 16) {
                        val item = current
                        if (item.packageName?.toString() !in DOCUMENTS_PACKAGES) {
                            rows += "outside-allowed-native-package"
                            break
                        }
                        val bounds = android.graphics.Rect()
                        item.getBoundsInScreen(bounds)
                        rows +=
                            "depth=${rows.size}, class=${item.className}, resource=${item.viewIdResourceName}, " +
                                "visible=${item.isVisibleToUser}, enabled=${item.isEnabled}, clickable=${item.isClickable}, " +
                                "focusable=${item.isFocusable}, focused=${item.isFocused}, selected=${item.isSelected}, " +
                                "bounds=$bounds, children=${item.childCount}, actions=${item.actionList.map { it.id }}"
                        current = item.parent
                    }
                    return rows.joinToString("\n") +
                        "\nancestorCap=${current != null && rows.size == 16}"
                }
                val before = ancestors()
                val refreshed = node.refresh()
                val after = ancestors()
                "stage=$stage; beforeRefresh:\n$before\nrefreshResult=$refreshed; afterRefresh:\n$after\n${diagnosticState()}"
            }
                .getOrElse { "diagnosticFailure=${it.javaClass.simpleName}" }
            val screenshot = runCatching {
                check(isExplicitApi26CompatibilityAvd())
                check(node.packageName?.toString() in DOCUMENTS_PACKAGES)
                val instrumentation = InstrumentationRegistry.getInstrumentation()
                check(
                    instrumentation.uiAutomation.rootInActiveWindow?.packageName?.toString() in
                        DOCUMENTS_PACKAGES
                )
                val bitmap =
                    instrumentation.uiAutomation.takeScreenshot()
                        ?: error("Native screenshot unavailable")
                try {
                    val cache = checkNotNull(instrumentation.targetContext.externalCacheDir)
                    File(cache, "photo-picker-api26-selection-failure.png").outputStream().use {
                        check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                    }
                } finally {
                    bitmap.recycle()
                }
                "captured"
            }
                .getOrElse { "failed:${it.javaClass.simpleName}" }
            throw IllegalStateException(
                "Exact DocumentsUI selection failed; screenshot=$screenshot\n$evidence",
                failure,
            )
        }
    }
}
