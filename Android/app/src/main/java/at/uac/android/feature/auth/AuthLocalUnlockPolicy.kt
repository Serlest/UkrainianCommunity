package at.uac.android.feature.auth

/** Memory-only lifecycle lease, never a password/MFA/local-unlock proof. */
class AuthLocalUnlockToken
internal constructor(internal val uid: String, internal val revision: Long) {
    override fun toString() = "AuthLocalUnlockToken([redacted])"
}

internal class AuthLocalUnlockPolicy {
    private class Pending(val token: AuthLocalUnlockToken, var paused: Boolean = false)

    private var pending: Pending? = null

    fun begin(uid: String, revision: Long): AuthLocalUnlockToken? {
        if (pending != null) return null
        return AuthLocalUnlockToken(uid, revision).also { pending = Pending(it) }
    }

    fun onHostPause() {
        val current = pending ?: return
        // A second background is not part of the original one-shot round trip.
        if (current.paused) pending = null else current.paused = true
    }

    fun finish(token: AuthLocalUnlockToken) {
        val current = pending ?: return
        if (current.token === token && !current.paused) pending = null
    }

    fun cancel(token: AuthLocalUnlockToken) {
        if (pending?.token === token) pending = null
    }

    fun invalidate() {
        pending = null
    }

    fun consumeResume(uid: String?, revision: Long, identityCurrent: Boolean): Boolean {
        val current = pending ?: return false
        pending = null
        return current.paused &&
            identityCurrent &&
            current.token.uid == uid &&
            current.token.revision == revision
    }
}
