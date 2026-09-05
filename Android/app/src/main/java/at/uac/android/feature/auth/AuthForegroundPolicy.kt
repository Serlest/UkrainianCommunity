package at.uac.android.feature.auth

/** Opaque, memory-only permission to preserve one known picker round trip. */
class AuthExternalPickerToken
internal constructor(internal val uid: String, internal val revision: Long) {
    override fun toString() = "AuthExternalPickerToken([redacted])"
}

/**
 * A picker result can arrive before or after Activity.onResume. Never release the exemption early
 * from a result callback, and never exempt an unrelated resume. Main-thread only, owned by the same
 * application-scoped AuthStore as the session.
 */
internal class AuthForegroundPolicy {
    private class Pending(val token: AuthExternalPickerToken, var paused: Boolean = false)

    private var pending: Pending? = null

    fun begin(uid: String, revision: Long): AuthExternalPickerToken? {
        if (pending != null) return null
        return AuthExternalPickerToken(uid, revision).also { pending = Pending(it) }
    }

    fun onHostPause() {
        pending?.paused = true
    }

    fun finish(token: AuthExternalPickerToken) {
        val current = pending ?: return
        if (current.token !== token) return
        // Synchronous/cancelled contracts that never paused the host need no
        // exemption. A normal result-before-resume retains its single use.
        if (!current.paused) pending = null
    }

    fun cancel(token: AuthExternalPickerToken) {
        if (pending?.token === token) pending = null
    }

    fun invalidate() {
        pending = null
    }

    fun consumeResume(uid: String?, revision: Long, ready: Boolean): Boolean {
        val current = pending ?: return false
        pending = null
        return current.paused &&
            ready &&
            current.token.uid == uid &&
            current.token.revision == revision
    }
}
