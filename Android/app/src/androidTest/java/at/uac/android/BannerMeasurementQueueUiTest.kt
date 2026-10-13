package at.uac.android

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.bannermeasurement.BannerMeasurement
import at.uac.android.feature.bannermeasurement.BannerMeasurementQueue
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BannerMeasurementQueueUiTest {
    @Test fun queuedReceiptSurvivesRestartButNeverCrossesAccountOrWithdrawal() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("banner-measurement-v1", Context.MODE_PRIVATE)
        prefs.edit().clear().commit()
        try {
            var now = 100_000L
            val event = BannerMeasurement("event-1", "banner-1", "home", "impression", now, "consent-1")
            val first = BannerMeasurementQueue(context) { now }
            first.switchPrincipal("alice")
            first.append(event)
            first.setPendingWithdrawal("alice", "consent-1")
            val restarted = BannerMeasurementQueue(context) { now }
            restarted.switchPrincipal("alice")
            assertEquals(event, restarted.first())
            assertEquals("consent-1", restarted.pendingWithdrawal("alice"))
            restarted.switchPrincipal("bob")
            assertNull(restarted.first())
            restarted.switchPrincipal("alice")
            assertNull(restarted.first())
            assertEquals("consent-1", restarted.pendingWithdrawal("alice"))
            restarted.setPendingWithdrawal("alice", null)
            assertNull(restarted.pendingWithdrawal("alice"))
            restarted.append(event)
            now += 49 * 60 * 60 * 1_000L
            restarted.prune()
            assertNull(restarted.first())
        } finally {
            prefs.edit().clear().commit()
        }
    }
}
