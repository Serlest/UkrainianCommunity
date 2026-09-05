package at.uac.android.feature.auth

/** One-use, memory-only proof issued after the actual password sign-in flow completes. */
class AuthPasswordProof internal constructor(private val uid: String, private val revision: Long) {
    private var consumed = false

    internal fun consume(expectedUid: String, expectedRevision: Long): Boolean {
        if (consumed || uid != expectedUid || revision != expectedRevision) return false
        consumed = true
        return true
    }

    override fun toString(): String = "AuthPasswordProof([redacted])"
}
