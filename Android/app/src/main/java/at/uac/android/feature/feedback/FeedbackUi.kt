package at.uac.android.feature.feedback

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.feature.browse.displayTime
import at.uac.android.feature.browse.tr

@Composable
fun FeedbackDestination(
    audience: FeedbackAudience,
    id: String?,
    language: String,
    snapshot: FeedbackState,
    model: FeedbackViewModel,
    onOpen: (String) -> Unit,
    onAccount: () -> Unit,
    onReadDecision: ((String) -> Unit)? = null,
) {
    val state =
        if (snapshot.audience == audience && snapshot.selectedId == id) snapshot
        else
            FeedbackState(
                session = snapshot.session,
                audience = audience,
                selectedId = id,
                loading = true,
            )
    LifecycleResumeEffect(audience, id, state.session) {
        model.show(audience, id)
        onPauseOrDispose { model.hide(audience, id) }
    }
    val canRead =
        state.session != null && (audience == FeedbackAudience.OWN || state.session.canManage)
    if (!canRead) {
        Column(
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier.testTag("feedback-account-gate"),
        ) {
            Text(
                tr(
                    language,
                    "Für diesen Bereich ist ein berechtigtes Konto erforderlich.",
                    "Для цього розділу потрібен обліковий запис із відповідними правами.",
                )
            )
            OutlinedButton(onAccount) { Text(tr(language, "Zum Konto", "До облікового запису")) }
        }
        return
    }
    if (id == null)
        FeedbackList(
            state,
            language,
            model::draft,
            { model.submit() },
            { more -> model.refresh(more) },
            onOpen,
            onAccount,
            model::inboxSearch,
            model::inboxFilter,
            model::inboxSort,
        )
    else
        FeedbackDetail(
            state,
            language,
            model::reply,
            { model.send() },
            {
                model.send(
                    close = true,
                    closingText =
                        tr(language, "Die Anfrage wurde geschlossen.", "Звернення закрито."),
                )
            },
            { model.refresh() },
            onAccount,
            onReadDecision,
        )
}

@Composable
fun FeedbackList(
    state: FeedbackState,
    language: String,
    onDraft: (FeedbackDraft) -> Unit,
    onSubmit: () -> Unit,
    onRefresh: (Boolean) -> Unit,
    onOpen: (String) -> Unit,
    onAccount: () -> Unit,
    onSearch: (String) -> Unit = {},
    onFilter: (FeedbackInboxFilter) -> Unit = {},
    onSort: (FeedbackInboxSort) -> Unit = {},
) {
    val manager = state.audience == FeedbackAudience.MANAGEMENT
    if (manager && state.session?.canManage != true) {
        Text(
            tr(language, "Der Zugriff wurde verweigert.", "У доступі відмовлено."),
            Modifier.testTag("feedback-inbox-access"),
        )
        return
    }
    val selection =
        remember(state.page, state.inbox, language, manager) {
            if (manager) FeedbackInboxSelector.select(state.page, state.inbox, language) else null
        }
    val visibleItems = selection?.items ?: state.page?.items.orEmpty()
    LazyColumn(
        Modifier.fillMaxSize().testTag("feedback-list"),
        contentPadding = PaddingValues(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item("header") {
            Text(
                if (manager) tr(language, "Support-Postfach", "Скринька підтримки")
                else tr(language, "Meine Anfragen", "Мої звернення"),
                style = MaterialTheme.typography.headlineSmall,
            )
            TextButton(
                { onRefresh(false) },
                Modifier.testTag("feedback-refresh"),
                enabled = !state.loading,
            ) {
                Text(tr(language, "Aktualisieren", "Оновити"))
            }
            FeedbackReadStatus(state, language)
        }
        if (selection != null)
            item("inbox-controls") {
                FeedbackInboxControls(state, selection, language, onSearch, onFilter, onSort)
            }
        if (!manager)
            item("compose") {
                Card(Modifier.fillMaxWidth()) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(
                            tr(language, "Neue Anfrage", "Нове звернення"),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        if (state.session?.ready == true) {
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                FeedbackType.entries.forEach { type ->
                                    FilterChip(
                                        state.draft.type == type,
                                        { onDraft(state.draft.copy(type = type)) },
                                        { Text(type.label(language)) },
                                        enabled = !state.pending && !state.createRetryPending,
                                        modifier = Modifier.testTag("feedback-type-${type.wire}"),
                                    )
                                }
                            }
                            FeedbackTextField(
                                state.draft.message,
                                { onDraft(state.draft.copy(message = it)) },
                                language,
                                !state.pending && !state.createRetryPending,
                                "feedback-draft",
                            )
                            FeedbackActionStatus(state, language)
                            SubmitButton(
                                state.pending,
                                state.draft.valid(),
                                state.createRetryPending,
                                language,
                                "feedback-submit",
                                onSubmit,
                            )
                            if (state.confirmedId != null)
                                TextButton(
                                    { onOpen(state.confirmedId) },
                                    Modifier.testTag("feedback-open-confirmed"),
                                ) {
                                    Text(
                                        tr(
                                            language,
                                            "Bestätigte Anfrage öffnen",
                                            "Відкрити підтверджене звернення",
                                        )
                                    )
                                }
                        } else {
                            Text(
                                tr(
                                    language,
                                    "Deine bisherigen Anfragen bleiben lesbar. Zum Schreiben bitte den Kontostatus prüfen.",
                                    "Попередні звернення залишаються доступними. Щоб написати, перевірте стан облікового запису.",
                                )
                            )
                            TextButton(onAccount) {
                                Text(tr(language, "Kontostatus prüfen", "Перевірити стан акаунта"))
                            }
                        }
                    }
                }
            }
        items(visibleItems, key = { it.id }) { item ->
            Card(
                onClick = { onOpen(item.id) },
                modifier = Modifier.fillMaxWidth().testTag("feedback-item-${item.id}"),
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        item.type?.label(language) ?: tr(language, "Anfrage", "Звернення"),
                        style = MaterialTheme.typography.labelLarge,
                    )
                    item.subject?.takeIf(String::isNotBlank)?.let {
                        Text(it, style = MaterialTheme.typography.titleMedium)
                    }
                    Text(item.preview, maxLines = 4)
                    Text(item.status.label(language), color = MaterialTheme.colorScheme.primary)
                    if (if (manager) item.unreadForOwner else item.unreadForUser)
                        Text(tr(language, "Neue Nachricht", "Нове повідомлення"))
                    if (manager) Text(item.name)
                    Text(
                        displayTime(
                            if (manager) item.lastMessageAt ?: item.updatedAt else item.createdAt,
                            language,
                        ),
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
        if (!state.loading && state.error == null && state.page != null && visibleItems.isEmpty())
            item("empty") {
                Text(
                    if (manager)
                        tr(
                            language,
                            "Keine passenden Anfragen im geladenen Teil.",
                            "У завантаженій частині немає відповідних звернень.",
                        )
                    else tr(language, "Noch keine Anfragen.", "Звернень поки немає."),
                    Modifier.testTag("feedback-empty"),
                )
            }
        if (state.page?.hasMore == true)
            item("more") {
                OutlinedButton(
                    { onRefresh(true) },
                    enabled = !state.loading,
                    modifier = Modifier.testTag("feedback-more"),
                ) {
                    Text(tr(language, "Weitere Anfragen laden", "Завантажити ще звернення"))
                }
            }
    }
}

@Composable
fun FeedbackDetail(
    state: FeedbackState,
    language: String,
    onReply: (String) -> Unit,
    onSend: () -> Unit,
    onClose: () -> Unit,
    onRefresh: () -> Unit,
    onAccount: () -> Unit,
    onReadDecision: ((String) -> Unit)? = null,
) {
    var closing by remember(state.session, state.selectedId) { mutableStateOf(false) }
    val conversation = state.conversation
    val item = conversation?.item
    ProtectFeedbackCaseWindow(item?.hasDsaCase == true)
    LazyColumn(
        Modifier.fillMaxSize().testTag("feedback-conversation"),
        contentPadding = PaddingValues(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        item("header") {
            Text(
                item?.subject?.takeIf(String::isNotBlank)
                    ?: tr(language, "Verlauf der Anfrage", "Історія звернення"),
                style = MaterialTheme.typography.headlineSmall,
            )
            item?.let {
                Text(it.status.label(language))
                it.caseNumber?.let { number ->
                    Text(tr(language, "Fallnummer: ", "Номер справи: ") + number)
                }
            }
            TextButton(
                onRefresh,
                Modifier.testTag("feedback-detail-refresh"),
                enabled = !state.loading,
            ) {
                Text(tr(language, "Aktualisieren", "Оновити"))
            }
            FeedbackReadStatus(state, language)
            if (conversation?.limited == true)
                Text(
                    tr(
                        language,
                        "Die letzten 100 Nachrichten; die ursprüngliche Anfrage bleibt sichtbar.",
                        "Останні 100 повідомлень; початкове звернення залишається видимим.",
                    )
                )
        }
        if (state.canReadCaseContext())
            item("case-context") { FeedbackCaseContextCard(state, language) }
        if (onReadDecision != null && state.canReviewOwnDecision())
            item("read-decision") {
                OutlinedButton(
                    { state.selectedId?.let(onReadDecision) },
                    Modifier.testTag("feedback-read-decision"),
                ) {
                    Text(
                        tr(
                            language,
                            "Entscheidung vor einer Beschwerde prüfen",
                            "Перевірити рішення перед скаргою",
                        )
                    )
                }
            }
        items(conversation?.messages.orEmpty(), key = { "${it.legacy}:${it.id}" }) { message ->
            Card(Modifier.fillMaxWidth().testTag("feedback-message-${message.id}")) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        if (message.owner) tr(language, "Support", "Підтримка") else message.name,
                        style = MaterialTheme.typography.labelLarge,
                    )
                    SelectionContainer { Text(message.text) }
                    Text(
                        displayTime(message.createdAt, language),
                        style = MaterialTheme.typography.labelMedium,
                    )
                }
            }
        }
        if (item != null)
            item("reply") {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    FeedbackActionStatus(state, language)
                    when {
                        item.status == FeedbackStatus.UNKNOWN -> Text(item.status.label(language))
                        item.status.closed ->
                            Text(
                                tr(
                                    language,
                                    "Diese Anfrage ist geschlossen; weitere Antworten sind nicht möglich.",
                                    "Звернення закрито; додаткові відповіді недоступні.",
                                )
                            )
                        state.session?.ready != true ->
                            TextButton(onAccount) {
                                Text(
                                    tr(
                                        language,
                                        "Zum Antworten den Kontostatus prüfen",
                                        "Для відповіді перевірте стан акаунта",
                                    )
                                )
                            }
                        else -> {
                            FeedbackTextField(
                                state.reply,
                                onReply,
                                language,
                                !state.pending && !state.replyRetryPending,
                                "feedback-reply",
                            )
                            SubmitButton(
                                state.pending,
                                state.reply.trim().length in 1..2_000,
                                state.replyRetryPending,
                                language,
                                "feedback-send",
                                onSend,
                            )
                            if (state.audience == FeedbackAudience.MANAGEMENT && !item.hasDsaCase)
                                OutlinedButton(
                                    { closing = true },
                                    enabled = !state.pending,
                                    modifier = Modifier.testTag("feedback-close"),
                                ) {
                                    Text(tr(language, "Anfrage schließen", "Закрити звернення"))
                                }
                            if (item.hasDsaCase)
                                Text(
                                    tr(
                                        language,
                                        "Rechtliche Entscheidungen und Einsprüche sind ein gesonderter, noch nicht freigeschalteter Ablauf.",
                                        "Правові рішення та оскарження — окрема процедура, яка ще не доступна тут.",
                                    )
                                )
                        }
                    }
                }
            }
    }
    if (closing)
        AlertDialog(
            onDismissRequest = { closing = false },
            title = { Text(tr(language, "Anfrage schließen?", "Закрити звернення?")) },
            text = {
                Text(
                    tr(
                        language,
                        "Danach sind keine weiteren Antworten möglich. Der Verlauf bleibt erhalten.",
                        "Після цього відповіді будуть недоступні. Історія збережеться.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        closing = false
                        onClose()
                    },
                    Modifier.testTag("feedback-confirm-close"),
                ) {
                    Text(tr(language, "Schließen", "Закрити"))
                }
            },
            dismissButton = {
                TextButton({ closing = false }) { Text(tr(language, "Abbrechen", "Скасувати")) }
            },
        )
}

@Composable
private fun FeedbackTextField(
    value: String,
    onValue: (String) -> Unit,
    language: String,
    enabled: Boolean,
    tag: String,
) {
    OutlinedTextField(
        value,
        onValue,
        Modifier.fillMaxWidth().testTag(tag),
        enabled = enabled,
        label = { Text(tr(language, "Nachricht", "Повідомлення")) },
        minLines = 3,
        maxLines = 8,
        isError = value.trim().length > 2_000,
        supportingText = { Text("${value.trim().length} / 2000") },
    )
}

@Composable
private fun SubmitButton(
    pending: Boolean,
    valid: Boolean,
    retry: Boolean,
    language: String,
    tag: String,
    onSubmit: () -> Unit,
) {
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    Button(
        {
            focus.clearFocus()
            keyboard?.hide()
            onSubmit()
        },
        enabled = !pending && valid,
        modifier = Modifier.testTag(tag),
    ) {
        Text(
            when {
                pending -> tr(language, "Wird gesendet …", "Надсилаємо …")
                retry -> tr(language, "Ergebnis bestätigen", "Підтвердити результат")
                else -> tr(language, "Senden", "Надіслати")
            }
        )
    }
}

@Composable
private fun FeedbackReadStatus(state: FeedbackState, language: String) {
    if (state.loading) LinearProgressIndicator(Modifier.fillMaxWidth().testTag("feedback-loading"))
    state.error?.let {
        Text(
            it.label(language),
            Modifier.testTag("feedback-error"),
            color = MaterialTheme.colorScheme.error,
        )
    }
    if (
        state.error == FeedbackFailure.OFFLINE && (state.page != null || state.conversation != null)
    )
        Text(
            tr(
                language,
                "Letzter bestätigter Stand dieses Kontos; möglicherweise veraltet.",
                "Останній підтверджений стан цього акаунта; може бути застарілим.",
            )
        )
    val invalid = (state.page?.invalid ?: 0) + (state.conversation?.invalid ?: 0)
    if (invalid > 0)
        Text(
            tr(language, "Ungültige Einträge übersprungen: ", "Пропущено некоректних записів: ") +
                invalid
        )
}

@Composable
private fun FeedbackActionStatus(state: FeedbackState, language: String) {
    state.actionError?.let {
        Text(
            it.label(language),
            Modifier.testTag("feedback-action-error"),
            color = MaterialTheme.colorScheme.error,
        )
    }
    if (state.confirmedId != null)
        Text(
            tr(
                language,
                "Gespeichert und vom Server bestätigt.",
                "Збережено та підтверджено сервером.",
            ),
            Modifier.testTag("feedback-confirmed"),
        )
    if (!state.pending && (state.createRetryPending || state.replyRetryPending))
        Text(
            tr(
                language,
                "Die Nachricht bleibt bis zur Bestätigung unverändert, damit kein Duplikat entsteht.",
                "Повідомлення зберігається без змін до підтвердження, щоб не створити дублікат.",
            )
        )
}

fun FeedbackType.label(l: String): String =
    when (this) {
        FeedbackType.QUESTION -> tr(l, "Frage", "Питання")
        FeedbackType.SUGGESTION -> tr(l, "Idee", "Ідея")
        FeedbackType.BUG -> tr(l, "Fehler", "Помилка")
        FeedbackType.REPORT -> tr(l, "Meldung", "Скарга")
    }

fun FeedbackStatus.label(l: String): String =
    when (this) {
        FeedbackStatus.OPEN -> tr(l, "Wartet auf Antwort", "Очікує відповіді")
        FeedbackStatus.ANSWERED,
        FeedbackStatus.REVIEWED -> tr(l, "Beantwortet", "Є відповідь")
        FeedbackStatus.CLOSED,
        FeedbackStatus.ARCHIVED -> tr(l, "Geschlossen", "Закрито")
        FeedbackStatus.UNKNOWN ->
            tr(l, "Unbekannter Status — nur Lesen", "Невідомий стан — лише перегляд")
    }

fun FeedbackFailure.label(l: String): String =
    when (this) {
        FeedbackFailure.SIGN_IN -> tr(l, "Bitte anmelden.", "Увійдіть в акаунт.")
        FeedbackFailure.NOT_READY ->
            tr(
                l,
                "Bitte Bestätigung, Kontostatus und Sicherheitsfreigaben prüfen.",
                "Перевірте підтвердження, стан акаунта й вимоги безпеки.",
            )
        FeedbackFailure.DENIED -> tr(l, "Der Zugriff wurde verweigert.", "У доступі відмовлено.")
        FeedbackFailure.MISSING ->
            tr(l, "Diese Anfrage ist nicht mehr verfügbar.", "Це звернення більше недоступне.")
        FeedbackFailure.CLOSED ->
            tr(l, "Diese Anfrage ist bereits geschlossen.", "Це звернення вже закрито.")
        FeedbackFailure.INVALID ->
            tr(l, "Ungültige Angaben oder Serverdaten.", "Некоректні дані або відповідь сервера.")
        FeedbackFailure.CONFLICT ->
            tr(
                l,
                "Der gespeicherte Vorgang passt nicht zu dieser Nachricht. Bitte aktualisieren.",
                "Збережена операція не відповідає цьому повідомленню. Оновіть дані.",
            )
        FeedbackFailure.OFFLINE ->
            tr(
                l,
                "Keine bestätigte Verbindung zum Server.",
                "Немає підтвердженого з’єднання із сервером.",
            )
        FeedbackFailure.UNCONFIRMED ->
            tr(
                l,
                "Der Ausgang ist unklar. Erneutes Bestätigen verwendet dieselbe Anfragekennung und erzeugt keine zweite Nachricht.",
                "Результат невідомий. Повторне підтвердження використовує той самий ідентифікатор, без створення дубліката.",
            )
        FeedbackFailure.UNKNOWN ->
            tr(l, "Der Vorgang konnte nicht bestätigt werden.", "Операцію не вдалося підтвердити.")
    }
