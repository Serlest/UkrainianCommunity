package at.uac.android.feature.dsastatement

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import at.uac.android.core.WindowSecurity
import at.uac.android.feature.browse.tr

@Composable
fun DsaStatementDestination(
    reportId: String,
    language: String,
    snapshot: DsaStatementState,
    model: DsaStatementViewModel,
    onAccount: () -> Unit,
) {
    val context = LocalContext.current
    DisposableEffect(context) {
        val lease = context.statementActivity()?.window?.let(WindowSecurity::acquire)
        onDispose { lease?.close() }
    }
    LifecycleResumeEffect(reportId, snapshot.session) {
        model.show(reportId)
        onPauseOrDispose { model.hide(reportId) }
    }
    DsaStatementScreen(snapshot, reportId, language, model::refresh, onAccount)
}

private fun Context.statementActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.takeIf { it !== this }?.statementActivity()
        else -> null
    }

@Composable
fun DsaStatementScreen(
    snapshot: DsaStatementState,
    reportId: String,
    language: String,
    onRefresh: () -> Unit,
    onAccount: () -> Unit,
) {
    val ready = snapshot.session?.ready == true
    val state =
        if (snapshot.reportId == reportId && snapshot.visible && ready) snapshot
        else DsaStatementState(session = snapshot.session, reportId = reportId, loading = ready)
    LazyColumn(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        contentPadding = PaddingValues(12.dp),
        modifier = Modifier.testTag("dsa-statement-list"),
    ) {
        item {
            Text(
                tr(language, "Begründung der Entscheidung", "Обґрунтування рішення"),
                style = MaterialTheme.typography.headlineSmall,
            )
        }
        if (!ready)
            item {
                Text(
                    tr(
                        language,
                        "Melde dich mit einem berechtigten, bestätigten Konto an.",
                        "Увійдіть у підтверджений обліковий запис із правом доступу.",
                    ),
                    Modifier.testTag("dsa-account-gate"),
                )
                OutlinedButton(onAccount) {
                    Text(tr(language, "Zum Konto", "До облікового запису"))
                }
            }
        else if (state.loading)
            item {
                LinearProgressIndicator(Modifier.fillMaxWidth().testTag("dsa-loading"))
            }
        else {
            state.error?.let { problem ->
                item {
                    Text(dsaStatementErrorText(problem, language), Modifier.testTag("dsa-error"))
                }
            }
            state.statement
                ?.takeIf { it.id == reportId && state.error == null }
                ?.let { statement ->
                    item {
                        StatementCard {
                            StatementField(
                                tr(language, "Aktenzeichen", "Номер справи"),
                                statement.caseNumber,
                                "dsa-case",
                            )
                            StatementField(
                                tr(language, "Status", "Статус"),
                                dsaStatementStatusText(statement, language),
                                "dsa-status",
                            )
                            StatementField(
                                tr(language, "Inhaltstyp", "Тип вмісту"),
                                statement.sourceType,
                                "dsa-source-type",
                            )
                            StatementField(
                                tr(language, "Inhaltskennung", "Ідентифікатор вмісту"),
                                statement.sourceId,
                                "dsa-source-id",
                            )
                        }
                    }
                    statement.decision?.let { decision ->
                        item {
                            StatementCard {
                                StatementField(
                                    tr(language, "Entscheidung", "Рішення"),
                                    dsaOutcomeText(decision, language),
                                    "dsa-outcome",
                                )
                                StatementField(
                                    tr(language, "Sachverhalt und Umstände", "Факти та обставини"),
                                    decision.factsAndCircumstances,
                                    "dsa-facts",
                                )
                                StatementField(
                                    tr(language, "Rechtsgrundlage", "Правова підстава"),
                                    decision.legalBasis,
                                    "dsa-legal-basis",
                                )
                                StatementField(
                                    tr(
                                        language,
                                        "Grundlage in den Nutzungsbedingungen",
                                        "Підстава в умовах користування",
                                    ),
                                    decision.termsBasis,
                                    "dsa-terms-basis",
                                )
                                StatementField(
                                    tr(language, "Räumlicher Geltungsbereich", "Територія дії"),
                                    decision.territorialScope,
                                    "dsa-territory",
                                )
                                StatementField(
                                    tr(language, "Dauer", "Тривалість"),
                                    decision.duration,
                                    "dsa-duration",
                                )
                                StatementField(
                                    tr(language, "Rechtsbehelfe", "Способи оскарження"),
                                    decision.redressInformation,
                                    "dsa-redress",
                                )
                                StatementField(
                                    tr(
                                        language,
                                        "Automatisierung verwendet",
                                        "Використано автоматизацію",
                                    ),
                                    yesNo(decision.automationUsed, language),
                                    "dsa-automation",
                                )
                            }
                        }
                    }
                    statement.appealDecision?.let { appeal ->
                        item {
                            StatementCard {
                                StatementField(
                                    tr(language, "Beschwerdeentscheidung", "Рішення за скаргою"),
                                    dsaAppealText(appeal, language),
                                    "dsa-appeal-outcome",
                                )
                                StatementField(
                                    tr(language, "Begründung", "Обґрунтування"),
                                    appeal.reason,
                                    "dsa-appeal-reason",
                                )
                                StatementField(
                                    tr(
                                        language,
                                        "Automatisierung verwendet",
                                        "Використано автоматизацію",
                                    ),
                                    yesNo(appeal.automationUsed, language),
                                    "dsa-appeal-automation",
                                )
                            }
                        }
                    }
                    if (statement.decision == null && statement.appealDecision == null)
                        item {
                            Text(
                                tr(
                                    language,
                                    "Der Server liefert derzeit keine Entscheidungsbegründung.",
                                    "Наразі сервер не надав обґрунтування рішення.",
                                ),
                                Modifier.testTag("dsa-no-decision"),
                            )
                        }
                    item {
                        Text(
                            tr(
                                language,
                                "Diese Ansicht enthält keine Identität, Kontaktdaten oder Belege der meldenden Person.",
                                "Цей перегляд не містить особи, контактних даних або доказів заявника.",
                            ),
                            Modifier.testTag("dsa-privacy-note"),
                        )
                    }
                }
            item {
                OutlinedButton(onRefresh, modifier = Modifier.testTag("dsa-refresh")) {
                    Text(tr(language, "Erneut laden", "Оновити"))
                }
            }
        }
    }
}

@Composable
private fun StatementCard(content: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            content()
        }
    }
}

@Composable
private fun StatementField(label: String, value: String?, tag: String) {
    if (value.isNullOrBlank()) return
    Column {
        Text(label, style = MaterialTheme.typography.labelLarge)
        SelectionContainer { Text(value, Modifier.testTag(tag)) }
    }
}

private fun yesNo(value: Boolean, language: String) =
    if (value) tr(language, "Ja", "Так") else tr(language, "Nein", "Ні")

fun dsaStatementErrorText(error: DsaStatementFailure, language: String): String =
    when (error) {
        DsaStatementFailure.ACCESS ->
            tr(
                language,
                "Dieses Konto hat derzeit keinen Zugriff.",
                "Цей обліковий запис наразі не має доступу.",
            )
        DsaStatementFailure.MISSING ->
            tr(
                language,
                "Diese Begründung ist für dieses Konto nicht verfügbar.",
                "Це обґрунтування недоступне для цього облікового запису.",
            )
        DsaStatementFailure.OFFLINE ->
            tr(
                language,
                "Der Server ist nicht erreichbar. Es werden keine gespeicherten privaten Daten angezeigt.",
                "Сервер недоступний. Збережені приватні дані не показуються.",
            )
        DsaStatementFailure.INVALID,
        DsaStatementFailure.UNKNOWN ->
            tr(
                language,
                "Die Antwort konnte nicht sicher gelesen werden.",
                "Не вдалося безпечно прочитати відповідь.",
            )
    }

fun dsaStatementStatusText(value: DsaStatement, language: String): String =
    when (value.status) {
        DsaStatementStatus.SUBMITTED -> tr(language, "Eingereicht", "Подано")
        DsaStatementStatus.UNDER_REVIEW -> tr(language, "In Prüfung", "На розгляді")
        DsaStatementStatus.DECIDED -> tr(language, "Entschieden", "Рішення ухвалено")
        DsaStatementStatus.APPEALED -> tr(language, "Beschwerde eingereicht", "Скаргу подано")
        DsaStatementStatus.APPEAL_DECIDED ->
            tr(language, "Beschwerde entschieden", "Скаргу розглянуто")
        DsaStatementStatus.UNKNOWN ->
            tr(language, "Unbekannter Status", "Невідомий статус") + ": " + value.rawStatus
    }

fun dsaOutcomeText(value: DsaStatementDecision, language: String): String =
    when (value.outcome) {
        DsaStatementOutcome.NO_ACTION -> tr(language, "Keine Maßnahme", "Без заходів")
        DsaStatementOutcome.RESTRICTED -> tr(language, "Eingeschränkt", "Обмежено")
        DsaStatementOutcome.REMOVED -> tr(language, "Entfernt", "Видалено")
        DsaStatementOutcome.UNKNOWN ->
            tr(language, "Unbekanntes Ergebnis", "Невідомий результат") + ": " + value.rawOutcome
    }

fun dsaAppealText(value: DsaStatementAppealDecision, language: String): String =
    when (value.outcome) {
        DsaStatementAppealOutcome.UPHELD -> tr(language, "Bestätigt", "Підтверджено")
        DsaStatementAppealOutcome.CHANGED ->
            tr(language, "Geändert – erneute Prüfung", "Змінено — повторний розгляд")
        DsaStatementAppealOutcome.UNKNOWN ->
            tr(language, "Unbekanntes Ergebnis", "Невідомий результат") + ": " + value.rawOutcome
    }
