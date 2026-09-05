package at.uac.android.core

import android.content.Context
import android.view.View
import android.view.Window
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import androidx.compose.ui.window.SecureFlagPolicy
import java.util.IdentityHashMap

/** Activity-owned registry: every app dialog participates without destroying its composition. */
class WindowPrivacy : AutoCloseable {
    private class Entry(val window: Window) {
        var references = 0
        var secure: AutoCloseable? = null
        var previousAccessibility: Int? = null
        var previousInputFlags: Int? = null
    }

    private val windows = IdentityHashMap<Window, Entry>()
    private var secure = false
    private var blocked = false
    private val observableBlocked = mutableStateOf(false)
    private val observableSecure = mutableStateOf(false)
    val interactionBlocked: Boolean
        get() = observableBlocked.value

    val requiresSecureWindow: Boolean
        get() = observableSecure.value

    private var closed = false

    fun register(window: Window): AutoCloseable {
        check(!closed)
        val entry = windows.getOrPut(window) { Entry(window) }
        entry.references++
        apply(entry)
        var released = false
        return AutoCloseable {
            if (!released) {
                released = true
                if (!closed && --entry.references == 0) {
                    restore(entry)
                    windows.remove(window)
                }
            }
        }
    }

    /** Called synchronously from lifecycle/auth protection changes, before a frame is drawn. */
    fun update(secure: Boolean, blocked: Boolean) {
        if (closed) return
        this.secure = secure
        this.blocked = blocked
        windows.values.forEach(::apply)
        observableBlocked.value = blocked
        observableSecure.value = secure
    }

    private fun apply(entry: Entry) {
        if (secure && entry.secure == null) entry.secure = WindowSecurity.acquire(entry.window)
        if (!secure) {
            entry.secure?.close()
            entry.secure = null
        }
        val root = entry.window.decorView
        if (blocked) {
            if (entry.previousAccessibility == null) {
                entry.previousAccessibility = root.importantForAccessibility
                entry.previousInputFlags = entry.window.attributes.flags and INPUT_FLAGS
                root.importantForAccessibility =
                    View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
                (root.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                    ?.hideSoftInputFromWindow(root.windowToken, 0)
            }
            entry.window.addFlags(INPUT_FLAGS)
        } else restoreInput(entry)
    }

    private fun restoreInput(entry: Entry) {
        entry.previousAccessibility?.let { entry.window.decorView.importantForAccessibility = it }
        entry.previousAccessibility = null
        entry.previousInputFlags?.let { original -> entry.window.setFlags(original, INPUT_FLAGS) }
        entry.previousInputFlags = null
    }

    private fun restore(entry: Entry) {
        restoreInput(entry)
        entry.secure?.close()
        entry.secure = null
    }

    override fun close() {
        if (closed) return
        windows.values.forEach(::restore)
        windows.clear()
        closed = true
    }

    private companion object {
        const val INPUT_FLAGS =
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
    }
}

val LocalWindowPrivacy = staticCompositionLocalOf<WindowPrivacy?> { null }

@Composable
private fun RegisterDialogWindow() {
    val registry = LocalWindowPrivacy.current
    val view = LocalView.current
    DisposableEffect(registry, view) {
        var ancestor = view.parent
        var window: Window? = null
        while (ancestor != null && window == null) {
            window = (ancestor as? DialogWindowProvider)?.window
            ancestor = ancestor.parent
        }
        check(registry == null || window != null) { "A protected dialog must expose its window" }
        val registration = window?.let { registry?.register(it) }
        onDispose { registration?.close() }
    }
}

@Composable
fun ProtectedDialog(
    onDismissRequest: () -> Unit,
    properties: DialogProperties = DialogProperties(),
    content: @Composable () -> Unit,
) {
    Dialog(onDismissRequest, protectedProperties(properties)) {
        RegisterDialogWindow()
        content()
    }
}

/**
 * Compose reapplies its own Window flags after creation/recomposition; it must share the policy.
 */
@Composable
private fun protectedProperties(properties: DialogProperties): DialogProperties =
    if (LocalWindowPrivacy.current?.requiresSecureWindow != true) properties
    else
        DialogProperties(
            dismissOnBackPress = properties.dismissOnBackPress,
            dismissOnClickOutside = properties.dismissOnClickOutside,
            securePolicy = SecureFlagPolicy.SecureOn,
            usePlatformDefaultWidth = properties.usePlatformDefaultWidth,
            decorFitsSystemWindows = properties.decorFitsSystemWindows,
            windowTitle = properties.windowTitle,
        )

@Composable
fun ProtectedAlertDialog(
    onDismissRequest: () -> Unit,
    confirmButton: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    dismissButton: (@Composable () -> Unit)? = null,
    icon: (@Composable () -> Unit)? = null,
    title: (@Composable () -> Unit)? = null,
    text: (@Composable () -> Unit)? = null,
    properties: DialogProperties = DialogProperties(),
) {
    AlertDialog(
        onDismissRequest = onDismissRequest,
        confirmButton = confirmButton,
        modifier = modifier,
        dismissButton = dismissButton,
        icon = icon,
        title = title,
        text = {
            RegisterDialogWindow()
            text?.invoke()
        },
        properties = protectedProperties(properties),
    )
}

/**
 * A modal selection list has a public Window, unlike Compose's native Popup on API 26+. It can
 * therefore be protected synchronously, including accessibility, before dismissal. The parent keeps
 * its selection/editor state when the temporary list is covered.
 */
@Composable
fun ProtectedDropdownMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val blocked = LocalWindowPrivacy.current?.interactionBlocked == true
    val maxHeight = (LocalConfiguration.current.screenHeightDp * 0.8f).dp
    if (expanded && !blocked)
        ProtectedDialog(
            onDismissRequest,
            properties = DialogProperties(securePolicy = SecureFlagPolicy.SecureOn),
        ) {
            Surface(shape = MaterialTheme.shapes.large, tonalElevation = 6.dp) {
                Column(
                    modifier
                        .widthIn(min = 240.dp, max = 360.dp)
                        .heightIn(max = maxHeight)
                        .verticalScroll(rememberScrollState()),
                    content = content,
                )
            }
        }
}
