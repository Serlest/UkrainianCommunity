package at.uac.android.feature.donationsettings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.core.ProtectedAlertDialog
import at.uac.android.feature.browse.tr
import at.uac.android.feature.moderation.ModerationSession

@Composable
fun DonationSettingsScreen(
    model: DonationSettingsViewModel,
    session: ModerationSession?,
    language: String,
    onBack: () -> Unit,
) {
    val state by model.state.collectAsState()
    LaunchedEffect(session) { model.load(session, force = true) }
    DonationSettingsContent(
        state.takeIf { it.session == session } ?: DonationSettingsState(),
        language,
        model::edit,
        model::save,
        { model.load(session, true) },
        { model.requestLeave(onBack) },
        model::cancelLeave,
        model::discardAndLeave,
    )
}

@Composable
fun DonationSettingsContent(
    state: DonationSettingsState,
    language: String,
    onEdit: (DonationDraft) -> Unit,
    onSave: () -> Unit,
    onRefresh: () -> Unit,
    onBack: () -> Unit,
    onCancelLeave: () -> Unit,
    onDiscard: () -> Unit,
) {
    val allowed = state.session?.let { it.ready && it.role == "owner" } == true
    val editable =
        allowed && state.baseline != null && !state.loading && !state.saving && !state.needsReadback
    LazyColumn(
        Modifier.fillMaxSize().testTag("donation-settings"),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            TextButton(onBack, enabled = !state.saving) { Text(tr(language, "Zurück", "Назад")) }
            Text(
                tr(language, "Projektunterstützung verwalten", "Керування підтримкою проєкту"),
                style = MaterialTheme.typography.headlineSmall,
            )
        }
        if (!allowed)
            item {
                Text(
                    tr(
                        language,
                        "Nur für den bestätigten App-Inhaber verfügbar.",
                        "Доступно лише підтвердженому власнику застосунку.",
                    )
                )
            }
        else {
            if (state.loading || state.saving)
                item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            state.problem?.let { problem ->
                item {
                    Text(
                        donationProblemText(problem, language),
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.testTag("donation-error"),
                    )
                }
            }
            if (state.saved && state.problem != DonationProblem.SAVED_REFRESH_FAILED)
                item {
                    Text(
                        tr(language, "Änderungen gespeichert.", "Зміни збережено."),
                        Modifier.testTag("donation-saved"),
                    )
                }
            if (state.baseline != null) {
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(
                            Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                tr(
                                    language,
                                    "Öffentliche Karte anzeigen",
                                    "Показувати публічну картку",
                                ),
                                style = MaterialTheme.typography.titleMedium,
                            )
                            Switch(
                                state.draft.enabled,
                                { onEdit(state.draft.copy(enabled = it)) },
                                enabled = editable,
                                modifier = Modifier.testTag("donation-enabled"),
                            )
                            OutlinedTextField(
                                state.draft.url,
                                { onEdit(state.draft.copy(url = it)) },
                                label = { Text(tr(language, "HTTPS-Link", "HTTPS-посилання")) },
                                isError =
                                    state.draft.url.isNotBlank() &&
                                        !DonationDraft(url = state.draft.url).valid(),
                                supportingText = {
                                    Text(
                                        tr(
                                            language,
                                            "Vollständige Adresse, z. B. https://example.org",
                                            "Повна адреса, наприклад https://example.org",
                                        )
                                    )
                                },
                                enabled = editable,
                                modifier = Modifier.fillMaxWidth().testTag("donation-url"),
                            )
                        }
                    }
                }
                for (locale in listOf("UK", "DE")) item("locale-$locale") {
                    Card(Modifier.fillMaxWidth()) {
                        Column(
                            Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Text(
                                if (locale == "UK") "Українська" else "Deutsch",
                                style = MaterialTheme.typography.titleLarge,
                            )
                            for (field in listOf("title", "message", "buttonTitle")) {
                                val key = field + locale
                                val label =
                                    when (field) {
                                        "title" -> tr(language, "Titel", "Заголовок")
                                        "message" -> tr(language, "Beschreibung", "Опис")
                                        else -> tr(language, "Schaltflächentext", "Текст кнопки")
                                    }
                                OutlinedTextField(
                                    state.draft.texts[key].orEmpty(),
                                    {
                                        onEdit(
                                            state.draft.copy(
                                                texts = state.draft.texts + (key to it)
                                            )
                                        )
                                    },
                                    label = { Text(label) },
                                    enabled = editable,
                                    isError =
                                        state.draft.texts[key].orEmpty().length >
                                            if (field == "message") 4000 else 200,
                                    supportingText = {
                                        Text(
                                            "${state.draft.texts[key].orEmpty().length} / ${if (field == "message") 4000 else 200}"
                                        )
                                    },
                                    minLines = if (field == "message") 3 else 1,
                                    modifier = Modifier.fillMaxWidth().testTag("donation-$key"),
                                )
                            }
                        }
                    }
                }
                item {
                    Button(
                        onSave,
                        enabled = editable && state.dirty && state.draft.valid(),
                        modifier = Modifier.fillMaxWidth().testTag("donation-save"),
                    ) {
                        Text(tr(language, "Speichern", "Зберегти"))
                    }
                }
            }
            item {
                OutlinedButton(
                    onRefresh,
                    enabled =
                        !state.loading && !state.saving && (!state.dirty || state.needsReadback),
                    modifier = Modifier.fillMaxWidth().testTag("donation-refresh"),
                ) {
                    Text(tr(language, "Serverstand laden", "Завантажити стан із сервера"))
                }
            }
        }
    }
    if (state.confirmLeave)
        ProtectedAlertDialog(
            onDismissRequest = onCancelLeave,
            title = {
                Text(
                    tr(
                        language,
                        "Ungespeicherte Änderungen verwerfen?",
                        "Відхилити незбережені зміни?",
                    )
                )
            },
            text = {
                Text(
                    tr(
                        language,
                        "Änderungen an der Unterstützungskarte gehen verloren.",
                        "Зміни картки підтримки буде втрачено.",
                    )
                )
            },
            confirmButton = {
                TextButton(onDiscard) { Text(tr(language, "Verwerfen", "Відхилити")) }
            },
            dismissButton = {
                TextButton(onCancelLeave) {
                    Text(tr(language, "Weiter bearbeiten", "Продовжити редагування"))
                }
            },
        )
}

private fun donationProblemText(problem: DonationProblem, language: String) =
    when (problem) {
        DonationProblem.ACCESS ->
            tr(
                language,
                "Inhaberzugriff konnte nicht bestätigt werden.",
                "Не вдалося підтвердити доступ власника.",
            )
        DonationProblem.INVALID ->
            tr(
                language,
                "Bitte prüfe den HTTPS-Link und die Texte.",
                "Перевірте HTTPS-посилання та тексти.",
            )
        DonationProblem.CONFLICT ->
            tr(
                language,
                "Die Einstellungen wurden inzwischen geändert. Lade den Serverstand.",
                "Налаштування вже змінилися. Завантажте стан із сервера.",
            )
        DonationProblem.UNCONFIRMED ->
            tr(
                language,
                "Das Ergebnis ist noch nicht bestätigt. Lade den Serverstand, bevor du erneut speicherst.",
                "Результат ще не підтверджено. Завантажте стан із сервера перед повторним збереженням.",
            )
        DonationProblem.SAVED_REFRESH_FAILED ->
            tr(
                language,
                "Gespeichert, aber die Aktualisierung ist fehlgeschlagen. Lade den Serverstand erneut.",
                "Збережено, але оновити дані не вдалося. Повторно завантажте стан із сервера.",
            )
        DonationProblem.LOAD ->
            tr(
                language,
                "Die Einstellungen konnten nicht geladen werden.",
                "Не вдалося завантажити налаштування.",
            )
    }
