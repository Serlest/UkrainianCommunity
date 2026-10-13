package at.uac.android.feature.startup

import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage

/** The public app shell is available only after the account and legal checks finish. */
internal enum class StartupAccess { LOADING, ACCOUNT, APP }

internal fun startupAccess(session: AuthSession): StartupAccess =
    when {
        session.stage == AuthStage.RESTORING -> StartupAccess.LOADING
        session.readyForActions -> StartupAccess.APP
        else -> StartupAccess.ACCOUNT
    }
