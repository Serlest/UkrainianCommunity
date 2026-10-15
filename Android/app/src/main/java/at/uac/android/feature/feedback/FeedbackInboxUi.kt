package at.uac.android.feature.feedback

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import at.uac.android.design.UacCard
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSymbol
import at.uac.android.feature.browse.tr

@Composable
internal fun FeedbackInboxControls(
    state: FeedbackState,
    selection: FeedbackInboxSelection,
    language: String,
    onSearch: (String) -> Unit,
    onFilter: (FeedbackInboxFilter) -> Unit,
    onSort: (FeedbackInboxSort) -> Unit,
) {
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    var expanded by rememberSaveable { mutableStateOf(false) }
    UacCard(Modifier.testTag("feedback-inbox-controls")) {
        Text(
            tr(
                language,
                "${selection.items.size} von ${selection.loadedCount} geladenen Anfragen",
                "${selection.items.size} із ${selection.loadedCount} завантажених звернень",
            ),
            Modifier.testTag("feedback-inbox-count"),
            style = MaterialTheme.typography.labelLarge,
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            listOf(FeedbackInboxFilter.ALL, FeedbackInboxFilter.OPEN,
                FeedbackInboxFilter.ANSWERED).forEach { filter ->
                FilterChip(
                    state.inbox.filter == filter,
                    { onFilter(filter) },
                    { Text("${filter.label(language)} ${selection.counts[filter] ?: 0}") },
                    modifier = Modifier.testTag("feedback-inbox-filter-${filter.name}"),
                )
            }
        }
        if (state.inbox.filter in setOf(FeedbackInboxFilter.CLOSED, FeedbackInboxFilter.UNKNOWN))
            FilterChip(true, { expanded = true },
                { Text(state.inbox.filter.label(language)) },
                modifier = Modifier.testTag("feedback-inbox-active-secondary"))
        OutlinedTextField(
            state.inbox.query,
            { value ->
                // IME/selection synchronization may emit the unchanged accepted text after a
                // rejected paste. It is not a new edit and must not erase the rejection notice.
                if (value != state.inbox.query) onSearch(value)
            },
            Modifier.fillMaxWidth().testTag("feedback-inbox-search"),
            label = {
                Text(
                    tr(language, "Geladene Anfragen durchsuchen", "Пошук у завантажених зверненнях")
                )
            },
            singleLine = true,
            leadingIcon = { UacSymbol(UacIcon.SEARCH) },
            isError = state.inboxQueryRejected,
            keyboardOptions =
                KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    imeAction = ImeAction.Search,
                ),
            keyboardActions =
                KeyboardActions(
                    onSearch = {
                        focus.clearFocus()
                        keyboard?.hide()
                    }
                ),
            supportingText = if (state.inboxQueryRejected) ({
                Text(tr(language,
                    "Eingabe nicht übernommen: maximal 200 Zeichen, gültiger Unicode.",
                    "Введення не прийнято: до 200 символів, коректний Unicode."))
            }) else null,
        )
        if (state.inbox.query.isNotEmpty() || state.inboxQueryRejected)
            TextButton({ onSearch("") }, Modifier.testTag("feedback-inbox-search-clear")) {
                Text(tr(language, "Suche löschen", "Очистити пошук"))
            }
        TextButton({ expanded = !expanded }, Modifier.testTag("feedback-inbox-more-filters")) {
            Text(if (expanded) tr(language, "Weniger Optionen", "Менше параметрів")
                else tr(language, "Weitere Filter und Sortierung", "Інші фільтри та сортування"))
        }
        if (expanded) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf(FeedbackInboxFilter.CLOSED, FeedbackInboxFilter.UNKNOWN).forEach { filter ->
                    FilterChip(state.inbox.filter == filter, { onFilter(filter) },
                        { Text("${filter.label(language)} ${selection.counts[filter] ?: 0}") },
                        modifier = Modifier.testTag("feedback-inbox-filter-${filter.name}"))
                }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                FeedbackInboxSort.entries.forEach { sort ->
                    FilterChip(state.inbox.sort == sort, { onSort(sort) },
                        { Text(if (sort == FeedbackInboxSort.NEWEST)
                            tr(language, "Neueste zuerst", "Спочатку новіші")
                        else tr(language, "Älteste zuerst", "Спочатку давніші")) },
                        modifier = Modifier.testTag("feedback-inbox-sort-${sort.name}"))
                }
            }
            Text(
                tr(
                    language,
                    "Suche, Filter und Zahlen gelten nur für geladene Anfragen.",
                    "Пошук, фільтри та кількість стосуються лише завантажених звернень.",
                ),
                Modifier.testTag("feedback-inbox-scope"),
                style = MaterialTheme.typography.bodySmall,
            )
        }
        if (selection.hasMore)
            Text(tr(language, "Weitere Anfragen unten laden", "Інші звернення — завантажити внизу"),
                Modifier.testTag("feedback-inbox-partial"),
                style = MaterialTheme.typography.bodySmall)
    }
}

private fun FeedbackInboxFilter.label(language: String): String =
    when (this) {
        FeedbackInboxFilter.OPEN -> tr(language, "Offen", "Відкриті")
        FeedbackInboxFilter.ANSWERED -> tr(language, "Beantwortet", "З відповіддю")
        FeedbackInboxFilter.CLOSED -> tr(language, "Geschlossen", "Закриті")
        FeedbackInboxFilter.UNKNOWN -> tr(language, "Unbekannt", "Невідомий стан")
        FeedbackInboxFilter.ALL -> tr(language, "Alle", "Усі")
    }
