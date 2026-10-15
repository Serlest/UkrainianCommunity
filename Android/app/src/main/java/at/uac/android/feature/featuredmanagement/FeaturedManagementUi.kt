package at.uac.android.feature.featuredmanagement

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.design.UacBackButton
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.design.UacSymbol
import at.uac.android.feature.browse.PublicImage
import at.uac.android.feature.browse.PublicImagePresentation
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.translation.ContentTranslationButton
import at.uac.android.feature.translation.TranslationField

@Composable
fun FeaturedManagementScreen(
    model: FeaturedManagementViewModel,
    session: ModerationSession?,
    language: String,
    onBack: () -> Unit,
) {
    val state by model.state.collectAsState()
    LaunchedEffect(session) { model.load(session) }
    var confirmLeave by remember { mutableStateOf(false) }
    val back: () -> Unit = {
        if (!state.saving && !state.uploading) {
            if (state.editing == null) onBack() else confirmLeave = true
        }
    }
    androidx.activity.compose.BackHandler(onBack = back)
    if (confirmLeave && state.editing != null) {
        at.uac.android.core.ProtectedAlertDialog(
            onDismissRequest = { confirmLeave = false },
            title = { Text(if (language == "uk") "Закрити редактор?" else "Editor schließen?") },
            text = {
                Text(
                    if (language == "uk") "Незбережені зміни буде втрачено."
                    else "Nicht gespeicherte Änderungen gehen verloren."
                )
            },
            confirmButton = {
                TextButton(
                    {
                        confirmLeave = false
                        model.closeEditor()
                    },
                    enabled = !state.saving && !state.uploading,
                ) {
                    Text(if (language == "uk") "Закрити" else "Schließen")
                }
            },
            dismissButton = {
                TextButton({ confirmLeave = false }) {
                    Text(if (language == "uk") "Продовжити" else "Weiter bearbeiten")
                }
            },
        )
    }
    Column(Modifier.fillMaxSize().testTag("featured-management")) {
        Column(
            Modifier.fillMaxWidth().padding(bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            UacBackButton(back, Modifier.testTag("featured-back")) {
                UacSymbol(UacIcon.BACK)
                Text(if (language == "uk") "Назад" else "Zurück")
            }
            UacSectionHeading(
                if (language == "uk") "Рекомендовані банери" else "Empfohlene Banner",
                UacIcon.NEWS,
            )
        }
        if (state.editing != null) FeaturedEditor(model, session, state, language)
        else FeaturedList(model, session, state, language)
    }
}

@Composable
private fun FeaturedList(
    model: FeaturedManagementViewModel,
    session: ModerationSession?,
    state: FeaturedState,
    language: String,
) {
    LazyColumn(
        Modifier.fillMaxSize().testTag("featured-list"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        item {
            Text(
                if (language == "uk")
                    "Створюйте, впорядковуйте й публікуйте банери для головної, подій та організацій."
                else
                    "Banner für Startseite, Veranstaltungen und Organisationen erstellen, sortieren und veröffentlichen."
            )
        }
        state.failure?.let {
            item { FeaturedError(it, state.unconfirmed, language) { model.load(session) } }
        }
        item {
            Button(
                model::create,
                Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("featured-create"),
                enabled =
                    session?.ready == true &&
                        session.role == "owner" &&
                        !state.loading &&
                        !state.saving,
            ) {
                Text(if (language == "uk") "Створити банер" else "Banner erstellen")
            }
        }
        if (state.loading)
            item { LinearProgressIndicator(Modifier.fillMaxWidth().testTag("featured-loading")) }
        if (!state.loading && state.banners.isEmpty())
            item {
                Text(
                    if (language == "uk") "Банерів ще немає." else "Noch keine Banner.",
                    Modifier.testTag("featured-empty"),
                )
            }
        items(state.banners, key = { it.id }) { banner ->
            ElevatedCard(Modifier.fillMaxWidth().testTag("featured-row-${banner.id}")) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    FeaturedImagePreview(banner.draft, language)
                    Text(
                        banner.draft.internalName.ifBlank {
                            banner.draft.localizations[language]?.title
                                ?: banner.draft.title.ifBlank { banner.id }
                        },
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        (if (language == "uk") "Пріоритет: " else "Priorität: ") +
                            banner.draft.priority +
                            " · " +
                            banner.draft.sections.joinToString {
                                featuredSectionLabel(it, language)
                            },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (banner.repairRequired)
                        Text(
                            if (language == "uk") "Потрібне виправлення перед активацією"
                            else "Vor Aktivierung reparieren",
                            color = MaterialTheme.colorScheme.error,
                        )
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(
                            { model.edit(banner) },
                            enabled = !state.saving,
                            modifier = Modifier.testTag("featured-edit-${banner.id}"),
                        ) {
                            Text(if (language == "uk") "Редагувати" else "Bearbeiten")
                        }
                        FilterChip(
                            selected = banner.draft.active,
                            onClick = { model.active(session, banner, !banner.draft.active) },
                            label = {
                                Text(
                                    if (banner.draft.active)
                                        (if (language == "uk") "Активний" else "Aktiv")
                                    else (if (language == "uk") "Неактивний" else "Inaktiv")
                                )
                            },
                            enabled =
                                !state.saving && (!banner.repairRequired || banner.draft.active),
                            modifier = Modifier.testTag("featured-active-${banner.id}"),
                        )
                    }
                    var confirmsDelete by remember { mutableStateOf(false) }
                    if (confirmsDelete) {
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(
                                {
                                    confirmsDelete = false
                                    model.delete(session, banner)
                                },
                                colors =
                                    ButtonDefaults.buttonColors(
                                        containerColor = MaterialTheme.colorScheme.error
                                    ),
                                enabled = !state.saving,
                                modifier = Modifier.testTag("featured-delete-confirm-${banner.id}"),
                            ) {
                                Text(
                                    if (language == "uk") "Підтвердити видалення"
                                    else "Löschen bestätigen"
                                )
                            }
                            TextButton({ confirmsDelete = false }) {
                                Text(if (language == "uk") "Скасувати" else "Abbrechen")
                            }
                        }
                    } else
                        TextButton(
                            { confirmsDelete = true },
                            enabled = !state.saving,
                            modifier = Modifier.testTag("featured-delete-${banner.id}"),
                        ) {
                            Text(if (language == "uk") "Видалити" else "Löschen")
                        }
                }
            }
        }
    }
}

@Composable
private fun FeaturedEditor(
    model: FeaturedManagementViewModel,
    session: ModerationSession?,
    state: FeaturedState,
    language: String,
) {
    val draft = state.editing ?: return
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) {
            it?.let { uri -> model.upload(session, uri.toString()) }
        }
    LazyColumn(
        Modifier.fillMaxSize().testTag("featured-editor"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        item {
            Text(
                if (state.editingVersion == null)
                    (if (language == "uk") "Новий банер" else "Neuer Banner")
                else (if (language == "uk") "Редагування банера" else "Banner bearbeiten"),
                style = MaterialTheme.typography.titleLarge,
            )
        }
        state.failure?.let {
            item { FeaturedError(it, state.unconfirmed, language) { model.load(session) } }
        }
        item {
            OutlinedTextField(
                draft.internalName,
                { value -> model.change { it.copy(internalName = value) } },
                label = { Text(if (language == "uk") "Внутрішня назва" else "Interner Name") },
                modifier = Modifier.fillMaxWidth().testTag("featured-internal-name"),
                singleLine = true,
            )
        }
        for (code in listOf("uk", "de")) {
            item {
                val localized = draft.localizations[code] ?: FeaturedLocalized()
                at.uac.android.design.UacSectionCard(
                    if (code == "uk") "Українська" else "Deutsch"
                ) {
                    OutlinedTextField(
                        localized.title,
                        { value ->
                            model.change { current ->
                                current.copy(
                                    localizations =
                                        current.localizations +
                                            (code to localized.copy(title = value))
                                )
                            }
                        },
                        label = { Text(if (language == "uk") "Заголовок" else "Titel") },
                        modifier = Modifier.fillMaxWidth().testTag("featured-title-$code"),
                    )
                    OutlinedTextField(
                        localized.subtitle,
                        { value ->
                            model.change { current ->
                                current.copy(
                                    localizations =
                                        current.localizations +
                                            (code to localized.copy(subtitle = value))
                                )
                            }
                        },
                        label = { Text(if (language == "uk") "Підзаголовок" else "Untertitel") },
                        modifier = Modifier.fillMaxWidth().testTag("featured-subtitle-$code"),
                    )
                }
            }
        }
        item {
            val uk = draft.localizations["uk"] ?: FeaturedLocalized()
            val de = draft.localizations["de"] ?: FeaturedLocalized()
            ContentTranslationButton(
                kind = "banner",
                language = language,
                fields =
                    listOf(
                        TranslationField(
                            "title",
                            if (language == "uk") "Заголовок" else "Titel",
                            uk.title,
                            de.title,
                            120,
                        ),
                        TranslationField(
                            "subtitle",
                            if (language == "uk") "Підзаголовок" else "Untertitel",
                            uk.subtitle,
                            de.subtitle,
                            240,
                        ),
                    ),
                enabled = !state.saving && !state.uploading,
            ) { translated ->
                model.change { current ->
                    val currentDe = current.localizations["de"] ?: FeaturedLocalized()
                    current.copy(
                        localizations =
                            current.localizations +
                                ("de" to
                                    currentDe.copy(
                                        title = translated["title"] ?: currentDe.title,
                                        subtitle = translated["subtitle"] ?: currentDe.subtitle,
                                    ))
                    )
                }
            }
        }
        item {
            OutlinedTextField(
                draft.imageUrl,
                { value -> model.change { it.copy(imageUrl = value) } },
                label = {
                    Text(if (language == "uk") "Посилання на зображення" else "Bildadresse")
                },
                modifier = Modifier.fillMaxWidth().testTag("featured-image-url"),
            )
            if (draft.imageUrl.isNotBlank()) {
                Spacer(Modifier.height(8.dp))
                FeaturedImagePreview(draft, language)
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                {
                    picker.launch(
                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                    )
                },
                enabled = !state.uploading && !state.saving,
                modifier = Modifier.fillMaxWidth().testTag("featured-image-pick"),
            ) {
                Text(
                    if (state.uploading)
                        (if (language == "uk") "Завантаження…" else "Wird hochgeladen…")
                    else
                        (if (language == "uk") "Вибрати зображення 16:9" else "16:9-Bild auswählen")
                )
            }
        }
        item {
            Text(
                if (language == "uk") "Дія" else "Aktion",
                style = MaterialTheme.typography.titleMedium,
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                FeaturedAction.entries.forEach { action ->
                    FilterChip(
                        draft.action == action,
                        { model.change { it.copy(action = action) } },
                        { Text(featuredActionLabel(action, language)) },
                        Modifier.padding(end = 6.dp).testTag("featured-action-${action.wire}"),
                    )
                }
            }
            if (draft.action.needsTarget)
                OutlinedTextField(
                    draft.actionTargetId,
                    { value -> model.change { it.copy(actionTargetId = value) } },
                    label = {
                        Text(if (language == "uk") "Ідентифікатор матеріалу" else "Inhaltskennung")
                    },
                    modifier = Modifier.fillMaxWidth().testTag("featured-target"),
                )
            if (draft.action == FeaturedAction.EXTERNAL_URL)
                OutlinedTextField(
                    draft.externalUrl,
                    { value -> model.change { it.copy(externalUrl = value) } },
                    label = { Text("HTTPS URL") },
                    modifier = Modifier.fillMaxWidth().testTag("featured-external-url"),
                )
        }
        item {
            Text(
                if (language == "uk") "Розділи" else "Bereiche",
                style = MaterialTheme.typography.titleMedium,
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                FeaturedSection.entries.forEach { section ->
                    FilterChip(
                        section in draft.sections,
                        {
                            model.change { current ->
                                current.copy(
                                    sections =
                                        if (section in current.sections) current.sections - section
                                        else current.sections + section
                                )
                            }
                        },
                        { Text(featuredSectionLabel(section, language)) },
                        Modifier.padding(end = 6.dp).testTag("featured-section-${section.wire}"),
                    )
                }
            }
        }
        item {
            Text(
                if (language == "uk") "Регіон" else "Region",
                style = MaterialTheme.typography.titleMedium,
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                FeaturedRegion.entries.forEach { region ->
                    FilterChip(
                        draft.region == region,
                        { model.change { it.copy(region = region) } },
                        {
                            Text(
                                if (region == FeaturedRegion.FEDERAL_STATE)
                                    (if (language == "uk") "Федеральна земля" else "Bundesland")
                                else (if (language == "uk") "Уся Австрія" else "Ganz Österreich")
                            )
                        },
                        Modifier.padding(end = 6.dp),
                    )
                }
            }
            if (draft.region == FeaturedRegion.FEDERAL_STATE) {
                var choosingState by remember { mutableStateOf(false) }
                Box(Modifier.fillMaxWidth()) {
                    OutlinedButton(
                        { choosingState = true },
                        modifier = Modifier.fillMaxWidth().testTag("featured-state"),
                    ) {
                        UacSymbol(UacIcon.LOCATION, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(8.dp))
                        Text(
                            at.uac.android.feature.browse.regions
                                .firstOrNull { it.first == draft.federalState }
                                ?.second
                                ?: if (language == "uk") "Оберіть федеральну землю"
                                else "Bundesland auswählen"
                        )
                    }
                    at.uac.android.core.ProtectedDropdownMenu(
                        choosingState,
                        { choosingState = false },
                    ) {
                        at.uac.android.feature.browse.regions
                            .filter { it.first in FeaturedManagementContract.states }
                            .forEach { (code, name) ->
                                DropdownMenuItem(
                                    text = { Text(name) },
                                    onClick = {
                                        model.change { it.copy(federalState = code) }
                                        choosingState = false
                                    },
                                )
                            }
                    }
                }
            }
        }
        item {
            OutlinedTextField(
                draft.priority.toString(),
                { value ->
                    value.toIntOrNull()?.let { number ->
                        model.change { it.copy(priority = number) }
                    }
                },
                label = {
                    Text(if (language == "uk") "Пріоритет (0–1000)" else "Priorität (0–1000)")
                },
                modifier = Modifier.fillMaxWidth().testTag("featured-priority"),
            )
        }
        item {
            OutlinedTextField(
                draft.displayDurationSeconds.toString(),
                { value ->
                    value.toIntOrNull()?.let { number ->
                        model.change { it.copy(displayDurationSeconds = number) }
                    }
                },
                label = { Text(if (language == "uk") "Тривалість (3–12 с)" else "Dauer (3–12 s)") },
                modifier = Modifier.fillMaxWidth().testTag("featured-duration"),
            )
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Checkbox(
                    draft.active,
                    { checked -> model.change { it.copy(active = checked) } },
                    enabled = !state.saving,
                )
                Text(
                    if (language == "uk") "Активувати після збереження"
                    else "Nach dem Speichern aktivieren"
                )
            }
        }
        item {
            Text(
                if (language == "uk")
                    "Перед збереженням дані перевіряються повторно. Якщо банер змінився, оновіть його та перевірте свої зміни."
                else
                    "Vor dem Speichern werden die Daten erneut geprüft. Wurde der Banner geändert, lade ihn erneut und prüfe deine Änderungen.",
                style = MaterialTheme.typography.bodySmall,
            )
        }
        item {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    { model.save(session) },
                    enabled =
                        !state.saving &&
                            !state.uploading &&
                            runCatching { FeaturedManagementContract.validate(draft) }.isSuccess,
                    modifier =
                        Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("featured-save"),
                ) {
                    Text(
                        if (state.saving) (if (language == "uk") "Збереження…" else "Speichern…")
                        else (if (language == "uk") "Зберегти" else "Speichern")
                    )
                }
                OutlinedButton(
                    model::closeEditor,
                    enabled = !state.saving && !state.uploading,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                ) {
                    Text(if (language == "uk") "Скасувати" else "Abbrechen")
                }
            }
        }
    }
}

private fun featuredSectionLabel(value: FeaturedSection, language: String): String =
    when (value.wire) {
        "home" -> if (language == "uk") "Головна" else "Startseite"
        "events" -> if (language == "uk") "Події" else "Veranstaltungen"
        else -> if (language == "uk") "Організації" else "Organisationen"
    }

private fun featuredActionLabel(value: FeaturedAction, language: String): String =
    when (value.wire) {
        "none" -> if (language == "uk") "Без переходу" else "Ohne Weiterleitung"
        "news" -> if (language == "uk") "Новина" else "Nachricht"
        "event" -> if (language == "uk") "Подія" else "Veranstaltung"
        "organization" -> if (language == "uk") "Організація" else "Organisation"
        else -> if (language == "uk") "Вебпосилання" else "Weblink"
    }

@Composable
internal fun FeaturedImagePreview(draft: FeaturedDraft, language: String) {
    var failed by remember(draft.imageUrl) { mutableStateOf(draft.imageUrl.isBlank()) }
    if (failed) {
        Surface(
            Modifier.fillMaxWidth().heightIn(min = 56.dp)
                .testTag("featured-preview-${draft.id}"),
            shape = RoundedCornerShape(12.dp),
            color = MaterialTheme.colorScheme.surfaceContainer,
        ) {
            Row(Modifier.padding(12.dp), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                UacSymbol(UacIcon.PHOTO)
                Text(if (draft.imageUrl.isBlank()) {
                    if (language == "uk") "Зображення ще не вибрано" else "Noch kein Bild ausgewählt"
                } else if (language == "uk") "Зображення недоступне" else "Bild nicht verfügbar",
                    style = MaterialTheme.typography.bodySmall)
            }
        }
    } else {
        PublicImage(
            draft.imageUrl,
            draft.localizations[language]?.title?.takeIf(String::isNotBlank)
                ?: draft.title.ifBlank { draft.internalName },
            language,
            Modifier.fillMaxWidth()
                .aspectRatio(16f / 9f)
                .clip(RoundedCornerShape(12.dp))
                .testTag("featured-preview-${draft.id}"),
            fallback = UacIcon.PHOTO,
            presentation = PublicImagePresentation.VIEWPORT_FIT,
            externalBanner = true,
            onLoadFinished = { succeeded -> failed = !succeeded },
        )
    }
}

@Composable
private fun FeaturedError(
    failure: FeaturedFailure,
    unconfirmed: Boolean,
    language: String,
    retry: () -> Unit,
) {
    ElevatedCard(
        colors =
            CardDefaults.elevatedCardColors(
                containerColor = MaterialTheme.colorScheme.errorContainer
            ),
        modifier = Modifier.fillMaxWidth().testTag("featured-error"),
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                if (unconfirmed)
                    (if (language == "uk")
                        "Результат операції не підтверджено. Не надсилайте її повторно — спочатку оновіть список."
                    else
                        "Das Ergebnis ist nicht bestätigt. Nicht erneut senden – zuerst die Liste aktualisieren.")
                else featuredFailureText(failure, language)
            )
            OutlinedButton(retry, Modifier.testTag("featured-recover")) {
                Text(if (language == "uk") "Оновити стан" else "Status aktualisieren")
            }
        }
    }
}

private fun featuredFailureText(failure: FeaturedFailure, language: String): String =
    if (language == "uk")
        when (failure) {
            FeaturedFailure.ACCESS -> "Доступ має лише підтверджений власник застосунку."
            FeaturedFailure.INVALID,
            FeaturedFailure.IMAGE -> "Перевірте всі поля та зображення."
            FeaturedFailure.MISSING -> "Банер більше не існує."
            FeaturedFailure.CONFLICT -> "Банер змінився на сервері. Оновіть список."
            FeaturedFailure.OFFLINE -> "Немає підтвердженого з’єднання із сервером."
            FeaturedFailure.UNCONFIRMED -> "Результат не підтверджено."
            FeaturedFailure.BUSY -> "Інша операція ще виконується."
        }
    else
        when (failure) {
            FeaturedFailure.ACCESS -> "Nur der bestätigte App-Inhaber hat Zugriff."
            FeaturedFailure.INVALID,
            FeaturedFailure.IMAGE -> "Bitte Felder und Bild prüfen."
            FeaturedFailure.MISSING -> "Der Banner existiert nicht mehr."
            FeaturedFailure.CONFLICT ->
                "Der Banner wurde auf dem Server geändert. Liste aktualisieren."
            FeaturedFailure.OFFLINE -> "Keine bestätigte Serververbindung."
            FeaturedFailure.UNCONFIRMED -> "Das Ergebnis ist nicht bestätigt."
            FeaturedFailure.BUSY -> "Eine andere Aktion läuft noch."
        }
