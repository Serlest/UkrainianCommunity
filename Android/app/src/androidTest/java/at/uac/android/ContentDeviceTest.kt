package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.browse.*
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ContentDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun sharedFixtureCodecAndDiskCacheKeepTimestampPrecision() = runBlocking {
        val fixtures = ContentJson.fixtures(context)
        assertEquals(84, fixtures.size)
        val row = fixtures.getValue("news/synthetic-news-01")
        assertEquals(123456000, row.fields.time("publishedAt")!!.nano)
        val cache = DiskContentCache(context)
        val stamp = Instant.parse("2026-09-02T10:00:00.123456789Z")
        cache.put("instrumented-codec-only", CachedRows(listOf(row), stamp))
        val freshCacheInstance = DiskContentCache(context)
        val saved = freshCacheInstance.get("instrumented-codec-only")!!
        assertEquals(stamp, saved.at)
        assertEquals(row.fields, saved.rows.single().fields)
        val source = SyntheticContentSource(fixtures)
        val repo = ContentRepository(source, MemoryContentCache())
        for (kind in ContentKind.entries) {
            assertFalse(repo.page(ContentQuery(kind)).value.items.isEmpty())
        }
    }

    @Test
    fun realSdkContractOrUnreachableEmulator() = runBlocking {
        val source = FirestoreContentSource(LocalFirebase.firestore(context))
        val repository = ContentRepository(source, MemoryContentCache())
        if (InstrumentationRegistry.getArguments().getString("expectEmulator") != "true") {
            try {
                repository.detail(ContentKind.NEWS, "synthetic-news-01")
                fail("Emulator should be stopped")
            } catch (e: ReadException) {
                assertEquals(ReadFailure.OFFLINE, e.reason)
            }
            return@runBlocking
        }
        for (kind in ContentKind.entries) {
            val first =
                repository.page(ContentQuery(kind, now = Instant.parse("2026-09-02T00:00:00Z")))
            assertEquals(6, first.value.items.size)
            assertTrue(first.value.hasMore)
            val second =
                repository.page(
                    ContentQuery(kind, now = Instant.parse("2026-09-02T00:00:00Z")),
                    first.value.next,
                )
            assertTrue(first.value.items.none { a -> second.value.items.any { it.id == a.id } })
        }
        for ((id, failure) in
            listOf(
                "synthetic-news-private" to ReadFailure.DENIED,
                "synthetic-news-malformed" to ReadFailure.INVALID,
            )) {
            try {
                repository.detail(ContentKind.NEWS, id)
                fail("Expected $failure")
            } catch (e: ReadException) {
                assertEquals(failure, e.reason)
            }
        }
        assertEquals(4, repository.banners("home", "").value.size)
        assertEquals(3, repository.banners("home", "wien").value.size)
        assertEquals(1, repository.photos("synthetic-org-01").value.size)
        assertEquals(
            "Demo · Олена",
            repository
                .profile("synthetic-public-owner")
                .value
                .single()
                .fields
                .string("displayName"),
        )
        assertNotNull(repository.donation().value.url)
    }
}
