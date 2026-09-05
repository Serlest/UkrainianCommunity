package at.uac.android.feature.history

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.PublicImage
import at.uac.android.feature.browse.displayTime
import at.uac.android.feature.browse.string
import at.uac.android.feature.browse.tr
import java.util.concurrent.atomic.AtomicBoolean

data class HistoryActions(
    val back: () -> Unit = {},
    val account: () -> Unit = {},
    val refresh: () -> Unit = {},
    val more: () -> Unit = {},
    val filter: (HistoryFilter) -> Unit = {},
    val sort: (HistorySort) -> Unit = {},
    val search: (String) -> Unit = {},
    val delete: (Set<String>) -> Unit = {},
    val confirm: () -> Unit = {},
    val cancel: () -> Unit = {},
    val reconcile: () -> Unit = {},
    val open: (HistoryEntry) -> Unit = {},
)

/** Full-height destination; never nest this list inside a vertically unbounded scrolling item. */
@Composable
fun HistoryScreen(
    model: HistoryViewModel,
    section: HistorySection,
    session: HistorySession?,
    language: String,
    onBack: () -> Unit,
    onAccount: () -> Unit,
    onOpen: (Content) -> Unit,
    visibleContent: (Content) -> Boolean,
) {
    val stored by model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    val scoped = stored.forSession(session, section)
    val state =
        scoped.copy(
            page =
                scoped.page?.let { page ->
                    page.copy(
                        entries =
                            page.entries.map {
                                it.copy(content = it.content?.takeIf(visibleContent))
                            }
                    )
                }
        )
    LifecycleResumeEffect(session, section) {
        model.show(section)
        onPauseOrDispose { model.hide() }
    }
    HistoryContent(
        state,
        language,
        HistoryActions(
            onBack,
            onAccount,
            { model.refresh() },
            { model.refresh(true) },
            model::filter,
            model::sort,
            model::search,
            model::requestDelete,
            model::confirmDelete,
            model::cancelDelete,
            model::reconcile,
            { entry ->
                if (entry.content?.let(visibleContent) == true && model.canOpen(entry))
                    onOpen(entry.content)
            },
        ),
    )
}

/**
 * Root's currentTarget must additionally require emulator mode, exact fresh detail and an unlocked
 * application.
 */
@Composable
fun HistoryViewRecorder(
    model: HistoryViewModel,
    content: Content,
    session: HistorySession?,
    visitKey: String,
    language: String,
    currentTarget: () -> Boolean,
) {
    val eligible = rememberUpdatedState(currentTarget)
    LifecycleResumeEffect(session, content.kind, content.id, visitKey) {
        val resumed = AtomicBoolean(true)
        if (session?.ready == true)
            model.recordView(content, visitKey, language) { resumed.get() && eligible.value() }
        onPauseOrDispose { resumed.set(false) }
    }
}

@Composable
fun HistoryContent(state: HistoryState, language: String, actions: HistoryActions) {
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    fun dismissKeyboard() {
        focus.clearFocus()
        keyboard?.hide()
    }
    val page =
        state.page?.takeIf {
            state.visible &&
                state.session?.ready == true &&
                it.session == state.session &&
                it.section == state.section &&
                !state.loading &&
                state.error == null
        }
    val entries =
        page
            ?.let {
                HistoryContract.selected(
                    it.entries,
                    state.filter,
                    state.sort,
                    state.search,
                    language,
                )
            }
            .orEmpty()
    LazyColumn(
        Modifier.fillMaxSize().imePadding().testTag("history-list"),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item("header") {
            TextButton(actions.back, Modifier.testTag("history-back")) {
                Text(tr(language, "Zurück", "Назад"))
            }
            Text(
                if (state.section == HistorySection.RECENT)
                    tr(language, "Zuletzt angesehen", "Нещодавно переглянуте")
                else tr(language, "Meine Aktivitäten", "Мої дії"),
                style = MaterialTheme.typography.headlineMedium,
            )
            Text(
                tr(
                    language,
                    "Nur dein Konto. Suche und Sortierung gelten für die geladenen Einträge.",
                    "Лише ваш акаунт. Пошук і сортування стосуються завантажених записів.",
                )
            )
        }
        if (state.session?.ready != true)
            item("account") {
                Text(
                    historyFailureText(
                        if (state.session == null) HistoryFailure.SIGN_IN
                        else HistoryFailure.NOT_READY,
                        language,
                    )
                )
                Button(actions.account, Modifier.testTag("history-account")) {
                    Text(tr(language, "Konto öffnen", "Відкрити акаунт"))
                }
            }
        else {
            item("refresh") {
                TextButton(
                    actions.refresh,
                    Modifier.testTag("history-refresh"),
                    enabled = !state.loading && !state.deleting,
                ) {
                    Text(tr(language, "Verlauf erneut laden", "Оновити історію"))
                }
            }
            if (state.loading || state.deleting)
                item("loading") {
                    LinearProgressIndicator(Modifier.fillMaxWidth().testTag("history-loading"))
                }
            state.error?.let { error ->
                item("error") {
                    Text(
                        historyFailureText(error, language),
                        Modifier.testTag("history-error"),
                        color = MaterialTheme.colorScheme.error,
                    )
                    if (state.uncertainDelete == null)
                        TextButton(
                            actions.refresh,
                            Modifier.testTag("history-retry"),
                            enabled = !state.loading && !state.deleting,
                        ) {
                            Text(tr(language, "Erneut lesen", "Перечитати"))
                        }
                }
            }
            if (
                state.notice != null ||
                    state.pendingWrites > 0 ||
                    state.uncertainDelete != null ||
                    state.reconciled
            )
                item("notice") {
                    HistoryNotice(state, language, actions.reconcile)
                }
            if (page != null) {
                item("window") {
                    Text(
                        tr(
                            language,
                            "${page.consumed} Einträge geladen · höchstens ${state.section.cap} pro Ansicht",
                            "Завантажено ${page.consumed} записів · не більше ${state.section.cap} у цьому перегляді",
                        ),
                        Modifier.testTag("history-window"),
                    )
                    if (page.next != null || page.capped)
                        Text(
                            tr(
                                language,
                                "Ältere Einträge können außerhalb dieses Ausschnitts liegen. Entfernen betrifft nur die ausdrücklich ausgewählten Einträge.",
                                "Старіші записи можуть бути поза цим переглядом. Видалення стосується лише явно вибраних записів.",
                            ),
                            Modifier.testTag("history-bounded"),
                        )
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        HistoryFilter.entries
                            .filter {
                                it != HistoryFilter.SAVED ||
                                    state.section == HistorySection.ACTIVITY
                            }
                            .forEach { filter ->
                                FilterChip(
                                    state.filter == filter,
                                    { actions.filter(filter) },
                                    { Text(historyFilterText(filter, language)) },
                                    modifier =
                                        Modifier.testTag(
                                            "history-filter-${filter.name.lowercase()}"
                                        ),
                                )
                            }
                    }
                    OutlinedTextField(
                        state.search,
                        actions.search,
                        Modifier.fillMaxWidth().testTag("history-search"),
                        singleLine = true,
                        label = {
                            Text(
                                tr(
                                    language,
                                    "In sichtbaren Titeln suchen",
                                    "Пошук у видимих назвах",
                                )
                            )
                        },
                    )
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        HistorySort.entries.forEach { sort ->
                            FilterChip(
                                state.sort == sort,
                                { actions.sort(sort) },
                                { Text(historySortText(sort, language)) },
                                modifier =
                                    Modifier.testTag("history-sort-${sort.name.lowercase()}"),
                            )
                        }
                    }
                }
                if (entries.isNotEmpty())
                    item("remove-loaded") {
                        OutlinedButton(
                            {
                                dismissKeyboard()
                                actions.delete(entries.map { it.record.id }.toSet())
                            },
                            Modifier.fillMaxWidth().testTag("history-delete-visible"),
                            enabled = !state.deleting && state.uncertainDelete == null,
                        ) {
                            Text(
                                tr(
                                    language,
                                    "Diese ${entries.size} angezeigten Einträge entfernen",
                                    "Видалити ці ${entries.size} показаних записів",
                                )
                            )
                        }
                    }
                if (entries.isEmpty())
                    item("empty") {
                        Text(
                            tr(
                                language,
                                "Keine passenden Einträge im geladenen Verlauf.",
                                "У завантаженій історії немає відповідних записів.",
                            ),
                            Modifier.testTag("history-empty"),
                        )
                    }
                items(entries, key = { it.record.id }) { entry ->
                    OutlinedCard(
                        Modifier.fillMaxWidth().testTag("history-row-${entry.record.id}")
                    ) {
                        Column(
                            Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            entry.record.action?.let {
                                Text(
                                    historyActionText(it, language),
                                    style = MaterialTheme.typography.labelLarge,
                                )
                            }
                            val content = entry.content
                            if (content == null)
                                Text(
                                    tr(
                                        language,
                                        "Inhalt derzeit nicht verfügbar",
                                        "Вміст наразі недоступний",
                                    ),
                                    Modifier.testTag("history-unavailable-${entry.record.id}"),
                                    style = MaterialTheme.typography.titleMedium,
                                )
                            else {
                                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    PublicImage(
                                        content.fields.string(
                                            if (
                                                content.kind ==
                                                    at.uac.android.feature.browse.ContentKind
                                                        .ORGANIZATIONS
                                            )
                                                "logoURL"
                                            else "imageURL"
                                        ),
                                        content.title(language),
                                        language,
                                        Modifier.size(56.dp),
                                        compact = true,
                                    )
                                    Text(
                                        content.title(language),
                                        Modifier.weight(1f),
                                        style = MaterialTheme.typography.titleMedium,
                                    )
                                }
                                TextButton(
                                    { actions.open(entry) },
                                    Modifier.testTag("history-open-${entry.record.id}"),
                                ) {
                                    Text(tr(language, "Öffnen", "Відкрити"))
                                }
                            }
                            Text(
                                displayTime(entry.record.at, language),
                                style = MaterialTheme.typography.bodySmall,
                            )
                            TextButton(
                                {
                                    dismissKeyboard()
                                    actions.delete(setOf(entry.record.id))
                                },
                                Modifier.testTag("history-delete-${entry.record.id}"),
                                enabled = !state.deleting && state.uncertainDelete == null,
                            ) {
                                Text(
                                    tr(
                                        language,
                                        "Aus meinem Verlauf entfernen",
                                        "Видалити з моєї історії",
                                    )
                                )
                            }
                        }
                    }
                }
                if (page.next != null)
                    item("more") {
                        Button(actions.more, Modifier.fillMaxWidth().testTag("history-more")) {
                            Text(tr(language, "Weitere Einträge laden", "Завантажити інші записи"))
                        }
                    }
            }
        }
    }
    val confirmation =
        state.confirmation?.takeIf {
            it.session == state.session && state.session.ready && state.visible
        }
    if (confirmation != null)
        AlertDialog(
            onDismissRequest = actions.cancel,
            title = {
                Text(
                    tr(
                        language,
                        "${confirmation.records.size} Einträge entfernen?",
                        "Видалити ${confirmation.records.size} записів?",
                    )
                )
            },
            text = {
                Text(
                    tr(
                        language,
                        "Nur diese ausgewählten Verlaufseinträge werden entfernt. Inhalte, Anmeldungen, Lesezeichen und Aufrufzähler bleiben unverändert.",
                        "Буде видалено лише ці вибрані записи історії. Вміст, реєстрації, збережене й лічильники переглядів не зміняться.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        dismissKeyboard()
                        actions.confirm()
                    },
                    Modifier.testTag("history-confirm-delete"),
                ) {
                    Text(tr(language, "Einträge entfernen", "Видалити записи"))
                }
            },
            dismissButton = {
                TextButton(actions.cancel, Modifier.testTag("history-cancel-delete")) {
                    Text(tr(language, "Abbrechen", "Скасувати"))
                }
            },
        )
}

@Composable
fun HistoryNotice(state: HistoryState, language: String, onReconcile: () -> Unit) {
    if (state.session?.ready != true) return
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.testTag("history-notice"),
    ) {
        if (state.reconciled)
            Text(
                tr(
                    language,
                    "Der aktuelle Server-Verlauf wurde erneut geprüft. Es wurde nichts erneut gesendet.",
                    "Поточну історію на сервері перевірено. Жодного запису не надіслано повторно.",
                )
            )
        else
            Text(
                tr(
                    language,
                    "Eine Verlaufsänderung ist noch nicht bestätigt. Bereits bestätigte Aktionen bleiben erfolgreich.",
                    "Зміну історії ще не підтверджено. Уже підтверджені дії залишаються успішними.",
                )
            )
        state.notice?.let { Text(historyFailureText(it, language)) }
        if (state.pendingWrites > 0 || state.uncertainDelete != null)
            TextButton(
                onReconcile,
                Modifier.testTag("history-reconcile"),
                enabled = !state.deleting,
            ) {
                Text(tr(language, "Nur Server-Status prüfen", "Лише перевірити стан сервера"))
            }
    }
}

fun historyFailureText(failure: HistoryFailure, language: String): String =
    when (failure) {
        HistoryFailure.SIGN_IN ->
            tr(
                language,
                "Melde dich an, um deinen Verlauf zu öffnen.",
                "Увійдіть, щоб відкрити свою історію.",
            )
        HistoryFailure.NOT_READY ->
            tr(
                language,
                "Bitte zuerst Bestätigung, Kontostatus und Sicherheitsanforderungen im Konto prüfen.",
                "Спочатку перевірте підтвердження, стан і вимоги безпеки акаунта.",
            )
        HistoryFailure.DENIED ->
            tr(
                language,
                "Der Server hat diesen Zugriff nicht erlaubt.",
                "Сервер не дозволив цей доступ.",
            )
        HistoryFailure.MISSING ->
            tr(
                language,
                "Der Inhalt ist nicht mehr verfügbar. Bestehende Verlaufseinträge bleiben erhalten.",
                "Вміст більше не доступний. Наявні записи історії збережено.",
            )
        HistoryFailure.OFFLINE ->
            tr(
                language,
                "Der Server ist nicht erreichbar. Privater Verlauf wird nicht aus dem Cache angezeigt.",
                "Сервер недоступний. Приватна історія не показується з кешу.",
            )
        HistoryFailure.INDEX ->
            tr(
                language,
                "Diese Serverabfrage ist noch nicht verfügbar.",
                "Цей серверний запит ще недоступний.",
            )
        HistoryFailure.CONFLICT ->
            tr(
                language,
                "Ein Eintrag wurde inzwischen geändert. Lade neu und bestätige die Auswahl erneut.",
                "Запис уже змінився. Оновіть список і підтвердьте вибір заново.",
            )
        HistoryFailure.UNCONFIRMED ->
            tr(
                language,
                "Das Ergebnis ist offen. Prüfe den Server-Status; es gibt keine automatische Wiederholung.",
                "Результат не визначено. Перевірте стан сервера; автоматичного повторення немає.",
            )
        HistoryFailure.INVALID,
        HistoryFailure.UNKNOWN ->
            tr(
                language,
                "Der Verlauf konnte nicht sicher bestätigt werden.",
                "Не вдалося безпечно підтвердити історію.",
            )
    }

fun historyFilterText(value: HistoryFilter, language: String) =
    when (value) {
        HistoryFilter.ALL -> tr(language, "Alle", "Усі")
        HistoryFilter.NEWS -> tr(language, "Nachrichten", "Новини")
        HistoryFilter.EVENTS -> tr(language, "Veranstaltungen", "Події")
        HistoryFilter.ORGANIZATIONS -> tr(language, "Organisationen", "Організації")
        HistoryFilter.SAVED -> tr(language, "Gespeichert", "Збережене")
    }

fun historySortText(value: HistorySort, language: String) =
    when (value) {
        HistorySort.NEWEST -> tr(language, "Neueste zuerst", "Спочатку нові")
        HistorySort.OLDEST -> tr(language, "Älteste zuerst", "Спочатку давні")
        HistorySort.NAME_ASCENDING -> tr(language, "Name A–Z", "Назва А–Я")
        HistorySort.NAME_DESCENDING -> tr(language, "Name Z–A", "Назва Я–А")
    }

fun historyActionText(value: HistoryAction, language: String) =
    when (value) {
        HistoryAction.REGISTER ->
            tr(language, "Für Veranstaltung angemeldet", "Зареєстровано на подію")
        HistoryAction.UNREGISTER -> tr(language, "Anmeldung zurückgenommen", "Реєстрацію скасовано")
        HistoryAction.FOLLOW -> tr(language, "Organisation abonniert", "Підписано на організацію")
        HistoryAction.UNFOLLOW ->
            tr(language, "Organisation nicht mehr abonniert", "Підписку на організацію скасовано")
        HistoryAction.SAVE_NEWS -> tr(language, "Nachricht gespeichert", "Новину збережено")
        HistoryAction.UNSAVE_NEWS ->
            tr(language, "Nachricht aus Gespeichert entfernt", "Новину видалено зі збереженого")
        HistoryAction.SAVE_EVENT -> tr(language, "Veranstaltung gespeichert", "Подію збережено")
        HistoryAction.UNSAVE_EVENT ->
            tr(language, "Veranstaltung aus Gespeichert entfernt", "Подію видалено зі збереженого")
        HistoryAction.SAVE_ORGANIZATION ->
            tr(language, "Organisation gespeichert", "Організацію збережено")
        HistoryAction.UNSAVE_ORGANIZATION ->
            tr(
                language,
                "Organisation aus Gespeichert entfernt",
                "Організацію видалено зі збереженого",
            )
    }
