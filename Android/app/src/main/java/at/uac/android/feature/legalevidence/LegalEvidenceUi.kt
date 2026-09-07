package at.uac.android.feature.legalevidence

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
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
import at.uac.android.feature.browse.tr
import at.uac.android.feature.moderation.ModerationSession
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.coroutines.CancellationException

@Composable
fun LegalEvidenceScreen(
    userId: String,
    session: ModerationSession?,
    language: String,
    loader: LegalEvidenceLoader,
    onBack: () -> Unit,
) {
    var events by remember(userId, session) { mutableStateOf<List<LegalEvidenceEvent>?>(null) }
    var failed by remember(userId, session) { mutableStateOf(false) }
    var reload by remember(userId, session) { mutableIntStateOf(0) }
    val allowed = session?.ready == true && session.role == "owner"
    LaunchedEffect(userId, session, reload) {
        events = null
        failed = false
        if (!allowed) return@LaunchedEffect
        try {
            events = loader.all(userId)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            failed = true
        }
    }
    LegalEvidenceContent(
        userId,
        allowed,
        events,
        failed,
        language,
        onBack,
        { reload++ },
    )
}

@Composable
fun LegalEvidenceContent(
    userId: String,
    allowed: Boolean,
    events: List<LegalEvidenceEvent>?,
    failed: Boolean,
    language: String,
    onBack: () -> Unit = {},
    onRetry: () -> Unit = {},
) {
    LazyColumn(
        Modifier.fillMaxSize().testTag("legal-evidence"),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item("header") {
            TextButton(onBack, Modifier.testTag("legal-evidence-back")) {
                Text(tr(language, "Zurück", "Назад"))
            }
            Text(
                tr(language, "Rechtliche Nachweise", "Юридичні підтвердження"),
                style = MaterialTheme.typography.headlineMedium,
            )
            Text(
                tr(
                    language,
                    "Geschützte Inhaberansicht · Konto $userId",
                    "Захищений перегляд власника · акаунт $userId",
                ),
                style = MaterialTheme.typography.bodySmall,
            )
        }
        if (!allowed)
            item("denied") {
                Text(
                    tr(
                        language,
                        "Nur der aktive App-Inhaber mit bestätigter Anmeldesicherheit darf diese Nachweise laden.",
                        "Лише активний власник застосунку з підтвердженим захистом входу може завантажувати ці підтвердження.",
                    ),
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.testTag("legal-evidence-denied"),
                )
            }
        else if (failed)
            item("failed") {
                Text(
                    tr(
                        language,
                        "Die serverseitigen Nachweise konnten nicht bestätigt werden.",
                        "Не вдалося підтвердити серверні юридичні записи.",
                    ),
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.testTag("legal-evidence-error"),
                )
                OutlinedButton(onRetry, Modifier.testTag("legal-evidence-retry")) {
                    Text(tr(language, "Erneut laden", "Спробувати знову"))
                }
            }
        else if (events == null)
            item("loading") { CircularProgressIndicator(Modifier.testTag("legal-evidence-loading")) }
        else if (events.isEmpty())
            item("empty") {
                Text(
                    tr(language, "Keine Nachweise vorhanden.", "Юридичних записів немає."),
                    Modifier.testTag("legal-evidence-empty"),
                )
            }
        else
            items(events, key = { it.id }) { event ->
                Card(Modifier.fillMaxWidth().testTag("legal-evidence-event-${event.id}")) {
                    Column(
                        Modifier.fillMaxWidth()
                            .padding(16.dp)
                            .testTag("legal-evidence-event-content"),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(legalEvidenceEventLabel(event.eventType, language))
                        Text(legalEvidenceDate(event, language))
                        Text(
                            tr(language, "Quelle: ${event.source}", "Джерело: ${event.source}"),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
    }
}

internal fun legalEvidenceEventLabel(value: String, language: String) =
    when (value) {
        "termsAccepted" -> tr(language, "Nutzungsbedingungen akzeptiert", "Умови використання прийнято")
        "privacyAcknowledged" -> tr(language, "Datenschutz bestätigt", "Політику приватності підтверджено")
        "minimumAgeConfirmed" -> tr(language, "Mindestalter bestätigt", "Мінімальний вік підтверджено")
        "organizationRulesAccepted" -> tr(language, "Organisationsregeln akzeptiert", "Правила організації прийнято")
        "analyticsGranted" -> tr(language, "Analyse-Einwilligung erteilt", "Згоду на аналітику надано")
        "analyticsWithdrawn" -> tr(language, "Analyse-Einwilligung widerrufen", "Згоду на аналітику відкликано")
        else -> value
    }

private fun legalEvidenceDate(event: LegalEvidenceEvent, language: String) =
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
        .withLocale(Locale.forLanguageTag(language))
        .withZone(ZoneId.systemDefault())
        .format(event.occurredAt)
