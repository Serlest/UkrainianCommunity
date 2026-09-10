package at.uac.android.feature.systemlogs

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.design.UacSymbol
import at.uac.android.feature.browse.tr
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun SystemLogsScreen(
    model: SystemLogsViewModel,
    session: ModerationSession?,
    language: String,
    onBack: () -> Unit,
) {
    val state by model.state.collectAsState()
    LaunchedEffect(session) { model.load(session) }
    val selected = model.selected()
    androidx.activity.compose.BackHandler {
        if (selected == null) onBack() else model.select(null)
    }
    Column(Modifier.fillMaxSize().testTag("system-logs")) {
        Column(
            Modifier.fillMaxWidth().padding(bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            at.uac.android.design.UacBackButton(
                { if (selected == null) onBack() else model.select(null) },
                Modifier.testTag("system-logs-back"),
            ) {
                UacSymbol(UacIcon.BACK)
                Text(if (language == "uk") "Назад" else "Zurück")
            }
            UacSectionHeading(
                if (selected == null)
                    (if (language == "uk") "Системний журнал" else "Systemprotokoll")
                else (if (language == "uk") "Деталі запису" else "Protokolldetails"),
                UacIcon.HISTORY,
            )
        }
        if (selected != null) SystemLogDetail(model, session, selected, state, language)
        else SystemLogList(model, session, state, language)
    }
}

@Composable
private fun SystemLogList(
    model: SystemLogsViewModel,
    session: ModerationSession?,
    state: SystemLogsState,
    language: String,
) {
    val values = model.visible()
    val metrics = model.metrics()
    var filtersExpanded by remember { mutableStateOf(false) }
    LazyColumn(
        Modifier.fillMaxSize().testTag("system-log-list"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        item {
            Text(
                if (state.access == SystemLogAccess.OWNER)
                    (if (language == "uk")
                        "Події застосунку, помилки та дії керування. Конфіденційні значення приховано."
                    else
                        "App-Ereignisse, Fehler und Verwaltungsaktionen. Vertrauliche Werte werden ausgeblendet.")
                else
                    (if (language == "uk")
                        "Обмежений журнал адміністратора без безпекових і власницьких записів."
                    else "Eingeschränktes Admin-Protokoll ohne Sicherheits- und Inhabereinträge."),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        state.failure?.let { item { SystemLogError(state, language) { model.load(session) } } }
        state.unconfirmedAction?.let {
            item { UnconfirmedAction(language) { model.acknowledgeUnconfirmed(session) } }
        }
        state.pushReceipt?.let { receipt ->
            item {
                Text(
                    (if (language == "uk") "Тестовий push підтверджено"
                    else "Test-Push bestätigt") +
                        ": ${receipt.successCount}/${receipt.targetCount}",
                    Modifier.testTag("system-log-push-receipt"),
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
        item {
            FlowRow(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Metric(
                    "unreviewed",
                    metrics.unreviewed,
                    if (language == "uk") "Непереглянуті" else "Ungelesen",
                )
                Metric(
                    "critical",
                    metrics.critical,
                    if (language == "uk") "Критичні" else "Kritisch",
                )
                Metric("errors", metrics.errors, if (language == "uk") "Помилки" else "Fehler")
                Metric(
                    if (state.access == SystemLogAccess.OWNER) "security" else "moderation",
                    if (state.access == SystemLogAccess.OWNER) metrics.security
                    else metrics.moderation,
                    if (state.access == SystemLogAccess.OWNER)
                        (if (language == "uk") "Безпека" else "Sicherheit")
                    else (if (language == "uk") "Модерація" else "Moderation"),
                )
            }
        }
        item {
            OutlinedTextField(
                state.search,
                model::search,
                label = {
                    Text(
                        if (language == "uk") "Пошук у завантажених записах"
                        else "Geladene Einträge durchsuchen"
                    )
                },
                modifier = Modifier.fillMaxWidth().testTag("system-log-search"),
                singleLine = true,
            )
        }
        item {
            OutlinedButton(
                { filtersExpanded = !filtersExpanded },
                Modifier.testTag("system-log-toggle-filters"),
            ) {
                UacSymbol(UacIcon.FILTER)
                Spacer(Modifier.width(8.dp))
                Text(if (language == "uk") "Фільтри й порядок" else "Filter und Sortierung")
            }
        }
        if (filtersExpanded) {
            item {
                Text(
                    tr(language, "Zeitraum und Priorität", "Період і пріоритет"),
                    style = MaterialTheme.typography.titleSmall,
                )
                FlowRow(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    SystemLogQuickFilter.entries.forEach { filter ->
                        FilterChip(
                            filter in state.quick,
                            { model.toggle(filter) },
                            { Text(quickLabel(filter, language)) },
                            Modifier.testTag("system-log-filter-${filter.name}"),
                        )
                    }
                }
            }
            item {
                Text(
                    tr(language, "Prüfstatus", "Стан перегляду"),
                    style = MaterialTheme.typography.titleSmall,
                )
                FlowRow(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    FilterChip(
                        state.review == null,
                        { model.reviewFilter(null) },
                        { Text(if (language == "uk") "Усі" else "Alle") },
                    )
                    FilterChip(
                        state.review == false,
                        { model.reviewFilter(false) },
                        { Text(if (language == "uk") "Не переглянуті" else "Nicht geprüft") },
                    )
                    FilterChip(
                        state.review == true,
                        { model.reviewFilter(true) },
                        { Text(if (language == "uk") "Переглянуті" else "Geprüft") },
                    )
                }
            }
            item {
                Text(
                    tr(language, "Sortierung", "Порядок записів"),
                    style = MaterialTheme.typography.titleSmall,
                )
                FlowRow(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    SystemLogSort.entries.forEach { sort ->
                        FilterChip(
                            state.sort == sort,
                            { model.sort(sort, session) },
                            { Text(sortLabel(sort, language)) },
                            enabled = !state.loading && !state.mutating,
                        )
                    }
                }
            }
        }
        if (state.loading)
            item { LinearProgressIndicator(Modifier.fillMaxWidth().testTag("system-log-loading")) }
        if (!state.loading && values.isEmpty())
            item {
                Text(
                    if (language == "uk") "Записів немає." else "Keine Einträge.",
                    Modifier.testTag("system-log-empty"),
                )
            }
        items(values, key = { it.id }) { log ->
            ElevatedCard(
                { model.select(log.id) },
                Modifier.fillMaxWidth().testTag("system-log-row-${log.id}"),
            ) {
                Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(
                        log.summary.ifBlank { log.eventType },
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        "${logSeverity(log.severity, language)} · ${logDate(log.createdAt)}",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        if (log.reviewed) (if (language == "uk") "Переглянуто" else "Geprüft")
                        else (if (language == "uk") "Не переглянуто" else "Nicht geprüft")
                    )
                }
            }
        }
        if (state.access == SystemLogAccess.OWNER)
            item { OwnerDiagnostics(model, session, state, language) }
    }
}

@Composable
private fun OwnerDiagnostics(
    model: SystemLogsViewModel,
    session: ModerationSession?,
    state: SystemLogsState,
    language: String,
) {
    var confirmClear by remember { mutableStateOf(false) }
    OutlinedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                tr(language, "Diagnose und Wartung", "Діагностика й обслуговування"),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                tr(
                    language,
                    "Werkzeuge für den App-Inhaber. Das Leeren betrifft den gesamten Journalbestand.",
                    "Інструменти власника. Очищення стосується всіх записів журналу.",
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedButton(
                { model.testPush(session) },
                Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("system-log-test-push"),
                enabled = !state.mutating && state.unconfirmedAction == null,
            ) {
                Text(if (language == "uk") "Надіслати тестовий push" else "Test-Push senden")
            }
            if (confirmClear)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        {
                            confirmClear = false
                            model.clear(session)
                        },
                        colors =
                            ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.error
                            ),
                        enabled = !state.mutating,
                        modifier = Modifier.testTag("system-log-clear-confirm"),
                    ) {
                        Text(if (language == "uk") "Підтвердити очищення" else "Leeren bestätigen")
                    }
                    TextButton(
                        { confirmClear = false },
                        Modifier.testTag("system-log-clear-cancel"),
                    ) {
                        Text(if (language == "uk") "Скасувати" else "Abbrechen")
                    }
                }
            else
                OutlinedButton(
                    { confirmClear = true },
                    Modifier.fillMaxWidth().testTag("system-log-clear"),
                    enabled = !state.mutating && state.unconfirmedAction == null,
                ) {
                    Text(
                        if (language == "uk") "Очистити весь журнал"
                        else "Gesamtes Protokoll leeren"
                    )
                }
        }
    }
}

@Composable
private fun SystemLogDetail(
    model: SystemLogsViewModel,
    session: ModerationSession?,
    log: SystemLogEntry,
    state: SystemLogsState,
    language: String,
) {
    var confirmDelete by remember(log.id) { mutableStateOf(false) }
    LazyColumn(
        Modifier.fillMaxSize().testTag("system-log-detail"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        item {
            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        logSeverity(log.severity, language),
                        style = MaterialTheme.typography.labelLarge,
                        color =
                            if (log.severity in setOf("critical", "error"))
                                MaterialTheme.colorScheme.error
                            else MaterialTheme.colorScheme.primary,
                    )
                    Text(log.summary, style = MaterialTheme.typography.titleMedium)
                    Text(
                        logDate(log.createdAt),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        state.failure?.let { item { SystemLogError(state, language) { model.load(session) } } }
        item { DetailRows(log, language) }
        if (!log.reviewed)
            item {
                Button(
                    { model.review(session, log) },
                    Modifier.fillMaxWidth().testTag("system-log-review"),
                    enabled = !state.mutating,
                ) {
                    Text(
                        if (language == "uk") "Позначити переглянутим" else "Als geprüft markieren"
                    )
                }
            }
        if (state.access == SystemLogAccess.OWNER)
            item {
                if (confirmDelete)
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            {
                                confirmDelete = false
                                model.delete(session, log)
                            },
                            colors =
                                ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.error
                                ),
                            enabled = !state.mutating,
                            modifier = Modifier.testTag("system-log-delete-confirm"),
                        ) {
                            Text(
                                if (language == "uk") "Підтвердити видалення"
                                else "Löschen bestätigen"
                            )
                        }
                        TextButton(
                            { confirmDelete = false },
                            Modifier.testTag("system-log-delete-cancel"),
                        ) {
                            Text(if (language == "uk") "Скасувати" else "Abbrechen")
                        }
                    }
                else
                    OutlinedButton(
                        { confirmDelete = true },
                        Modifier.fillMaxWidth().testTag("system-log-delete"),
                        enabled = !state.mutating && state.unconfirmedAction == null,
                    ) {
                        Text(if (language == "uk") "Видалити запис" else "Eintrag löschen")
                    }
            }
    }
}

@Composable
private fun DetailRows(log: SystemLogEntry, language: String) {
    val rows =
        listOf(
            (if (language == "uk") "Категорія" else "Kategorie") to log.category,
            (if (language == "uk") "Рівень" else "Stufe") to logSeverity(log.severity, language),
            (if (language == "uk") "Подія" else "Ereignis") to log.eventType,
            tr(language, "Ausgeführt von", "Виконавець") to
                listOfNotNull(log.actorDisplayName, log.actorUserId).joinToString(" · "),
            tr(language, "Betroffener Eintrag", "Пов’язаний запис") to
                listOfNotNull(log.targetTitle, log.targetId).joinToString(" · "),
            (if (language == "uk") "Зберігати до" else "Aufbewahrung bis") to
                logDate(log.retentionUntil),
            tr(language, "Technisches Modul", "Технічний модуль") to
                listOfNotNull(log.moduleName, log.operationName, log.errorCode).joinToString(" · "),
            tr(language, "App und Gerät", "Застосунок і пристрій") to
                listOfNotNull(log.appVersion, log.osVersion, log.deviceModel).joinToString(" · "),
            tr(language, "Vorgangskennung", "Ідентифікатор операції") to (log.correlationId ?: "—"),
            tr(language, "Technische Meldung", "Технічне повідомлення") to
                log.technicalMessage.orEmpty(),
        ) + log.metadata.entries.sortedBy { it.key }.map { it.key to it.value }
    ElevatedCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            rows
                .filter { it.second.isNotBlank() }
                .forEach { (title, value) ->
                    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(
                            title,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(value, style = MaterialTheme.typography.bodyMedium)
                    }
                }
        }
    }
}

private fun logDate(value: Instant?): String =
    value?.let {
        DateTimeFormatter.ofPattern("dd.MM.yyyy · HH:mm")
            .withZone(ZoneId.of("Europe/Vienna"))
            .format(it)
    } ?: "—"

private fun logSeverity(value: String, language: String): String =
    when (value) {
        "critical" -> tr(language, "Kritisch", "Критично")
        "error" -> tr(language, "Fehler", "Помилка")
        "warning" -> tr(language, "Warnung", "Попередження")
        "info" -> tr(language, "Information", "Інформація")
        "debug" -> tr(language, "Diagnose", "Діагностика")
        else -> value
    }

@Composable
private fun Metric(id: String, value: Int, title: String) {
    ElevatedCard(
        Modifier.fillMaxWidth(if (LocalDensity.current.fontScale >= 1.3f) 1f else 0.48f)
            .testTag("system-log-metric-$id")
    ) {
        Column(Modifier.padding(12.dp)) {
            Text(value.toString(), style = MaterialTheme.typography.titleLarge)
            Text(title, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun SystemLogError(state: SystemLogsState, language: String, retry: () -> Unit) {
    ElevatedCard(
        colors =
            CardDefaults.elevatedCardColors(
                containerColor = MaterialTheme.colorScheme.errorContainer
            ),
        modifier = Modifier.fillMaxWidth().testTag("system-log-error"),
    ) {
        Column(Modifier.padding(12.dp)) {
            Text(
                if (state.failure == SystemLogFailure.UNCONFIRMED)
                    (if (language == "uk")
                        "Результат дії не підтверджено. Автоматичного повтору немає."
                    else "Aktion nicht bestätigt. Keine automatische Wiederholung.")
                else
                    (if (language == "uk") "Не вдалося підтвердити дані журналу."
                    else "Protokolldaten konnten nicht bestätigt werden.")
            )
            OutlinedButton(retry) { Text(if (language == "uk") "Оновити" else "Aktualisieren") }
        }
    }
}

@Composable
private fun UnconfirmedAction(language: String, acknowledge: () -> Unit) {
    ElevatedCard(
        colors =
            CardDefaults.elevatedCardColors(
                containerColor = MaterialTheme.colorScheme.errorContainer
            ),
        modifier = Modifier.fillMaxWidth().testTag("system-log-unconfirmed"),
    ) {
        Column(Modifier.padding(12.dp)) {
            Text(
                if (language == "uk")
                    "Перед новою операцією перевірте актуальний стан. Попередня дія не буде повторена."
                else
                    "Vor einer neuen Aktion den aktuellen Stand prüfen. Die vorige Aktion wird nicht wiederholt."
            )
            OutlinedButton(acknowledge, Modifier.testTag("system-log-acknowledge")) {
                Text(if (language == "uk") "Я перевірив — оновити" else "Geprüft – aktualisieren")
            }
        }
    }
}

private fun quickLabel(value: SystemLogQuickFilter, language: String) =
    when (value) {
        SystemLogQuickFilter.UNREVIEWED ->
            if (language == "uk") "Не переглянуті" else "Nicht geprüft"
        SystemLogQuickFilter.CRITICAL -> if (language == "uk") "Критичні" else "Kritisch"
        SystemLogQuickFilter.TODAY -> if (language == "uk") "Сьогодні" else "Heute"
        SystemLogQuickFilter.SEVEN_DAYS -> if (language == "uk") "7 днів" else "7 Tage"
    }

private fun sortLabel(value: SystemLogSort, language: String) =
    when (value) {
        SystemLogSort.NEWEST -> if (language == "uk") "Нові" else "Neueste"
        SystemLogSort.OLDEST -> if (language == "uk") "Старі" else "Älteste"
        SystemLogSort.SEVERITY_HIGH -> if (language == "uk") "Критичність ↓" else "Schwere ↓"
        SystemLogSort.SEVERITY_LOW -> if (language == "uk") "Критичність ↑" else "Schwere ↑"
        SystemLogSort.CATEGORY -> if (language == "uk") "Категорія" else "Kategorie"
    }
