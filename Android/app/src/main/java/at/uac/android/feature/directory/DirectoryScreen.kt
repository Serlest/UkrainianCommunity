package at.uac.android.feature.directory

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.core.backend.AppBackend
import androidx.lifecycle.viewmodel.compose.viewModel
import at.uac.android.design.UacCard
import at.uac.android.design.UacDesign
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.feature.browse.Choice
import at.uac.android.feature.browse.SafeLink
import at.uac.android.feature.browse.regions
import at.uac.android.feature.browse.tr

/** Public catalog stays readable from the reviewed bundle while cloud edits sync. */
@Composable
fun DirectoryDestination(
    route: String,
    language: String,
    region: String,
    onRegion: (String) -> Unit,
    onOpen: (String) -> Unit,
    onFeedback: (String?, String?, String) -> Unit,
    editor: DirectoryEditorAccess? = null,
) {
    val context = LocalContext.current
    val content: DirectoryViewModel = viewModel()
    val snapshot by content.snapshot.collectAsState()
    val bundled = content.bundled
    val categories = remember(bundled, snapshot) {
        DirectoryCatalog.merge(bundled, snapshot.published, snapshot.deleted)
    }
    val allCategories = remember(bundled, snapshot) {
        DirectoryCatalog.allMerged(bundled, snapshot.published, snapshot.deleted)
    }
    var editorGranted by remember(editor?.uid) { mutableStateOf(false) }
    DisposableEffect(editor?.uid, editor?.owner) {
        if (editor == null || editor.owner) onDispose { }
        else {
            val listener = AppBackend.firestore(context).collection("directoryEditors")
                .document(editor.uid).addSnapshotListener { result, error ->
                    editorGranted = error == null && result?.getBoolean("enabled") == true
                }
            onDispose { listener.remove() }
        }
    }
    val canEdit = editor != null && (editor.owner || editorGranted)
    val activeEditor = editor?.takeIf { canEdit }
    val parts = route.split('/')
    if (parts.getOrNull(1) == "manage") {
        if (activeEditor != null) {
            DirectoryEditorScreen(parts.getOrNull(2), language, allCategories,
                snapshot.revisions, activeEditor, onOpen)
        } else {
            Text(tr(language, "Zugriff auf die Redaktion nicht verfügbar.",
                "Доступ до редактора недоступний."), Modifier.padding(UacDesign.pageInset))
        }
        return
    }
    val category = parts.getOrNull(1)?.let { id -> categories.firstOrNull { it.id == id } }
    val topic = category?.let { c -> parts.getOrNull(2)?.let(c::visibleTopic) }
    val missing = (parts.size > 1 && category == null) || (parts.size > 2 && topic == null)
    LazyColumn(
        Modifier.fillMaxSize().testTag("directory-list"),
        contentPadding = PaddingValues(start = UacDesign.pageInset, end = UacDesign.pageInset, bottom = 36.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item("directory-status") {
            if (snapshot.status == "failed" || snapshot.invalid > 0)
                Column {
                    Text(
                        tr(language, "Aktuelle Änderungen sind nicht verfügbar. Gespeicherte Inhalte werden angezeigt.",
                            "Актуальні зміни недоступні. Показано збережені матеріали."),
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.testTag("directory-sync-warning"),
                    )
                    if (snapshot.status == "failed") TextButton(content::retry,
                        modifier = Modifier.testTag("directory-retry")) {
                        Text(tr(language, "Erneut versuchen", "Спробувати ще раз"))
                    }
                }
            else if (snapshot.status == "cached")
                Text(tr(language, "Gespeicherte Fassung", "Збережена версія"),
                    style = MaterialTheme.typography.bodySmall)
        }
        if (missing) {
            item("missing") {
                UacCard {
                    Text(tr(language, "Dieser Beitrag ist nicht mehr verfügbar.",
                        "Цей матеріал більше недоступний."))
                    TextButton({ onOpen("directory") }) {
                        Text(tr(language, "Zum Ratgeber", "До довідника"))
                    }
                }
            }
        } else if (topic != null) {
            item("heading") {
                UacSectionHeading(topic.title.forLanguage(language), UacIcon.NEWS)
                Text(category.title.forLanguage(language), color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(topic.summary.forLanguage(language), style = MaterialTheme.typography.bodyLarge)
            }
            items(topic.sections.filterNot { it.hidden }.sortedBy { it.order }, key = { "section:${it.id}" }) { section ->
                DirectorySectionCard(section, language)
            }
            val regional = topic.regionalSections[region].orEmpty().filterNot { it.hidden }.sortedBy { it.order }
            if (topic.regionalSections.isNotEmpty()) {
                item("region") {
                    Choice(tr(language, "Bundesland", "Федеральна земля"), region,
                        listOf("" to tr(language, "Österreich", "Австрія")) + regions,
                        "directory-region", onRegion)
                }
                if (region.isNotEmpty()) {
                    item("region-heading") {
                        UacSectionHeading(tr(language, "In Ihrem Bundesland", "У вашій землі"), UacIcon.LOCATION)
                    }
                    items(regional, key = { "regional:${it.id}" }) { section ->
                        DirectorySectionCard(section, language)
                    }
                }
            }
            if (topic.sources.isNotEmpty()) item("sources") {
                UacCard {
                    UacSectionHeading(tr(language, "Quellen", "Джерела"), UacIcon.OPEN_ARROW)
                    topic.sources.distinctBy { it.url }.forEach { source ->
                        if (source.safeUrl != null) SafeLink(source.name, source.url, language)
                    }
                }
            }
            item("feedback") {
                FeedbackCard(language, tr(language, "Stimmt etwas nicht?", "Є неточність?")) {
                    onFeedback(category.id, topic.id, topic.title.forLanguage(language))
                }
            }
        } else if (category != null) {
            item("heading") {
                UacSectionHeading(category.title.forLanguage(language), UacIcon.NEWS)
                Text(category.summary.forLanguage(language), style = MaterialTheme.typography.bodyLarge)
            }
            category.visibleGroups.forEach { group ->
                item("group:${group.id}") {
                    UacSectionHeading(group.title.forLanguage(language), UacIcon.NEWS)
                }
                items(category.visibleTopics(group.id), key = { "topic:${it.id}" }) { item ->
                    UacCard(Modifier.clickable { onOpen("directory/${category.id}/${item.id}") }
                        .testTag("directory-topic-${item.id}")) {
                        Text(item.title.forLanguage(language), style = MaterialTheme.typography.titleMedium)
                        Text(item.summary.forLanguage(language), maxLines = 3)
                        TextButton({ onOpen("directory/${category.id}/${item.id}") }) {
                            Text(tr(language, "Lesen", "Читати"))
                        }
                    }
                }
            }
            item("feedback") {
                FeedbackCard(language, tr(language, "Fehlt eine Antwort?", "Бракує відповіді?")) {
                    onFeedback(category.id, null, category.title.forLanguage(language))
                }
            }
        } else {
            item("intro") {
                UacSectionHeading(tr(language, "Ratgeber", "Довідник"), UacIcon.NEWS)
                Text(tr(language, "Wichtige Themen für das Leben in Österreich – vom Ankommen bis zum Alltag.",
                    "Важливі теми для життя в Австрії — від перших кроків до щоденних питань."),
                    style = MaterialTheme.typography.bodyLarge)
                if (canEdit) TextButton({ onOpen("directory/manage") }) {
                    Text(tr(language, "Ratgeber verwalten", "Керування довідником"))
                }
            }
            item("search") {
                var query by rememberSaveable { mutableStateOf("") }
                OutlinedTextField(query, { query = it.take(160) },
                    label = { Text(tr(language, "Im Ratgeber suchen", "Пошук у довіднику")) },
                    modifier = Modifier.fillMaxWidth().testTag("directory-search"), singleLine = true)
                val results = remember(query, language, categories) { searchDirectory(categories, query, language) }
                if (query.trim().length >= 2) {
                    if (results.isEmpty())
                        Text(tr(language, "Keine Treffer", "Нічого не знайдено"))
                    results.take(40).forEach { result ->
                        TextButton({ onOpen(result.first) }, Modifier.fillMaxWidth()) {
                            Text(result.second)
                        }
                    }
                }
            }
            listOf("start", "life", "support").forEach { placement ->
                val section = categories.filter { it.placement == placement }
                if (section.isNotEmpty()) {
                    item("placement:$placement") {
                        UacSectionHeading(when (placement) {
                            "start" -> tr(language, "Ankommen in Österreich", "Початок в Австрії")
                            "life" -> tr(language, "Alltag", "Повсякденне життя")
                            else -> tr(language, "Unterstützung und Teilhabe", "Підтримка та участь")
                        }, UacIcon.NEWS)
                    }
                    items(section, key = { "category:${it.id}" }) { item ->
                        UacCard(Modifier.clickable { onOpen("directory/${item.id}") }
                            .testTag("directory-category-${item.id}")) {
                            Text(item.title.forLanguage(language), style = MaterialTheme.typography.titleMedium)
                            Text(item.summary.forLanguage(language), maxLines = 3)
                            TextButton({ onOpen("directory/${item.id}") }) {
                                Text(tr(language, "Bereich öffnen", "Відкрити розділ"))
                            }
                        }
                    }
                }
            }
            item("feedback") {
                FeedbackCard(language, tr(language, "Fehlt eine Antwort?", "Бракує відповіді?")) {
                    onFeedback(null, null, tr(language, "Ratgeber", "Довідник"))
                }
            }
        }
    }
}

@Composable
private fun DirectorySectionCard(section: DirectorySection, language: String) {
    UacCard(Modifier.testTag("directory-section-${section.id}")) {
        Text(section.title.forLanguage(language), style = MaterialTheme.typography.titleMedium)
        Text(section.body.forLanguage(language), style = MaterialTheme.typography.bodyMedium)
        section.phoneNumber?.let { DirectoryPhone(it) }
        section.contacts.forEach { contact ->
            Text(contact.title.forLanguage(language))
            DirectoryPhone(contact.number)
            Text(contact.detail.forLanguage(language), style = MaterialTheme.typography.bodySmall)
        }
        section.source?.takeIf { it.safeUrl != null }?.let { SafeLink(it.name, it.url, language) }
    }
}

@Composable
private fun DirectoryPhone(number: String) {
    if (!Regex("[0-9 +()/-]{1,40}").matches(number)) return
    val context = LocalContext.current
    TextButton({ runCatching {
        context.startActivity(Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", number, null)))
    } }) { Text(number) }
}

@Composable
private fun FeedbackCard(language: String, heading: String, onClick: () -> Unit) {
    UacCard {
        Text(heading, style = MaterialTheme.typography.titleMedium)
        Text(tr(language, "Unser Team prüft die Quellen. Den Status finden Sie in Ihren Anfragen.",
            "Команда перевірить джерела. Статус буде у ваших зверненнях."))
        OutlinedButton(onClick, Modifier.testTag("directory-feedback")) {
            Text(tr(language, "Team kontaktieren", "Написати команді"))
        }
    }
}

private fun searchDirectory(categories: List<DirectoryCategory>, raw: String, language: String): List<Pair<String, String>> {
    val query = raw.trim().lowercase()
    if (query.length < 2) return emptyList()
    val found = mutableListOf<Pair<String, String>>()
    categories.forEach { category ->
        val title = category.title.forLanguage(language)
        if (title.lowercase().contains(query) || category.summary.forLanguage(language).lowercase().contains(query))
            found += "directory/${category.id}" to title
        category.visibleGroups.forEach { group ->
            category.visibleTopics(group.id).forEach { topic ->
                if (topic.title.forLanguage(language).lowercase().contains(query) ||
                    topic.summary.forLanguage(language).lowercase().contains(query) ||
                    topic.sections.any { !it.hidden && (it.title.forLanguage(language).lowercase().contains(query) ||
                        it.body.forLanguage(language).lowercase().contains(query)) })
                    found += "directory/${category.id}/${topic.id}" to
                        "${topic.title.forLanguage(language)} · $title"
            }
        }
    }
    return found
}
