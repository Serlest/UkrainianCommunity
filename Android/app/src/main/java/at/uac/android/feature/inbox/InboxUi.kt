package at.uac.android.feature.inbox

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.design.UacIcon
import at.uac.android.design.UacNavigationRow
import at.uac.android.design.UacSectionHeading
import at.uac.android.feature.browse.displayTime
import at.uac.android.feature.browse.tr
import java.time.Instant

@Composable
fun InboxScreen(
    state: InboxState,
    language: String,
    onRefresh: (Boolean) -> Unit,
    onFilter: (Boolean) -> Unit,
    onChange: (InboxNotice, InboxMutation) -> Unit,
    onChangeAll: (InboxMutation) -> Unit,
    onOpen: (InboxNotice, InboxDestination) -> Unit,
    onSettings: () -> Unit,
    destinationAvailable: (InboxDestination) -> Boolean = { true },
) {
    var delete by remember(state.session) { mutableStateOf<InboxNotice?>(null) }
    var clear by remember(state.session) { mutableStateOf(false) }
    LazyColumn(
        Modifier.fillMaxSize().testTag("inbox-list"),
        contentPadding = PaddingValues(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                UacSectionHeading(
                    tr(language, "Mitteilungen", "Повідомлення"),
                    UacIcon.NOTIFICATIONS,
                )
                Text(
                    tr(
                        language,
                        "Ungelesen: ${state.unreadCount}",
                        "Непрочитані: ${state.unreadCount}",
                    ),
                    Modifier.testTag("inbox-unread-count"),
                )
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        !state.unreadOnly,
                        { onFilter(false) },
                        { Text(tr(language, "Alle", "Усі")) },
                        modifier = Modifier.testTag("inbox-filter-all"),
                    )
                    FilterChip(
                        state.unreadOnly,
                        { onFilter(true) },
                        { Text(tr(language, "Ungelesen", "Непрочитані")) },
                        modifier = Modifier.testTag("inbox-filter-unread"),
                    )
                }
                OutlinedButton(
                    { onRefresh(false) },
                    enabled = !state.loading && !state.mutating,
                    modifier = Modifier.fillMaxWidth().testTag("inbox-refresh"),
                ) {
                    Text(tr(language, "Aktualisieren", "Оновити"))
                }
                UacNavigationRow(
                    title = tr(language, "Mitteilungseinstellungen", "Налаштування повідомлень"),
                    icon = UacIcon.SETTINGS,
                    modifier = Modifier.testTag("inbox-settings"),
                    onClick = onSettings,
                )
                if (state.unreadCount > 0)
                    OutlinedButton(
                        { onChangeAll(InboxMutation.READ) },
                        enabled = !state.mutating,
                        modifier = Modifier.fillMaxWidth().testTag("inbox-read-all"),
                    ) {
                        Text(
                            tr(language, "Alle als gelesen markieren", "Позначити всі як прочитані")
                        )
                    }
                if (state.items.isNotEmpty())
                    TextButton(
                        { clear = true },
                        enabled = !state.mutating,
                        modifier = Modifier.fillMaxWidth().testTag("inbox-clear"),
                    ) {
                        Text(
                            tr(language, "Mitteilungen leeren", "Очистити повідомлення"),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
            }
        }
        if (state.session == null)
            item {
                Text(
                    tr(
                        language,
                        "Melde dich an, um deine Mitteilungen zu sehen.",
                        "Увійдіть, щоб переглянути свої повідомлення.",
                    )
                )
            }
        if (state.loading || state.mutating)
            item { CircularProgressIndicator(Modifier.testTag("inbox-progress")) }
        state.error?.let { error ->
            item {
                Text(
                    inboxError(error, language),
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.testTag("inbox-error"),
                )
            }
        }
        if (state.partialSweep || state.invalidRows > 0)
            item {
                Text(
                    tr(
                        language,
                        "Nicht alle Einträge konnten verarbeitet werden. Bitte aktualisieren und erneut versuchen.",
                        "Не всі записи вдалося обробити. Оновіть список і спробуйте ще раз.",
                    ),
                    Modifier.testTag("inbox-partial"),
                )
            }
        if (
            state.visibleItems.isEmpty() &&
                !state.loading &&
                state.error == null &&
                state.session != null
        )
            item {
                Text(
                    if (state.unreadOnly)
                        tr(
                            language,
                            "Keine ungelesenen Mitteilungen",
                            "Немає непрочитаних повідомлень",
                        )
                    else tr(language, "Noch keine Mitteilungen", "Повідомлень поки немає"),
                    Modifier.testTag("inbox-empty"),
                )
            }
        items(state.visibleItems, key = { it.id }) { notice ->
            InboxCard(
                notice,
                language,
                !state.mutating,
                { action -> onChange(notice, action) },
                { delete = notice },
                { destination -> onOpen(notice, destination) },
                destinationAvailable,
            )
        }
        if (state.hasMore)
            item {
                OutlinedButton(
                    { onRefresh(true) },
                    enabled = !state.loading && !state.mutating,
                    modifier = Modifier.fillMaxWidth().testTag("inbox-more"),
                ) {
                    Text(tr(language, "Weitere Mitteilungen", "Більше повідомлень"))
                }
            }
    }
    if (clear || delete != null)
        AlertDialog(
            onDismissRequest = {
                clear = false
                delete = null
            },
            title = {
                Text(
                    if (clear)
                        tr(language, "Alle Mitteilungen entfernen?", "Видалити всі повідомлення?")
                    else tr(language, "Mitteilung entfernen?", "Видалити повідомлення?")
                )
            },
            text = {
                Text(
                    tr(
                        language,
                        "Die Inhalte selbst bleiben unverändert. Entfernte Mitteilungen werden in diesem Posteingang nicht mehr angezeigt.",
                        "Самі матеріали залишаться без змін. Видалені повідомлення більше не відображатимуться у цьому списку.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        if (clear) onChangeAll(InboxMutation.DELETE)
                        else delete?.let { onChange(it, InboxMutation.DELETE) }
                        clear = false
                        delete = null
                    },
                    modifier = Modifier.testTag("inbox-confirm-delete"),
                ) {
                    Text(
                        tr(language, "Entfernen", "Видалити"),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            },
            dismissButton = {
                TextButton({
                    clear = false
                    delete = null
                }) {
                    Text(tr(language, "Abbrechen", "Скасувати"))
                }
            },
        )
}

@Composable
private fun InboxCard(
    notice: InboxNotice,
    language: String,
    enabled: Boolean,
    onChange: (InboxMutation) -> Unit,
    onDelete: () -> Unit,
    onOpen: (InboxDestination) -> Unit,
    destinationAvailable: (InboxDestination) -> Boolean,
) {
    var expanded by remember(notice.uid, notice.id) { mutableStateOf(false) }
    Card(Modifier.fillMaxWidth().testTag("inbox-${notice.id}")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(notice.displayTitle(language), style = MaterialTheme.typography.titleMedium)
            Text(
                displayTime(notice.createdAt, language),
                style = MaterialTheme.typography.labelMedium,
            )
            if (notice.unread)
                Text(
                    tr(language, "Ungelesen", "Непрочитане"),
                    color = MaterialTheme.colorScheme.primary,
                )
            if (notice.archivedAt != null)
                Text(
                    tr(language, "Archiviert", "Архівовано"),
                    style = MaterialTheme.typography.labelMedium,
                )
            Text(notice.displayBody(language), maxLines = if (expanded) Int.MAX_VALUE else 3)
            TextButton(
                {
                    expanded = !expanded
                    if (expanded && notice.unread) onChange(InboxMutation.READ)
                },
                enabled = enabled,
                modifier = Modifier.fillMaxWidth().testTag("inbox-details-${notice.id}"),
            ) {
                Text(
                    tr(
                        language,
                        if (expanded) "Weniger anzeigen" else "Details anzeigen",
                        if (expanded) "Згорнути" else "Переглянути подробиці",
                    )
                )
            }
            if (expanded) {
                notice.actorName?.let { Text(tr(language, "Von: $it", "Від: $it")) }
                val destination = notice.destination(Instant.now())
                if (destination != null && destinationAvailable(destination))
                    Button(
                        {
                            notice
                                .destination(Instant.now())
                                ?.takeIf(destinationAvailable)
                                ?.let(onOpen)
                        },
                        enabled = enabled,
                        modifier = Modifier.fillMaxWidth().testTag("inbox-open-${notice.id}"),
                    ) {
                        Text(tr(language, "Öffnen", "Відкрити"))
                    }
                else if (destination != null)
                    Text(
                        tr(
                            language,
                            "Dieser Zielbereich ist in dieser Android-Version noch nicht verfügbar.",
                            "Цей розділ ще недоступний у цій Android-версії.",
                        ),
                        Modifier.testTag("inbox-destination-unavailable"),
                    )
                OutlinedButton(
                    { onChange(if (notice.isRead) InboxMutation.UNREAD else InboxMutation.READ) },
                    enabled = enabled,
                    modifier = Modifier.fillMaxWidth().testTag("inbox-toggle-${notice.id}"),
                ) {
                    Text(
                        if (notice.isRead)
                            tr(language, "Als ungelesen markieren", "Позначити як непрочитане")
                        else tr(language, "Als gelesen markieren", "Позначити як прочитане")
                    )
                }
                if (notice.archivedAt == null)
                    TextButton(
                        { onChange(InboxMutation.ARCHIVE) },
                        enabled = enabled,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(tr(language, "Archivieren", "Архівувати"))
                    }
                TextButton(
                    onDelete,
                    enabled = enabled,
                    modifier = Modifier.fillMaxWidth().testTag("inbox-delete-${notice.id}"),
                ) {
                    Text(tr(language, "Entfernen", "Видалити"))
                }
            }
        }
    }
}

@Composable
fun InboxPreferencesScreen(
    state: InboxState,
    language: String,
    onLoad: () -> Unit,
    onSave: (InboxPreferences) -> Unit,
    localReminders: @Composable () -> Unit = {},
) {
    LaunchedEffect(state.session) { if (state.session != null) onLoad() }
    val preferences = state.preferences
    LazyColumn(
        Modifier.fillMaxSize().testTag("inbox-preferences"),
        contentPadding = PaddingValues(bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            UacSectionHeading(
                tr(language, "Mitteilungseinstellungen", "Налаштування повідомлень"),
                UacIcon.NOTIFICATIONS,
            )
        }
        item {
            Text(
                tr(
                    language,
                    "Wähle, welche Mitteilungen du erhalten möchtest. Erlaube Benachrichtigungen auch in den Android-Einstellungen. Dein Posteingang bleibt jederzeit verfügbar.",
                    "Оберіть, які повідомлення отримувати. Також дозвольте сповіщення в налаштуваннях Android. Список повідомлень доступний завжди.",
                )
            )
        }
        if (preferences != null) {
            item {
                PreferenceToggle(
                    tr(
                        language,
                        "Mitteilungen für mein Konto aktivieren",
                        "Увімкнути повідомлення для мого акаунта",
                    ),
                    preferences.notificationsEnabled,
                    state.session?.canEditPreferences == true && !state.mutating,
                    "inbox-push-toggle",
                ) {
                    onSave(preferences.copy(notificationsEnabled = it))
                }
            }
            item {
                PreferenceToggle(
                    tr(language, "Erinnerungen an Veranstaltungen", "Нагадування про події"),
                    preferences.eventRemindersEnabled,
                    state.session?.canEditPreferences == true &&
                        !state.mutating &&
                        preferences.notificationsEnabled,
                    "inbox-reminders-toggle",
                ) {
                    onSave(preferences.copy(eventRemindersEnabled = it))
                }
            }
            item {
                Text(
                    tr(
                        language,
                        "Wann möchtest du erinnert werden?",
                        "Коли нагадати про подію?",
                    )
                )
            }
            item("reminder-times") {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(15, 30, 60, 120, 1_440).forEach { minutes ->
                        FilterChip(
                            preferences.reminderLeadMinutes == minutes,
                            { onSave(preferences.copy(reminderLeadMinutes = minutes)) },
                            {
                                Text(
                                    when (minutes) {
                                        60 -> tr(language, "1 Stunde", "1 година")
                                        120 -> tr(language, "2 Stunden", "2 години")
                                        1_440 -> tr(language, "1 Tag", "1 день")
                                        else -> tr(language, "$minutes Min.", "$minutes хв")
                                    }
                                )
                            },
                            enabled =
                                state.session?.canEditPreferences == true &&
                                    !state.mutating &&
                                    preferences.notificationsEnabled &&
                                    preferences.eventRemindersEnabled,
                            modifier = Modifier.testTag("inbox-reminder-lead-$minutes"),
                        )
                    }
                }
            }
        } else if (state.session != null && state.error == null)
            item { CircularProgressIndicator() }
        if (state.session?.canEditPreferences != true)
            item {
                Text(
                    tr(
                        language,
                        "Bestätige dein Konto, um Einstellungen zu ändern.",
                        "Підтвердьте обліковий запис, щоб змінити налаштування.",
                    )
                )
            }
        state.error?.let { error ->
            item {
                Text(inboxError(error, language), color = MaterialTheme.colorScheme.error)
                OutlinedButton(onLoad, enabled = !state.mutating) {
                    Text(tr(language, "Erneut laden", "Завантажити знову"))
                }
            }
        }
        if (state.preferencesSaved)
            item {
                Text(
                    tr(language, "Gespeichert", "Збережено"),
                    Modifier.testTag("inbox-preferences-saved"),
                )
            }
        if (state.session?.canEditPreferences == true) item("local-reminders") { localReminders() }
    }
}

@Composable
private fun PreferenceToggle(
    title: String,
    checked: Boolean,
    enabled: Boolean,
    tag: String,
    onChecked: (Boolean) -> Unit,
) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, Modifier.weight(1f), style = MaterialTheme.typography.titleSmall)
        Switch(
            checked,
            onChecked,
            enabled = enabled,
            modifier = Modifier.testTag(tag).semantics { contentDescription = title },
        )
    }
}

fun inboxError(error: InboxFailure, language: String): String =
    when (error) {
        InboxFailure.SIGN_IN ->
            tr(language, "Bitte melde dich an.", "Увійдіть до облікового запису.")
        InboxFailure.NOT_READY ->
            tr(
                language,
                "Dein Konto ist für diese Änderung noch nicht freigegeben.",
                "Ця зміна ще недоступна для вашого облікового запису.",
            )
        InboxFailure.DENIED ->
            tr(
                language,
                "Kein Zugriff. Bitte prüfe deinen Kontostatus.",
                "Немає доступу. Перевірте стан свого облікового запису.",
            )
        InboxFailure.OFFLINE ->
            tr(
                language,
                "Keine Serververbindung. Bitte versuche es erneut, sobald du online bist.",
                "Немає зв’язку із сервером. Спробуйте знову після відновлення з’єднання.",
            )
        InboxFailure.MISSING ->
            tr(
                language,
                "Diese Mitteilung ist nicht mehr verfügbar.",
                "Це повідомлення більше недоступне.",
            )
        InboxFailure.INVALID ->
            tr(
                language,
                "Die Daten konnten nicht sicher gelesen werden.",
                "Не вдалося безпечно прочитати дані.",
            )
        InboxFailure.UNKNOWN ->
            tr(
                language,
                "Die Änderung konnte nicht bestätigt werden. Bitte aktualisieren.",
                "Не вдалося підтвердити зміну. Оновіть список.",
            )
    }
