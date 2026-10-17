package at.uac.android

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.backend.AppBackend
import at.uac.android.design.UacTheme
import at.uac.android.feature.directory.*
import java.io.File
import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Rule
import org.junit.Test

/** Explicitly invoked only on productionDebug, never a runtime backend selector or a production write. */
class DirectoryCloudSdkReadTest {
    @get:Rule val compose = createComposeRule()
    @Test fun publicCloudSdkCatalogAndColdOfflineCacheRemainAuthoritative() = runBlocking {
        assumeFalse(BuildConfig.USE_LOCAL_BACKEND)
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as Application
        val source = FirebaseDirectoryCatalogSource(app)
        val first = withTimeout(45_000) { source.confirmedCatalog() }
        assertFalse(first.fromCache)
        assertEquals(0, first.snapshot.invalid)
        assertEquals(25, first.snapshot.published.size)
        assertEquals(145, first.snapshot.published.values.sumOf { it.topics.size })
        val regional = first.snapshot.published.values.sumOf { c -> c.topics.sumOf { t -> t.regionalSections.values.sumOf { it.size } } }
        assertEquals(288, regional)
        val folder = File(app.cacheDir, "directory-sdk-smoke").apply { mkdirs() }
        val cache = DiskDirectoryCatalogCache(app, "ukrainiancommunity-dbd5f", folder, "production-sdk-smoke")
        cache.write(first.snapshot.copy(authoritative = true, complete = true))
        var store = ViewModelStore()
        fun create(): DirectoryViewModel = ViewModelProvider(store, object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T = DirectoryViewModel(app, source,
                DiskDirectoryCatalogCache(app, "ukrainiancommunity-dbd5f", folder, "production-sdk-smoke")) as T
        })[DirectoryViewModel::class.java]
        val shown = mutableStateOf(compose.runOnIdle { create() })
        val recent = DirectoryRecentViewModel { DirectoryRecentPage(emptyList(), null, false) }
        try {
            compose.setContent { UacTheme("light") {
                DirectoryDestination("directory", "uk", "", {}, {}, { _, _, _ -> }, contentModel = shown.value, recentModel = recent)
            } }
            compose.waitUntil(20_000) { shown.value.snapshot.value.authoritative && shown.value.snapshot.value.complete }
            compose.onNodeWithTag("directory-list").performScrollToNode(hasTestTag("directory-category-health"))
            compose.onNodeWithTag("directory-category-health").assertIsDisplayed()
            File(app.cacheDir, "directory-cloud-sdk-live.png").outputStream().use {
                compose.onRoot().captureToImage().asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
            }
            withTimeout(10_000) { AppBackend.firestore(app).disableNetwork().await() }
            compose.runOnIdle { store.clear(); store = ViewModelStore(); shown.value = create() }
            compose.waitUntil(15_000) { shown.value.snapshot.value.complete }
            compose.runOnIdle { shown.value.retry() }
            compose.waitUntil(10_000) { shown.value.snapshot.value.status in setOf("cached", "failed") }
            assertEquals(25, shown.value.snapshot.value.published.size)
            assertEquals(145, shown.value.snapshot.value.published.values.sumOf { it.topics.size })
            assertTrue(shown.value.snapshot.value.authoritative)
            compose.onNodeWithTag("directory-list").performScrollToNode(hasTestTag("directory-category-health"))
            compose.onNodeWithTag("directory-category-health").assertIsDisplayed()
            File(app.cacheDir, "directory-cloud-sdk-live.json").writeText(JSONObject()
                .put("checkedAt", Instant.now().toString()).put("firebaseSDKVerified", true)
                .put("source", "FirebaseDirectoryCatalogSource.confirmedCatalog; Source.SERVER")
                .put("categoryCount", 25).put("topicCount", 145).put("regionalSectionCount", regional)
                .put("guestAuth", AppBackend.auth(app).currentUser == null)
                .put("coldViewModelAndDiskCacheRead", true).put("sdkNetworkDisabledRetryKeptCatalog", true)
                .put("productionWrites", 0).toString(2))
        } finally {
            compose.runOnIdle { store.clear() }
            withTimeout(10_000) { AppBackend.firestore(app).enableNetwork().await() }
        }
    }
}
