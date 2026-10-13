package at.uac.android.feature.bannermeasurement

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.design.UacSymbol
import at.uac.android.feature.browse.tr
import at.uac.android.feature.owneranalytics.AnalyticsPeriod
import at.uac.android.feature.owneranalytics.OwnerAnalyticsSession
import java.text.NumberFormat
import java.util.Locale
import kotlinx.coroutines.CancellationException

@Composable
fun BannerMeasurementReportScreen(
    source: BannerReportSource,
    session: OwnerAnalyticsSession?,
    language: String,
    onBack: () -> Unit,
) {
    BackHandler(onBack = onBack)
    var period by remember { mutableStateOf(AnalyticsPeriod.SEVEN_DAYS) }
    var retry by remember { mutableIntStateOf(0) }
    var report by remember(session, period) { mutableStateOf<BannerReport?>(null) }
    var loading by remember(session, period) { mutableStateOf(false) }
    var error by remember(session, period) { mutableStateOf(false) }
    LaunchedEffect(session, period, retry) {
        if (session?.ready != true) return@LaunchedEffect
        loading = true
        error = false
        try { report = source.load(session, period) }
        catch (failure: CancellationException) { throw failure }
        catch (_: Exception) { error = true }
        finally { loading = false }
    }
    Column(Modifier.fillMaxSize().testTag("banner-report")) {
        at.uac.android.design.UacBackButton(onBack, Modifier.testTag("banner-report-back")) {
            UacSymbol(UacIcon.BACK)
            Text(tr(language, "Zurück", "Назад"))
        }
        UacSectionHeading(tr(language, "Banner-Statistik", "Статистика банерів"), UacIcon.ANALYTICS)
        LazyColumn(Modifier.fillMaxSize().testTag("banner-report-list"),
            verticalArrangement = Arrangement.spacedBy(12.dp),
            contentPadding = PaddingValues(bottom = 32.dp)) {
            item {
                Text(tr(language, "Zusammengefasste sichtbare Einblendungen und Aufrufe · UTC-Tage",
                    "Зведені видимі покази й натискання · дні UTC"),
                    style = MaterialTheme.typography.bodySmall)
            }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AnalyticsPeriod.entries.forEach { candidate ->
                        FilterChip(selected = period == candidate,
                            onClick = { period = candidate },
                            label = { Text(when (candidate) {
                                AnalyticsPeriod.TODAY -> tr(language, "Heute", "Сьогодні")
                                AnalyticsPeriod.SEVEN_DAYS -> tr(language, "7 Tage", "7 днів")
                                AnalyticsPeriod.THIRTY_DAYS -> tr(language, "30 Tage", "30 днів")
                            }) },
                            modifier = Modifier.testTag("banner-report-period-${candidate.name}"))
                    }
                }
            }
            if (session?.ready != true) item {
                Text(tr(language, "Owner-Zugriff nicht bestätigt.", "Доступ власника не підтверджено."))
            }
            if (loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
            if (error) item {
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(14.dp)) {
                        Text(tr(language, "Bericht nicht verfügbar.", "Звіт недоступний."))
                        TextButton(onClick = { retry++ }, modifier = Modifier.testTag("banner-report-retry")) {
                            Text(tr(language, "Erneut versuchen", "Спробувати ще раз"))
                        }
                    }
                }
            }
            report?.let { loaded ->
                if (loaded.namesUnavailable) item {
                    Text(tr(language, "Bannernamen derzeit nicht verfügbar; IDs werden angezeigt.",
                        "Назви банерів зараз недоступні; показано ID."),
                        style = MaterialTheme.typography.bodySmall)
                }
                if (loaded.banners.isEmpty()) item {
                    Text(tr(language, "Für diesen Zeitraum liegen keine Bannerdaten vor.",
                        "За цей період даних банерів немає."), Modifier.testTag("banner-report-empty"))
                } else {
                    item { ReportRow(tr(language, "Überblick", "Огляд"), loaded.totals, language) }
                    item { Text(tr(language, "Nach Bereich", "За розділом"),
                        style = MaterialTheme.typography.titleMedium) }
                    items(loaded.sections.entries.sortedBy { it.key }, key = { "section:${it.key}" }) {
                        ReportRow(sectionTitle(it.key, language), it.value, language)
                    }
                    item { Text(tr(language, "Nach Tag", "За днем"),
                        style = MaterialTheme.typography.titleMedium) }
                    items(loaded.days.entries.sortedByDescending { it.key }, key = { "day:${it.key}" }) {
                        ReportRow(it.key, it.value, language)
                    }
                    item { Text(tr(language, "Nach Banner", "За банером"),
                        style = MaterialTheme.typography.titleMedium) }
                    items(loaded.banners.entries.sortedWith(compareByDescending<Map.Entry<String, BannerTotals>> {
                        it.value.impressions }.thenBy { it.key }), key = { "banner:${it.key}" }) {
                        val bannerId = it.key
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            ReportRow(loaded.names[bannerId] ?: bannerId, it.value, language)
                            if (loaded.names[bannerId] != null)
                                Text(bannerId, style = MaterialTheme.typography.bodySmall)
                            loaded.bannerSections[bannerId]?.entries?.sortedBy { section -> section.key }
                                ?.forEach { section ->
                                    ReportRow(sectionTitle(section.key, language), section.value, language,
                                        Modifier.testTag("banner-section-$bannerId-${section.key}"))
                                }
                        }
                    }
                }
                item { Text(tr(language,
                    "Eine Einblendung zählt bei mindestens 50 % Sichtbarkeit für eine Sekunde. Ein Tippen zählt als Aufruf; Werte können verzögert erscheinen.",
                    "Показ зараховується за видимості щонайменше 50 % протягом секунди. Натискання рахується окремо; дані можуть з’являтися із затримкою."),
                    style = MaterialTheme.typography.bodySmall) }
            }
        }
    }
}

@Composable
private fun ReportRow(title: String, totals: BannerTotals, language: String,
    modifier: Modifier = Modifier) {
    val rate = totals.clickRate?.let {
        NumberFormat.getPercentInstance(Locale.forLanguageTag(language)).apply {
            maximumFractionDigits = 1
        }.format(it)
    } ?: "—"
    ElevatedCard(modifier.fillMaxWidth()) {
        Column(Modifier.padding(14.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text("${tr(language, "Einblendungen", "Покази")}: ${totals.impressions} · " +
                "${tr(language, "Aufrufe", "Натискання")}: ${totals.clicks} · $rate",
                style = MaterialTheme.typography.bodySmall)
        }
    }
}

private fun sectionTitle(section: String, language: String): String = when (section) {
    "home" -> tr(language, "Nachrichten", "Новини")
    "events" -> tr(language, "Termine", "Події")
    "organizations" -> tr(language, "Organisation", "Організації")
    "directory" -> tr(language, "Ratgeber", "Довідник")
    else -> section
}
