package at.uac.android.feature.authoring

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.core.PickerLocale
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.core.ProtectedDialog
import at.uac.android.core.ProtectedDropdownMenu as DropdownMenu
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.string
import at.uac.android.feature.contentlifecycle.ContentLifecycleContract
import at.uac.android.feature.organization.OrganizationSession
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.delay

data class AuthoringActions(
    val back: () -> Unit = {},
    val account: () -> Unit = {},
    val open: (Content) -> Unit = {},
    val refresh: () -> Unit = {},
    val more: () -> Unit = {},
    val select: (ContentKind, AuthoringStatus) -> Unit = { _, _ -> },
    val create: () -> Unit = {},
    val edit: (String) -> Unit = {},
    val change: ((AuthoringDraft) -> AuthoringDraft) -> Unit = {},
    val preview: () -> Unit = {},
    val closePreview: () -> Unit = {},
    val submit: () -> Unit = {},
    val confirm: () -> Unit = {},
    val dismiss: () -> Unit = {},
    val discard: () -> Unit = {},
    val recover: () -> Unit = {},
    val retry: () -> Unit = {},
    val cover: ((AuthoringItem) -> Unit)? = null,
    val lifecycle: ((AuthoringItem) -> Unit)? = null,
    val restoreDraft: () -> Unit = {},
    val discardRecoveredDraft: () -> Unit = {},
    val retryLocalSave: () -> Unit = {},
)

@Composable
fun AuthoringScreen(
    model: AuthoringViewModel,
    organizationId: String,
    session: OrganizationSession?,
    language: String,
    onBack: () -> Unit,
    onAccount: () -> Unit,
    onOpenContent: (Content) -> Unit,
    initialKind: ContentKind = ContentKind.NEWS,
    onCover: ((AuthoringItem) -> Unit)? = null,
    onLifecycle: ((AuthoringItem) -> Unit)? = null,
) {
    val stored by model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    val state =
        if (stored.session == session && stored.organizationId == organizationId) stored
        else AuthoringState(session, organizationId, kind = initialKind)
    LifecycleResumeEffect(session, organizationId, initialKind) {
        model.show(organizationId, initialKind)
        onPauseOrDispose { model.hide() }
    }
    AuthoringContent(
        state,
        language,
        AuthoringActions(
            onBack,
            onAccount,
            onOpenContent,
            model::refresh,
            model::more,
            model::select,
            model::create,
            model::edit,
            model::change,
            model::preview,
            model::closePreview,
            model::requestSubmit,
            model::confirm,
            model::dismissConfirmation,
            model::discardLocalForm,
            model::recover,
            model::retryAbsentCreation,
            onCover,
            onLifecycle,
            model::restoreDraft,
            model::discardRecoveredDraft,
            model::retryFailedLocalSave,
        ),
    )
}

@Composable
fun AuthoringContent(state: AuthoringState, language: String, actions: AuthoringActions) {
    var leave by remember(state.session, state.organizationId) { mutableStateOf(false) }
    var discard by remember(state.session, state.organizationId) { mutableStateOf(false) }
    var discardRecovered by remember(state.session, state.organizationId) { mutableStateOf(false) }
    val ticking =
        state.visible &&
            state.session?.ready == true &&
            (state.draft?.publicationMode == AuthoringPublicationMode.SCHEDULED ||
                state.uncertain?.fields?.get("scheduledAt") != null ||
                state.confirmation?.fields?.get("scheduledAt") != null)
    val now by
        produceState(Instant.now(), ticking) {
            if (ticking)
                while (true) {
                    value = Instant.now()
                    delay(1_000)
                }
        }
    val scheduleValid =
        state.draft?.let {
            it.publicationMode == AuthoringPublicationMode.NOW ||
                AuthoringPublication.hasEnoughLeadTime(it.scheduledAt, now)
        } != false
    val back = { if (state.draft != null) leave = true else actions.back() }
    BackHandler(state.draft != null && state.session?.ready == true, back)
    Column(
        Modifier.fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
            .testTag("authoring-screen"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        TextButton(back) { Text(at(language, "Zurück", "Назад")) }
        Text(
            at(language, "Nachrichten & Veranstaltungen", "Новини та події"),
            style = MaterialTheme.typography.headlineMedium,
        )
        if (state.session?.ready != true) {
            Text(
                at(
                    language,
                    "Ein bestätigtes, aktives Konto mit erfüllten Sicherheitsanforderungen ist erforderlich.",
                    "Потрібен підтверджений активний акаунт з виконаними вимогами безпеки.",
                )
            )
            Button(actions.account, Modifier.testTag("authoring-account")) {
                Text(at(language, "Konto öffnen", "Відкрити акаунт"))
            }
        } else {
            state.error?.let {
                Text(
                    authoringFailureText(it, language, state.invalidField),
                    Modifier.testTag("authoring-error"),
                    color = MaterialTheme.colorScheme.error,
                )
            }
            if (state.recoveryError != null)
                Text(
                    at(
                        language,
                        "Die sichere lokale Speicherung ist nicht verfügbar. Nichts wird deshalb neu gesendet oder verworfen. Bitte nicht die App-Daten löschen; den aktuellen Stand erneut prüfen.",
                        "Безпечне локальне збереження недоступне. Через це нічого не надсилається повторно й не видаляється. Не очищуйте дані застосунку; перевірте стан знову.",
                    ),
                    Modifier.testTag("authoring-storage-error"),
                    color = MaterialTheme.colorScheme.error,
                )
            if (state.unsavedExitCount > 0) {
                Text(
                    at(
                        language,
                        "Letzte Änderungen in ${state.unsavedExitCount} Bereich(en) sind nur im Arbeitsspeicher erhalten. Die App nicht schließen. Den betroffenen Bereich öffnen und lokal erneut sichern oder bewusst verwerfen.",
                        "Останні зміни у ${state.unsavedExitCount} розділах залишаються лише в пам’яті. Не закривайте застосунок. Відкрийте потрібний розділ і повторіть локальне збереження або свідомо відкиньте зміни.",
                    ),
                    Modifier.testTag("authoring-exit-save-error"),
                    color = MaterialTheme.colorScheme.error,
                )
                if (state.failedCurrentDraft)
                    OutlinedButton(
                        actions.retryLocalSave,
                        Modifier.testTag("authoring-retry-local-save"),
                        enabled =
                            state.actionable &&
                                state.uncertain == null &&
                                state.recoveryError == null &&
                                state.base == null,
                    ) {
                        Text(
                            at(
                                language,
                                "Lokal erneut sichern · nicht senden",
                                "Зберегти локально знову · не надсилати",
                            )
                        )
                    }
            }
            if (state.loading || state.busy)
                CircularProgressIndicator(Modifier.testTag("authoring-progress"))
            TextButton(
                actions.refresh,
                Modifier.testTag("authoring-refresh"),
                enabled = !state.loading && !state.busy,
            ) {
                Text(at(language, "Aktualisieren", "Оновити"))
            }
            state.hub?.organization?.let {
                Text(it.name, style = MaterialTheme.typography.titleLarge)
            }
            if (!state.fresh)
                Text(
                    at(
                        language,
                        "Aktionen bleiben gesperrt, bis der Server den aktuellen Stand bestätigt.",
                        "Дії заблоковано до підтвердження актуального стану сервером.",
                    )
                )
            if (state.recoveredDraft != null && state.draft == null && state.uncertain == null)
                Card(Modifier.fillMaxWidth().testTag("authoring-saved-draft")) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            at(
                                language,
                                "Ungesendeter Entwurf auf diesem Gerät",
                                "Ненадіслана чернетка на цьому пристрої",
                            ),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(
                            state.recoveredDraft.title.ifBlank {
                                at(language, "Ohne Titel", "Без назви")
                            }
                        )
                        Text(at(language, "Zeitzone: ", "Часовий пояс: ") + state.draftZoneId)
                        if (
                            state.recoveredDraft.publicationMode ==
                                AuthoringPublicationMode.SCHEDULED
                        )
                            state.recoveredDraft.scheduledAt?.let {
                                AuthoringScheduleText(it, state.draftZoneId, language)
                            }
                        Button(
                            actions.restoreDraft,
                            Modifier.testTag("authoring-restore-draft"),
                            enabled =
                                state.actionable &&
                                    state.recoveryLoaded &&
                                    state.recoveryError == null,
                        ) {
                            Text(at(language, "Entwurf fortsetzen", "Продовжити чернетку"))
                        }
                        TextButton(
                            { discardRecovered = true },
                            Modifier.testTag("authoring-delete-draft"),
                            enabled = state.actionable && state.recoveryError == null,
                        ) {
                            Text(
                                at(
                                    language,
                                    "Ungesendeten Entwurf löschen",
                                    "Видалити ненадіслану чернетку",
                                )
                            )
                        }
                    }
                }
            state.uncertain?.let { intent ->
                Text(
                    authoringFailureText(AuthoringFailure.UNCONFIRMED, language),
                    Modifier.testTag("authoring-uncertain"),
                )
                Text(
                    at(
                        language,
                        "Der ursprüngliche Auftrag bleibt erhalten. Es wird kein neuer Beitrag automatisch angelegt; eine genau-einmalige Veröffentlichung kann nicht zugesichert werden.",
                        "Початковий запит збережено. Новий матеріал автоматично не створюється; гарантувати публікацію рівно один раз неможливо.",
                    )
                )
                Button(
                    actions.recover,
                    Modifier.testTag("authoring-recover"),
                    enabled = !state.busy && !state.loading,
                ) {
                    Text(at(language, "Serverstand prüfen", "Перевірити стан на сервері"))
                }
                if (state.recoveryChecked) {
                    Text(
                        if (state.recoveryConflict)
                            at(
                                language,
                                "Der Server enthält eine andere Version. Sie wird nicht überschrieben.",
                                "На сервері інша версія. Її не буде перезаписано.",
                            )
                        else
                            at(
                                language,
                                "Unter dieser Kennung wurde kein Eintrag gefunden. Das löscht den ursprünglichen Auftrag nicht und löst keinen neuen Versand aus.",
                                "За цим ідентифікатором запису немає. Це не видаляє початковий запит і не запускає повторне надсилання.",
                            )
                    )
                    if (!state.recoveryConflict && intent.base == null)
                        OutlinedButton(
                            actions.retry,
                            Modifier.testTag("authoring-retry-same"),
                            enabled =
                                state.actionable &&
                                    state.recoveryError == null &&
                                    AuthoringPublication.canSend(intent, now),
                        ) {
                            Text(
                                at(
                                    language,
                                    "Denselben Beitrag bewusst erneut senden",
                                    "Свідомо надіслати той самий матеріал знову",
                                )
                            )
                        }
                }
                (intent.fields["scheduledAt"] as? Instant)?.let { scheduled ->
                    AuthoringScheduleText(scheduled, state.draftZoneId, language)
                    if (!AuthoringPublication.hasEnoughLeadTime(scheduled, now))
                        Text(
                            at(
                                language,
                                "Die ursprüngliche Planzeit liegt weniger als fünf Minuten in der Zukunft. Der Auftrag bleibt erhalten und wird nicht neu datiert oder erneut gesendet. Nur den Serverstand prüfen.",
                                "До початкового часу публікації менше п’яти хвилин. Запит збережено; його час не змінюється й він не надсилається знову. Лише перевірте стан сервера.",
                            ),
                            Modifier.testTag("authoring-expired-pending"),
                        )
                }
            }
            state.confirmed?.let { item ->
                Card(Modifier.fillMaxWidth().testTag("authoring-confirmed")) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            at(language, "Vom Server bestätigt", "Підтверджено сервером"),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        Text(item.content.title(language))
                        Text(authoringStatusText(item.status, language))
                        (item.fields["scheduledAt"] as? Instant)?.let {
                            AuthoringScheduleText(it, state.draftZoneId, language)
                        }
                        if (item.status == AuthoringStatus.APPROVED)
                            TextButton({ actions.open(item.content) }, enabled = state.actionable) {
                                Text(at(language, "Öffnen", "Відкрити"))
                            }
                    }
                }
            }
            if (state.draft == null) {
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    AuthoringContract.kinds.forEach { kind ->
                        FilterChip(
                            selected = state.kind == kind,
                            onClick = { actions.select(kind, state.status) },
                            label = { Text(kind.label(language)) },
                            enabled = state.actionable,
                            modifier = Modifier.testTag("authoring-kind-${kind.collection}"),
                        )
                    }
                }
                AuthoringChoice(
                    at(language, "Status", "Статус"),
                    state.status.wire,
                    AuthoringStatus.entries.map { it.wire },
                    state.actionable,
                    { wire ->
                        authoringStatusText(
                            AuthoringStatus.entries.first { it.wire == wire },
                            language,
                        )
                    },
                ) { wire ->
                    actions.select(state.kind, AuthoringStatus.entries.first { it.wire == wire })
                }
                Button(
                    actions.create,
                    Modifier.fillMaxWidth().testTag("authoring-create"),
                    enabled = state.canCreate,
                ) {
                    Text(
                        if (state.kind == ContentKind.NEWS)
                            at(language, "Nachricht erstellen", "Створити новину")
                        else at(language, "Veranstaltung erstellen", "Створити подію")
                    )
                }
                if (state.status == AuthoringStatus.SCHEDULED)
                    Text(
                        at(
                            language,
                            "Nur Ihre geplanten Server-Entwürfe. Zeitplanung und Freigabe werden in diesem Bereich nicht verändert.",
                            "Лише ваші заплановані серверні чернетки. Розклад і публікацію в цьому розділі не змінюємо.",
                        ),
                        Modifier.testTag("authoring-scheduled-readonly"),
                    )
                state.hub?.page?.let { page ->
                    if (page.items.isEmpty() && state.fresh)
                        Text(
                            at(
                                language,
                                "Noch keine Einträge in diesem Status.",
                                "Записів із цим статусом поки немає.",
                            ),
                            Modifier.testTag("authoring-empty"),
                        )
                    page.items.forEach { item ->
                        Card(Modifier.fillMaxWidth().testTag("authoring-item-${item.id}")) {
                            Column(
                                Modifier.padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(
                                    item.content.title(language),
                                    style = MaterialTheme.typography.titleMedium,
                                )
                                Text(item.content.summary(language))
                                Text(
                                    authoringStatusText(item.status, language),
                                    style = MaterialTheme.typography.labelLarge,
                                )
                                (item.fields["scheduledAt"] as? Instant)?.let {
                                    Text(
                                        DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm z")
                                            .withZone(ZoneId.systemDefault())
                                            .format(it)
                                    )
                                }
                                FlowRow(
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    verticalArrangement = Arrangement.spacedBy(4.dp),
                                ) {
                                    if (item.status == AuthoringStatus.APPROVED)
                                        TextButton(
                                            { actions.open(item.content) },
                                            enabled = state.actionable,
                                        ) {
                                            Text(at(language, "Ansehen", "Переглянути"))
                                        }
                                    if (item.editable)
                                        OutlinedButton(
                                            { actions.edit(item.id) },
                                            Modifier.testTag("authoring-edit-${item.id}"),
                                            enabled = state.actionable,
                                        ) {
                                            Text(at(language, "Bearbeiten", "Редагувати"))
                                        }
                                    else Text(at(language, "Schreibgeschützt", "Лише перегляд"))
                                    if (item.editable)
                                        actions.cover?.let { cover ->
                                            OutlinedButton(
                                                { cover(item) },
                                                Modifier.testTag("authoring-cover-${item.id}"),
                                                enabled = state.actionable,
                                            ) {
                                                Text(at(language, "Titelbild", "Обкладинка"))
                                            }
                                        }
                                    if (
                                        state.fresh &&
                                            ContentLifecycleContract.permitted(
                                                state.hub.organization,
                                                state.session,
                                            ) &&
                                            item.status != AuthoringStatus.SCHEDULED &&
                                            item.fields["scheduledAt"] == null &&
                                            item.fields["cancellationState"] != "cancelled"
                                    )
                                        actions.lifecycle?.let { lifecycle ->
                                            TextButton(
                                                { lifecycle(item) },
                                                Modifier.testTag("authoring-lifecycle-${item.id}"),
                                                enabled = state.actionable,
                                            ) {
                                                Text(
                                                    if (item.kind == ContentKind.NEWS)
                                                        at(language, "Löschen", "Видалити")
                                                    else at(language, "Absagen", "Скасувати"),
                                                    color = MaterialTheme.colorScheme.error,
                                                )
                                            }
                                        }
                                }
                            }
                        }
                    }
                    if (page.next != null)
                        TextButton(
                            actions.more,
                            Modifier.testTag("authoring-more"),
                            enabled = state.actionable,
                        ) {
                            Text(at(language, "Weitere laden", "Завантажити ще"))
                        }
                }
            } else {
                HorizontalDivider()
                Text(
                    state.draft.kind.label(language) +
                        " · " +
                        if (state.base == null) at(language, "Neuer Beitrag", "Новий матеріал")
                        else at(language, "Beitrag bearbeiten", "Редагування матеріалу"),
                    style = MaterialTheme.typography.titleLarge,
                )
                Text(
                    if (state.base != null)
                        at(
                            language,
                            "Diese ungesendete Bearbeitung bleibt nur im Speicher dieser Sitzung.",
                            "Це ненадіслане редагування залишається лише в пам’яті цієї сесії.",
                        )
                    else if (state.draftSaved)
                        at(
                            language,
                            "Verschlüsselt auf diesem Gerät gesichert. Beim Fortsetzen werden Rechte erneut geprüft. Abmeldung entfernt nur ungesendete Entwürfe, keine unbestätigten Aufträge.",
                            "Зашифровано збережено на цьому пристрої. Під час продовження права перевіряються знову. Вихід прибирає лише ненадіслані чернетки, але не непідтверджені запити.",
                        )
                    else
                        at(
                            language,
                            "Die letzten Änderungen sind noch nicht lokal gesichert.",
                            "Останні зміни ще не збережено локально.",
                        ),
                    Modifier.testTag("authoring-draft-save-state"),
                    style = MaterialTheme.typography.bodySmall,
                )
                if (!state.draftWritable && !state.busy && state.confirmation == null)
                    Text(
                        at(
                            language,
                            "Diese Formularversion ist schreibgeschützt. Rechte oder Serverstand können sich geändert haben; der ungesendete Text bleibt sichtbar.",
                            "Ця версія форми лише для перегляду. Права або серверні дані могли змінитися; ненадісланий текст залишається видимим.",
                        ),
                        Modifier.testTag("authoring-readonly"),
                    )
                AuthoringEditor(
                    state.draft,
                    language,
                    state.draftWritable,
                    ZoneId.of(state.draftZoneId),
                    actions.change,
                )
                if (state.base == null)
                    AuthoringPublicationSettings(
                        state.draft,
                        state.draftZoneId,
                        language,
                        state.draftWritable,
                        now,
                        actions.change,
                    )
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    OutlinedButton(
                        actions.preview,
                        Modifier.testTag("authoring-preview"),
                        enabled = state.draftWritable && scheduleValid,
                    ) {
                        Text(at(language, "Vorschau", "Попередній перегляд"))
                    }
                    Button(
                        actions.submit,
                        Modifier.testTag("authoring-submit"),
                        enabled = state.draftWritable && scheduleValid,
                    ) {
                        Text(authoringSubmitText(state, language))
                    }
                }
                TextButton(
                    { discard = true },
                    Modifier.testTag("authoring-discard-local"),
                    enabled = !state.busy && state.uncertain == null,
                ) {
                    Text(
                        at(
                            language,
                            "Lokale Formularversion schließen",
                            "Закрити локальну версію форми",
                        )
                    )
                }
            }
        }
    }
    if (leave)
        AlertDialog(
            onDismissRequest = { leave = false },
            title = { Text(at(language, "Formular verlassen?", "Залишити форму?")) },
            text = {
                Text(
                    at(
                        language,
                        "Es wird nichts gesendet oder gelöscht. Gesicherte neue Entwürfe bleiben auf diesem Gerät; bestehende Beiträge behalten ihre ungesendete Bearbeitung nur in dieser Sitzung.",
                        "Нічого не буде надіслано чи видалено. Збережені нові чернетки залишаться на цьому пристрої; ненадіслані зміни наявних матеріалів — лише в цій сесії.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        leave = false
                        actions.back()
                    },
                    enabled = !state.busy,
                ) {
                    Text(at(language, "Zurück", "Назад"))
                }
            },
            dismissButton = {
                TextButton({ leave = false }) {
                    Text(at(language, "Weiter bearbeiten", "Продовжити редагування"))
                }
            },
        )
    if (discard)
        AlertDialog(
            onDismissRequest = { discard = false },
            title = { Text(at(language, "Lokalen Text verwerfen?", "Відкинути локальний текст?")) },
            text = {
                Text(
                    at(
                        language,
                        "Nur diese lokale Formularversion wird entfernt. Bereits gespeicherte Serverdaten bleiben unverändert.",
                        "Буде прибрано лише цю локальну версію форми. Уже збережені серверні дані не зміняться.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        discard = false
                        actions.discard()
                    },
                    enabled = !state.busy,
                ) {
                    Text(at(language, "Verwerfen", "Відкинути"))
                }
            },
            dismissButton = {
                TextButton({ discard = false }) { Text(at(language, "Abbrechen", "Скасувати")) }
            },
        )
    if (discardRecovered && state.recoveredDraft != null && state.uncertain == null)
        AlertDialog(
            onDismissRequest = { discardRecovered = false },
            title = {
                Text(
                    at(language, "Ungesendeten Entwurf löschen?", "Видалити ненадіслану чернетку?")
                )
            },
            text = {
                Text(
                    at(
                        language,
                        "Nur diese lokale, noch nicht gesendete Kopie wird gelöscht. Auf dem Server wird nichts geändert.",
                        "Буде видалено лише цю локальну ненадіслану копію. На сервері нічого не зміниться.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        discardRecovered = false
                        actions.discardRecoveredDraft()
                    },
                    Modifier.testTag("authoring-delete-draft-confirm"),
                    enabled = state.actionable,
                ) {
                    Text(at(language, "Löschen", "Видалити"))
                }
            },
            dismissButton = {
                TextButton({ discardRecovered = false }) {
                    Text(at(language, "Abbrechen", "Скасувати"))
                }
            },
        )
    state.confirmation
        ?.takeIf { state.session?.ready == true }
        ?.let { intent ->
            val review = intent.fields["moderationStatus"] == "pendingReview"
            val scheduled = intent.fields["scheduledAt"] as? Instant
            AlertDialog(
                onDismissRequest = actions.dismiss,
                title = { Text(at(language, "Beitrag bestätigen", "Підтвердити матеріал")) },
                text = {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(intent.fields.string("title"))
                        Text(
                            if (scheduled != null)
                                at(
                                    language,
                                    "Ein geplanter Server-Entwurf wird gespeichert, noch keine öffentliche Veröffentlichung. Bei Fälligkeit prüft der Server Rechte und Inhalt erneut.",
                                    "Буде збережено заплановану серверну чернетку, ще не публічний матеріал. У призначений час сервер знову перевірить права та вміст.",
                                )
                            else if (review)
                                at(
                                    language,
                                    "Dieser Beitrag wird zur Prüfung eingereicht und ist noch nicht öffentlich.",
                                    "Матеріал буде надіслано на перевірку й поки не стане публічним.",
                                )
                            else
                                at(
                                    language,
                                    "Diese Angaben werden jetzt für Ihre Organisation gespeichert. Veröffentlichte Beiträge sind öffentlich sichtbar.",
                                    "Ці дані буде збережено для вашої організації зараз. Опубліковані матеріали доступні всім.",
                                )
                        )
                        if (scheduled != null) {
                            AuthoringScheduleText(scheduled, state.draftZoneId, language)
                            if (!AuthoringPublication.canSend(intent, now))
                                Text(
                                    authoringFailureText(
                                        AuthoringFailure.INVALID,
                                        language,
                                        "schedule",
                                    )
                                )
                        }
                    }
                },
                confirmButton = {
                    TextButton(
                        actions.confirm,
                        Modifier.testTag("authoring-confirm"),
                        enabled = state.actionable && AuthoringPublication.canSend(intent, now),
                    ) {
                        Text(at(language, "Bestätigen", "Підтвердити"))
                    }
                },
                dismissButton = {
                    TextButton(actions.dismiss) { Text(at(language, "Abbrechen", "Скасувати")) }
                },
            )
        }
    if (state.preview && state.draft != null && state.session?.ready == true)
        ProtectedDialog(onDismissRequest = actions.closePreview) {
            Surface(shape = MaterialTheme.shapes.extraLarge) {
                Column(
                    Modifier.padding(24.dp).verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text(
                        at(
                            language,
                            "Lokale Vorschau · nicht gesendet",
                            "Локальний перегляд · не надіслано",
                        ),
                        style = MaterialTheme.typography.labelLarge,
                    )
                    val d = state.draft
                    Text(
                        if (language == "de") d.germanTitle.ifBlank { d.title } else d.title,
                        style = MaterialTheme.typography.headlineSmall,
                    )
                    Text(
                        if (language == "de") d.germanSummary.ifBlank { d.summary } else d.summary,
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(if (language == "de") d.germanBody.ifBlank { d.body } else d.body)
                    if (d.kind == ContentKind.EVENTS) {
                        Text(d.event.city + " · " + d.event.venue)
                        Text(d.event.address)
                    }
                    if (d.publicationMode == AuthoringPublicationMode.SCHEDULED)
                        d.scheduledAt?.let {
                            AuthoringScheduleText(it, state.draftZoneId, language)
                        }
                    TextButton(actions.closePreview) {
                        Text(at(language, "Zurück zum Formular", "Повернутися до форми"))
                    }
                }
            }
        }
}

@Composable
private fun AuthoringScheduleText(time: Instant, zoneId: String, language: String) {
    Text(
        at(language, "Geplante Veröffentlichung: ", "Запланована публікація: ") +
            DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm XXX")
                .withZone(ZoneId.of(zoneId))
                .format(time) +
            " · " +
            zoneId
    )
}

@Composable
private fun AuthoringPublicationSettings(
    draft: AuthoringDraft,
    zoneId: String,
    language: String,
    enabled: Boolean,
    now: Instant,
    change: ((AuthoringDraft) -> AuthoringDraft) -> Unit,
) {
    HorizontalDivider()
    Text(
        at(language, "Veröffentlichungszeit", "Час публікації"),
        style = MaterialTheme.typography.titleMedium,
    )
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        AuthoringPublicationMode.entries.forEach { mode ->
            FilterChip(
                draft.publicationMode == mode,
                {
                    change {
                        it.copy(
                            publicationMode = mode,
                            scheduledAt =
                                if (mode == AuthoringPublicationMode.SCHEDULED)
                                    // The NOW form may have been idle for hours without a ticker.
                                    it.scheduledAt
                                        ?: AuthoringPublication.initialTime(Instant.now())
                                else it.scheduledAt,
                        )
                    }
                },
                label = {
                    Text(
                        if (mode == AuthoringPublicationMode.NOW) at(language, "Jetzt", "Зараз")
                        else at(language, "Später planen", "Запланувати")
                    )
                },
                enabled = enabled,
                modifier = Modifier.testTag("authoring-publication-${mode.name.lowercase()}"),
            )
        }
    }
    if (draft.publicationMode == AuthoringPublicationMode.SCHEDULED) {
        draft.scheduledAt?.let { time ->
            AuthoringDateTime(
                at(language, "Datum", "Дата"),
                time,
                true,
                language,
                enabled,
                ZoneId.of(zoneId),
                "authoring-publication",
            ) {
                change { old -> old.copy(scheduledAt = it) }
            }
        }
        Text(
            at(language, "Zeitzone: ", "Часовий пояс: ") + zoneId,
            Modifier.testTag("authoring-publication-zone"),
        )
        Text(
            if (AuthoringPublication.hasEnoughLeadTime(draft.scheduledAt, now))
                at(
                    language,
                    "Mindestens fünf Minuten Vorlauf. Die Planung bestätigt noch keine spätere Freigabe; der Server prüft beim Veröffentlichen erneut.",
                    "Щонайменше п’ять хвилин наперед. Планування ще не підтверджує майбутню публікацію; сервер перевірить її знову.",
                )
            else authoringFailureText(AuthoringFailure.INVALID, language, "schedule"),
            Modifier.testTag("authoring-schedule-validation"),
        )
    }
}

@Composable
private fun AuthoringEditor(
    d: AuthoringDraft,
    language: String,
    enabled: Boolean,
    zone: ZoneId,
    change: ((AuthoringDraft) -> AuthoringDraft) -> Unit,
) {
    var section by remember(d.id) { mutableStateOf(0) }
    val sections =
        if (d.kind == ContentKind.EVENTS)
            listOf(
                at(language, "Text", "Текст"),
                at(language, "Details", "Деталі"),
                at(language, "Termine", "Дати"),
                at(language, "Teilnahme", "Участь"),
            )
        else listOf(at(language, "Text", "Текст"), at(language, "Details", "Деталі"))
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        sections.forEachIndexed { index, label ->
            FilterChip(
                section == index,
                { section = index },
                label = { Text(label) },
                modifier = Modifier.testTag("authoring-section-$index"),
            )
        }
    }
    fun update(block: (AuthoringDraft, String) -> AuthoringDraft): (String) -> Unit = { text ->
        change { block(it, text) }
    }
    when (section) {
        0 -> {
            Text("Українська", style = MaterialTheme.typography.titleMedium)
            AuthoringField(
                at(language, "Titel", "Заголовок"),
                d.title,
                "authoring-title",
                enabled,
                change = update { old, value -> old.copy(title = value) },
            )
            AuthoringField(
                at(language, "Zusammenfassung", "Короткий опис"),
                d.summary,
                "authoring-summary",
                enabled,
                true,
                update { old, value -> old.copy(summary = value) },
            )
            AuthoringField(
                at(language, "Text", "Текст"),
                d.body,
                "authoring-body",
                enabled,
                true,
                update { old, value -> old.copy(body = value) },
            )
            Text(
                at(language, "Deutsch · optional", "Deutsch · необов’язково"),
                style = MaterialTheme.typography.titleMedium,
            )
            AuthoringField(
                "Titel · Deutsch",
                d.germanTitle,
                "authoring-de-title",
                enabled,
                change = update { old, value -> old.copy(germanTitle = value) },
            )
            AuthoringField(
                "Zusammenfassung · Deutsch",
                d.germanSummary,
                "authoring-de-summary",
                enabled,
                true,
                update { old, value -> old.copy(germanSummary = value) },
            )
            AuthoringField(
                "Text · Deutsch",
                d.germanBody,
                "authoring-de-body",
                enabled,
                true,
                update { old, value -> old.copy(germanBody = value) },
            )
        }
        1 -> {
            AuthoringChoice(
                at(language, "Kategorie", "Категорія"),
                d.category,
                AuthoringContract.categories(d.kind),
                enabled,
                { authoringCategoryText(it, language) },
            ) { value ->
                change {
                    it.copy(
                        category = value,
                        additionalCategories = it.additionalCategories - value,
                    )
                }
            }
            Text(
                at(
                    language,
                    "Weitere Kategorien · höchstens 2",
                    "Додаткові категорії · не більше 2",
                )
            )
            AuthoringContract.categories(d.kind)
                .filterNot { it == d.category }
                .forEach { category ->
                    AuthoringCheckboxRow(
                        authoringCategoryText(category, language),
                        category in d.additionalCategories,
                        enabled &&
                            (category in d.additionalCategories || d.additionalCategories.size < 2),
                        "authoring-additional-category-$category",
                    ) { chosen ->
                        change {
                            it.copy(
                                additionalCategories =
                                    if (chosen) it.additionalCategories + category
                                    else it.additionalCategories - category
                            )
                        }
                    }
                }
            AuthoringField(
                at(language, "Tags · mit Komma trennen", "Теги · через кому"),
                d.tags,
                "authoring-tags",
                enabled,
                change = update { old, value -> old.copy(tags = value) },
            )
            if (d.kind == ContentKind.NEWS) {
                AuthoringChoice(
                    at(language, "Reichweite", "Охоплення"),
                    d.regionScope,
                    listOf("federalState", "austria"),
                    enabled,
                    {
                        if (it == "austria")
                            at(
                                language,
                                "Ganz Österreich · eventuell Prüfung",
                                "Уся Австрія · можлива перевірка",
                            )
                        else at(language, "Bundesland der Organisation", "Земля організації")
                    },
                ) { value ->
                    change { it.copy(regionScope = value) }
                }
                AuthoringField(
                    at(language, "Quelle · Name oder Weblink", "Джерело · назва або вебпосилання"),
                    d.source,
                    "authoring-source",
                    enabled,
                    change = update { old, value -> old.copy(source = value) },
                )
            }
            AuthoringField(
                at(language, "Link-Schaltfläche · Titel", "Назва кнопки посилання"),
                d.actionTitle,
                "authoring-action-title",
                enabled,
                change = update { old, value -> old.copy(actionTitle = value) },
            )
            AuthoringField(
                at(language, "HTTPS-Link", "HTTPS-посилання"),
                d.actionUrl,
                "authoring-action-url",
                enabled,
                change = update { old, value -> old.copy(actionUrl = value) },
            )
        }
        2 ->
            AuthoringEventDates(d.event, language, enabled, zone) { transform ->
                change { it.copy(event = transform(it.event)) }
            }
        3 ->
            AuthoringEventParticipation(d.event, language, enabled) { transform ->
                change { it.copy(event = transform(it.event)) }
            }
    }
}

@Composable
private fun AuthoringEventDates(
    d: AuthoringEventDraft,
    language: String,
    enabled: Boolean,
    zone: ZoneId,
    change: ((AuthoringEventDraft) -> AuthoringEventDraft) -> Unit,
) {
    fun update(block: (AuthoringEventDraft, String) -> AuthoringEventDraft): (String) -> Unit =
        { text ->
            change { block(it, text) }
        }
    AuthoringField(
        at(language, "Stadt", "Місто"),
        d.city,
        "authoring-city",
        enabled,
        change = update { old, value -> old.copy(city = value) },
    )
    AuthoringField(
        at(language, "Veranstaltungsort", "Місце проведення"),
        d.venue,
        "authoring-venue",
        enabled,
        change = update { old, value -> old.copy(venue = value) },
    )
    AuthoringField(
        at(language, "Adresse", "Адреса"),
        d.address,
        "authoring-address",
        enabled,
        change = update { old, value -> old.copy(address = value) },
    )
    AuthoringField(
        at(language, "Hinweis zum Ort", "Примітка щодо місця"),
        d.locationNote,
        "authoring-location-note",
        enabled,
        change = update { old, value -> old.copy(locationNote = value) },
    )
    Text(at(language, "Zeitzone: ", "Часовий пояс: ") + zone.id)
    d.occurrences.forEachIndexed { index, occurrence ->
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    at(language, "Termin ", "Дата ") + (index + 1),
                    style = MaterialTheme.typography.titleMedium,
                )
                fun row(transform: (AuthoringOccurrence) -> AuthoringOccurrence) {
                    change { old ->
                        old.copy(
                            occurrences =
                                old.occurrences.map {
                                    if (it.id == occurrence.id) transform(it) else it
                                }
                        )
                    }
                }
                AuthoringCheckboxRow(
                    at(language, "Ganztägig", "Увесь день"),
                    occurrence.allDay,
                    enabled,
                    "authoring-all-day-${occurrence.id}",
                ) { value ->
                    row { it.copy(allDay = value) }
                }
                AuthoringDateTime(
                    at(language, "Beginn", "Початок"),
                    occurrence.start,
                    !occurrence.allDay,
                    language,
                    enabled,
                    zone,
                ) { value ->
                    row { it.copy(start = value) }
                }
                AuthoringCheckboxRow(
                    at(language, "Ende bekannt", "Час завершення відомий"),
                    occurrence.endKnown,
                    enabled,
                    "authoring-end-known-${occurrence.id}",
                ) { value ->
                    row { it.copy(endKnown = value) }
                }
                if (occurrence.endKnown)
                    AuthoringDateTime(
                        at(language, "Ende", "Завершення"),
                        occurrence.end,
                        !occurrence.allDay,
                        language,
                        enabled,
                        zone,
                    ) { value ->
                        row { it.copy(end = value) }
                    }
                if (index > 0)
                    TextButton(
                        {
                            change { old ->
                                old.copy(
                                    occurrences =
                                        old.occurrences.filterNot { it.id == occurrence.id }
                                )
                            }
                        },
                        enabled = enabled,
                    ) {
                        Text(at(language, "Termin entfernen", "Прибрати дату"))
                    }
            }
        }
    }
    TextButton(
        {
            change { old ->
                val last = old.occurrences.last()
                old.copy(
                    occurrences =
                        old.occurrences +
                            last.copy(
                                id = java.util.UUID.randomUUID().toString(),
                                start =
                                    last.start
                                        .atZone(ZoneId.systemDefault())
                                        .plusDays(1)
                                        .toInstant(),
                                end =
                                    last.end.atZone(ZoneId.systemDefault()).plusDays(1).toInstant(),
                                status = "scheduled",
                            )
                )
            }
        },
        enabled = enabled && d.occurrences.size in 1..29,
    ) {
        Text(at(language, "Weiteren Termin hinzufügen", "Додати ще дату"))
    }
}

@Composable
private fun AuthoringCheckboxRow(
    label: String,
    checked: Boolean,
    enabled: Boolean,
    tag: String,
    change: (Boolean) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth()
            .heightIn(min = 48.dp)
            .testTag(tag)
            .toggleable(
                value = checked,
                enabled = enabled,
                role = Role.Checkbox,
                onValueChange = change,
            ),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(checked, onCheckedChange = null, enabled = enabled)
        Text(label, Modifier.weight(1f).padding(vertical = 12.dp))
    }
}

@Composable
private fun AuthoringEventParticipation(
    d: AuthoringEventDraft,
    language: String,
    enabled: Boolean,
    change: ((AuthoringEventDraft) -> AuthoringEventDraft) -> Unit,
) {
    fun update(block: (AuthoringEventDraft, String) -> AuthoringEventDraft): (String) -> Unit =
        { text ->
            change { block(it, text) }
        }
    AuthoringChoice(
        at(language, "Teilnahme", "Участь"),
        d.participation,
        AuthoringContract.participationModes,
        enabled,
        { authoringParticipationText(it, language) },
    ) { value ->
        change { it.copy(participation = value) }
    }
    if (d.participation in setOf("externalRegistration", "externalTickets"))
        Text(
            at(
                language,
                "Den HTTPS-Anmeldelink bitte unter Details angeben.",
                "HTTPS-посилання для реєстрації вкажіть у розділі «Деталі».",
            )
        )
    if (d.participation == "inAppRegistration")
        AuthoringField(
            at(language, "Kapazität · leer = unbegrenzt", "Місця · порожньо = без обмеження"),
            d.capacity,
            "authoring-capacity",
            enabled,
            change = update { old, value -> old.copy(capacity = value) },
        )
    AuthoringChoice(
        at(language, "Preis", "Ціна"),
        d.priceKind,
        AuthoringContract.priceKinds,
        enabled,
        { authoringPriceText(it, language) },
    ) { value ->
        change { it.copy(priceKind = value) }
    }
    if (d.priceKind in setOf("exact", "startingFrom", "range"))
        AuthoringField(
            at(language, "Betrag · ", "Сума · ") + d.currency,
            d.amount,
            "authoring-price",
            enabled,
            change = update { old, value -> old.copy(amount = value) },
        )
    if (d.priceKind == "range")
        AuthoringField(
            at(language, "Höchstbetrag", "Максимальна сума"),
            d.maximumAmount,
            "authoring-price-max",
            enabled,
            change = update { old, value -> old.copy(maximumAmount = value) },
        )
    AuthoringField(
        at(language, "Preishinweis", "Примітка до ціни"),
        d.priceNote,
        "authoring-price-note",
        enabled,
        change = update { old, value -> old.copy(priceNote = value) },
    )
    AuthoringChoice(
        at(language, "Zielgruppe", "Аудиторія"),
        d.audience,
        AuthoringContract.audiences,
        enabled,
        { authoringAudienceText(it, language) },
    ) { value ->
        change { it.copy(audience = value) }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.weight(1f)) {
            AuthoringField(
                at(language, "Alter ab", "Вік від"),
                d.minimumAge,
                "authoring-min-age",
                enabled,
                change = update { old, value -> old.copy(minimumAge = value) },
            )
        }
        Box(Modifier.weight(1f)) {
            AuthoringField(
                at(language, "Alter bis", "Вік до"),
                d.maximumAge,
                "authoring-max-age",
                enabled,
                change = update { old, value -> old.copy(maximumAge = value) },
            )
        }
    }
    AuthoringField(
        at(language, "Veranstalter", "Організатор"),
        d.organizer,
        "authoring-organizer",
        enabled,
        change = update { old, value -> old.copy(organizer = value) },
    )
    AuthoringField(
        at(language, "Veranstalter · Weblink", "Вебпосилання організатора"),
        d.organizerUrl,
        "authoring-organizer-url",
        enabled,
        change = update { old, value -> old.copy(organizerUrl = value) },
    )
    AuthoringField(
        at(language, "Telefon", "Телефон"),
        d.contactPhone,
        "authoring-contact-phone",
        enabled,
        change = update { old, value -> old.copy(contactPhone = value) },
    )
    AuthoringField(
        "E-Mail",
        d.contactEmail,
        "authoring-contact-email",
        enabled,
        change = update { old, value -> old.copy(contactEmail = value) },
    )
    AuthoringField(
        at(language, "Kontakt · Weblink", "Контактне вебпосилання"),
        d.contactUrl,
        "authoring-contact-url",
        enabled,
        change = update { old, value -> old.copy(contactUrl = value) },
    )
}

@Composable
private fun AuthoringField(
    label: String,
    value: String,
    tag: String,
    enabled: Boolean,
    multiline: Boolean = false,
    change: (String) -> Unit,
) {
    OutlinedTextField(
        value,
        change,
        Modifier.fillMaxWidth().testTag(tag),
        label = { Text(label) },
        enabled = enabled,
        singleLine = !multiline,
        minLines = if (multiline) 3 else 1,
        maxLines = if (multiline) 12 else 1,
    )
}

@Composable
private fun AuthoringChoice(
    label: String,
    value: String,
    options: List<String>,
    enabled: Boolean,
    title: (String) -> String,
    change: (String) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        OutlinedButton({ open = true }, enabled = enabled) { Text("$label: ${title(value)}") }
        DropdownMenu(open, { open = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(title(option)) },
                    onClick = {
                        open = false
                        change(option)
                    },
                )
            }
        }
    }
}

/** DatePicker uses UTC dates, while authored event time belongs to the displayed local zone. */
object AuthoringCalendar {
    fun resolve(date: LocalDate, time: LocalTime, zone: ZoneId, previous: Instant): Instant? {
        val local = date.atTime(time.withSecond(0).withNano(0))
        val offsets = zone.rules.getValidOffsets(local)
        if (offsets.isEmpty()) return null
        val priorOffset = previous.atZone(zone).offset
        return local.toInstant(priorOffset.takeIf { it in offsets } ?: offsets.first())
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun AuthoringDateTime(
    label: String,
    value: Instant,
    withTime: Boolean,
    language: String,
    enabled: Boolean,
    zone: ZoneId,
    tag: String = "",
    change: (Instant) -> Unit,
) {
    var dateOpen by remember(language) { mutableStateOf(false) }
    var timeOpen by remember(language) { mutableStateOf(false) }
    val local = value.atZone(zone)
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        OutlinedButton(
            { dateOpen = true },
            if (tag.isEmpty()) Modifier else Modifier.testTag("$tag-date"),
            enabled = enabled,
        ) {
            Text(label + ": " + local.format(DateTimeFormatter.ofPattern("dd.MM.yyyy")))
        }
        if (withTime)
            OutlinedButton(
                { timeOpen = true },
                if (tag.isEmpty()) Modifier else Modifier.testTag("$tag-time"),
                enabled = enabled,
            ) {
                Text(local.format(DateTimeFormatter.ofPattern("HH:mm")))
            }
    }
    if (dateOpen) {
        PickerLocale(language) {
            val picker =
                rememberDatePickerState(
                    initialSelectedDateMillis =
                        local.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
                )
            val date =
                picker.selectedDateMillis?.let {
                    Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                }
            val selected = date?.let {
                AuthoringCalendar.resolve(it, local.toLocalTime(), zone, value)
            }
            AuthoringPickerDialog(
                language,
                { dateOpen = false },
                selected != null,
                {
                    selected?.let(change)
                    dateOpen = false
                },
            ) {
                DatePicker(picker)
            }
        }
    }
    if (timeOpen) {
        PickerLocale(language) {
            val picker = rememberTimePickerState(local.hour, local.minute, is24Hour = true)
            val selected =
                AuthoringCalendar.resolve(
                    local.toLocalDate(),
                    LocalTime.of(picker.hour, picker.minute),
                    zone,
                    value,
                )
            AuthoringPickerDialog(
                language,
                { timeOpen = false },
                selected != null,
                {
                    selected?.let(change)
                    timeOpen = false
                },
            ) {
                TimePicker(picker)
                if (selected == null)
                    Text(
                        at(
                            language,
                            "Diese Uhrzeit existiert an diesem Datum wegen der Zeitumstellung nicht.",
                            "Цього часу немає в цю дату через переведення годинника.",
                        )
                    )
            }
        }
    }
}

@Composable
private fun AuthoringPickerDialog(
    language: String,
    dismiss: () -> Unit,
    enabled: Boolean,
    confirm: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    ProtectedDialog(dismiss, DialogProperties(usePlatformDefaultWidth = false)) {
        // Dialog creates a new Android composition owner and re-provides platform locals.
        PickerLocale(language) {
            Surface(
                Modifier.padding(20.dp).widthIn(max = 560.dp).fillMaxWidth(),
                shape = MaterialTheme.shapes.extraLarge,
            ) {
                Column(
                    Modifier.padding(16.dp).verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    content()
                    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        TextButton(dismiss, Modifier.heightIn(min = 48.dp)) {
                            Text(at(language, "Abbrechen", "Скасувати"))
                        }
                        TextButton(confirm, Modifier.heightIn(min = 48.dp), enabled = enabled) {
                            Text(at(language, "Übernehmen", "Застосувати"))
                        }
                    }
                }
            }
        }
    }
}

private fun at(language: String, de: String, uk: String) = if (language == "uk") uk else de

fun authoringStatusText(status: AuthoringStatus, language: String): String =
    when (status) {
        AuthoringStatus.APPROVED -> at(language, "Veröffentlicht", "Опубліковано")
        AuthoringStatus.REVIEW -> at(language, "In Prüfung", "На перевірці")
        AuthoringStatus.REJECTED -> at(language, "Abgelehnt", "Відхилено")
        AuthoringStatus.ARCHIVED -> at(language, "Archiviert / abgesagt", "Архівовано / скасовано")
        AuthoringStatus.SCHEDULED ->
            at(language, "Geplant · schreibgeschützt", "Заплановано · лише перегляд")
    }

private fun authoringSubmitText(state: AuthoringState, language: String): String =
    when {
        state.base == null && state.draft?.publicationMode == AuthoringPublicationMode.SCHEDULED ->
            at(language, "Veröffentlichung planen", "Запланувати публікацію")
        state.draft?.kind == ContentKind.NEWS &&
            state.draft.regionScope == "austria" &&
            state.session?.globalRole != "owner" &&
            (state.base == null || state.base.status == AuthoringStatus.APPROVED) ->
            at(language, "Zur Prüfung einreichen", "Надіслати на перевірку")
        state.base != null -> at(language, "Änderungen speichern", "Зберегти зміни")
        else -> at(language, "Jetzt veröffentlichen", "Опублікувати зараз")
    }

fun authoringFailureText(
    reason: AuthoringFailure,
    language: String,
    field: String? = null,
): String =
    when (reason) {
        AuthoringFailure.SIGN_IN,
        AuthoringFailure.NOT_READY ->
            at(
                language,
                "Bitte zuerst das Konto und seine Sicherheitsanforderungen bestätigen.",
                "Спочатку підтвердьте акаунт і виконайте його вимоги безпеки.",
            )
        AuthoringFailure.DENIED ->
            at(
                language,
                "Für diese Aktion fehlen aktuelle Organisationsrechte.",
                "Для цієї дії немає актуальних прав організації.",
            )
        AuthoringFailure.MISSING ->
            at(language, "Der Eintrag ist nicht mehr verfügbar.", "Запис більше недоступний.")
        AuthoringFailure.STALE ->
            at(
                language,
                "Die Daten wurden geändert. Aktuellen Stand laden und eine neue Entscheidung treffen.",
                "Дані змінилися. Завантажте актуальну версію та ухваліть нове рішення.",
            )
        AuthoringFailure.OFFLINE ->
            at(
                language,
                "Der lokale Server ist nicht erreichbar. Es wurde keine neue Bestätigung erhalten.",
                "Локальний сервер недоступний. Нового підтвердження немає.",
            )
        AuthoringFailure.INDEX ->
            at(
                language,
                "Diese Abfrage ist lokal noch nicht vollständig eingerichtet.",
                "Цей запит ще не повністю налаштовано локально.",
            )
        AuthoringFailure.UNCONFIRMED ->
            at(
                language,
                "Das Ergebnis ist noch nicht bestätigt. Nicht erneut veröffentlichen; zuerst den Serverstand prüfen.",
                "Результат ще не підтверджено. Не публікуйте повторно; спочатку перевірте стан на сервері.",
            )
        AuthoringFailure.INVALID ->
            at(
                language,
                "Bitte Pflichtfelder, Längen, Links und Datumsangaben prüfen",
                "Перевірте обов’язкові поля, довжину, посилання та дати",
            ) + field?.let { ": " + authoringFieldText(it, language) }.orEmpty() + "."
        AuthoringFailure.UNKNOWN ->
            at(
                language,
                "Die Aktion konnte nicht bestätigt werden. Bitte den aktuellen Stand prüfen.",
                "Дію не вдалося підтвердити. Перевірте актуальний стан.",
            )
    }

private fun authoringFieldText(key: String, language: String) =
    when (key) {
        "title",
        "germanTitle" ->
            at(language, "Titel · höchstens 120 Zeichen", "заголовок · не більше 120 символів")
        "summary",
        "germanSummary" ->
            at(
                language,
                "Zusammenfassung · höchstens 200 Zeichen",
                "короткий опис · не більше 200 символів",
            )
        "body",
        "germanBody" -> at(language, "Text", "текст")
        "category" -> at(language, "Kategorie", "категорія")
        "tags" ->
            at(language, "höchstens 8 Tags mit je 30 Zeichen", "не більше 8 тегів по 30 символів")
        "dates" -> at(language, "Termine und Reihenfolge", "дати та їх порядок")
        "schedule" ->
            at(
                language,
                "Veröffentlichungszeit · mindestens fünf Minuten in der Zukunft",
                "час публікації · щонайменше через п’ять хвилин",
            )
        "price" ->
            at(
                language,
                "Preis · nicht negativ, höchstens zwei Dezimalstellen",
                "ціна · невід’ємна, не більше двох десяткових знаків",
            )
        "capacity" ->
            at(
                language,
                "Kapazität · positive ganze Zahl, nicht unter bestehenden Anmeldungen",
                "місця · додатне ціле число, не менше наявних реєстрацій",
            )
        "age" ->
            at(
                language,
                "Alter · 0 bis 120, Mindestalter nicht über Höchstalter",
                "вік · від 0 до 120, нижня межа не більша за верхню",
            )
        "region" -> at(language, "Bundesland der Organisation", "федеральна земля організації")
        "city" -> at(language, "Stadt", "місто")
        "venue",
        "address",
        "locationNote" -> at(language, "Veranstaltungsort / Adresse", "місце / адреса")
        "participation",
        "action" -> at(language, "Teilnahme und HTTPS-Link", "участь і HTTPS-посилання")
        else -> at(language, "Kontakt / Quelle / Weblink", "контакт / джерело / вебпосилання")
    }

private fun authoringCategoryText(value: String, language: String): String {
    val labels =
        mapOf(
            "news" to ("Nachrichten" to "Новини"),
            "event" to ("Veranstaltungen" to "Події"),
            "lawAndDocuments" to ("Recht & Dokumente" to "Право й документи"),
            "benefitsAndSupport" to ("Leistungen & Unterstützung" to "Виплати й підтримка"),
            "financeTaxesAndConsumerRights" to
                ("Finanzen & Verbraucherrechte" to "Фінанси й права споживачів"),
            "health" to ("Gesundheit" to "Здоров’я"),
            "safetyAndEmergencies" to ("Sicherheit" to "Безпека"),
            "work" to ("Arbeit" to "Робота"),
            "education" to ("Bildung" to "Освіта"),
            "housing" to ("Wohnen" to "Житло"),
            "transport" to ("Verkehr" to "Транспорт"),
            "communityAndIntegration" to ("Gemeinschaft & Integration" to "Спільнота й інтеграція"),
            "culture" to ("Kultur" to "Культура"),
            "other" to ("Sonstiges" to "Інше"),
            "meetups" to ("Treffen" to "Зустрічі"),
            "training" to ("Kurse" to "Тренінги"),
            "childrenAndFamily" to ("Kinder & Familie" to "Діти й сім’я"),
            "sportsAndWellness" to ("Sport & Wohlbefinden" to "Спорт і здоров’я"),
            "excursionsAndNature" to ("Ausflüge & Natur" to "Подорожі й природа"),
            "music" to ("Musik" to "Музика"),
            "nightlifeAndParties" to ("Partys" to "Вечірки"),
            "foodAndMarket" to ("Essen & Märkte" to "Їжа й ринки"),
            "festivalsAndFairs" to ("Festivals & Messen" to "Фестивалі й ярмарки"),
            "businessAndNetworking" to ("Berufliche Kontakte" to "Ділові контакти"),
            "volunteering" to ("Freiwilligenarbeit" to "Волонтерство"),
            "supportAndIntegration" to ("Unterstützung & Integration" to "Підтримка й інтеграція"),
            "celebration" to ("Feiern" to "Свята"),
            "saleAndPromotion" to ("Angebote & Aktionen" to "Пропозиції й акції"),
        )
    return labels[value]?.let { at(language, it.first, it.second) }
        ?: at(language, "Kategorie prüfen", "Перевірте категорію")
}

private fun authoringParticipationText(value: String, language: String) =
    when (value) {
        "none" -> at(language, "Ohne Anmeldung", "Без реєстрації")
        "inAppRegistration" -> at(language, "Anmeldung in der App", "Реєстрація в застосунку")
        "externalRegistration" -> at(language, "Externe Anmeldung", "Зовнішня реєстрація")
        else -> at(language, "Externe Tickets", "Зовнішні квитки")
    }

private fun authoringPriceText(value: String, language: String) =
    when (value) {
        "unspecified" -> at(language, "Keine Angabe", "Не вказано")
        "free" -> at(language, "Kostenlos", "Безкоштовно")
        "exact" -> at(language, "Fester Preis", "Фіксована ціна")
        "startingFrom" -> at(language, "Ab", "Від")
        else -> at(language, "Preisspanne", "Діапазон цін")
    }

private fun authoringAudienceText(value: String, language: String) =
    when (value) {
        "everyone" -> at(language, "Alle", "Усі")
        "families" -> at(language, "Familien", "Сім’ї")
        "children" -> at(language, "Kinder", "Діти")
        "teens" -> at(language, "Jugendliche", "Підлітки")
        "adults" -> at(language, "Erwachsene", "Дорослі")
        else -> at(language, "Senioren", "Літні люди")
    }
