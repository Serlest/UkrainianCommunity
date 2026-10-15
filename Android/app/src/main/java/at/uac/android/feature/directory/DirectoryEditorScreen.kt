package at.uac.android.feature.directory

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.design.UacCard
import at.uac.android.design.UacDesign
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.feature.browse.Choice
import at.uac.android.feature.browse.regions
import at.uac.android.feature.browse.tr
import at.uac.android.feature.translation.ContentTranslationButton
import at.uac.android.feature.translation.TranslationField
import java.util.UUID
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/** Publication is revision checked by the server. Drafts stay local until explicit publish. */
@Composable
fun DirectoryEditorScreen(
    categoryId: String?,
    language: String,
    categories: List<DirectoryCategory>,
    revisions: Map<String, Int>,
    access: DirectoryEditorAccess,
    onOpen: (String) -> Unit,
) {
    if (categoryId == null) {
        DirectoryManagementList(language, categories, onOpen)
        return
    }
    val original = categories.firstOrNull { it.id == categoryId }
    val newPlacement = categoryId.removePrefix("new-").takeIf {
        categoryId.startsWith("new-") && it in setOf("start", "life", "support")
    }
    if (original == null && newPlacement == null) {
        Text(tr(language, "Bereich nicht gefunden", "Розділ не знайдено"))
        return
    }
    val draftId = rememberSaveable(categoryId) {
        original?.id ?: "custom-${UUID.randomUUID()}"
    }
    val initial = remember(categoryId, original?.rawJson) {
        original?.rawJson ?: newCategoryJson(draftId, newPlacement!!).toString()
    }
    var draft by rememberSaveable(categoryId) { mutableStateOf(initial) }
    var baseline by rememberSaveable(categoryId) { mutableStateOf(initial) }
    var expectedRevision by rememberSaveable(categoryId) { mutableStateOf(revisions[categoryId] ?: 0) }
    var pane by rememberSaveable(categoryId) { mutableStateOf("category") }
    var selectedRegion by rememberSaveable(categoryId) { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmDelete by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val json = remember(draft) { JSONObject(draft) }
    fun mutate(change: (JSONObject) -> Unit) {
        val next = JSONObject(draft)
        change(next)
        draft = next.toString()
        error = null
    }
    val topics = json.getJSONArray("topics")
    val groups = json.getJSONArray("groups")
    val topicIndex = pane.removePrefix("topic:").toIntOrNull()?.takeIf { it in 0 until topics.length() }
    val groupIndex = pane.removePrefix("group:").toIntOrNull()?.takeIf { it in 0 until groups.length() }
    val sectionIndex = pane.takeIf { it.startsWith("section:") }
        ?.removePrefix("section:")?.split(':')?.mapNotNull(String::toIntOrNull)
        ?.takeIf { it.size == 2 && it[0] in 0 until topics.length() }
    val regionSectionIndex = pane.takeIf { it.startsWith("region:") }
        ?.removePrefix("region:")?.split(':')?.mapNotNull(String::toIntOrNull)
        ?.takeIf { it.size == 2 && it[0] in 0 until topics.length() }
    LazyColumn(
        Modifier.fillMaxSize().testTag("directory-editor"),
        contentPadding = PaddingValues(start = UacDesign.pageInset, end = UacDesign.pageInset, bottom = 36.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item("header") {
            UacSectionHeading(tr(language, "Ratgeber bearbeiten", "Редагування довідника"), UacIcon.EDIT)
            if (draft != baseline) Text(tr(language, "Nicht veröffentlichte Änderungen", "Неопубліковані зміни"),
                color = MaterialTheme.colorScheme.primary)
            if (error != null) Text(error!!, color = MaterialTheme.colorScheme.error,
                modifier = Modifier.testTag("directory-editor-error"))
            TextButton({ pane = "category" }, Modifier.testTag("directory-editor-category-back")) {
                Text(tr(language, "Zum Bereich", "До розділу"))
            }
        }
        when {
            sectionIndex != null || regionSectionIndex != null -> {
                val index = sectionIndex ?: regionSectionIndex!!
                val topic = topics.getJSONObject(index[0])
                val regional = regionSectionIndex != null
                val list = if (regional) topic.getJSONObject("regionalSections").optJSONArray(selectedRegion) ?: JSONArray()
                    else topic.getJSONArray("sections")
                if (index[1] in 0 until list.length()) {
                    val section = list.getJSONObject(index[1])
                    item("section-fields") {
                        UacSectionHeading(tr(language, "Informationsabschnitt", "Інформаційний блок"), UacIcon.EDIT)
                        BilingualEditor(language, tr(language, "Titel", "Назва"), section.getJSONObject("title"),
                            tag = "directory-editor-section-title") { key, value ->
                            mutate { root -> sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                .getJSONObject("title").put(key, value) }
                        }
                        BilingualEditor(language, tr(language, "Text", "Текст"), section.getJSONObject("body"),
                            multiline = true, tag = "directory-editor-section-body") { key, value ->
                            mutate { root -> sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                .getJSONObject("body").put(key, value) }
                        }
                        DirectoryTranslationControls("section:$categoryId:$index", language,
                            listOf(
                                DirectoryTranslationEntry("title", tr(language, "Titel", "Назва"), section.getJSONObject("title"), 160),
                                DirectoryTranslationEntry("body", tr(language, "Text", "Текст"), section.getJSONObject("body"), 6000),
                            )) { values, target ->
                            mutate { root ->
                                val current = sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                values.forEach { (key, value) -> current.getJSONObject(key).put(target, value) }
                            }
                        }
                        EditorText(language, tr(language, "Symbol", "Символ"), section.getString("symbol")) {
                            mutate { root -> sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                .put("symbol", it) }
                        }
                        val source = section.optJSONObject("source") ?: JSONObject().put("name", "").put("url", "")
                        SourceEditor(language, source, "directory-editor-section-source") { key, value ->
                            mutate { root ->
                                val target = sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                val s = target.optJSONObject("source") ?: JSONObject().also { target.put("source", it) }
                                s.put(key, value)
                            }
                        }
                        val phone = section.optString("phoneNumber").takeUnless { it == "null" }.orEmpty()
                        EditorText(language, tr(language, "Telefon", "Телефон"), phone) {
                            mutate { root -> sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                .put("phoneNumber", it.takeIf(String::isNotBlank) ?: JSONObject.NULL) }
                        }
                        val contacts = section.getJSONArray("contacts")
                        if (contacts.length() > 0)
                            Text(tr(language, "Kontakte", "Контакти"), style = MaterialTheme.typography.titleMedium)
                        (0 until contacts.length()).forEach { contactIndex ->
                            val contact = contacts.getJSONObject(contactIndex)
                            EditorText(language, tr(language, "Nummer", "Номер"), contact.getString("number")) { value ->
                                mutate { root -> sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                    .getJSONArray("contacts").getJSONObject(contactIndex).put("number", value) }
                            }
                            BilingualEditor(language, tr(language, "Kontakt", "Контакт"), contact.getJSONObject("title")) { key, value ->
                                mutate { root -> sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                    .getJSONArray("contacts").getJSONObject(contactIndex).getJSONObject("title").put(key, value) }
                            }
                            BilingualEditor(language, tr(language, "Beschreibung", "Пояснення"), contact.getJSONObject("detail")) { key, value ->
                                mutate { root -> sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                    .getJSONArray("contacts").getJSONObject(contactIndex).getJSONObject("detail").put(key, value) }
                            }
                            DirectoryTranslationControls("contact:$categoryId:$index:$contactIndex", language,
                                listOf(
                                    DirectoryTranslationEntry("title", tr(language, "Kontakt", "Контакт"), contact.getJSONObject("title"), 100),
                                    DirectoryTranslationEntry("detail", tr(language, "Beschreibung", "Пояснення"), contact.getJSONObject("detail"), 200),
                                )) { values, target ->
                                mutate { root ->
                                    val current = sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                        .getJSONArray("contacts").getJSONObject(contactIndex)
                                    values.forEach { (key, value) -> current.getJSONObject(key).put(target, value) }
                                }
                            }
                            TextButton({ mutate { root -> sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                .getJSONArray("contacts").remove(contactIndex) } }) {
                                Text(tr(language, "Kontakt entfernen", "Видалити контакт"))
                            }
                        }
                        OutlinedButton({ mutate { root -> sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                            .getJSONArray("contacts").put(JSONObject().put("number", "")
                                .put("title", bilingual()).put("detail", bilingual())) } }) {
                            Text(tr(language, "Kontakt hinzufügen", "Додати контакт"))
                        }
                        LabeledSwitch(tr(language, "Verbergen", "Приховати"), section.getBoolean("isHidden")) {
                            mutate { root -> sectionAt(root, index[0], index[1], selectedRegion.takeIf { regional })
                                .put("isHidden", it) }
                        }
                        OutlinedButton({ pane = "topic:${index[0]}" }) {
                            Text(tr(language, "Zurück zum Beitrag", "Назад до статті"))
                        }
                        OutlinedButton({
                            val canRemove = regional || list.length() > 1
                            if (canRemove) {
                                mutate { root ->
                                    val target = root.getJSONArray("topics").getJSONObject(index[0])
                                    val targetList = if (regional) target.getJSONObject("regionalSections").getJSONArray(selectedRegion)
                                        else target.getJSONArray("sections")
                                    targetList.remove(index[1])
                                }
                                pane = "topic:${index[0]}"
                            } else error = tr(language, "Der letzte Abschnitt kann nicht entfernt werden.",
                                "Останній блок не можна видалити.")
                        }) { Text(tr(language, "Abschnitt entfernen", "Видалити блок")) }
                    }
                }
            }
            groupIndex != null -> {
                val group = groups.getJSONObject(groupIndex)
                item("group-fields") {
                    UacSectionHeading(tr(language, "Unterbereich", "Підрозділ"), UacIcon.EDIT)
                    BilingualEditor(language, tr(language, "Titel", "Назва"), group.getJSONObject("title"),
                        tag = "directory-editor-group-title") { key, value ->
                        mutate { it.getJSONArray("groups").getJSONObject(groupIndex).getJSONObject("title").put(key, value) }
                    }
                    DirectoryTranslationControls("group:$categoryId:$groupIndex", language,
                        listOf(DirectoryTranslationEntry("title", tr(language, "Titel", "Назва"),
                            group.getJSONObject("title"), 100))) { values, target ->
                        mutate { root -> values.forEach { (key, value) -> root.getJSONArray("groups")
                            .getJSONObject(groupIndex).getJSONObject(key).put(target, value) } }
                    }
                    LabeledSwitch(tr(language, "Verbergen", "Приховати"), group.getBoolean("isHidden")) {
                        mutate { root -> root.getJSONArray("groups").getJSONObject(groupIndex).put("isHidden", it) }
                    }
                    OutlinedButton({
                        val id = group.getString("id")
                        val remaining = (0 until topics.length()).count {
                            topics.getJSONObject(it).getString("groupID") != id
                        }
                        if (groups.length() > 1 && remaining > 0) {
                            mutate { root ->
                                val targetTopics = root.getJSONArray("topics")
                                for (i in targetTopics.length() - 1 downTo 0)
                                    if (targetTopics.getJSONObject(i).getString("groupID") == id)
                                        targetTopics.remove(i)
                                root.getJSONArray("groups").remove(groupIndex)
                            }
                            pane = "category"
                        } else error = tr(language, "Der letzte Bereich mit Beiträgen bleibt erhalten.",
                            "Останній підрозділ зі статтями має залишитися.")
                    }) { Text(tr(language, "Unterbereich und Beiträge entfernen", "Видалити підрозділ і статті")) }
                }
            }
            topicIndex != null -> {
                val topic = topics.getJSONObject(topicIndex)
                item("topic-fields") {
                    UacSectionHeading(tr(language, "Beitrag", "Стаття"), UacIcon.EDIT)
                    BilingualEditor(language, tr(language, "Titel", "Назва"), topic.getJSONObject("title"),
                        tag = "directory-editor-topic-title") { key, value ->
                        mutate { it.getJSONArray("topics").getJSONObject(topicIndex).getJSONObject("title").put(key, value) }
                    }
                    BilingualEditor(language, tr(language, "Einleitung", "Вступ"), topic.getJSONObject("summary"),
                        multiline = true, tag = "directory-editor-topic-summary") { key, value ->
                        mutate { it.getJSONArray("topics").getJSONObject(topicIndex).getJSONObject("summary").put(key, value) }
                    }
                    DirectoryTranslationControls("topic:$categoryId:$topicIndex", language,
                        listOf(
                            DirectoryTranslationEntry("title", tr(language, "Titel", "Назва"), topic.getJSONObject("title"), 140),
                            DirectoryTranslationEntry("summary", tr(language, "Einleitung", "Вступ"), topic.getJSONObject("summary"), 800),
                        )) { values, target ->
                        mutate { root -> values.forEach { (key, value) -> root.getJSONArray("topics")
                            .getJSONObject(topicIndex).getJSONObject(key).put(target, value) } }
                    }
                    Choice(tr(language, "Unterbereich", "Підрозділ"), topic.getString("groupID"),
                        (0 until groups.length()).map { i -> groups.getJSONObject(i).let { it.getString("id") to
                            it.getJSONObject("title").getString(if (language == "uk") "ukrainian" else "german") } },
                        "directory-editor-group-choice") {
                        mutate { root -> root.getJSONArray("topics").getJSONObject(topicIndex).put("groupID", it) }
                    }
                    LabeledSwitch(tr(language, "Verbergen", "Приховати"), topic.getBoolean("isHidden")) {
                        mutate { root -> root.getJSONArray("topics").getJSONObject(topicIndex).put("isHidden", it) }
                    }
                    Text(tr(language, "Quellen des Beitrags", "Джерела статті"), style = MaterialTheme.typography.titleMedium)
                    val sources = topic.getJSONArray("sources")
                    (0 until sources.length()).forEach { i ->
                        SourceEditor(language, sources.getJSONObject(i), "directory-editor-topic-source-$i") { key, value ->
                            mutate { root -> root.getJSONArray("topics").getJSONObject(topicIndex)
                                .getJSONArray("sources").getJSONObject(i).put(key, value) }
                        }
                    }
                    OutlinedButton({ mutate { it.getJSONArray("topics").getJSONObject(topicIndex)
                        .getJSONArray("sources").put(JSONObject().put("name", "").put("url", "")) } }) {
                        Text(tr(language, "Quelle hinzufügen", "Додати джерело"))
                    }
                    if (sources.length() > 0) TextButton({ mutate { it.getJSONArray("topics")
                        .getJSONObject(topicIndex).getJSONArray("sources").remove(sources.length() - 1) } }) {
                        Text(tr(language, "Letzte Quelle entfernen", "Видалити останнє джерело"))
                    }
                    Text(tr(language, "Informationsabschnitte", "Інформаційні блоки"), style = MaterialTheme.typography.titleMedium)
                    val sections = topic.getJSONArray("sections")
                    (0 until sections.length()).forEach { i ->
                        Row {
                            TextButton({ pane = "section:$topicIndex:$i" },
                                Modifier.weight(1f).testTag("directory-editor-open-section-$i")) {
                                Text(sections.getJSONObject(i).getJSONObject("title")
                                    .getString(if (language == "uk") "ukrainian" else "german")
                                    .ifBlank { tr(language, "Neuer Abschnitt", "Новий блок") })
                            }
                            MoveButtons(i, sections.length()) { delta ->
                                mutate { root ->
                                    val t = root.getJSONArray("topics").getJSONObject(topicIndex)
                                    t.put("sections", moved(t.getJSONArray("sections"), i, delta))
                                }
                            }
                        }
                    }
                    OutlinedButton({
                        mutate { root -> root.getJSONArray("topics").getJSONObject(topicIndex)
                            .getJSONArray("sections").put(newSection("section-${UUID.randomUUID().toString().take(8)}", sections.length())) }
                        pane = "section:$topicIndex:${sections.length()}"
                    }) { Text(tr(language, "Abschnitt hinzufügen", "Додати блок")) }
                    Choice(tr(language, "Bundesland", "Федеральна земля"), selectedRegion,
                        listOf("" to tr(language, "Wählen", "Обрати")) + regions,
                        "directory-editor-region") { selectedRegion = it }
                    if (selectedRegion.isNotBlank()) {
                        val regionSections = topic.getJSONObject("regionalSections").optJSONArray(selectedRegion) ?: JSONArray()
                        (0 until regionSections.length()).forEach { i ->
                            TextButton({ pane = "region:$topicIndex:$i" }) {
                                Text(regionSections.getJSONObject(i).getJSONObject("title")
                                    .getString(if (language == "uk") "ukrainian" else "german"))
                            }
                        }
                        OutlinedButton({
                            mutate { root ->
                                val regional = root.getJSONArray("topics").getJSONObject(topicIndex).getJSONObject("regionalSections")
                                val list = regional.optJSONArray(selectedRegion) ?: JSONArray().also { regional.put(selectedRegion, it) }
                                list.put(newSection("regional-${UUID.randomUUID().toString().take(8)}", list.length()))
                            }
                            pane = "region:$topicIndex:${regionSections.length()}"
                        }) { Text(tr(language, "Regionalen Abschnitt hinzufügen", "Додати регіональний блок")) }
                    }
                    OutlinedButton({
                        if (topics.length() > 1) {
                            mutate { it.getJSONArray("topics").remove(topicIndex) }
                            pane = "category"
                        } else error = tr(language, "Der letzte Beitrag kann nicht entfernt werden.",
                            "Останню статтю не можна видалити.")
                    }) { Text(tr(language, "Beitrag entfernen", "Видалити статтю")) }
                }
            }
            else -> {
                item("category-fields") {
                    BilingualEditor(language, tr(language, "Bereichstitel", "Назва розділу"),
                        json.getJSONObject("title"), tag = "directory-editor-category-title") { key, value ->
                        mutate { it.getJSONObject("title").put(key, value) }
                    }
                    BilingualEditor(language, tr(language, "Kurzbeschreibung", "Опис"), json.getJSONObject("summary"),
                        multiline = true, tag = "directory-editor-category-summary") { key, value ->
                        mutate { it.getJSONObject("summary").put(key, value) }
                    }
                    DirectoryTranslationControls("category:$categoryId", language,
                        listOf(
                            DirectoryTranslationEntry("title", tr(language, "Bereichstitel", "Назва розділу"), json.getJSONObject("title"), 100),
                            DirectoryTranslationEntry("summary", tr(language, "Kurzbeschreibung", "Опис"), json.getJSONObject("summary"), 500),
                        )) { values, target ->
                        mutate { root -> values.forEach { (key, value) -> root.getJSONObject(key).put(target, value) } }
                    }
                    EditorText(language, tr(language, "Symbol", "Символ"), json.getString("symbol")) {
                        mutate { root -> root.put("symbol", it) }
                    }
                    Choice(tr(language, "Platzierung", "Розташування"), json.getString("placement"),
                        listOf("start", "life", "support").map { it to it }, "directory-editor-placement") {
                        mutate { root -> root.put("placement", it) }
                    }
                    LabeledSwitch(tr(language, "Verbergen", "Приховати"), json.getBoolean("isHidden")) {
                        mutate { root -> root.put("isHidden", it) }
                    }
                    Text(tr(language, "Unterbereiche", "Підрозділи"), style = MaterialTheme.typography.titleMedium)
                    (0 until groups.length()).forEach { i ->
                        Row {
                            TextButton({ pane = "group:$i" }, Modifier.weight(1f).testTag("directory-editor-open-group-$i")) {
                                Text(groups.getJSONObject(i).getJSONObject("title")
                                    .getString(if (language == "uk") "ukrainian" else "german")
                                    .ifBlank { tr(language, "Neuer Unterbereich", "Новий підрозділ") })
                            }
                            MoveButtons(i, groups.length()) { delta ->
                                mutate { root -> root.put("groups", moved(root.getJSONArray("groups"), i, delta)) }
                            }
                        }
                    }
                    OutlinedButton({ mutate { it.getJSONArray("groups").put(newGroup(groups.length())) } }) {
                        Text(tr(language, "Unterbereich hinzufügen", "Додати підрозділ"))
                    }
                    Text(tr(language, "Beiträge", "Статті"), style = MaterialTheme.typography.titleMedium)
                    (0 until topics.length()).forEach { i ->
                        Row {
                            TextButton({ pane = "topic:$i" }, Modifier.weight(1f).testTag("directory-editor-open-topic-$i")) {
                                Text(topics.getJSONObject(i).getJSONObject("title")
                                    .getString(if (language == "uk") "ukrainian" else "german")
                                    .ifBlank { tr(language, "Neuer Beitrag", "Нова стаття") })
                            }
                            MoveButtons(i, topics.length()) { delta ->
                                mutate { root -> root.put("topics", moved(root.getJSONArray("topics"), i, delta)) }
                            }
                        }
                    }
                    OutlinedButton({
                        mutate { it.getJSONArray("topics").put(newTopic(
                            "topic-${UUID.randomUUID().toString().take(8)}",
                            groups.getJSONObject(0).getString("id"), topics.length())) }
                        pane = "topic:${topics.length()}"
                    }) { Text(tr(language, "Beitrag hinzufügen", "Додати статтю")) }
                }
            }
        }
        item("actions") {
            UacCard {
                Button({
                    val submission = DirectoryDraftValidation.normalizedPayload(draft)
                    val issue = DirectoryDraftValidation.firstIssue(submission)
                    if (issue != null) {
                        error = DirectoryDraftValidation.firstIssueDescription(submission, language)
                    } else {
                        busy = true
                        scope.launch {
                            error = runCatching {
                                access.publish(draftId, submission, expectedRevision)
                            }.fold({ revision ->
                                expectedRevision = revision
                                draft = submission
                                baseline = submission
                                onOpen("directory/manage")
                                null
                            }, { tr(language, "Veröffentlichen fehlgeschlagen. Revision oder Berechtigung prüfen.",
                                "Не вдалося опублікувати. Перевірте ревізію або права.") })
                            busy = false
                        }
                    }
                }, enabled = !busy && draft != baseline, modifier = Modifier.testTag("directory-publish")) {
                    Text(tr(language, "Veröffentlichen", "Опублікувати"))
                }
                if (draft != baseline) OutlinedButton({ draft = baseline; pane = "category" }, enabled = !busy) {
                    Text(tr(language, "Änderungen verwerfen", "Відкинути зміни"))
                }
                if (draftId.startsWith("custom-") && expectedRevision > 0) {
                    TextButton({ confirmDelete = true }, enabled = !busy) {
                        Text(tr(language, "Bereich löschen", "Видалити розділ"))
                    }
                    if (confirmDelete) {
                        Text(tr(language, "Bereich und Inhalt dauerhaft entfernen?", "Назавжди видалити розділ і матеріали?"))
                        OutlinedButton({ confirmDelete = false }) { Text(tr(language, "Abbrechen", "Скасувати")) }
                        Button({
                            busy = true
                            scope.launch {
                                error = runCatching { access.delete(draftId, expectedRevision) }.fold({
                                    onOpen("directory/manage")
                                    null
                                }, { tr(language, "Löschen fehlgeschlagen.", "Не вдалося видалити.") })
                                busy = false
                                confirmDelete = false
                            }
                        }) { Text(tr(language, "Endgültig löschen", "Видалити назавжди")) }
                    }
                }
            }
        }
    }
}

@Composable
private fun DirectoryManagementList(language: String, categories: List<DirectoryCategory>, onOpen: (String) -> Unit) {
    LazyColumn(Modifier.fillMaxSize().testTag("directory-management"),
        contentPadding = PaddingValues(UacDesign.pageInset), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { UacSectionHeading(tr(language, "Ratgeber verwalten", "Керування довідником"), UacIcon.EDIT) }
        listOf("start", "life", "support").forEach { placement ->
            item("placement:$placement") { Text(placement, style = MaterialTheme.typography.titleMedium) }
            items(categories.filter { it.placement == placement }, key = { it.id }) { category ->
                UacCard {
                    Text(category.title.forLanguage(language))
                    if (category.hidden) Text(tr(language, "Verborgen", "Приховано"))
                    TextButton({ onOpen("directory/manage/${category.id}") }) {
                        Text(tr(language, "Bearbeiten", "Редагувати"))
                    }
                }
            }
            item("add:$placement") {
                OutlinedButton({ onOpen("directory/manage/new-$placement") }) {
                    Text(tr(language, "Bereich hinzufügen", "Додати розділ"))
                }
            }
        }
    }
}

@Composable
private fun BilingualEditor(language: String, label: String, text: JSONObject,
                            multiline: Boolean = false, tag: String? = null,
                            onChange: (String, String) -> Unit) {
    Text(label, style = MaterialTheme.typography.titleMedium)
    EditorText(language, "$label · Українська", text.getString("ukrainian"), multiline,
        tag?.let { "$it-uk" }) { onChange("ukrainian", it) }
    EditorText(language, "$label · Deutsch", text.getString("german"), multiline,
        tag?.let { "$it-de" }) { onChange("german", it) }
}

private data class DirectoryTranslationEntry(
    val key: String,
    val label: String,
    val text: JSONObject,
    val limit: Int,
)

@Composable
private fun DirectoryTranslationControls(
    identity: String,
    language: String,
    entries: List<DirectoryTranslationEntry>,
    onApply: (Map<String, String>, String) -> Unit,
) {
    var source by rememberSaveable(identity) { mutableStateOf("uk") }
    Choice(tr(language, "Sprache des Originals", "Мова оригіналу"), source,
        listOf("uk" to "Українська", "de" to "Deutsch"), "directory-translation-source") {
        source = it
    }
    val from = if (source == "uk") "ukrainian" else "german"
    val to = if (source == "uk") "german" else "ukrainian"
    ContentTranslationButton(
        kind = "directory",
        language = language,
        fields = entries.map {
            TranslationField(it.key, it.label, it.text.optString(from), it.text.optString(to), it.limit)
        },
        enabled = true,
        sourceLanguage = source,
    ) { values -> onApply(values, to) }
}

@Composable
private fun EditorText(language: String, label: String, value: String,
                       multiline: Boolean = false, tag: String? = null,
                       onBlur: (() -> Unit)? = null,
                       onChange: (String) -> Unit) {
    OutlinedTextField(value, onChange, label = { Text(label) },
        modifier = Modifier.fillMaxWidth().then(if (tag == null) Modifier else Modifier.testTag(tag))
            .then(if (onBlur == null) Modifier else Modifier.onFocusChanged { if (!it.isFocused) onBlur() }),
        singleLine = !multiline, minLines = if (multiline) 3 else 1)
}

@Composable
private fun SourceEditor(language: String, source: JSONObject, tag: String? = null,
                         onChange: (String, String) -> Unit) {
    EditorText(language, tr(language, "Quellenname", "Назва джерела"), source.optString("name"),
        tag = tag?.let { "$it-name" }) {
        onChange("name", it)
    }
    EditorText(language, tr(language, "Webadresse · z. B. serlest.com", "Вебадреса · напр. serlest.com"),
        source.optString("url"), tag = tag?.let { "$it-url" },
        onBlur = {
            val raw = source.optString("url")
            val canonical = DirectoryDraftValidation.canonicalSourceUrl(raw)
            if (canonical != null && canonical != raw) onChange("url", canonical)
        }) {
        onChange("url", it)
    }
}

@Composable
private fun LabeledSwitch(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Column { Text(label); Switch(checked, onChange) }
}

@Composable
private fun MoveButtons(index: Int, size: Int, onMove: (Int) -> Unit) {
    TextButton({ onMove(-1) }, enabled = index > 0) { Text("↑") }
    TextButton({ onMove(1) }, enabled = index < size - 1) { Text("↓") }
}

private fun moved(array: JSONArray, index: Int, delta: Int): JSONArray {
    val values = (0 until array.length()).map(array::getJSONObject).toMutableList()
    val target = index + delta
    if (index !in values.indices || target !in values.indices) return array
    java.util.Collections.swap(values, index, target)
    return JSONArray().also { result ->
        values.forEachIndexed { rank, value -> result.put(value.put("order", rank)) }
    }
}

private fun sectionAt(root: JSONObject, topic: Int, section: Int, region: String?): JSONObject {
    val item = root.getJSONArray("topics").getJSONObject(topic)
    val list = if (region == null) item.getJSONArray("sections")
        else item.getJSONObject("regionalSections").getJSONArray(region)
    return list.getJSONObject(section)
}

private fun bilingual() = JSONObject().put("ukrainian", "").put("german", "")

private fun newSection(id: String, order: Int) = JSONObject()
    .put("id", id).put("order", order).put("isHidden", false)
    .put("title", bilingual()).put("body", bilingual()).put("symbol", "doc.text")
    .put("phoneNumber", JSONObject.NULL).put("source", JSONObject.NULL)
    .put("contacts", JSONArray())

private fun newGroup(order: Int) = JSONObject()
    .put("id", "group-${UUID.randomUUID().toString().take(8)}")
    .put("order", order).put("isHidden", false).put("title", bilingual())

private fun newTopic(id: String, groupId: String, order: Int) = JSONObject()
    .put("id", id).put("groupID", groupId).put("order", order).put("isHidden", false)
    .put("title", bilingual()).put("summary", bilingual())
    .put("sections", JSONArray().put(newSection("section-${UUID.randomUUID().toString().take(8)}", 0)))
    .put("sources", JSONArray()).put("regionalSections", JSONObject())

private fun newCategoryJson(id: String, placement: String): JSONObject {
    val group = newGroup(0)
    return JSONObject().put("id", id).put("placement", placement).put("order", 100)
        .put("isHidden", false).put("title", bilingual()).put("summary", bilingual())
        .put("symbol", "book.closed").put("groups", JSONArray().put(group))
        .put("topics", JSONArray().put(newTopic("topic-${UUID.randomUUID().toString().take(8)}",
            group.getString("id"), 0)))
}
