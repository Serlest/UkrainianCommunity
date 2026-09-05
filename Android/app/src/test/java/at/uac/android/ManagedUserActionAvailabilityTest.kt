package at.uac.android

import at.uac.android.feature.platformrolemanagement.*
import at.uac.android.feature.usermanagement.*
import at.uac.android.feature.userstatusmanagement.*
import org.junit.Assert.*
import org.junit.Test

class ManagedUserActionAvailabilityTest {
    @Test
    fun absentOptionalModelsDoNotDisableExistingFeature() {
        assertTrue((null as PlatformRoleState?).allowsSiblingStatusAction())
        assertTrue((null as UserStatusState?).allowsSiblingRoleAction())
    }

    @Test
    fun idleModelsAllowSiblingWithoutGrantingOwnAuthority() {
        assertTrue(PlatformRoleState().allowsSiblingStatusAction())
        assertTrue(UserStatusState().allowsSiblingRoleAction())
        assertFalse(PlatformRoleState().canAct)
        assertFalse(UserStatusState().canAct)
    }

    @Test
    fun everyRoleConfirmationBlocksStatusEvenWithoutValidReason() {
        PlatformRoleAction.entries.forEach {
            assertFalse(PlatformRoleState(confirmation = it).allowsSiblingStatusAction())
        }
    }

    @Test
    fun everyStatusConfirmationBlocksRoleEvenWithoutValidReason() {
        UserStatusAction.entries.forEach {
            assertFalse(UserStatusState(confirmation = it).allowsSiblingRoleAction())
        }
    }

    @Test
    fun submittedBusyLatchesRemainBlockingWhenDraftHasBeenCleared() {
        assertFalse(PlatformRoleState(busy = true).allowsSiblingStatusAction())
        assertFalse(UserStatusState(busy = true).allowsSiblingRoleAction())
    }

    @Test
    fun readErrorsAndOldOutcomesDoNotPretendAnOperationIsStillRunning() {
        assertTrue(
            PlatformRoleState(error = PlatformRoleFailure.OFFLINE).allowsSiblingStatusAction()
        )
        assertTrue(UserStatusState(error = UserStatusFailure.JOURNAL).allowsSiblingRoleAction())
    }
}
