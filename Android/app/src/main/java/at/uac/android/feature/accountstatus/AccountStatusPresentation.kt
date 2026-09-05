package at.uac.android.feature.accountstatus

/** Close the content gate before the asynchronously observed Auth version reaches this model. */
internal fun AccountStatusState.coversContent(current: AccountStatusSession?): Boolean {
    if (current == null) return false
    return if (session == current) notice != null else current.observation.notice != null
}
