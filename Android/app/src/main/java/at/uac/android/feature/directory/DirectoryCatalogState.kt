package at.uac.android.feature.directory

/** The marker is separate from directoryCategories so older clients never parse it as a category. */
data class DirectoryCatalogMarker(val baselineIDs: Set<String>) {
    companion object {
        fun decode(fields: Map<String, Any?>): DirectoryCatalogMarker? {
            if ((fields["schemaVersion"] as? Number)?.toDouble() != 1.0 || fields["source"] != "firestore" ||
                fields["migrationComplete"] != true) return null
            val ids = fields["baselineCategoryIDs"] as? List<*> ?: return null
            if (ids.isEmpty() || ids.size > 1000 || ids.any { it !is String || !DirectoryCatalog.validId(it) } ||
                ids.distinct().size != ids.size) return null
            return DirectoryCatalogMarker(ids.filterIsInstance<String>().toSet())
        }
    }
}

data class DirectorySnapshot(
    val published: Map<String, DirectoryCategory> = emptyMap(),
    val revisions: Map<String, Int> = emptyMap(),
    val deleted: Set<String> = emptySet(),
    val status: String = "bundled",
    val invalid: Int = 0,
    val authoritative: Boolean = false,
    val complete: Boolean = false,
    val cacheWriteFailed: Boolean = false,
)

data class DirectoryBatch(val snapshot: DirectorySnapshot, val fromCache: Boolean, val pendingWrites: Boolean = false)

/** Keeps the last complete catalog while independent marker/query listeners catch up. */
class DirectoryCatalogState(cached: DirectorySnapshot? = null, activatedBefore: Boolean = false) {
    var value = cached?.copy(status = "cached", authoritative = true, complete = true)
        ?: DirectorySnapshot(authoritative = activatedBefore, status = if (activatedBefore) "loading" else "bundled")
        private set
    var marker: DirectoryCatalogMarker? = null
        private set
    private var lastBatch: DirectoryBatch? = null

    fun marker(next: DirectoryCatalogMarker?, pending: Boolean = false): DirectorySnapshot {
        if (!pending) marker = next
        if (!value.authoritative) lastBatch?.let { batch(it) }
        return value
    }

    fun batch(next: DirectoryBatch, serverReadAfterMarker: Boolean = false): DirectorySnapshot {
        lastBatch = next
        val data = next.snapshot
        if (next.pendingWrites || data.invalid > 0) {
            if (value.authoritative || marker != null) value = value.copy(status = "failed", invalid = data.invalid)
            else value = data.copy(status = "cached")
            return value
        }
        val ids = data.published.keys + data.deleted
        val cachedBaseline = marker?.baselineIDs?.let { ids.containsAll(it) } == true
        val acceptComplete = if (value.authoritative) !next.fromCache
            else serverReadAfterMarker && !next.fromCache || marker != null && cachedBaseline
        if (acceptComplete) {
            value = data.copy(authoritative = true, complete = true, status = if (next.fromCache) "cached" else "current")
        } else if (!value.authoritative) {
            value = data.copy(status = if (next.fromCache) "cached" else "current")
        } // A partial SDK cache must never replace an already accepted full catalog.
        return value
    }

    fun failure(): DirectorySnapshot { value = value.copy(status = "failed"); return value }
    fun cacheFailure(): DirectorySnapshot { value = value.copy(cacheWriteFailed = true); return value }
    fun cached(): DirectorySnapshot { value = value.copy(status = if (value.complete) "cached" else value.status); return value }

    fun patch(id: String, category: DirectoryCategory?, revision: Int?, deleted: Boolean): DirectorySnapshot {
        if (value.authoritative && !value.complete) return value
        if (category != null && revision != null && revision >= (value.revisions[id] ?: 0)) {
            value = value.copy(published = value.published + (id to category), deleted = value.deleted - id,
                revisions = value.revisions + (id to revision))
        } else if (deleted || category == null && value.authoritative) {
            value = value.copy(published = value.published - id, deleted = value.deleted + id,
                revisions = if (revision != null) value.revisions + (id to revision) else value.revisions - id)
        }
        return value
    }
}
