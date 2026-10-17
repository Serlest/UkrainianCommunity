package at.uac.android

import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.browse.*
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class ContentCacheAuditDeviceTest {
    @Test fun eventQueryCutoffSurvivesDiskCacheRecreation() = runBlocking {
        check(BuildConfig.USE_LOCAL_BACKEND)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val cutoff = Instant.parse("2026-10-17T12:00:00Z")
        val cache = DiskContentCache(context)
        val key = "audit-cutoff-roundtrip"
        cache.put(key, CachedRows(listOf(RawDocument("event", mapOf("title" to "Local test"))), cutoff, cutoff))
        val reread = DiskContentCache(context).get(key)!!
        assertEquals(cutoff, reread.sourceStartInclusive)
        assertEquals(cutoff, reread.at)
        assertEquals("event", reread.rows.single().id)
        cache.clear()
        assertNull(DiskContentCache(context).get(key))
    }
}
