package at.uac.android

import at.uac.android.feature.directory.*
import org.junit.Assert.*
import org.junit.Test

class DirectoryCloudCatalogTest {
    private val title = DirectoryText("UK", "DE")
    private fun category(id: String, hidden: Boolean = false): DirectoryCategory {
        val section = DirectorySection("block", 0, false, title, title, null, null, emptyList())
        val topic = DirectoryTopic("topic", "group", 0, false, title, title, listOf(section), emptyList(), emptyMap())
        return DirectoryCategory(id, "life", 0, hidden, title, title, listOf(DirectoryGroup("group", 0, false, title)), listOf(topic), "{}")
    }
    private val baseline = setOf("safety", "health")
    private fun batch(vararg ids: String, cached: Boolean = false, invalid: Int = 0, pending: Boolean = false,
        deleted: Set<String> = emptySet()) = DirectoryBatch(DirectorySnapshot(ids.associateWith(::category),
        (ids.toSet() + deleted).associateWith { 1 }, deleted, invalid = invalid), cached, pending)
    private fun visible(state: DirectorySnapshot) = DirectoryCatalog.merge(baseline.map(::category),
        state.published, state.deleted, state.authoritative).map { it.id }.toSet()

    @Test fun legacyBootstrapStillMergesTheUnmigratedBundle() {
        val state = DirectoryCatalogState()
        state.batch(batch("health", "custom-guide", cached = true))
        assertFalse(state.value.authoritative)
        assertEquals(setOf("safety", "health", "custom-guide"), visible(state.value))
    }
    @Test fun markerAndPartialCacheNeverActivateUntilCompletenessIsProved() {
        val state = DirectoryCatalogState()
        state.marker(DirectoryCatalogMarker(baseline))
        state.batch(batch("health", cached = true))
        assertFalse(state.value.authoritative)
        assertEquals(baseline, visible(state.value))
        state.batch(batch("safety", "health", cached = true))
        assertTrue(state.value.authoritative)
        assertTrue(state.value.complete)
        assertEquals("cached", state.value.status)
    }
    @Test fun reversedListenerOrderingAndTombstonesAlsoProveCachedBaseline() {
        val state = DirectoryCatalogState()
        state.batch(batch("health", cached = true, deleted = setOf("safety")))
        state.marker(DirectoryCatalogMarker(baseline))
        assertTrue(state.value.authoritative)
        assertEquals(setOf("health"), visible(state.value))
    }
    @Test fun explicitReadAfterMarkerAcceptsLegitimateLaterMissingBaselineAndNeverResurrectsIt() {
        val state = DirectoryCatalogState()
        state.batch(batch("health"), serverReadAfterMarker = true)
        assertTrue(state.value.authoritative)
        assertEquals(setOf("health"), visible(state.value))
        state.batch(batch()) // Full authoritative server catalog may legitimately become empty.
        assertTrue(state.value.complete)
        assertTrue(visible(state.value).isEmpty())
        state.failure()
        state.marker(null)
        state.batch(batch("safety", cached = true))
        assertTrue(state.value.authoritative)
        assertTrue(visible(state.value).isEmpty())
    }
    @Test fun cacheSubsetAndPendingWritesNeverReplaceAcceptedFullSnapshot() {
        val state = DirectoryCatalogState()
        state.batch(batch("safety", "health", "custom-guide"), true)
        state.batch(batch("health", cached = true))
        assertEquals(setOf("safety", "health", "custom-guide"), visible(state.value))
        state.batch(batch("health", pending = true))
        assertEquals(setOf("safety", "health", "custom-guide"), visible(state.value))
    }
    @Test fun malformedCategoryDoesNotCauseBundleFallbackOrCommitPartialCloudCatalog() {
        val state = DirectoryCatalogState()
        state.batch(batch("custom-guide"), true)
        state.batch(batch("health", invalid = 1))
        assertEquals(setOf("custom-guide"), visible(state.value))
        assertEquals("failed", state.value.status)
        state.batch(batch("health"))
        assertEquals(setOf("health"), visible(state.value))
        assertEquals(0, state.value.invalid)
    }
    @Test fun stickyAuthorityWithLostOrCorruptCacheStaysEmptyUntilAFullServerRead() {
        val state = DirectoryCatalogState(activatedBefore = true)
        assertTrue(state.value.authoritative)
        assertFalse(state.value.complete)
        assertTrue(visible(state.value).isEmpty())
        state.batch(batch("safety", "health", cached = true))
        assertFalse(state.value.complete)
        assertTrue(visible(state.value).isEmpty())
        state.patch("health", category("health"), 1, false)
        assertTrue(visible(state.value).isEmpty())
        state.batch(batch("health"), true)
        assertTrue(state.value.complete)
        assertEquals(setOf("health"), visible(state.value))
    }
    @Test fun offlineRestartRetainsHiddenAndDeletedSemanticsAndLaterPublicationUpdatesRevision() {
        val first = DirectoryCatalogState()
        first.batch(batch("health", deleted = setOf("safety")), true)
        val cached = first.value.copy(published = mapOf("health" to category("health", hidden = true)))
        val state = DirectoryCatalogState(cached)
        assertTrue(visible(state.value).isEmpty())
        state.patch("health", category("health"), 2, false)
        assertEquals(setOf("health"), visible(state.value))
        state.patch("health", category("health", hidden = true), 1, false)
        assertEquals(setOf("health"), visible(state.value))
        assertEquals(2, state.value.revisions["health"])
        state.patch("health", null, null, false)
        assertTrue(visible(state.value).isEmpty())
    }
    @Test fun invalidPendingOrWrongVersionMarkerDoesNotSwitchSource() {
        val valid = mapOf("schemaVersion" to 1, "source" to "firestore", "migrationComplete" to true,
            "baselineCategoryIDs" to baseline.toList())
        assertNotNull(DirectoryCatalogMarker.decode(valid))
        listOf(mapOf("schemaVersion" to 2), mapOf("source" to "bundle"), mapOf("migrationComplete" to false),
            mapOf("baselineCategoryIDs" to listOf("safety", "safety")), mapOf("baselineCategoryIDs" to listOf("../private")))
            .forEach { assertNull(DirectoryCatalogMarker.decode(valid + it)) }
        val state = DirectoryCatalogState()
        state.batch(batch("safety", "health", cached = true))
        state.marker(DirectoryCatalogMarker(baseline), pending = true)
        assertFalse(state.value.authoritative)
    }
}
