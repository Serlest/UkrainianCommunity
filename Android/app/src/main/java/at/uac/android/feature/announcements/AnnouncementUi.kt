package at.uac.android.feature.announcements

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.res.Configuration
import android.view.ContextThemeWrapper
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.design.UacCard
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.feature.browse.regions
import at.uac.android.feature.browse.tr
import at.uac.android.feature.translation.ContentTranslationButton
import at.uac.android.feature.translation.TranslationField
import java.text.DateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

@Composable
fun AnnouncementPopup(
    item: UserAnnouncement,
    language: String,
    onDismiss: () -> Unit,
    onAcknowledge: () -> Unit,
    onFeedback: () -> Unit,
    actionsEnabled: Boolean = true,
) {
    AlertDialog(
        modifier = Modifier.testTag("announcement-popup-dialog"),
        onDismissRequest = {},
        title = { Text(item.title.localized(language)) },
        text = {
            Column(
                Modifier.verticalScroll(rememberScrollState()).testTag("announcement-popup"),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(item.body.localized(language))
                if (item.feedback && actionsEnabled)
                    TextButton(onFeedback, Modifier.testTag("announcement-feedback")) {
                        Text(tr(language, "Support kontaktieren", "Звернутися до підтримки"))
                    }
            }
        },
        confirmButton = {
            Button(
                if (item.mode == "acknowledge" && actionsEnabled) onAcknowledge else onDismiss,
                Modifier.testTag("announcement-confirm"),
            ) {
                Text(
                    if (item.mode == "acknowledge" && actionsEnabled)
                        tr(language, "Bestätigen", "Підтвердити")
                    else tr(language, "Verstanden", "Зрозуміло")
                )
            }
        },
        dismissButton =
            if (item.mode == "acknowledge" && actionsEnabled) {
                {
                    TextButton(onDismiss, Modifier.testTag("announcement-dismiss")) {
                        Text(tr(language, "Später", "Пізніше"))
                    }
                }
            } else null,
    )
}

@Composable
fun AnnouncementHistoryScreen(
    state: AnnouncementState,
    language: String,
    pushAvailable: Boolean,
    notificationPermission: Boolean,
    onRefresh: () -> Unit,
    onOpen: (String) -> Unit,
    onGuestPush: (Boolean) -> Unit,
) {
    Column(
        Modifier.fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 24.dp)
            .testTag("announcement-history"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        UacSectionHeading(tr(language, "Mitteilungen", "Оповіщення"), UacIcon.NOTIFICATIONS)
        if (state.session?.uid == null)
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(tr(language, "Push für Gäste", "Push для гостей"), Modifier.weight(1f))
                Switch(
                    checked = state.guestPushEnabled && notificationPermission,
                    onCheckedChange = onGuestPush,
                    enabled = pushAvailable,
                    modifier = Modifier.testTag("announcement-guest-push"),
                )
            }
        if (state.loading) CircularProgressIndicator()
        state.error?.let {
            Text(announcementFailureText(it, language), color = MaterialTheme.colorScheme.error)
        }
        OutlinedButton(onRefresh, Modifier.testTag("announcement-refresh")) {
            Text(tr(language, "Aktualisieren", "Оновити"))
        }
        state.items
            .sortedByDescending { it.startsAt }
            .forEach { item ->
                UacCard {
                    Text(
                        item.title.localized(language),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(item.body.localized(language), maxLines = 3)
                    Text(DateFormat.getDateTimeInstance().format(Date(item.startsAt)))
                    OutlinedButton({ onOpen(item.id) }) {
                        Text(tr(language, "Öffnen", "Відкрити"))
                    }
                }
            }
        if (!state.loading && state.items.isEmpty())
            Text(tr(language, "Keine Mitteilungen vorhanden.", "Оповіщень немає."))
    }
}

@Composable
fun AnnouncementOwnerScreen(
    state: AnnouncementOwnerState,
    language: String,
    onLoad: () -> Unit,
    onLoadMore: () -> Unit,
    onNew: () -> Unit,
    onChange: ((AnnouncementDraft) -> AnnouncementDraft) -> Unit,
    onSave: () -> Unit,
    onTest: () -> Unit,
    onPreview: () -> Unit,
    onLoadUsers: (Boolean) -> Unit,
    onPublish: () -> Unit,
    onEdit: (UserAnnouncement) -> Unit,
    onStats: (UserAnnouncement) -> Unit,
    onCancel: (UserAnnouncement) -> Unit,
) {
    Column(
        Modifier.fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(bottom = 24.dp)
            .testTag("announcement-owner"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        UacSectionHeading(
            tr(language, "Nutzer-Mitteilungen", "Оповіщення користувачів"),
            UacIcon.NOTIFICATIONS,
        )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onLoad) { Text(tr(language, "Aktualisieren", "Оновити")) }
            Button(onNew, Modifier.testTag("announcement-new")) {
                Text(tr(language, "Neu", "Нове"))
            }
        }
        if (state.loading) CircularProgressIndicator()
        state.error?.let {
            Text(
                announcementFailureText(it, language),
                Modifier.testTag("announcement-owner-error"),
                color = MaterialTheme.colorScheme.error,
            )
        }
        state.notice?.let { Text(tr(language, "Änderung gespeichert.", "Зміну збережено.")) }
        state.draft?.let { draft ->
            var reviewed by
                remember(draft) {
                    mutableStateOf(false)
                }
            var confirmPublish by
                remember(draft.id) {
                    mutableStateOf(false)
                }
            var previewOpen by
                remember(draft.id) {
                    mutableStateOf(false)
                }
            var userPicker by remember(draft.id) { mutableStateOf(false) }
            var userQuery by remember(draft.id) { mutableStateOf("") }
            UacCard(Modifier.testTag("announcement-content-uk")) {
                UacSectionHeading(tr(language, "Ukrainisch", "Українська"), UacIcon.EDIT)
                OutlinedTextField(
                    draft.titleUk,
                    { value -> onChange { it.copy(titleUk = value.take(160)) } },
                    label = { Text(tr(language, "Titel UK", "Заголовок UK")) },
                    modifier = Modifier.fillMaxWidth().testTag("announcement-title-uk"),
                )
                OutlinedTextField(
                    draft.bodyUk,
                    { value -> onChange { it.copy(bodyUk = value.take(6_000)) } },
                    label = { Text(tr(language, "Text UK", "Текст UK")) },
                    modifier = Modifier.fillMaxWidth().testTag("announcement-body-uk"),
                    minLines = 4,
                )
                ContentTranslationButton(
                    kind = "announcement",
                    language = language,
                    fields =
                        listOf(
                            TranslationField(
                                "title",
                                tr(language, "Titel", "Заголовок"),
                                draft.titleUk,
                                draft.titleDe,
                                160,
                            ),
                            TranslationField(
                                "body",
                                tr(language, "Text", "Текст"),
                                draft.bodyUk,
                                draft.bodyDe,
                                6_000,
                            ),
                        ),
                    enabled = !state.loading,
                ) { translated ->
                    onChange {
                        it.copy(
                            titleDe = translated["title"] ?: it.titleDe,
                            bodyDe = translated["body"] ?: it.bodyDe,
                        )
                    }
                }
            }
            UacCard(Modifier.testTag("announcement-content-de")) {
                UacSectionHeading(tr(language, "Deutsch", "Німецька"), UacIcon.EDIT)
                OutlinedTextField(
                    draft.titleDe,
                    { value -> onChange { it.copy(titleDe = value.take(160)) } },
                    label = { Text(tr(language, "Titel DE", "Заголовок DE")) },
                    modifier = Modifier.fillMaxWidth().testTag("announcement-title-de"),
                )
                OutlinedTextField(
                    draft.bodyDe,
                    { value -> onChange { it.copy(bodyDe = value.take(6_000)) } },
                    label = { Text(tr(language, "Text DE", "Текст DE")) },
                    modifier = Modifier.fillMaxWidth().testTag("announcement-body-de"),
                    minLines = 4,
                )
                ContentTranslationButton(
                    kind = "announcement",
                    language = language,
                    fields =
                        listOf(
                            TranslationField(
                                "title",
                                tr(language, "Titel", "Заголовок"),
                                draft.titleDe,
                                draft.titleUk,
                                160,
                            ),
                            TranslationField(
                                "body",
                                tr(language, "Text", "Текст"),
                                draft.bodyDe,
                                draft.bodyUk,
                                6_000,
                            ),
                        ),
                    enabled = !state.loading,
                    sourceLanguage = "de",
                ) { translated ->
                    onChange {
                        it.copy(
                            titleUk = translated["title"] ?: it.titleUk,
                            bodyUk = translated["body"] ?: it.bodyUk,
                        )
                    }
                }
            }
            UacCard(Modifier.testTag("announcement-audience-section")) {
                UacSectionHeading(
                    tr(language, "Empfängergruppen", "Групи отримувачів"),
                    UacIcon.PROFILE,
                )
                AnnouncementContract.GROUPS.sorted().forEach { group ->
                    OptionRow(announcementGroupLabel(group, language), group in draft.groups) {
                        selected ->
                        onChange {
                            it.copy(groups = if (selected) it.groups + group else it.groups - group)
                        }
                    }
                }
                OutlinedButton(
                    {
                        userPicker = true
                        onLoadUsers(false)
                    },
                    modifier = Modifier.fillMaxWidth().testTag("announcement-users"),
                ) {
                    Text(
                        tr(
                            language,
                            "Bestimmte Personen (${draft.userIds.size})",
                            "Конкретні користувачі (${draft.userIds.size})",
                        )
                    )
                }
                if (userPicker) {
                    AlertDialog(
                        onDismissRequest = { userPicker = false },
                        modifier = Modifier.testTag("announcement-user-dialog"),
                        title = { Text(tr(language, "Personen auswählen", "Обрати користувачів")) },
                        text = {
                            Column(
                                Modifier.verticalScroll(rememberScrollState()),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                OutlinedTextField(
                                    userQuery,
                                    { userQuery = it.take(100) },
                                    label = { Text(tr(language, "Suchen", "Пошук")) },
                                    modifier =
                                        Modifier.fillMaxWidth().testTag("announcement-user-search"),
                                )
                                state.users
                                    .filter {
                                        userQuery.isBlank() ||
                                            it.name.contains(userQuery, ignoreCase = true)
                                    }
                                    .forEach { user ->
                                        OptionRow(
                                            "${user.name}${user.region?.let { " · $it" }.orEmpty()}",
                                            user.id in draft.userIds,
                                        ) { selected ->
                                            onChange {
                                                it.copy(
                                                    userIds =
                                                        if (selected && it.userIds.size < 100)
                                                            it.userIds + user.id
                                                        else it.userIds - user.id
                                                )
                                            }
                                        }
                                    }
                                if (
                                    state.users.none {
                                        userQuery.isBlank() ||
                                            it.name.contains(userQuery, ignoreCase = true)
                                    }
                                )
                                    Text(
                                        tr(
                                            language,
                                            "Keine passenden Personen im geladenen Teil.",
                                            "У завантаженій частині немає відповідних користувачів.",
                                        ),
                                        Modifier.testTag("announcement-users-empty"),
                                    )
                                if (state.usersCursor != null)
                                    OutlinedButton({ onLoadUsers(true) }) {
                                        Text(tr(language, "Mehr laden", "Завантажити ще"))
                                    }
                            }
                        },
                        confirmButton = {
                            Button(
                                { userPicker = false },
                                Modifier.testTag("announcement-users-done"),
                            ) {
                                Text(tr(language, "Fertig", "Готово"))
                            }
                        },
                    )
                }
            }
            UacCard(Modifier.testTag("announcement-regions-section")) {
                UacSectionHeading(
                    tr(
                        language,
                        "Regionen (leer = ganz Österreich)",
                        "Регіони (порожньо = уся Австрія)",
                    ),
                    UacIcon.LOCATION,
                )
                AnnouncementContract.REGIONS.sorted().forEach { region ->
                    OptionRow(
                        regions.firstOrNull { it.first == region }?.second ?: region,
                        region in draft.regions,
                    ) { selected ->
                        onChange {
                            it.copy(
                                regions = if (selected) it.regions + region else it.regions - region
                            )
                        }
                    }
                }
            }
            UacCard(Modifier.testTag("announcement-delivery-section")) {
                UacSectionHeading(
                    tr(language, "Zeitraum und Zustellung", "Період і доставка"),
                    UacIcon.CALENDAR,
                )
                AnnouncementDateTimeButton(
                    tr(language, "Beginn", "Початок"),
                    draft.startsAt,
                    "announcement-start",
                    language,
                ) {
                    onChange { draft -> draft.copy(startsAt = it) }
                }
                AnnouncementDateTimeButton(
                    tr(language, "Ende", "Завершення"),
                    draft.expiresAt,
                    "announcement-end",
                    language,
                ) {
                    onChange { draft -> draft.copy(expiresAt = it) }
                }
                OptionRow(
                    tr(language, "iPhone", "iPhone"),
                    "ios" in draft.targetPlatforms,
                ) { selected ->
                    onChange {
                        it.copy(
                            targetPlatforms =
                                if (selected) it.targetPlatforms + "ios"
                                else it.targetPlatforms - "ios"
                        )
                    }
                }
                OptionRow(
                    "Android",
                    "android" in draft.targetPlatforms,
                ) { selected ->
                    onChange {
                        it.copy(
                            targetPlatforms =
                                if (selected) it.targetPlatforms + "android"
                                else it.targetPlatforms - "android"
                        )
                    }
                }
                OptionRow(
                    tr(language, "Bestätigung erforderlich", "Потрібне підтвердження"),
                    draft.mode == "acknowledge",
                ) { selected ->
                    onChange { it.copy(mode = if (selected) "acknowledge" else "once") }
                }
                OptionRow(
                    tr(language, "Feedback erlauben", "Дозволити звернення"),
                    draft.feedback,
                ) { selected ->
                    onChange { it.copy(feedback = selected) }
                }
                OptionRow(tr(language, "Push senden", "Надіслати push"), draft.push) { selected ->
                    onChange { it.copy(push = selected) }
                }
            }
            UacCard(Modifier.testTag("announcement-release-section")) {
                UacSectionHeading(
                    tr(language, "Prüfen und veröffentlichen", "Перевірити й опублікувати"),
                    UacIcon.SECURITY,
                )
                OptionRow(
                    tr(language, "Inhalt und Zielgruppe geprüft", "Вміст і аудиторію перевірено"),
                    reviewed,
                    modifier = Modifier.testTag("announcement-reviewed"),
                ) {
                    reviewed = it
                }
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedButton(onSave, Modifier.testTag("announcement-save")) {
                        Text(tr(language, "Entwurf speichern", "Зберегти чернетку"))
                    }
                    OutlinedButton(onTest, enabled = draft.publishable() && reviewed) {
                        Text(tr(language, "Test an mich", "Тест собі"))
                    }
                    OutlinedButton(
                        {
                            previewOpen = true
                            onPreview()
                        },
                        enabled = draft.groups.isNotEmpty() || draft.userIds.isNotEmpty(),
                        modifier = Modifier.testTag("announcement-preview"),
                    ) {
                        Text(tr(language, "Vorschau", "Попередній перегляд"))
                    }
                    Button(
                        { confirmPublish = true },
                        enabled = draft.revision > 0 && draft.publishable() && reviewed,
                        modifier = Modifier.testTag("announcement-publish"),
                    ) {
                        Text(tr(language, "Veröffentlichen", "Опублікувати"))
                    }
                }
                if (confirmPublish) {
                    AlertDialog(
                        modifier = Modifier.testTag("announcement-publish-dialog"),
                        onDismissRequest = { confirmPublish = false },
                        title = {
                            Text(
                                tr(
                                    language,
                                    "Mitteilung veröffentlichen?",
                                    "Опублікувати оповіщення?",
                                )
                            )
                        },
                        text = {
                            Text(
                                tr(
                                    language,
                                    "Die ausgewählte Zielgruppe kann die Mitteilung sofort erhalten.",
                                    "Обрана аудиторія може отримати оповіщення одразу.",
                                )
                            )
                        },
                        confirmButton = {
                            Button(
                                {
                                    confirmPublish = false
                                    onPublish()
                                },
                                Modifier.testTag("announcement-publish-confirm"),
                            ) {
                                Text(tr(language, "Veröffentlichen", "Опублікувати"))
                            }
                        },
                        dismissButton = {
                            OutlinedButton(
                                { confirmPublish = false },
                                Modifier.testTag("announcement-publish-dismiss"),
                            ) {
                                Text(tr(language, "Abbrechen", "Скасувати"))
                            }
                        },
                    )
                }
                state.audience?.let {
                    Text(
                        tr(
                            language,
                            "Konten: ${it.accounts}; Gäste: ${if (it.guests) "ja" else "nein"}",
                            "Акаунти: ${it.accounts}; гості: ${if (it.guests) "так" else "ні"}",
                        )
                    )
                }
                if (previewOpen) {
                    AlertDialog(
                        modifier = Modifier.testTag("announcement-preview-dialog"),
                        onDismissRequest = { previewOpen = false },
                        title = { Text(tr(language, "Vorschau", "Попередній перегляд")) },
                        text = {
                            Column(Modifier.verticalScroll(rememberScrollState())) {
                                Text("Українська")
                                Text(draft.titleUk, style = MaterialTheme.typography.titleMedium)
                                Text(draft.bodyUk)
                                Text("Deutsch", Modifier.padding(top = 12.dp))
                                Text(draft.titleDe, style = MaterialTheme.typography.titleMedium)
                                Text(draft.bodyDe)
                                Text(
                                    tr(
                                        language,
                                        "Gruppen: ${draft.groups.joinToString { announcementGroupLabel(it, language) }}; Personen: ${draft.userIds.size}; Regionen: ${draft.regions.ifEmpty { setOf("Österreich") }.joinToString()}",
                                        "Групи: ${draft.groups.joinToString { announcementGroupLabel(it, language) }}; користувачі: ${draft.userIds.size}; регіони: ${draft.regions.ifEmpty { setOf("Австрія") }.joinToString()}",
                                    ),
                                    Modifier.padding(top = 12.dp),
                                )
                            }
                        },
                        confirmButton = {
                            Button(
                                { previewOpen = false },
                                Modifier.testTag("announcement-preview-close"),
                            ) {
                                Text(tr(language, "Schließen", "Закрити"))
                            }
                        },
                    )
                }
            }
        }
        UacSectionHeading(
            tr(language, "Bisherige Mitteilungen", "Попередні оповіщення"),
            UacIcon.HISTORY,
        )
        if (state.items.isEmpty() && !state.loading)
            UacCard {
                Text(
                    tr(
                        language,
                        "Noch keine Mitteilungen. Erstelle oben eine neue Mitteilung.",
                        "Оповіщень поки немає. Створіть нове за допомогою кнопки вгорі.",
                    )
                )
            }
        state.items.forEach { item ->
            UacCard(Modifier.testTag("announcement-item-${item.id}")) {
                Text(item.title.localized(language), style = MaterialTheme.typography.titleMedium)
                Text(
                    announcementStatusLabel(item.status, language),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (item.status == "draft")
                        OutlinedButton({ onEdit(item) }) {
                            Text(tr(language, "Bearbeiten", "Редагувати"))
                        }
                    OutlinedButton({ onStats(item) }) {
                        Text(tr(language, "Statistik", "Статистика"))
                    }
                    if (item.status == "published")
                        OutlinedButton({ onCancel(item) }) {
                            Text(tr(language, "Stoppen", "Скасувати"))
                        }
                }
                state.statistics[item.id]?.let { stats ->
                    Text(
                        tr(
                            language,
                            "Angezeigt ${stats.presented + stats.guestPresented}, bestätigt ${stats.acknowledged + stats.guestAcknowledged}, Aktion ${stats.action}, Push ${stats.pushSuccess}/${stats.pushFailure} (${stats.pushState})",
                            "Показано ${stats.presented + stats.guestPresented}, підтверджено ${stats.acknowledged + stats.guestAcknowledged}, дія ${stats.action}, push ${stats.pushSuccess}/${stats.pushFailure} (${stats.pushState})",
                        )
                    )
                }
            }
        }
        if (state.itemsCursor != null)
            OutlinedButton(onLoadMore, Modifier.fillMaxWidth()) {
                Text(tr(language, "Mehr laden", "Завантажити ще"))
            }
    }
}

@Composable
private fun AnnouncementDateTimeButton(
    label: String,
    value: Long,
    tag: String,
    language: String,
    onChange: (Long) -> Unit,
) {
    val context = LocalContext.current
    val currentConfiguration = LocalConfiguration.current
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val locale = if (language == "de") Locale.GERMAN else Locale.forLanguageTag("uk")
    val pickerContext =
        remember(context, currentConfiguration, language, dark) {
            val configuration = Configuration(currentConfiguration).apply { setLocale(locale) }
            ContextThemeWrapper(
                    context,
                    if (dark) android.R.style.Theme_Material_Dialog_Alert
                    else android.R.style.Theme_Material_Light_Dialog_Alert,
                )
                .apply { applyOverrideConfiguration(configuration) }
        }
    OutlinedButton(
        onClick = {
            val initial = Calendar.getInstance().apply { timeInMillis = value }
            DatePickerDialog(
                    pickerContext,
                    { _, year, month, day ->
                        TimePickerDialog(
                                pickerContext,
                                if (currentConfiguration.fontScale >= 1.5f) {
                                    if (dark) at.uac.android.R.style.AnnouncementTimePickerLargeDark
                                    else at.uac.android.R.style.AnnouncementTimePickerLargeLight
                                } else 0,
                                { _, hour, minute ->
                                    val selected =
                                        Calendar.getInstance().apply {
                                            set(year, month, day, hour, minute, 0)
                                            set(Calendar.MILLISECOND, 0)
                                        }
                                    onChange(selected.timeInMillis)
                                },
                                initial.get(Calendar.HOUR_OF_DAY),
                                initial.get(Calendar.MINUTE),
                                true,
                            )
                            .show()
                    },
                    initial.get(Calendar.YEAR),
                    initial.get(Calendar.MONTH),
                    initial.get(Calendar.DAY_OF_MONTH),
                )
                .show()
        },
        modifier = Modifier.fillMaxWidth().testTag(tag),
    ) {
        Text(
            "$label · ${DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT, locale).format(Date(value))}"
        )
    }
}

@Composable
private fun OptionRow(
    label: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onSelected: (Boolean) -> Unit,
) {
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .toggleable(value = selected, role = Role.Checkbox, onValueChange = onSelected),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Checkbox(selected, null)
        Text(label, Modifier.weight(1f))
    }
}

private fun announcementStatusLabel(status: String, language: String): String =
    when (status) {
        "draft" -> tr(language, "Entwurf", "Чернетка")
        "published" -> tr(language, "Veröffentlicht", "Опубліковано")
        "cancelled",
        "canceled" -> tr(language, "Gestoppt", "Зупинено")
        "expired" -> tr(language, "Abgelaufen", "Завершено")
        else -> tr(language, "Status: ", "Стан: ") + status
    }

private fun announcementGroupLabel(group: String, language: String): String =
    when (group) {
        "registered" -> tr(language, "Registrierte Personen", "Зареєстровані користувачі")
        "guests" -> tr(language, "Gäste", "Гості")
        "organizationOwners" -> tr(language, "Inhaber von Organisationen", "Власники організацій")
        "appAdmins" -> tr(language, "App-Administratoren", "Адміністратори застосунку")
        "organizationAdmins" ->
            tr(language, "Administratoren von Organisationen", "Адміністратори організацій")
        "organizationModerators" ->
            tr(language, "Moderatoren von Organisationen", "Модератори організацій")
        else -> group
    }

fun announcementFailureText(failure: AnnouncementFailure, language: String) =
    when (failure) {
        AnnouncementFailure.SIGN_IN -> tr(language, "Bitte anmelden.", "Увійдіть в акаунт.")
        AnnouncementFailure.NOT_READY ->
            tr(
                language,
                "Konto oder Funktion ist noch nicht bereit.",
                "Акаунт або функція ще не готові.",
            )
        AnnouncementFailure.DENIED -> tr(language, "Zugriff nicht erlaubt.", "Доступ заборонено.")
        AnnouncementFailure.OFFLINE ->
            tr(language, "Server nicht erreichbar.", "Сервер недоступний.")
        AnnouncementFailure.INVALID ->
            tr(language, "Ungültige Mitteilungsdaten.", "Некоректні дані оповіщення.")
        AnnouncementFailure.STALE ->
            tr(language, "Stand geändert. Bitte neu laden.", "Дані змінилися. Оновіть сторінку.")
        AnnouncementFailure.LIMIT ->
            tr(
                language,
                "Limit erreicht; manuelle Eingabe bleibt möglich.",
                "Ліміт вичерпано; доступне ручне введення.",
            )
        AnnouncementFailure.UNKNOWN ->
            tr(language, "Vorgang fehlgeschlagen.", "Не вдалося виконати дію.")
    }
