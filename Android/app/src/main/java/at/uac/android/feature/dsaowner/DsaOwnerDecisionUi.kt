package at.uac.android.feature.dsaowner

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import at.uac.android.core.ProtectedAlertDialog
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.feature.browse.displayTime
import at.uac.android.feature.browse.tr
import at.uac.android.feature.feedback.ProtectFeedbackCaseWindow

@Composable
fun DsaOwnerDecisionDestination(
    reportId: String,
    language: String,
    state: DsaOwnerState,
    model: DsaOwnerDecisionViewModel,
) {
    ProtectFeedbackCaseWindow(true)
    LifecycleResumeEffect(reportId, state.session) {
        model.show(reportId)
        onPauseOrDispose { model.hide(reportId) }
    }
    DsaOwnerDecisionScreen(state, reportId, language, model::refresh, model::decide)
}

@Composable
fun DsaOwnerDecisionScreen(
    snapshot: DsaOwnerState,
    reportId: String,
    language: String,
    onRefresh: () -> Unit,
    onDecide: (Any) -> Unit,
) {
    var outcome by remember(reportId, snapshot.session) { mutableStateOf("noAction") }
    var facts by remember(reportId, snapshot.session) { mutableStateOf("") }
    var legalBasis by remember(reportId, snapshot.session) { mutableStateOf("") }
    var termsBasis by remember(reportId, snapshot.session) { mutableStateOf("") }
    var territory by remember(reportId, snapshot.session) { mutableStateOf("Österreich") }
    var duration by remember(reportId, snapshot.session) { mutableStateOf("") }
    var redress by remember(reportId, snapshot.session) { mutableStateOf("") }
    var reason by remember(reportId, snapshot.session) { mutableStateOf("") }
    var humanReview by remember(reportId, snapshot.session) { mutableStateOf(false) }
    var confirmation by remember(reportId, snapshot.session) { mutableStateOf(false) }
    LaunchedEffect(snapshot.receipt) {
        if (snapshot.receipt != null) {
            facts = ""; legalBasis = ""; termsBasis = ""; duration = ""; redress = ""; reason = ""
        }
    }
    val state = if (snapshot.visible && snapshot.reportId == reportId &&
        snapshot.session?.role == "owner" && snapshot.session.ready) snapshot
        else DsaOwnerState(session = snapshot.session, loading = true)
    val review = state.review
    val caseDraft = DsaOwnerCaseDraft(outcome, facts, legalBasis, termsBasis, territory,
        duration, redress, humanReview)
    val appealDraft = DsaOwnerAppealDraft(outcome, reason, humanReview)
    val canSubmit = review != null && humanReview && !state.submitting &&
        if (review.action == DsaOwnerAction.CASE) {
            outcome in setOf("noAction", "restricted", "removed") &&
                facts.trim().length >= 20 &&
                (legalBasis.isNotBlank() || termsBasis.isNotBlank()) &&
                territory.isNotBlank() && duration.isNotBlank() && redress.isNotBlank()
        } else outcome in setOf("upheld", "changed") && reason.trim().length >= 20

    LazyColumn(
        Modifier.fillMaxWidth().testTag("dsa-owner-list"),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item { UacSectionHeading(tr(language, "DSA-Entscheidung", "Рішення DSA"), UacIcon.SECURITY) }
        if (state.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        state.error?.let { failure -> item {
            Text(ownerError(failure, language), Modifier.testTag("dsa-owner-error"))
        } }
        state.receipt?.let { receipt -> item {
            Card(Modifier.fillMaxWidth().testTag("dsa-owner-receipt")) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(tr(language, "Entscheidung bestätigt", "Рішення підтверджено"),
                        style = MaterialTheme.typography.titleMedium)
                    Text(receipt.caseNumber)
                    Text(displayTime(receipt.decidedAt, language))
                }
            }
        } }
        if (review != null && state.receipt == null) {
            item { Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(review.caseNumber, style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.testTag("dsa-owner-case"))
                    Text(review.message)
                    Text(review.context.exactLocation)
                    Text(review.context.illegalExplanation)
                    review.context.appeal?.let { Text(it.reason) }
                }
            } }
            item {
                Text(tr(language,
                    "Eine Einschränkung oder Entfernung muss vor der Entscheidung am verknüpften Inhalt ausgeführt sein.",
                    "Обмеження або видалення пов’язаного вмісту має бути виконане до ухвалення рішення."),
                    style = MaterialTheme.typography.bodySmall)
            }
            item {
                Text(tr(language, "Ergebnis", "Результат"), style = MaterialTheme.typography.titleSmall)
                val choices = if (review.action == DsaOwnerAction.CASE)
                    listOf("noAction" to tr(language,"Keine Maßnahme","Без заходів"),
                        "restricted" to tr(language,"Eingeschränkt","Обмежено"),
                        "removed" to tr(language,"Entfernt","Видалено"))
                    else listOf("upheld" to tr(language,"Bestätigt","Підтверджено"),
                        "changed" to tr(language,"Geändert","Змінено"))
                Column {
                    choices.forEach { (wire, label) ->
                        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                            RadioButton(selected = outcome == wire, onClick = { outcome = wire },
                                modifier = Modifier.testTag("dsa-owner-outcome-$wire"))
                            Text(label)
                        }
                    }
                }
            }
            if (review.action == DsaOwnerAction.CASE) {
                item { OwnerField(facts, { facts = it }, language, "Sachverhalt und Umstände", "Факти та обставини", "dsa-owner-facts", 5_000) }
                item { OwnerField(legalBasis, { legalBasis = it }, language, "Rechtsgrundlage", "Правова підстава", "dsa-owner-legal", 2_000) }
                item { OwnerField(termsBasis, { termsBasis = it }, language, "Grundlage in den Nutzungsbedingungen", "Підстава в умовах користування", "dsa-owner-terms", 2_000) }
                item { OwnerField(territory, { territory = it }, language, "Geltungsbereich", "Територія дії", "dsa-owner-territory", 500) }
                item { OwnerField(duration, { duration = it }, language, "Dauer", "Тривалість", "dsa-owner-duration", 500) }
                item { OwnerField(redress, { redress = it }, language, "Rechtsbehelfe", "Способи оскарження", "dsa-owner-redress", 2_000) }
            } else item { OwnerField(reason, { reason = it }, language, "Begründung der Einspruchsentscheidung", "Обґрунтування рішення за скаргою", "dsa-owner-reason", 5_000) }
            item {
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Checkbox(humanReview, { humanReview = it }, Modifier.testTag("dsa-owner-human"))
                    Text(tr(language, "Menschliche Prüfung bestätigt", "Підтверджую розгляд людиною"))
                }
            }
            item {
                Button({ confirmation = true }, Modifier.fillMaxWidth().testTag("dsa-owner-submit"),
                    enabled = canSubmit) {
                    Text(tr(language, "Entscheidung speichern", "Зберегти рішення"))
                }
                if (state.submitting) LinearProgressIndicator(Modifier.fillMaxWidth())
            }
        }
        if (state.receipt == null) item {
            OutlinedButton(onRefresh, Modifier.testTag("dsa-owner-refresh"), enabled = !state.submitting) {
                Text(tr(language, "Erneut prüfen", "Перевірити знову"))
            }
        }
    }
    if (confirmation && canSubmit) ProtectedAlertDialog(
        onDismissRequest = { confirmation = false },
        title = { Text(tr(language, "Entscheidung senden?", "Надіслати рішення?")) },
        text = { Text(tr(language,
            "Fall und Berechtigung werden vor dem Senden erneut geprüft.",
            "Перед надсиланням справу та права буде перевірено повторно.")) },
        confirmButton = { TextButton({
            confirmation = false
            onDecide(if (review.action == DsaOwnerAction.CASE) caseDraft else appealDraft)
        }, Modifier.testTag("dsa-owner-confirm")) { Text(tr(language,"Senden","Надіслати")) } },
        dismissButton = { TextButton({ confirmation = false }) { Text(tr(language,"Abbrechen","Скасувати")) } },
    )
}

@Composable
private fun OwnerField(value: String, onChange: (String) -> Unit, language: String,
    de: String, uk: String, tag: String, max: Int) {
    OutlinedTextField(value, { if (it.length <= max) onChange(it) },
        Modifier.fillMaxWidth().testTag(tag), label = { Text(tr(language, de, uk)) },
        minLines = if (max > 500) 2 else 1)
}

private fun ownerError(failure: DsaOwnerFailure, language: String): String = when (failure) {
    DsaOwnerFailure.ACCESS -> tr(language,"Nur ein geschütztes Inhaberkonto kann entscheiden.","Рішення доступне лише захищеному акаунту власника.")
    DsaOwnerFailure.STALE -> tr(language,"Der Fall hat sich geändert. Bitte erneut prüfen.","Справу змінено. Перевірте її знову.")
    DsaOwnerFailure.UNCONFIRMED -> tr(language,"Das Ergebnis ist nicht bestätigt. Vor einem neuen Versuch den Fall laden.","Результат не підтверджено. Перед повтором оновіть справу.")
    DsaOwnerFailure.INELIGIBLE -> tr(language,"Dieser Fall ist derzeit nicht für eine Entscheidung bereit.","Ця справа зараз не готова до рішення.")
    DsaOwnerFailure.OFFLINE -> tr(language,"Server nicht erreichbar.","Сервер недоступний.")
    else -> tr(language,"Der Fall konnte nicht zuverlässig geprüft werden.","Не вдалося надійно перевірити справу.")
}
