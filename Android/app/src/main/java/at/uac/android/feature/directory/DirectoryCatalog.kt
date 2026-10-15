package at.uac.android.feature.directory

import android.content.Context
import at.uac.android.feature.browse.safeHttps
import org.json.JSONArray
import org.json.JSONObject

data class DirectoryText(val ukrainian: String, val german: String) {
    fun forLanguage(language: String) = if (language == "uk") ukrainian else german
}

data class DirectorySource(val name: String, val url: String) {
    val safeUrl: String?
        get() = safeHttps(url)
}

data class DirectoryContact(
    val number: String,
    val title: DirectoryText,
    val detail: DirectoryText,
)

data class DirectorySection(
    val id: String,
    val order: Int,
    val hidden: Boolean,
    val title: DirectoryText,
    val body: DirectoryText,
    val phoneNumber: String?,
    val source: DirectorySource?,
    val contacts: List<DirectoryContact>,
)

data class DirectoryTopic(
    val id: String,
    val groupId: String,
    val order: Int,
    val hidden: Boolean,
    val title: DirectoryText,
    val summary: DirectoryText,
    val sections: List<DirectorySection>,
    val sources: List<DirectorySource>,
    val regionalSections: Map<String, List<DirectorySection>>,
)

data class DirectoryGroup(
    val id: String,
    val order: Int,
    val hidden: Boolean,
    val title: DirectoryText,
)

data class DirectoryCategory(
    val id: String,
    val placement: String,
    val order: Int,
    val hidden: Boolean,
    val title: DirectoryText,
    val summary: DirectoryText,
    val groups: List<DirectoryGroup>,
    val topics: List<DirectoryTopic>,
    val rawJson: String,
    val symbol: String = "",
) {
    val visibleGroups: List<DirectoryGroup>
        get() = groups.filterNot { it.hidden }.filter { group ->
            topics.any { !it.hidden && it.groupId == group.id }
        }.sortedWith(compareBy<DirectoryGroup> { it.order }.thenBy { it.id })

    fun visibleTopics(groupId: String): List<DirectoryTopic> =
        topics.filter { !it.hidden && it.groupId == groupId }
            .sortedWith(compareBy<DirectoryTopic> { it.order }.thenBy { it.id })

    fun visibleTopic(id: String): DirectoryTopic? =
        topics.firstOrNull { it.id == id && !it.hidden && visibleGroups.any { g -> g.id == it.groupId } }

    val visible: Boolean get() = !hidden && visibleGroups.isNotEmpty()
}

object DirectoryCatalog {
    private val slug = Regex("[a-z0-9][a-z0-9-]{0,63}")
    private val regions = setOf(
        "burgenland", "kaernten", "niederoesterreich", "oberoesterreich",
        "salzburg", "steiermark", "tirol", "vorarlberg", "wien",
    )

    fun validId(id: String) = slug.matches(id)

    fun bundled(context: Context): List<DirectoryCategory> =
        context.assets.open("directory-catalog.json").bufferedReader().use { input ->
            parseArray(JSONArray(input.readText()))
        }

    fun parseArray(array: JSONArray): List<DirectoryCategory> =
        (0 until array.length()).map { parseCategory(array.getJSONObject(it)) }

    fun parseCategory(json: JSONObject): DirectoryCategory {
        val id = json.getString("id")
        require(validId(id))
        val placement = json.getString("placement")
        require(placement in setOf("start", "life", "support"))
        val groups = json.getJSONArray("groups").objects().map {
            DirectoryGroup(it.getString("id"), it.getInt("order"), it.getBoolean("isHidden"),
                it.getJSONObject("title").text())
        }
        val topics = json.getJSONArray("topics").objects().map { topic ->
            val regional = topic.getJSONObject("regionalSections")
            val regionalSections = regional.keys().asSequence().filter { it in regions }
                .associateWith { key -> regional.getJSONArray(key).objects().map(::section) }
            DirectoryTopic(
                topic.getString("id"), topic.getString("groupID"), topic.getInt("order"),
                topic.getBoolean("isHidden"), topic.getJSONObject("title").text(),
                topic.getJSONObject("summary").text(),
                topic.getJSONArray("sections").objects().map(::section),
                topic.getJSONArray("sources").objects().map(::source), regionalSections,
            )
        }
        require(groups.map { it.id }.distinct().size == groups.size)
        require(topics.map { it.id }.distinct().size == topics.size)
        require(groups.all { validId(it.id) } && topics.all { validId(it.id) && groups.any { g -> g.id == it.groupId } })
        return DirectoryCategory(
            id, placement, json.getInt("order"), json.getBoolean("isHidden"),
            json.getJSONObject("title").text(), json.getJSONObject("summary").text(), groups, topics,
            json.toString(), json.optString("symbol"),
        )
    }

    fun merge(bundled: List<DirectoryCategory>, published: Map<String, DirectoryCategory>,
              deleted: Set<String>): List<DirectoryCategory> =
        allMerged(bundled, published, deleted).filter(DirectoryCategory::visible)

    fun allMerged(bundled: List<DirectoryCategory>, published: Map<String, DirectoryCategory>,
                  deleted: Set<String>): List<DirectoryCategory> {
        val base = bundled.mapNotNull { if (it.id in deleted) null else published[it.id] ?: it }
        val added = published.values.filter { category ->
            category.id !in deleted && bundled.none { it.id == category.id }
        }
        val order = mapOf("start" to 0, "life" to 1, "support" to 2)
        return (base + added)
            .sortedWith(compareBy<DirectoryCategory> { order[it.placement] ?: 3 }
                .thenBy { it.order }.thenBy { it.id })
    }

    private fun JSONArray.objects(): List<JSONObject> =
        (0 until length()).map(::getJSONObject)

    private fun JSONObject.text() = DirectoryText(getString("ukrainian"), getString("german"))
    private fun source(json: JSONObject) = DirectorySource(json.getString("name"), json.getString("url"))
    private fun section(json: JSONObject): DirectorySection = DirectorySection(
        json.getString("id"), json.getInt("order"), json.getBoolean("isHidden"),
        json.getJSONObject("title").text(), json.getJSONObject("body").text(),
        json.optString("phoneNumber").takeIf { it.isNotBlank() && it != "null" },
        json.optJSONObject("source")?.let(::source),
        json.getJSONArray("contacts").objects().map {
            DirectoryContact(it.getString("number"), it.getJSONObject("title").text(),
                it.getJSONObject("detail").text())
        },
    )
}
