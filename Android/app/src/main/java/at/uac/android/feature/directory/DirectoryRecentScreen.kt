package at.uac.android.feature.directory

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.style.TextOverflow
import at.uac.android.design.UacSymbol
import at.uac.android.design.UacCard
import at.uac.android.design.UacDesign
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.feature.browse.localizedRegionName
import at.uac.android.feature.browse.tr
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

@Composable
fun DirectoryRecentScreen(state: DirectoryRecentState, language: String, onOpen: (String) -> Unit,
    onMore: () -> Unit, onRetry: () -> Unit, onRefresh: () -> Unit) {
    LazyColumn(Modifier.fillMaxSize().testTag("directory-recent-list"),
        contentPadding = PaddingValues(start = UacDesign.pageInset, end = UacDesign.pageInset, bottom = 36.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        directoryRecentItems(state, language, onOpen, onMore, onRetry, onRefresh)
    }
}

internal fun LazyListScope.directoryRecentItems(state: DirectoryRecentState, language: String,
    onOpen: (String) -> Unit, onMore: () -> Unit, onRetry: () -> Unit, onRefresh: () -> Unit, preview: Boolean = false) {
    val formatter = DateTimeFormatter.ofPattern("dd.MM.yyyy · HH:mm", if (language == "uk") Locale.forLanguageTag("uk") else Locale.GERMAN)
        .withZone(ZoneId.of("Europe/Vienna"))
    item("directory-recent-heading") {
        Column(Modifier.testTag("directory-recent-heading"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            UacSectionHeading(tr(language, "Zuletzt hinzugefügt", "Останнє додане"), UacIcon.HISTORY)
            if (!preview) Text(tr(language, "Neue Themen und Abschnitte aus allen Bereichen und Bundesländern.",
                "Нові теми й блоки з усіх розділів і федеральних земель."), style = MaterialTheme.typography.bodyMedium)
            if (!preview) TextButton(onRefresh, enabled = !state.loading, modifier = Modifier.testTag("directory-recent-refresh")) {
                Text(tr(language, "Aktualisieren", "Оновити"))
            }
        }
    }
    if (preview && state.items.isNotEmpty()) item("directory-recent-preview") {
        UacCard(Modifier.testTag("directory-recent-preview")) {
            Column {
                state.items.take(3).forEachIndexed { index, entry ->
                    if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .65f))
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp)
                        .clickable(role = Role.Button) { onOpen(entry.destination) }
                        .semantics(mergeDescendants = true) {}
                        .testTag("directory-recent-${entry.id}")
                        .padding(vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(entry.title.forLanguage(language), Modifier.weight(1f),
                            style = MaterialTheme.typography.bodyMedium, maxLines = 1,
                            overflow = TextOverflow.Ellipsis)
                        UacSymbol(UacIcon.BACK, modifier = Modifier.size(18.dp).rotate(180f))
                    }
                }
            }
        }
    }
    if (!preview) items(state.items, key = { "recent:${it.id}" }) { item ->
        UacCard(Modifier.fillMaxWidth().clickable(role = Role.Button) { onOpen(item.destination) }
            .testTag("directory-recent-${item.id}")) {
            val kind = if (item.kind == "topic") tr(language, "Neues Thema", "Нова тема")
                else tr(language, "Neuer Abschnitt", "Новий блок")
            val region = item.federalState?.let { localizedRegionName(it, language) }
                ?: tr(language, "Ganz Österreich", "Уся Австрія")
            Text(listOfNotNull(kind, region).joinToString(" · "), style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary)
            Text(item.title.forLanguage(language), style = MaterialTheme.typography.titleMedium,
                maxLines = 3, overflow = TextOverflow.Ellipsis)
            val context = if (item.kind == "section") listOf(item.categoryTitle, item.topicTitle) else listOf(item.categoryTitle)
            Text(context.joinToString(" · ") { it.forLanguage(language) }, style = MaterialTheme.typography.bodySmall,
                maxLines = 3, overflow = TextOverflow.Ellipsis,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(formatter.format(item.publishedAt), style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
    if (state.loading) item("directory-recent-loading") {
        CircularProgressIndicator(Modifier.padding(12.dp).testTag("directory-recent-loading"))
    }
    if (state.failed) item("directory-recent-failed") {
        UacCard(Modifier.testTag("directory-recent-error")) {
            Text(tr(language, "Neue Einträge konnten nicht geladen werden. Bitte erneut versuchen.",
                "Не вдалося завантажити нові записи. Спробуйте ще раз."))
            TextButton(onRetry, modifier = Modifier.testTag("directory-recent-retry")) {
                Text(tr(language, "Erneut versuchen", "Спробувати ще раз"))
            }
        }
    }
    if (state.loaded && state.items.isEmpty() && !state.loading && !state.failed && !state.hasMore) item("directory-recent-empty") {
        Text(tr(language, "Noch keine neuen Veröffentlichungen. Neue Themen und Abschnitte erscheinen hier nach ihrer Veröffentlichung.",
            "Нових публікацій поки немає. Нові теми й блоки з’являться тут після публікації."),
            modifier = Modifier.testTag("directory-recent-empty"))
    }
    if (preview && (state.items.size > 3 || state.hasMore)) item("directory-recent-show-all") {
        TextButton({ onOpen("directory/recent") }, modifier = Modifier.heightIn(min = 48.dp).testTag("directory-recent-show-all")) {
            Text(tr(language, "Mehr anzeigen", "Показати більше"))
        }
    }
    if (!preview && state.hasMore && !state.loading && !state.failed) item("directory-recent-more") {
        TextButton(onMore, modifier = Modifier.testTag("directory-recent-more")) {
            Text(tr(language, "Weitere laden", "Завантажити ще"))
        }
    }
}

/** Visibility is re-evaluated against the current reader, never inferred from a historical feed title. */
fun directoryTargetAvailable(categories: List<DirectoryCategory>, target: DirectoryRoute): Boolean {
    val category = categories.firstOrNull { it.id == target.category && it.visible } ?: return false
    val topic = category.visibleTopic(target.topic ?: return true) ?: return false
    if (target.section == null) return true
    val sections = if (target.region == null) topic.sections else topic.regionalSections[target.region].orEmpty()
    return sections.any { it.id == target.section && !it.hidden }
}
