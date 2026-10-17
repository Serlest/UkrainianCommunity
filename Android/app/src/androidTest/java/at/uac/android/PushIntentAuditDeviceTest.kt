package at.uac.android

import android.content.Intent
import androidx.lifecycle.SavedStateHandle
import at.uac.android.feature.push.PushNavigationViewModel
import org.junit.Assert.*
import org.junit.Test

class PushIntentAuditDeviceTest {
    private fun legacy() = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        .putExtra("google.message_id", "legacy-fcm-message")
        .putExtra("notificationId", "notice-audit")
        .putExtra("type", "organizationNewsPublished")
        .putExtra("actionType", "openNews")
        .putExtra("targetId", "news-audit")

    @Test fun deployedDefaultLauncherEnvelopeQueuesOnlyTheValidatedCurrentAccountRoute() {
        val vm = PushNavigationViewModel(SavedStateHandle())
        assertTrue(vm.offer(legacy(), "account-a"))
        assertEquals("account-a", vm.pending.value?.ownerUid)
        assertEquals("news/news-audit", vm.pending.value?.decision?.route)
        val revision = vm.pending.value!!.revision
        vm.consume(revision)
        assertTrue(vm.offer(legacy(), "account-a"))
        assertNull(vm.pending.value)
    }

    @Test fun ordinaryLaunchMalformedDataAndExternalUrisCannotBecomePushRoutes() {
        val invalid = listOf(
            legacy().removeCategoryAndReturn(),
            legacy().apply { removeExtra("google.message_id") },
            legacy().apply { removeExtra("notificationId") },
            legacy().putExtra("targetId", "../private"),
            legacy().putExtra("targetId", 5),
            legacy().setAction(Intent.ACTION_VIEW),
            legacy().setData(android.net.Uri.parse("https://example.org")),
            legacy().putExtra("type", "externalURL").putExtra("targetId", "https://example.org"),
        )
        invalid.forEach { intent -> assertFalse(PushNavigationViewModel(SavedStateHandle()).offer(intent, "account-a")) }
        assertFalse(PushNavigationViewModel(SavedStateHandle()).offer(legacy(), null))
    }

    private fun Intent.removeCategoryAndReturn(): Intent = apply { removeCategory(Intent.CATEGORY_LAUNCHER) }
}
