package at.uac.android.feature.owneranalytics

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.design.UacSymbol
import at.uac.android.feature.browse.tr
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun OwnerAnalyticsScreen(
    model: OwnerAnalyticsViewModel,
    session: OwnerAnalyticsSession?,
    language: String,
    onBack: () -> Unit,
) {
    val observed by model.state.collectAsState()
    val state =
        observed.takeIf { it.session == session && session?.ready == true } ?: OwnerAnalyticsState()
    LaunchedEffect(session) { model.load(session) }
    androidx.activity.compose.BackHandler {
        if (state.detailTarget == null) onBack() else model.closeDetail()
    }
    Column(Modifier.fillMaxSize().testTag("owner-analytics")) {
        Column(
            Modifier.fillMaxWidth().padding(bottom = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            at.uac.android.design.UacBackButton(
                if (state.detailTarget == null) onBack else model::closeDetail,
                Modifier.testTag("owner-analytics-back"),
            ) {
                UacSymbol(UacIcon.BACK)
                Text(tr(language, "Zurück", "Назад"))
            }
            UacSectionHeading(
                if (state.detailTarget == null) tr(language, "Analytics", "Аналітика")
                else tr(language, "Detailanalyse", "Детальна аналітика"),
                UacIcon.ANALYTICS,
            )
        }
        if (state.detailTarget != null) {
            key(state.detailTarget) { DetailContent(model, session, state, language) }
        } else OverviewContent(model, session, state, language)
    }
}

@Composable
private fun OverviewContent(
    model: OwnerAnalyticsViewModel,
    session: OwnerAnalyticsSession?,
    state: OwnerAnalyticsState,
    language: String,
) {
    LazyColumn(
        Modifier.fillMaxSize().testTag("owner-analytics-overview"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        item {
            Text(
                tr(
                    language,
                    "Nutzung im Überblick · Wiener Ortszeit",
                    "Огляд використання · віденський час",
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        item { Periods(state.period, language) { model.period(it, session) } }
        item {
            OutlinedTextField(
                state.search,
                model::search,
                label = {
                    Text(tr(language, "Inhalte und Regionen suchen", "Знайти матеріал або регіон"))
                },
                modifier = Modifier.fillMaxWidth().testTag("owner-analytics-search"),
                singleLine = true,
            )
        }
        if (state.loading && state.snapshot == null)
            item {
                LinearProgressIndicator(Modifier.fillMaxWidth().testTag("owner-analytics-loading"))
            }
        state.failure?.let { failure ->
            item { Failure(failure, language) { model.load(session, true) } }
        }
        state.snapshot?.let { snapshot ->
            if (snapshot.unavailable.isNotEmpty())
                item {
                    Surface(
                        modifier = Modifier.fillMaxWidth().testTag("owner-analytics-partial"),
                        shape = MaterialTheme.shapes.medium,
                        color = MaterialTheme.colorScheme.secondaryContainer,
                        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                    ) {
                        Text(
                            tr(
                                language,
                                "Teildaten: ${snapshot.unavailable.joinToString { analyticsSourceName(it, language) }}",
                                "Часткові дані: ${snapshot.unavailable.joinToString { analyticsSourceName(it, language) }}",
                            ),
                            modifier = Modifier.padding(12.dp),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            snapshot.generatedAt?.let { updated ->
                item {
                    Text(
                        "${tr(language, "Aktualisiert", "Оновлено")}: ${DateTimeFormatter.ofPattern("dd.MM.yyyy HH:mm").withZone(ZoneId.of("Europe/Vienna")).format(updated)}",
                        style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.testTag("owner-analytics-updated"),
                    )
                }
            }
            if (!snapshot.hasData && state.failure == null) item { Empty(language) }
            if (snapshot.hasData) {
                if ("daily" !in snapshot.unavailable) {
                    item { SectionTitle(tr(language, "Überblick", "Огляд")) }
                    item {
                        MetricGrid(summaryMetrics(snapshot), snapshot.previousMetrics, language)
                    }
                    if (snapshot.daily.size > 1) item { Trend(snapshot, language) }
                    val actions = actionMetrics(snapshot.metrics)
                    if (actions.values.any { it > 0 }) {
                        item { SectionTitle(tr(language, "Aktionen", "Дії")) }
                        item { MetricGrid(actions, emptyMap(), language) }
                    }
                }
                val top = model.filteredTop()
                if (top.isNotEmpty()) {
                    item { SectionTitle(tr(language, "Beliebte Inhalte", "Популярні матеріали")) }
                    items(top, key = { "${it.type}:${it.id}" }) { item ->
                        ElevatedCard(
                            { model.open(session, item.type, item.id) },
                            Modifier.fillMaxWidth()
                                .testTag("owner-analytics-top-${item.type}-${item.id}"),
                        ) {
                            Column(Modifier.padding(14.dp)) {
                                Text(item.title, style = MaterialTheme.typography.titleMedium)
                                Text(
                                    "${kind(item.type, language)} · ${item.views} ${tr(language, "Aufrufe", "переглядів")}"
                                )
                            }
                        }
                    }
                }
                val regions = model.filteredRegions()
                if (regions.isNotEmpty()) {
                    item {
                        SectionTitle(tr(language, "Regionale Aktivität", "Регіональна активність"))
                    }
                    items(regions, key = { "region:${it.id}" }) { RegionRow(it, language) }
                }
                if (snapshot.users != AnalyticsUsers()) {
                    item { SectionTitle(tr(language, "Nutzer", "Користувачі")) }
                    item { UserMetrics(snapshot.users, language) }
                    items(
                        snapshot.users.byFederalState.entries.sortedByDescending { it.value },
                        key = { "users-region:${it.key}" },
                    ) {
                        Text(
                            "${stateName(it.key, language)}: ${it.value}",
                            Modifier.fillMaxWidth().padding(8.dp),
                        )
                    }
                }
                item {
                    Text(
                        tr(
                            language,
                            "Werte sind aggregiert und können durch verzögerte Materialisierung später erscheinen.",
                            "Значення агреговані й можуть з’являтися із затримкою через матеріалізацію.",
                        ),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
        }
    }
}

@Composable
private fun DetailContent(
    model: OwnerAnalyticsViewModel,
    session: OwnerAnalyticsSession?,
    state: OwnerAnalyticsState,
    language: String,
) {
    LazyColumn(
        Modifier.fillMaxSize().testTag("owner-analytics-detail"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        item {
            Periods(state.period, language) { period ->
                model.period(period, session)
                state.detailTarget?.let { model.open(session, it.first, it.second) }
            }
        }
        if (state.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        state.failure?.let { failure ->
            item {
                Failure(failure, language) {
                    state.detailTarget?.let { model.open(session, it.first, it.second) }
                }
            }
        }
        state.detail?.let { detail ->
            item {
                Text(
                    detail.title.ifBlank { detail.id },
                    style = MaterialTheme.typography.titleLarge,
                )
            }
            detail.partialSince?.let {
                item {
                    Text(
                        tr(language, "Teildaten seit $it", "Часткові дані від $it"),
                        color = MaterialTheme.colorScheme.tertiary,
                    )
                }
            }
            if (!detail.hasData) item { Empty(language) }
            if (detail.metrics.isNotEmpty())
                item { MetricGrid(detail.metrics, emptyMap(), language) }
            if (detail.regions.isNotEmpty()) {
                item { SectionTitle(tr(language, "Regionale Aktivität", "Регіональна активність")) }
                items(detail.regions, key = { "region:${it.id}" }) { RegionRow(it, language) }
            }
            val related = detail.topNews + detail.topEvents
            if (related.isNotEmpty()) {
                item { SectionTitle(tr(language, "Top-Inhalte", "Топ матеріалів")) }
                items(related, key = { "${it.type}:${it.id}" }) { item ->
                    ElevatedCard(
                        { model.open(session, item.type, item.id) },
                        Modifier.fillMaxWidth().testTag("owner-analytics-related-${item.id}"),
                    ) {
                        Column(
                            Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Text(item.title, style = MaterialTheme.typography.titleMedium)
                            Text(
                                "${kind(item.type, language)} · ${item.views} ${tr(language, "Aufrufe", "переглядів")}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Periods(
    selected: AnalyticsPeriod,
    language: String,
    change: (AnalyticsPeriod) -> Unit,
) {
    FlowRow(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        AnalyticsPeriod.entries.forEach { period ->
            FilterChip(
                selected == period,
                { change(period) },
                {
                    Text(
                        when (period) {
                            AnalyticsPeriod.TODAY -> tr(language, "Heute", "Сьогодні")
                            AnalyticsPeriod.SEVEN_DAYS -> tr(language, "7 Tage", "7 днів")
                            AnalyticsPeriod.THIRTY_DAYS -> tr(language, "30 Tage", "30 днів")
                        }
                    )
                },
                Modifier.testTag("owner-analytics-period-${period.name}"),
            )
        }
    }
}

@Composable
private fun MetricGrid(values: Map<String, Int>, previous: Map<String, Int>, language: String) {
    val fontScale = LocalDensity.current.fontScale
    val columns = if (fontScale >= 1.3f || LocalConfiguration.current.screenWidthDp < 360) 1 else 2
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        values
            .filterValues { it > 0 }
            .entries
            .chunked(columns)
            .forEach { row ->
                Row(
                    Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    row.forEach { (key, value) ->
                        ElevatedCard(
                            Modifier.weight(1f)
                                .fillMaxHeight()
                                .testTag("owner-analytics-metric-$key")
                        ) {
                            Column(
                                Modifier.fillMaxHeight().padding(12.dp),
                                verticalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                Text(value.toString(), style = MaterialTheme.typography.titleLarge)
                                Text(
                                    metricName(key, language),
                                    style = MaterialTheme.typography.bodySmall,
                                )
                                previous[key]?.let {
                                    Text(
                                        metricDelta(value, it),
                                        style = MaterialTheme.typography.labelLarge,
                                    )
                                    Text(
                                        "${tr(language, "zuvor", "раніше")}: $it",
                                        style = MaterialTheme.typography.labelSmall,
                                    )
                                }
                            }
                        }
                    }
                    if (row.size < columns)
                        repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
    }
}

internal fun metricDelta(current: Int, previous: Int): String =
    when {
        previous == 0 && current == 0 -> "0%"
        previous == 0 -> "+100%"
        else -> {
            val percent = (current - previous) * 100.0 / previous
            val rounded =
                java.math
                    .BigDecimal(percent)
                    .setScale(1, java.math.RoundingMode.HALF_UP)
                    .stripTrailingZeros()
            (if (percent > 0) "+" else "") + rounded.toPlainString() + "%"
        }
    }

@Composable
private fun Trend(snapshot: OwnerAnalyticsSnapshot, language: String) {
    ElevatedCard(Modifier.fillMaxWidth().testTag("owner-analytics-trend")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                tr(language, "Aufruftrend", "Динаміка переглядів"),
                style = MaterialTheme.typography.titleMedium,
            )
            val maximum =
                snapshot.daily.maxOfOrNull { it.second["totalViews"] ?: 0 }?.coerceAtLeast(1) ?: 1
            snapshot.daily.forEach { (day, metrics) ->
                val count = metrics["totalViews"] ?: 0
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(
                            day,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.weight(1f),
                        )
                        Text(count.toString(), style = MaterialTheme.typography.labelLarge)
                    }
                    LinearProgressIndicator(
                        progress = { count.toFloat() / maximum },
                        modifier = Modifier.fillMaxWidth(),
                        drawStopIndicator = {},
                    )
                }
            }
        }
    }
}

@Composable
private fun RegionRow(region: AnalyticsRegion, language: String) {
    ElevatedCard(Modifier.fillMaxWidth().testTag("owner-analytics-region-${region.id}")) {
        Column(Modifier.padding(14.dp)) {
            Text(
                region.federalState?.let { stateName(it, language) }
                    ?: tr(language, "Österreich", "Австрія"),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                "${region.views} ${tr(language, "Aufrufe", "переглядів")} · ${region.contentCount} ${tr(language, "Inhalte", "матеріалів")}"
            )
        }
    }
}

@Composable
private fun UserMetrics(users: AnalyticsUsers, language: String) {
    MetricGrid(
        linkedMapOf(
            "totalUsers" to users.total,
            "activeUsersToday" to users.activeToday,
            "activeUsersSevenDays" to users.activeSevenDays,
            "activeUsersThirtyDays" to users.activeThirtyDays,
            "newRegistrations" to users.newRegistrations,
            "deletedAccounts" to users.deleted,
            "blockedUsers" to users.blocked,
            "deactivatedUsers" to users.deactivated,
        ),
        emptyMap(),
        language,
    )
}

@Composable
private fun Failure(failure: OwnerAnalyticsFailure, language: String, retry: () -> Unit) {
    ElevatedCard(
        colors =
            CardDefaults.elevatedCardColors(
                containerColor = MaterialTheme.colorScheme.errorContainer
            ),
        modifier = Modifier.fillMaxWidth().testTag("owner-analytics-error"),
    ) {
        Column(Modifier.padding(14.dp)) {
            Text(
                when (failure) {
                    OwnerAnalyticsFailure.ACCESS ->
                        tr(
                            language,
                            "Nur für bestätigte Inhaber verfügbar.",
                            "Доступно лише підтвердженому власнику.",
                        )
                    OwnerAnalyticsFailure.REFRESHING ->
                        tr(
                            language,
                            "Der Bericht wird gerade aktualisiert.",
                            "Звіт зараз оновлюється.",
                        )
                    else ->
                        tr(
                            language,
                            "Analytics konnten nicht bestätigt geladen werden.",
                            "Не вдалося підтверджено завантажити аналітику.",
                        )
                }
            )
            TextButton(retry) { Text(tr(language, "Erneut laden", "Оновити")) }
        }
    }
}

@Composable
private fun Empty(language: String) {
    Text(
        tr(
            language,
            "Für diesen Zeitraum liegen noch keine bestätigten Daten vor.",
            "За цей період ще немає підтверджених даних.",
        ),
        Modifier.fillMaxWidth().testTag("owner-analytics-empty"),
    )
}

@Composable
private fun SectionTitle(value: String) {
    Text(value, style = MaterialTheme.typography.titleLarge)
}

private fun summaryMetrics(snapshot: OwnerAnalyticsSnapshot) =
    listOf("totalViews", "newsViews", "eventViews", "organizationViews", "activeRegions")
        .mapNotNull { key -> snapshot.metrics[key]?.let { key to it } }
        .toMap()

private fun actionMetrics(values: Map<String, Int>) =
    listOf(
            "newsLikes",
            "totalBookmarks",
            "eventRegistrations",
            "cancelledEventRegistrations",
            "organizationFollows",
            "organizationUnfollows",
        )
        .mapNotNull { key -> values[key]?.let { key to it } }
        .toMap()

private fun kind(type: String, language: String) =
    when (type) {
        "news" -> tr(language, "Nachricht", "Новина")
        "event" -> tr(language, "Veranstaltung", "Подія")
        else -> tr(language, "Organisation", "Організація")
    }

private fun metricName(key: String, language: String) =
    when (key) {
        "views" -> tr(language, "Aufrufe", "Перегляди")
        "totalViews" -> tr(language, "Aufrufe gesamt", "Усього переглядів")
        "newsViews" -> tr(language, "Nachrichtenaufrufe", "Перегляди новин")
        "eventViews" -> tr(language, "Veranstaltungsaufrufe", "Перегляди подій")
        "organizationViews",
        "profileViews" -> tr(language, "Organisationsaufrufe", "Перегляди організацій")
        "activeRegions" -> tr(language, "Aktive Regionen", "Активні регіони")
        "newsLikes",
        "likes" -> tr(language, "Gefällt mir", "Вподобання")
        "totalBookmarks",
        "bookmarks" -> tr(language, "Gespeichert", "Збереження")
        "eventRegistrations",
        "registrations" -> tr(language, "Anmeldungen", "Реєстрації")
        "cancelledEventRegistrations",
        "cancelledRegistrations" -> tr(language, "Stornierungen", "Скасування")
        "organizationFollows",
        "follows" -> tr(language, "Abonnements", "Підписки")
        "organizationUnfollows",
        "unfollows" -> tr(language, "Abbestellungen", "Відписки")
        "totalUsers" -> tr(language, "Nutzer gesamt", "Усього користувачів")
        "activeUsersToday" -> tr(language, "Heute aktiv", "Активні сьогодні")
        "activeUsersSevenDays" -> tr(language, "7 Tage aktiv", "Активні за 7 днів")
        "activeUsersThirtyDays" -> tr(language, "30 Tage aktiv", "Активні за 30 днів")
        "newRegistrations" -> tr(language, "Neue Konten", "Нові акаунти")
        "deletedAccounts" -> tr(language, "Gelöschte Konten", "Видалені акаунти")
        "blockedUsers" -> tr(language, "Gesperrt", "Заблоковані")
        "deactivatedUsers" -> tr(language, "Deaktiviert", "Деактивовані")
        else -> key
    }

private fun stateName(value: String, language: String) =
    mapOf(
        "wien" to tr(language, "Wien", "Відень"),
        "niederoesterreich" to tr(language, "Niederösterreich", "Нижня Австрія"),
        "oberoesterreich" to tr(language, "Oberösterreich", "Верхня Австрія"),
        "steiermark" to tr(language, "Steiermark", "Штирія"),
        "kaernten" to tr(language, "Kärnten", "Каринтія"),
        "salzburg" to tr(language, "Salzburg", "Зальцбург"),
        "tirol" to tr(language, "Tirol", "Тіроль"),
        "vorarlberg" to tr(language, "Vorarlberg", "Форарльберг"),
        "burgenland" to tr(language, "Burgenland", "Бургенланд"),
    )[value] ?: value

private fun analyticsSourceName(source: String, language: String) =
    when (source) {
        "daily" -> tr(language, "Tagesstatistik", "Щоденна статистика")
        "top" -> tr(language, "Beliebte Inhalte", "Популярні матеріали")
        "regions" -> tr(language, "Regionen", "Регіони")
        "users" -> tr(language, "Nutzer", "Користувачі")
        else -> source
    }
