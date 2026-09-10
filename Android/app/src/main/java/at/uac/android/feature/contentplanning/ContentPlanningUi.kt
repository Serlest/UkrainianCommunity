package at.uac.android.feature.contentplanning

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.design.UacSymbol
import at.uac.android.feature.browse.tr
import at.uac.android.feature.moderation.ModerationSession
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

@Composable
fun ContentPlanningScreen(
    model: ContentPlanningViewModel,
    session: ModerationSession?,
    language: String,
    onBack: () -> Unit,
    onOpenPublished: (ContentPlanningKind, String) -> Unit,
    initialDraftId: String? = null,
    onStartEditor: ((ContentPlanningDraft, String) -> Unit)? = null,
) {
    val state by model.state.collectAsStateWithLifecycle()
    DisposableEffect(session) {
        model.show(session)
        onDispose(model::hide)
    }
    LaunchedEffect(session, initialDraftId) {
        if (session?.ready == true && session.role == "owner" && initialDraftId != null)
            model.open(initialDraftId)
    }
    ContentPlanningContent(
        state,
        language,
        onBack,
        model::select,
        model::refresh,
        model::more,
        model::open,
        model::closeDetail,
        { draft, organizationId -> onStartEditor?.invoke(draft, organizationId) },
        model::archive,
        model::delete,
        model::reconcile,
        model::retryRecovery,
        onOpenPublished,
        editorAvailable = onStartEditor != null,
    )
}

@Composable
fun ContentPlanningContent(
    state: ContentPlanningUiState,
    language: String,
    onBack: () -> Unit = {},
    onSection: (ContentPlanningSection) -> Unit = {},
    onRefresh: () -> Unit = {},
    onMore: () -> Unit = {},
    onOpen: (String) -> Unit = {},
    onClose: () -> Unit = {},
    onBegin: (ContentPlanningDraft, String) -> Unit = { _, _ -> },
    onArchive: (ContentPlanningDraft) -> Unit = {},
    onDelete: (ContentPlanningDraft) -> Unit = {},
    onReconcile: () -> Unit = {},
    onRetryRecovery: () -> Unit = {},
    onOpenPublished: (ContentPlanningKind, String) -> Unit = { _, _ -> },
    editorAvailable: Boolean = true,
) {
    var confirmation by remember { mutableStateOf<Pair<String, ContentPlanningDraft>?>(null) }
    val selected = state.selected
    androidx.activity.compose.BackHandler {
        if (confirmation != null) confirmation = null
        else if (selected != null) onClose() else onBack()
    }
    if (selected != null) {
        ContentPlanningDetail(
            selected,
            state,
            language,
            onClose,
            onBegin,
            { confirmation = "archive" to selected },
            { confirmation = "delete" to selected },
            onReconcile,
            onRetryRecovery,
            onOpenPublished,
            editorAvailable,
        )
    } else {
        val section = state.section()
        LazyColumn(
            Modifier.fillMaxSize().testTag("content-planning"),
            contentPadding = PaddingValues(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item("header") {
                at.uac.android.design.UacBackButton(
                    onBack,
                    Modifier.testTag("content-planning-back"),
                ) {
                    UacSymbol(UacIcon.BACK)
                    Text(tr(language, "Zurück", "Назад"))
                }
                UacSectionHeading(
                    tr(language, "Inhaltsplanung", "Планування контенту"),
                    UacIcon.EDIT,
                )
                Text(
                    tr(
                        language,
                        "Private Inhaberansicht für geprüfte Entwürfe und Veröffentlichungsbelege.",
                        "Приватний простір власника для перевірених чернеток і підтверджень публікації.",
                    ),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            if (!state.allowed)
                item("denied") {
                    Text(
                        tr(
                            language,
                            "Nur der aktive App-Inhaber darf die Inhaltsplanung öffnen.",
                            "Планування контенту доступне лише активному власнику застосунку.",
                        ),
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.testTag("content-planning-denied"),
                    )
                }
            else {
                item("sections") {
                    LazyRow(
                        modifier = Modifier.testTag("content-planning-sections"),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        items(ContentPlanningSection.entries, key = { it.name }) { value ->
                            FilterChip(
                                selected = state.selectedSection == value,
                                onClick = { onSection(value) },
                                label = { Text(sectionLabel(value, language)) },
                                modifier =
                                    Modifier.testTag(
                                        "content-planning-section-${value.name.lowercase()}"
                                    ),
                            )
                        }
                    }
                }
                state.recovery?.let { recovery ->
                    item("recovery") {
                        RecoveryCard(recovery, language, onReconcile, onRetryRecovery)
                    }
                }
                state.error?.let { error ->
                    item("error") {
                        ErrorCard(error, language, onRefresh)
                    }
                }
                if (section.loading && section.items.isEmpty())
                    item("loading") {
                        CircularProgressIndicator(Modifier.testTag("content-planning-loading"))
                    }
                else if (section.loaded && section.items.isEmpty())
                    item("empty") {
                        Text(
                            emptyLabel(state.selectedSection, language),
                            Modifier.testTag("content-planning-empty"),
                        )
                    }
                items(section.items, key = { it.id }) { draft ->
                    DraftCard(draft, state.busyDraftId == draft.id, language) { onOpen(draft.id) }
                }
                if (section.hasMore)
                    item("more") {
                        OutlinedButton(
                            onMore,
                            enabled = !section.loadingMore,
                            modifier = Modifier.fillMaxWidth().testTag("content-planning-more"),
                        ) {
                            if (section.loadingMore) CircularProgressIndicator()
                            else Text(tr(language, "Mehr laden", "Завантажити ще"))
                        }
                    }
            }
        }
    }

    confirmation?.let { (action, draft) ->
        AlertDialog(
            onDismissRequest = { confirmation = null },
            title = {
                Text(
                    if (action == "archive")
                        tr(language, "Entwurf archivieren?", "Архівувати чернетку?")
                    else tr(language, "Datensatz löschen?", "Видалити запис?")
                )
            },
            text = {
                Text(
                    tr(
                        language,
                        "Diese Aktion wird erst nach einer Serverbestätigung als abgeschlossen angezeigt.",
                        "Дія вважатиметься завершеною лише після підтвердження сервера.",
                    )
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        confirmation = null
                        if (action == "archive") onArchive(draft) else onDelete(draft)
                    },
                    modifier = Modifier.testTag("content-planning-confirm-$action"),
                ) {
                    Text(
                        if (action == "archive") tr(language, "Archivieren", "Архівувати")
                        else tr(language, "Löschen", "Видалити")
                    )
                }
            },
            dismissButton = {
                TextButton({ confirmation = null }) { Text(tr(language, "Abbrechen", "Скасувати")) }
            },
        )
    }
}

@Composable
private fun DraftCard(
    draft: ContentPlanningDraft,
    busy: Boolean,
    language: String,
    onOpen: () -> Unit,
) {
    Card(
        onClick = onOpen,
        modifier = Modifier.fillMaxWidth().testTag("content-planning-draft-${draft.id}"),
    ) {
        Column(
            Modifier.fillMaxWidth().padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                kindLabel(draft.kind, language),
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.primary,
            )
            Text(draft.title, style = MaterialTheme.typography.titleMedium)
            Text(stateLabel(draft.state, language), style = MaterialTheme.typography.bodySmall)
            draft.scheduledAt?.let {
                Text(format(it, language), style = MaterialTheme.typography.bodySmall)
            }
            if (draft.missingFields.isNotEmpty())
                Text(
                    tr(language, "Fehlt: ", "Бракує: ") + draft.missingFields.joinToString(),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            if (busy) CircularProgressIndicator(Modifier.testTag("content-planning-draft-busy"))
        }
    }
}

@Composable
private fun ContentPlanningDetail(
    draft: ContentPlanningDraft,
    state: ContentPlanningUiState,
    language: String,
    onClose: () -> Unit,
    onBegin: (ContentPlanningDraft, String) -> Unit,
    onArchive: () -> Unit,
    onDelete: () -> Unit,
    onReconcile: () -> Unit,
    onRetryRecovery: () -> Unit,
    onOpenPublished: (ContentPlanningKind, String) -> Unit,
    editorAvailable: Boolean,
) {
    val uri = LocalUriHandler.current
    var organizationId by remember(draft.id) { mutableStateOf<String?>(null) }
    LazyColumn(
        Modifier.fillMaxSize().testTag("content-planning-detail"),
        contentPadding = PaddingValues(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item("header") {
            at.uac.android.design.UacBackButton(
                onClose,
                Modifier.testTag("content-planning-detail-back"),
            ) {
                UacSymbol(UacIcon.BACK)
                Text(tr(language, "Zurück", "Назад"))
            }
            UacSectionHeading(draft.title, UacIcon.EDIT)
            Text("${kindLabel(draft.kind, language)} · ${stateLabel(draft.state, language)}")
        }
        if (draft.missingFields.isNotEmpty())
            item("missing") {
                DetailCard(tr(language, "Fehlende Angaben", "Відсутні дані"), draft.missingFields)
            }
        if (draft.verificationNotes.isNotEmpty())
            item("notes") {
                DetailCard(
                    tr(language, "Prüfhinweise", "Нотатки перевірки"),
                    draft.verificationNotes,
                )
            }
        item("sources") {
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        tr(language, "Quellen", "Джерела"),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    draft.sources.forEachIndexed { index, source ->
                        AssistChip(
                            onClick = { uri.openUri(source.url) },
                            label = {
                                Text(
                                    (if (source.primary) "★ " else "") +
                                        (source.title ?: source.url)
                                )
                            },
                            modifier = Modifier.testTag("content-planning-source-$index"),
                        )
                    }
                }
            }
        }
        draft.failureMessage?.let { message ->
            item("failure") {
                DetailCard(tr(language, "Letzter Fehler", "Остання помилка"), listOf(message))
            }
        }
        state.recovery
            ?.takeIf { it.draftId == draft.id }
            ?.let { recovery ->
                item("recovery") { RecoveryCard(recovery, language, onReconcile, onRetryRecovery) }
            }
        state.error?.let { error -> item("error") { ErrorCard(error, language, onReconcile) } }
        if (draft.canPublish && editorAvailable)
            item("organization") {
                Card(Modifier.fillMaxWidth().testTag("content-planning-organization-picker")) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            tr(language, "Organisation auswählen", "Оберіть організацію"),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        if (state.organizationsLoading) CircularProgressIndicator()
                        else if (state.organizations.isEmpty())
                            Text(
                                tr(
                                    language,
                                    "Keine bestätigte Organisation verfügbar.",
                                    "Немає підтвердженої організації.",
                                ),
                                color = MaterialTheme.colorScheme.error,
                            )
                        else
                            state.organizations.forEach { organization ->
                                FilterChip(
                                    selected = organizationId == organization.id,
                                    onClick = { organizationId = organization.id },
                                    label = { Text(organization.name) },
                                    modifier =
                                        Modifier.testTag(
                                            "content-planning-organization-${organization.id}"
                                        ),
                                )
                            }
                    }
                }
            }
        item("actions") {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (draft.canPublish && editorAvailable)
                    Button(
                        { organizationId?.let { onBegin(draft, it) } },
                        enabled = state.busyDraftId == null && organizationId != null,
                        modifier = Modifier.fillMaxWidth().testTag("content-planning-review"),
                    ) {
                        Text(
                            tr(language, "Prüfen und veröffentlichen", "Перевірити й опублікувати")
                        )
                    }
                if (draft.canArchive)
                    OutlinedButton(
                        onArchive,
                        enabled = state.busyDraftId == null,
                        modifier = Modifier.fillMaxWidth().testTag("content-planning-archive"),
                    ) {
                        Text(tr(language, "Archivieren", "Архівувати"))
                    }
                if (draft.canDelete)
                    OutlinedButton(
                        onDelete,
                        enabled = state.busyDraftId == null,
                        modifier = Modifier.fillMaxWidth().testTag("content-planning-delete"),
                    ) {
                        Text(tr(language, "Löschen", "Видалити"))
                    }
                draft.publishedContentId?.let { id ->
                    Button(
                        { onOpenPublished(draft.publishedKind ?: draft.kind, id) },
                        Modifier.fillMaxWidth().testTag("content-planning-open-published"),
                    ) {
                        Text(
                            tr(
                                language,
                                "Veröffentlichten Inhalt öffnen",
                                "Відкрити опублікований матеріал",
                            )
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailCard(title: String, values: List<String>) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            values.forEach { Text("• $it") }
        }
    }
}

@Composable
private fun RecoveryCard(
    recovery: ContentPlanningRecovery,
    language: String,
    onReconcile: () -> Unit,
    onRetry: () -> Unit,
) {
    Card(Modifier.fillMaxWidth().testTag("content-planning-recovery")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                tr(
                    language,
                    "Die letzte Serverantwort ist nicht eindeutig. Die Aktion wird nicht automatisch wiederholt.",
                    "Остання відповідь сервера неоднозначна. Дію не буде повторено автоматично.",
                ),
                color = MaterialTheme.colorScheme.error,
            )
            OutlinedButton(onReconcile, Modifier.testTag("content-planning-reconcile")) {
                Text(tr(language, "Serverstatus prüfen", "Перевірити стан на сервері"))
            }
            if (
                recovery.phase in
                    setOf(
                        ContentPlanningRecoveryPhase.BEGIN_UNCONFIRMED,
                        ContentPlanningRecoveryPhase.FINALIZE_UNCONFIRMED,
                        ContentPlanningRecoveryPhase.FAIL_UNCONFIRMED,
                    )
            )
                OutlinedButton(onRetry, Modifier.testTag("content-planning-retry-operation")) {
                    Text(tr(language, "Dieselbe Aktion erneut senden", "Повторити ту саму дію"))
                }
        }
    }
}

@Composable
private fun ErrorCard(error: ContentPlanningFailure, language: String, onRetry: () -> Unit) {
    Card(Modifier.fillMaxWidth().testTag("content-planning-error")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(errorLabel(error, language), color = MaterialTheme.colorScheme.error)
            OutlinedButton(onRetry, Modifier.testTag("content-planning-retry")) {
                Text(tr(language, "Erneut versuchen", "Спробувати знову"))
            }
        }
    }
}

private fun sectionLabel(value: ContentPlanningSection, language: String) =
    when (value) {
        ContentPlanningSection.DRAFTS -> tr(language, "Entwürfe", "Чернетки")
        ContentPlanningSection.SCHEDULED -> tr(language, "Geplant", "Заплановано")
        ContentPlanningSection.ATTENTION -> tr(language, "Zu prüfen", "Потребує уваги")
        ContentPlanningSection.HISTORY -> tr(language, "Verlauf", "Історія")
    }

private fun emptyLabel(value: ContentPlanningSection, language: String) =
    when (value) {
        ContentPlanningSection.DRAFTS ->
            tr(language, "Keine Entwürfe vorhanden.", "Чернеток немає.")
        ContentPlanningSection.SCHEDULED ->
            tr(language, "Keine geplanten Inhalte.", "Запланованих матеріалів немає.")
        ContentPlanningSection.ATTENTION ->
            tr(language, "Nichts benötigt Aufmerksamkeit.", "Нічого не потребує уваги.")
        ContentPlanningSection.HISTORY ->
            tr(language, "Noch kein Verlauf.", "Історія поки порожня.")
    }

private fun kindLabel(value: ContentPlanningKind, language: String) =
    if (value == ContentPlanningKind.NEWS) tr(language, "News", "Новина")
    else tr(language, "Veranstaltung", "Подія")

private fun stateLabel(value: ContentPlanningState, language: String) =
    when (value) {
        ContentPlanningState.READY -> tr(language, "Bereit zur Prüfung", "Готово до перевірки")
        ContentPlanningState.ATTENTION -> tr(language, "Angaben fehlen", "Бракує даних")
        ContentPlanningState.SCHEDULED -> tr(language, "Geplant", "Заплановано")
        ContentPlanningState.PUBLISHING ->
            tr(language, "Veröffentlichung läuft", "Триває публікація")
        ContentPlanningState.FAILED -> tr(language, "Fehlgeschlagen", "Помилка")
        ContentPlanningState.COMPLETED -> tr(language, "Veröffentlicht", "Опубліковано")
        ContentPlanningState.ARCHIVED -> tr(language, "Archiviert", "Архівовано")
    }

private fun errorLabel(value: ContentPlanningFailure, language: String) =
    when (value) {
        ContentPlanningFailure.OFFLINE ->
            tr(
                language,
                "Keine bestätigte Serververbindung.",
                "Немає підтвердженого з'єднання із сервером.",
            )
        ContentPlanningFailure.INDEX ->
            tr(
                language,
                "Der erforderliche Serverindex fehlt.",
                "Бракує необхідного серверного індексу.",
            )
        ContentPlanningFailure.CONFLICT ->
            tr(
                language,
                "Der Entwurf wurde bereits geändert. Bitte neu laden.",
                "Чернетку вже змінено. Оновіть дані.",
            )
        ContentPlanningFailure.UNCONFIRMED ->
            tr(language, "Die Serverantwort ist unbestätigt.", "Відповідь сервера не підтверджена.")
        ContentPlanningFailure.DENIED,
        ContentPlanningFailure.SIGN_IN,
        ContentPlanningFailure.NOT_READY ->
            tr(language, "Zugriff nicht bestätigt.", "Доступ не підтверджено.")
        ContentPlanningFailure.MISSING ->
            tr(language, "Der Entwurf wurde nicht gefunden.", "Чернетку не знайдено.")
        else ->
            tr(
                language,
                "Die Inhaltsplanung konnte nicht bestätigt werden.",
                "Не вдалося підтвердити планування контенту.",
            )
    }

private fun format(value: java.time.Instant, language: String) =
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withLocale(Locale.forLanguageTag(language))
        .withZone(ZoneId.systemDefault())
        .format(value)
