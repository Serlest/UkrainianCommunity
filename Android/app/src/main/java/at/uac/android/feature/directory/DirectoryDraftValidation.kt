package at.uac.android.feature.directory

import org.json.JSONArray
import org.json.JSONObject

/** Fast client feedback; the callable remains the authoritative validator and rights gate. */
object DirectoryDraftValidation {
    fun firstIssueDescription(payload: String, language: String): String? {
        val issue = firstIssue(payload) ?: return null
        val german = language != "uk"
        val category = runCatching { JSONObject(payload) }.getOrNull()
        val field = when {
            issue == "category.text" -> category?.let {
                bilingualIssue(it.optJSONObject("title"), 100,
                    if (german) "Bereichstitel" else "Назва розділу", language)
                    ?: bilingualIssue(it.optJSONObject("summary"), 500,
                        if (german) "Kurzbeschreibung" else "Короткий опис", language)
            }
            issue.startsWith("group:") -> category?.optJSONArray("groups")?.let { groups ->
                (0 until groups.length()).firstOrNull { groups.optJSONObject(it)?.optString("id") == issue.removePrefix("group:") }
                    ?.let { bilingualIssue(groups.getJSONObject(it).optJSONObject("title"), 100,
                        if (german) "Name des Unterbereichs" else "Назва підрозділу", language) }
            }
            issue.startsWith("topic:") -> category?.optJSONArray("topics")?.let { topics ->
                (0 until topics.length()).firstOrNull { topics.optJSONObject(it)?.optString("id") == issue.removePrefix("topic:") }
                    ?.let { index -> topics.getJSONObject(index).let { topic ->
                        bilingualIssue(topic.optJSONObject("title"), 140,
                            if (german) "Beitragstitel" else "Назва статті", language)
                            ?: bilingualIssue(topic.optJSONObject("summary"), 800,
                                if (german) "Kurze Einleitung" else "Короткий вступ", language,
                                required = !topic.optBoolean("isHidden"))
                    } }
            }
            else -> null
        }
        return field ?: when {
            issue == "category.size" -> if (german) "Der Bereich ist zu groß. Kürzen Sie Texte oder entfernen Sie Inhalte."
                else "Розділ завеликий. Скоротіть тексти або приберіть матеріали."
            issue == "category.empty" -> if (german) "Fügen Sie mindestens einen sichtbaren Beitrag mit Informationsabschnitt hinzu."
                else "Додайте принаймні одну видиму статтю з інформаційним блоком."
            issue == "category.symbol" -> if (german) "Wählen Sie ein Symbol für den Bereich."
                else "Оберіть символ для розділу."
            issue.startsWith("sources.duplicate:") -> if (german) "Eine Quelle wurde im Beitrag doppelt hinzugefügt. Entfernen Sie das Duplikat."
                else "Одне джерело додано до статті двічі. Приберіть повтор."
            issue.startsWith("sources:") -> if (german) "Prüfen Sie Quellenname und vollständige HTTPS-Adresse im Beitrag."
                else "Перевірте назву джерела та повну HTTPS-адресу в статті."
            issue.startsWith("sections:") || issue.startsWith("region:") ->
                if (german) "Prüfen Sie Titel und Text in beiden Sprachen und ergänzen Sie eine offizielle HTTPS-Quelle im Abschnitt oder Beitrag."
                else "Перевірте назву й текст обома мовами та додайте офіційне HTTPS-джерело до блока або статті."
            issue.startsWith("topic:") -> if (german) "Prüfen Sie Titel, Einleitung und Unterbereich des Beitrags."
                else "Перевірте назву, вступ і підрозділ статті."
            issue.startsWith("group:") -> if (german) "Prüfen Sie den Namen des Unterbereichs in beiden Sprachen."
                else "Перевірте назву підрозділу обома мовами."
            else -> if (german) "Prüfen Sie Pflichtfelder, eindeutige Kennungen und HTTPS-Quellen."
                else "Перевірте обов’язкові поля, унікальні ідентифікатори та HTTPS-джерела."
        }
    }

    private fun bilingualIssue(text: JSONObject?, max: Int, label: String, language: String,
        required: Boolean = true): String? {
        for ((key, name) in listOf("ukrainian" to "Українська", "german" to "Deutsch")) {
            val value = text?.optString(key).orEmpty()
            if (required && value.isBlank()) return if (language == "uk")
                "$label · $name: заповніть це поле." else "$label · $name: Bitte ausfüllen."
            if (value.length > max) return if (language == "uk")
                "$label · $name: ${value.length} із $max символів. Скоротіть текст."
                else "$label · $name: ${value.length} von $max Zeichen. Bitte kürzen."
        }
        return null
    }

    fun firstIssue(payload: String): String? = runCatching {
        val category = JSONObject(payload)
        if (payload.toByteArray(Charsets.UTF_8).size > 800_000) return "category.size"
        if (!DirectoryCatalog.validId(category.getString("id"))) return "category.id"
        if (category.getString("placement") !in setOf("start", "life", "support")) return "category.placement"
        if (category.optString("symbol").isBlank() || category.optString("symbol").length > 80)
            return "category.symbol"
        if (!bilingual(category.getJSONObject("title"), 100) ||
            !bilingual(category.getJSONObject("summary"), 500)) return "category.text"
        val groups = category.getJSONArray("groups")
        val topics = category.getJSONArray("topics")
        if (groups.length() > 30 || topics.length() > 100) return "category.count"
        val groupIds = mutableSetOf<String>()
        val activeGroups = mutableSetOf<String>()
        for (i in 0 until groups.length()) {
            val group = groups.getJSONObject(i)
            val id = group.getString("id")
            if (!DirectoryCatalog.validId(id) || !groupIds.add(id) ||
                !bilingual(group.getJSONObject("title"), 100)) return "group:$id"
            if (!group.getBoolean("isHidden")) activeGroups += id
        }
        val topicIds = mutableSetOf<String>()
        var visibleTopics = 0
        for (i in 0 until topics.length()) {
            val topic = topics.getJSONObject(i)
            val id = topic.getString("id")
            val groupId = topic.getString("groupID")
            val hidden = topic.getBoolean("isHidden")
            if (!DirectoryCatalog.validId(id) || !topicIds.add(id) || groupId !in groupIds ||
                !bilingual(topic.getJSONObject("title"), 140) ||
                !bilingual(topic.getJSONObject("summary"), 800, !hidden)) return "topic:$id"
            val sources = topic.getJSONArray("sources")
            if (sources.length() > 80 || !validSources(sources)) return "sources:$id"
            if ((0 until sources.length()).map { sources.getJSONObject(it).getString("url") }.toSet().size != sources.length())
                return "sources.duplicate:$id"
            val sections = topic.getJSONArray("sections")
            if (sections.length() > 80 || !validSections(sections, sources.length() > 0)) return "sections:$id"
            val regional = topic.getJSONObject("regionalSections")
            for (region in regional.keys()) {
                if (region !in regions || !validSections(regional.getJSONArray(region), false))
                    return "region:$id/$region"
            }
            if (!hidden && groupId in activeGroups) {
                visibleTopics++
                if ((0 until sections.length()).none { !sections.getJSONObject(it).getBoolean("isHidden") })
                    return "sections:$id"
            }
        }
        if (!category.getBoolean("isHidden") && visibleTopics == 0) return "category.empty"
        null
    }.getOrElse { "category.invalid" }

    private val regions = setOf("burgenland", "kaernten", "niederoesterreich", "oberoesterreich",
        "salzburg", "steiermark", "tirol", "vorarlberg", "wien")

    private fun bilingual(text: JSONObject, max: Int, required: Boolean = true): Boolean =
        listOf("ukrainian", "german").all { key ->
            val value = text.getString(key)
            value.length <= max && (!required || value.isNotBlank())
        }

    private fun validSources(sources: JSONArray): Boolean =
        (0 until sources.length()).all { index ->
            val source = sources.getJSONObject(index)
            source.getString("name").let { it.isNotBlank() && it.length <= 160 } &&
                source.getString("url").let { it.length <= 1024 && DirectorySource("", it).safeUrl != null }
        }

    private fun validSections(sections: JSONArray, topicHasSource: Boolean): Boolean {
        if (sections.length() > 80) return false
        val ids = mutableSetOf<String>()
        for (i in 0 until sections.length()) {
            val section = sections.getJSONObject(i)
            val hidden = section.getBoolean("isHidden")
            val id = section.getString("id")
            if (!DirectoryCatalog.validId(id) || !ids.add(id) ||
                section.optString("symbol").isBlank() || section.optString("symbol").length > 80 ||
                !bilingual(section.getJSONObject("title"), 160) ||
                !bilingual(section.getJSONObject("body"), 6000, !hidden)) return false
            val source = section.optJSONObject("source")
            if (source != null && !validSources(JSONArray().put(source))) return false
            if (!hidden && source == null && !topicHasSource) return false
            val contacts = section.getJSONArray("contacts")
            if (contacts.length() > 12) return false
            for (j in 0 until contacts.length()) {
                val contact = contacts.getJSONObject(j)
                if (!Regex("[0-9 +()/-]{1,40}").matches(contact.getString("number")) ||
                    !bilingual(contact.getJSONObject("title"), 100) ||
                    !bilingual(contact.getJSONObject("detail"), 200)) return false
            }
        }
        return true
    }
}
