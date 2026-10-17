package at.uac.android

import android.app.Application
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.lifecycle.viewModelScope
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.UacTheme
import at.uac.android.feature.directory.*
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.cancel
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class DirectoryCloudCatalogDeviceTest {
    @get:Rule val compose = createComposeRule()
    private val app get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as Application
    private fun snapshot(categories: List<DirectoryCategory>, deleted: Set<String> = emptySet()) = DirectorySnapshot(
        categories.associateBy { it.id }, (categories.map { it.id } + deleted).associateWith { 1 }, deleted,
        "current", authoritative = true, complete = true)
    private class MemoryCache(var value: DirectorySnapshot? = null, var sticky: Boolean = value != null) : DirectoryCatalogCache {
        override fun read() = value
        override fun activatedBefore() = sticky
        override fun write(snapshot: DirectorySnapshot) { value = snapshot; sticky = true }
    }
    private class TestSource(var batch: DirectoryBatch, private val markerValue: DirectoryCatalogMarker?,
        var offline: Boolean = false) : DirectoryCatalogSource {
        var receive: ((DirectoryBatch) -> Unit)? = null
        override fun categories(result: (DirectoryBatch) -> Unit, failure: () -> Unit): DirectoryCatalogSubscription {
            receive = result
            if (offline) failure() else result(batch)
            return DirectoryCatalogSubscription { receive = null }
        }
        override fun marker(result: (DirectoryCatalogMarker?, Boolean) -> Unit, failure: () -> Unit): DirectoryCatalogSubscription {
            if (offline) failure() else result(markerValue, false)
            return DirectoryCatalogSubscription { }
        }
        override suspend fun confirmedCatalog(): DirectoryBatch { check(!offline && markerValue != null); return batch }
        override suspend fun target(id: String): DirectoryTargetRecord {
            check(!offline)
            return DirectoryTargetRecord(batch.snapshot.published[id], batch.snapshot.revisions[id], id in batch.snapshot.deleted)
        }
    }
    private fun waitModel(model: DirectoryViewModel, condition: (DirectorySnapshot) -> Boolean) =
        compose.waitUntil(15_000) { condition(model.snapshot.value) }
    private fun screenshot(name: String) {
        compose.waitForIdle()
        File(app.cacheDir, name).outputStream().use {
            compose.onRoot().captureToImage().asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
    }
    @Test fun atomicDiskCacheSurvivesColdReadCorruptionAndProjectIsolationWithoutResurrection() {
        val folder = File(app.cacheDir, "catalog-test-${UUID.randomUUID()}").apply { mkdirs() }
        val namespace = "test-${UUID.randomUUID()}"
        val catalog = DirectoryCatalog.bundled(app)
        val cache = DiskDirectoryCatalogCache(app, "demo-cache-test", folder, namespace)
        val healthOnly = snapshot(listOf(catalog.first { it.id == "health" }), setOf("safety"))
        cache.write(healthOnly)
        val cold = DiskDirectoryCatalogCache(app, "demo-cache-test", folder, namespace)
        assertTrue(cold.activatedBefore())
        assertEquals(setOf("health"), cold.read()!!.published.keys)
        assertTrue("safety" in cold.read()!!.deleted)
        assertNull(DiskDirectoryCatalogCache(app, "another-project", folder, namespace).read())
        folder.listFiles()!!.filter { it.extension == "json" }.forEach { it.writeText("{broken") }
        assertNull(cold.read())
        assertTrue(cold.activatedBefore())
        val model = DirectoryViewModel(app, null, cold)
        try {
            assertTrue(model.snapshot.value.authoritative) // No bundle flash before asynchronous cache load.
            waitModel(model) { it.authoritative && !it.complete }
            assertTrue(model.snapshot.value.published.isEmpty())
            assertTrue(DirectoryCatalog.merge(catalog, model.snapshot.value.published, model.snapshot.value.deleted, true).isEmpty())
        } finally { model.viewModelScope.cancel(); folder.deleteRecursively() }
    }
    @Test fun offlineRetryKeepsLastGoodCatalogAndMissingLinkedTargetNeverFallsBackToBundle() {
        val health = DirectoryCatalog.bundled(app).first { it.id == "health" }
        val cache = MemoryCache(snapshot(listOf(health)))
        val source = TestSource(DirectoryBatch(cache.value!!, false), DirectoryCatalogMarker(setOf("safety", "health")), offline = true)
        val model = DirectoryViewModel(app, source, cache)
        val route = mutableStateOf("directory")
        val recent = DirectoryRecentViewModel { DirectoryRecentPage(emptyList(), null, false) }
        try {
            compose.setContent { UacTheme("light") {
                DirectoryDestination(route.value, "de", "tirol", {}, {}, { _, _, _ -> },
                    contentModel = model, recentModel = recent)
            } }
            waitModel(model) { it.complete }
            model.retry()
            waitModel(model) { it.status == "failed" }
            assertEquals(setOf("health"), model.snapshot.value.published.keys)
            assertTrue(model.snapshot.value.authoritative)
            compose.onNodeWithTag("directory-list").performScrollToNode(hasTestTag("directory-category-health"))
            source.offline = false
            compose.runOnIdle { route.value = "directory/safety/emergency?section=choose" }
            compose.waitUntil(10_000) { compose.onAllNodesWithTag("directory-target-missing").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("directory-section-choose").assertDoesNotExist()
            assertEquals(setOf("health"), model.snapshot.value.published.keys)
        } finally { model.viewModelScope.cancel(); recent.viewModelScope.cancel() }
    }
    @Test fun completeServerRemovalsAndHiddenChangesReachSearchAndEditorSourceWithoutBundleMixing() {
        val all = DirectoryCatalog.bundled(app)
        val state = snapshot(all)
        val source = TestSource(DirectoryBatch(state, false), DirectoryCatalogMarker(all.map { it.id }.toSet()))
        val model = DirectoryViewModel(app, source, MemoryCache())
        val recent = DirectoryRecentViewModel { DirectoryRecentPage(emptyList(), null, false) }
        try {
            compose.setContent { UacTheme("light") {
                DirectoryDestination("directory", "de", "wien", {}, {}, { _, _, _ -> },
                    contentModel = model, recentModel = recent, searchVisible = true)
            } }
            waitModel(model) { it.authoritative && it.published.size == 25 }
            val health = all.first { it.id == "health" }
            compose.runOnIdle { source.receive!!(DirectoryBatch(snapshot(listOf(health)), false)) }
            assertEquals(setOf("health"), model.snapshot.value.published.keys)
            compose.onNodeWithTag("directory-search").performTextInput("Sicherheit & Schutz")
            compose.onNodeWithText("Keine Treffer. Versuchen Sie einen anderen Begriff.").assertIsDisplayed()
            val hidden = health.copy(hidden = true)
            compose.runOnIdle { source.receive!!(DirectoryBatch(snapshot(listOf(hidden)), false)) }
            assertTrue(DirectoryCatalog.merge(all, model.snapshot.value.published, emptySet(), true).isEmpty())
            assertEquals(listOf("health"), DirectoryCatalog.allMerged(all, model.snapshot.value.published, emptySet(), true).map { it.id })
        } finally { model.viewModelScope.cancel(); recent.viewModelScope.cancel() }
    }
    private fun get(path: String): JSONObject {
        val connection = URL("https://firestore.googleapis.com/v1/projects/ukrainiancommunity-dbd5f/databases/(default)/documents/$path")
            .openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 15_000; connection.readTimeout = 15_000
            connection.requestMethod = "GET"
            assertEquals(200, connection.responseCode)
            return JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
        } finally { connection.disconnect() }
    }
    @Test fun livePublicProductionRestSnapshotPassesAndroidParserAndActualReaderRenderer() {
        // Read only, anonymous HTTPS. This verifies the public REST->parser->VM->UI path, not Firebase SDK/App Check.
        val marker = get("appConfig/directoryCatalog").getJSONObject("fields")
        assertTrue(marker.getJSONObject("migrationComplete").getBoolean("booleanValue"))
        val idsArray = marker.getJSONObject("baselineCategoryIDs").getJSONObject("arrayValue").getJSONArray("values")
        val baseline = (0 until idsArray.length()).map { idsArray.getJSONObject(it).getString("stringValue") }.toSet()
        val response = get("directoryCategories?pageSize=100")
        assertFalse(response.has("nextPageToken"))
        val docs = response.getJSONArray("documents")
        val categories = mutableMapOf<String, DirectoryCategory>()
        val revisions = mutableMapOf<String, Int>()
        val deleted = mutableSetOf<String>()
        for (index in 0 until docs.length()) {
            val doc = docs.getJSONObject(index)
            val id = doc.getString("name").substringAfterLast('/')
            val fields = doc.getJSONObject("fields")
            revisions[id] = fields.getJSONObject("revision").getString("integerValue").toInt()
            if (fields.optJSONObject("isDeleted")?.optBoolean("booleanValue") == true) deleted += id
            else {
                val parsed = DirectoryCatalog.parseCategory(JSONObject(fields.getJSONObject("payload").getString("stringValue")))
                assertEquals(id, parsed.id)
                categories[id] = parsed
            }
        }
        assertEquals(25, categories.size)
        assertEquals(145, categories.values.sumOf { it.topics.size })
        assertTrue((categories.keys + deleted).containsAll(baseline))
        val batch = DirectoryBatch(DirectorySnapshot(categories, revisions, deleted), false)
        val source = TestSource(batch, DirectoryCatalogMarker(baseline))
        val model = DirectoryViewModel(app, source, MemoryCache())
        val recent = DirectoryRecentViewModel { DirectoryRecentPage(emptyList(), null, false) }
        try {
            compose.setContent { UacTheme("light") {
                DirectoryDestination("directory", "uk", "", {}, {}, { _, _, _ -> }, contentModel = model, recentModel = recent)
            } }
            waitModel(model) { it.authoritative && it.complete && it.status == "current" }
            compose.onNodeWithTag("directory-list").performScrollToNode(hasTestTag("directory-category-health"))
            compose.onNodeWithTag("directory-category-health").assertIsDisplayed()
            screenshot("directory-cloud-live-production.png")
            File(app.cacheDir, "directory-cloud-live-production.json").writeText(JSONObject()
                .put("checkedAt", Instant.now().toString()).put("transport", "anonymous public REST, GET only")
                .put("projectID", "ukrainiancommunity-dbd5f").put("categoryCount", categories.size)
                .put("topicCount", categories.values.sumOf { it.topics.size }).put("baselineIDs", org.json.JSONArray(baseline.sorted()))
                .put("parser", "DirectoryCatalog.parseCategory").put("readerAuthoritative", model.snapshot.value.authoritative)
                .put("firebaseSDKVerified", false).toString(2))
        } finally { model.viewModelScope.cancel(); recent.viewModelScope.cancel() }
    }
}
