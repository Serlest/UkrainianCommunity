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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
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
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            tr(
                language,
                "Suche, Filter, Zahlen und Sortierung gelten nur für geladene Anfragen.",
                "Пошук, фільтри, кількість і сортування стосуються лише завантажених звернень.",
            ),
            Modifier.testTag("feedback-inbox-scope"),
            style = MaterialTheme.typography.bodySmall,
        )
        Text(
            tr(
                language,
                "Geladen: ${selection.loadedCount} · Treffer: ${selection.items.size}",
                "Завантажено: ${selection.loadedCount} · Знайдено: ${selection.items.size}",
            ),
            Modifier.testTag("feedback-inbox-count"),
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FeedbackInboxFilter.entries.forEach { filter ->
                FilterChip(
                    state.inbox.filter == filter,
                    { onFilter(filter) },
                    { Text("${filter.label(language)} ${selection.counts[filter] ?: 0}") },
                    modifier = Modifier.testTag("feedback-inbox-filter-${filter.name}"),
                )
            }
        }
        Text(tr(language, "Letzte Aktivität", "Остання активність"))
        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            FeedbackInboxSort.entries.forEach { sort ->
                FilterChip(
                    state.inbox.sort == sort,
                    { onSort(sort) },
                    {
                        Text(
                            if (sort == FeedbackInboxSort.NEWEST)
                                tr(language, "Neueste zuerst", "Спочатку новіші")
                            else tr(language, "Älteste zuerst", "Спочатку давніші")
                        )
                    },
                    modifier = Modifier.testTag("feedback-inbox-sort-${sort.name}"),
                )
            }
        }
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
            supportingText = {
                Text(
                    if (state.inboxQueryRejected)
                        tr(
                            language,
                            "Eingabe nicht übernommen: maximal 200 Zeichen, gültiger Unicode.",
                            "Введення не прийнято: до 200 символів, коректний Unicode.",
                        )
                    else "${state.inbox.query.length} / ${FeedbackInboxSelector.MAX_QUERY_LENGTH}"
                )
            },
        )
        if (state.inbox.query.isNotEmpty() || state.inboxQueryRejected)
            TextButton({ onSearch("") }, Modifier.testTag("feedback-inbox-search-clear")) {
                Text(tr(language, "Suche löschen", "Очистити пошук"))
            }
        if (selection.hasMore)
            Text(
                tr(
                    language,
                    "Weitere Anfragen sind noch nicht geladen. Unten kannst du mehr laden — auch ohne Treffer.",
                    "Є ще незавантажені звернення. Унизу можна завантажити ще — навіть якщо нічого не знайдено.",
                ),
                Modifier.testTag("feedback-inbox-partial"),
                style = MaterialTheme.typography.bodySmall,
            )
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
