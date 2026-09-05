package at.uac.android.feature.usermanagement

import at.uac.android.feature.platformrolemanagement.PlatformRoleState
import at.uac.android.feature.userstatusmanagement.UserStatusState

/** UI coordination only. These latches neither grant authority nor replace repository guards. */
internal fun PlatformRoleState?.allowsSiblingStatusAction(): Boolean =
    this == null || (!busy && confirmation == null)

internal fun UserStatusState?.allowsSiblingRoleAction(): Boolean =
    this == null || (!busy && confirmation == null)
