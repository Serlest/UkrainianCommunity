package at.uac.android.core

import android.os.Looper
import android.view.Window
import android.view.WindowManager
import androidx.annotation.MainThread
import java.io.Closeable
import java.util.IdentityHashMap

/**
 * Shared ownership of FLAG_SECURE. Every app feature that temporarily protects a window must use a
 * lease rather than snapshotting and clearing its own flag. A flag present before the first lease
 * belongs to another owner and is retained.
 */
object WindowSecurity {
    private val leases =
        SecureFlagLeasePool<Window>(
            isSecure = { (it.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE) != 0 },
            setSecure = { window, secure ->
                if (secure) window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                else window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
            },
        )

    @MainThread
    fun acquire(window: Window): Closeable {
        checkMainThread()
        val lease = leases.acquire(window)
        return Closeable {
            checkMainThread()
            lease.close()
        }
    }

    private fun checkMainThread() {
        check(Looper.myLooper() == Looper.getMainLooper()) {
            "Window security must be updated on the main thread"
        }
    }
}

/** Pure ownership policy; actual Window operations remain main-thread-only. */
internal class SecureFlagLeasePool<T : Any>(
    private val isSecure: (T) -> Boolean,
    private val setSecure: (T, Boolean) -> Unit,
) {
    private class Entry(val preexisting: Boolean, var count: Int = 1)

    private val entries = IdentityHashMap<T, Entry>()

    fun acquire(target: T): Closeable {
        val entry =
            entries[target]?.also { it.count++ }
                ?: Entry(isSecure(target)).also {
                    setSecure(target, true)
                    entries[target] = it
                }
        var closed = false
        return Closeable {
            if (!closed) {
                closed = true
                check(entries[target] === entry)
                entry.count--
                if (entry.count == 0) {
                    entries.remove(target)
                    if (!entry.preexisting) setSecure(target, false)
                }
            }
        }
    }
}
