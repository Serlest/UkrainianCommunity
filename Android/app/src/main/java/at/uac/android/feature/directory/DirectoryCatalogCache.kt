package at.uac.android.feature.directory

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.security.MessageDigest
import org.json.JSONArray
import org.json.JSONObject

interface DirectoryCatalogCache {
    fun activatedBefore(): Boolean
    fun read(): DirectorySnapshot?
    fun write(snapshot: DirectorySnapshot)
}

/** Public content only. Project/package binding and one atomic envelope prevent cross-flavor/partial restores. */
class DiskDirectoryCatalogCache(context: Context, private val projectID: String,
    root: File = context.noBackupFilesDir, namespace: String = context.packageName) : DirectoryCatalogCache {
    private val key = MessageDigest.getInstance("SHA-256").digest("$projectID|$namespace".toByteArray())
        .joinToString("") { "%02x".format(it) }
    private val preferences = context.getSharedPreferences("directory-authority-$key", Context.MODE_PRIVATE)
    private val file = AtomicFile(File(root, "directory-$key.json"))
    override fun activatedBefore() = preferences.getBoolean("activated", false)
    override fun read(): DirectorySnapshot? = runCatching {
        val bytes = file.openRead().use { input ->
            val output = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                require(output.size() + count <= MAX_BYTES)
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
        val root = JSONObject(bytes.toString(Charsets.UTF_8))
        require(root.getInt("schemaVersion") == 1 && root.getString("projectID") == projectID && root.getString("binding") == key)
        val published = mutableMapOf<String, DirectoryCategory>()
        val revisions = mutableMapOf<String, Int>()
        val deleted = mutableSetOf<String>()
        val records = root.getJSONArray("records")
        for (i in 0 until records.length()) {
            val record = records.getJSONObject(i)
            val id = record.getString("id")
            require(DirectoryCatalog.validId(id) && id !in published && id !in deleted)
            val revision = record.optInt("revision", 0)
            if (revision > 0) revisions[id] = revision
            if (record.getBoolean("deleted")) deleted += id
            else {
                require(revision > 0)
                val category = DirectoryCatalog.parseCategory(JSONObject(record.getString("payload")))
                require(category.id == id)
                published[id] = category
            }
        }
        DirectorySnapshot(published, revisions, deleted, "cached", authoritative = true, complete = true)
    }.getOrNull()

    override fun write(snapshot: DirectorySnapshot) {
        require(snapshot.authoritative && snapshot.complete && snapshot.invalid == 0)
        // Persist the switch first: even a corrupt/lost payload must not resurrect the bundle later.
        check(preferences.edit().putBoolean("activated", true).commit())
        val records = JSONArray()
        (snapshot.published.keys + snapshot.deleted).sorted().forEach { id ->
            records.put(JSONObject().put("id", id).put("revision", snapshot.revisions[id] ?: 0)
                .put("deleted", id in snapshot.deleted).apply {
                    snapshot.published[id]?.let { put("payload", it.rawJson) }
                })
        }
        val bytes = JSONObject().put("schemaVersion", 1).put("projectID", projectID).put("binding", key)
            .put("records", records).toString().toByteArray()
        require(bytes.size <= MAX_BYTES)
        val stream = file.startWrite()
        try { stream.write(bytes); file.finishWrite(stream) }
        catch (error: Exception) { file.failWrite(stream); throw error }
    }
    private companion object { const val MAX_BYTES = 16 * 1024 * 1024 }
}
