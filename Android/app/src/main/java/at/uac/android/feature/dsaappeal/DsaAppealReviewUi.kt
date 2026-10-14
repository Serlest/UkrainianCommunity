package at.uac.android.feature.dsaappeal

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import at.uac.android.core.WindowSecurity
import at.uac.android.feature.browse.displayTime
import at.uac.android.feature.browse.tr
import java.time.Instant

@Composable
fun DsaAppealReviewDestination(
    reportId: String,
    language: String,
    snapshot: DsaAppealReviewState,
    model: DsaAppealReviewViewModel,
    onAccount: () -> Unit,
) {
    val context = LocalContext.current
    DisposableEffect(context) {
        val lease = context.reviewActivity()?.window?.let(WindowSecurity::acquire)
        onDispose { lease?.close() }
    }
    LifecycleResumeEffect(reportId, snapshot.session) {
        model.show(reportId)
        onPauseOrDispose { model.hide(reportId) }
    }
    DsaAppealReviewScreen(
        snapshot, reportId, language, Instant.now(), model::refresh, onAccount,
        if (model.canSubmit) model::submit else null,
    )
}

private fun Context.reviewActivity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.takeIf { it !== this }?.reviewActivity()
        else -> null
    }

@Composable
fun DsaAppealReviewScreen(
    snapshot: DsaAppealReviewState,
    reportId: String,
    language: String,
    now: Instant,
    onRefresh: () -> Unit,
    onAccount: () -> Unit,
    onSubmit: ((String) -> Unit)? = null,
) {
    var reason by remember(reportId, snapshot.session) { mutableStateOf("") }
    var confirmSubmit by remember(reportId, snapshot.session) { mutableStateOf(false) }
    LaunchedEffect(snapshot.submitted) {
        if (snapshot.submitted != null) reason = ""
    }
    val ready = snapshot.session?.ready == true
    val state =
        if (snapshot.visible && snapshot.reportId == reportId && ready)
            snapshot.forSession(snapshot.session, now)
        else DsaAppealReviewState(session = snapshot.session, loading = ready)
    LazyColumn(
        Modifier.testTag("dsa-review-list"),
        contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            at.uac.android.design.UacSectionHeading(
                tr(
                    language,
                    "Entscheidung vor einer Beschwerde prüfen",
                    "Перевірка рішення перед скаргою",
                ),
                icon = at.uac.android.design.UacIcon.SECURITY,
            )
        }
        if (onSubmit == null) item {
            Text(
                tr(language,
                    "Nur Ansicht. Das Einreichen einer Beschwerde ist hier nicht verfügbar.",
                    "Лише перегляд. Подання скарги тут недоступне."),
                Modifier.testTag("dsa-review-readonly"),
            )
        }
        when {
            !ready ->
                item {
                    Text(
                        tr(
                            language,
                            "Ein bestätigtes, berechtigtes Konto ist erforderlich.",
                            "Потрібен підтверджений обліковий запис із правом доступу.",
                        ),
                        Modifier.testTag("dsa-review-access"),
                    )
                    OutlinedButton(onAccount) {
                        Text(tr(language, "Zum Konto", "До облікового запису"))
                    }
                }
            state.loading ->
                item {
                    LinearProgressIndicator(Modifier.fillMaxWidth().testTag("dsa-review-loading"))
                }
            else -> {
                state.submitted?.let { receipt ->
                    item {
                        Card(Modifier.fillMaxWidth().testTag("dsa-review-receipt")) {
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(tr(language, "Beschwerde eingereicht", "Скаргу подано"),
                                    style = MaterialTheme.typography.titleMedium)
                                Text(receipt.caseNumber)
                                Text(displayTime(receipt.submittedAt, language))
                            }
                        }
                    }
                }
                state.submitError?.let { failure ->
                    item { Text(dsaAppealReviewErrorText(failure, language), Modifier.testTag("dsa-review-submit-error")) }
                }
                state.reasonError?.let { failure ->
                    item { Text(dsaAppealReasonErrorText(failure, language), Modifier.testTag("dsa-review-reason-error")) }
                }
                state.error?.let { error ->
                    item {
                        Text(
                            dsaAppealReviewErrorText(error, language),
                            Modifier.testTag("dsa-review-error"),
                        )
                    }
                }
                state.review
                    ?.takeIf {
                        state.error == null &&
                            it.session == state.session &&
                            it.snapshot.reportId == reportId &&
                            it.snapshot.reporterUid == state.session.uid
                    }
                    ?.snapshot
                    ?.let { review ->
                        item {
                            ReviewField(
                                tr(language, "Aktenzeichen", "Номер справи"),
                                review.context.caseNumber,
                                "dsa-review-case",
                            )
                        }
                        item {
                            ReviewField(
                                tr(language, "Entscheidung", "Рішення"),
                                when (review.decision.outcome) {
                                    "noAction" -> tr(language, "Keine Maßnahme", "Без заходів")
                                    "restricted" -> tr(language, "Eingeschränkt", "Обмежено")
                                    "removed" -> tr(language, "Entfernt", "Видалено")
                                    else -> tr(language, "Unbekannt", "Невідомо")
                                },
                                "dsa-review-outcome",
                            )
                        }
                        item {
                            ReviewField(
                                tr(language, "Sachverhalt und Umstände", "Факти та обставини"),
                                review.decision.facts,
                                "dsa-review-facts",
                            )
                        }
                        review.decision.legalBasis?.let {
                            item {
                                ReviewField(
                                    tr(language, "Rechtsgrundlage", "Правова підстава"),
                                    it,
                                    "dsa-review-legal",
                                )
                            }
                        }
                        review.decision.termsBasis?.let {
                            item {
                                ReviewField(
                                    tr(
                                        language,
                                        "Grundlage in den Nutzungsbedingungen",
                                        "Підстава в умовах користування",
                                    ),
                                    it,
                                    "dsa-review-terms",
                                )
                            }
                        }
                        item {
                            ReviewField(
                                tr(language, "Geltungsbereich", "Територія дії"),
                                review.decision.territory,
                                "dsa-review-territory",
                            )
                        }
                        item {
                            ReviewField(
                                tr(language, "Dauer", "Тривалість"),
                                review.decision.duration,
                                "dsa-review-duration",
                            )
                        }
                        item {
                            ReviewField(
                                tr(language, "Rechtsbehelfe", "Способи оскарження"),
                                review.decision.redress,
                                "dsa-review-redress",
                            )
                        }
                        item {
                            ReviewField(
                                tr(
                                    language,
                                    "Automatisierung verwendet",
                                    "Використано автоматизацію",
                                ),
                                reviewYesNo(review.decision.automationUsed, language),
                                "dsa-review-automation",
                            )
                        }
                        item {
                            ReviewField(
                                tr(
                                    language,
                                    "Menschliche Prüfung bestätigt",
                                    "Розгляд людиною підтверджено",
                                ),
                                reviewYesNo(review.decision.humanReviewConfirmed, language),
                                "dsa-review-human",
                            )
                        }
                        item {
                            ReviewField(
                                tr(language, "Entschieden am", "Рішення ухвалено"),
                                displayTime(review.decision.decidedAt, language),
                                "dsa-review-date",
                            )
                        }
                        item {
                            ReviewField(
                                tr(
                                    language,
                                    "Beschwerdefrist laut Entscheidung",
                                    "Строк подання скарги за рішенням",
                                ),
                                displayTime(review.decision.appealDeadline, language),
                                "dsa-review-deadline",
                            )
                        }
                        item {
                            Text(
                                tr(
                                    language,
                                    "Diese Lesekopie reserviert keine Beschwerde. Vor dem Senden werden Fall und Frist erneut geprüft.",
                                    "Ця копія не резервує подання. Перед надсиланням справу й строк буде перевірено повторно.",
                                ),
                                Modifier.testTag("dsa-review-not-receipt"),
                            )
                        }
                        if (onSubmit != null && state.submitted == null) {
                            item {
                                OutlinedTextField(
                                    reason,
                                    { if (it.length <= DsaAppealContract.MAX_RAW_UTF16) reason = it },
                                    Modifier.fillMaxWidth().testTag("dsa-review-reason"),
                                    label = { Text(tr(language, "Grund der Beschwerde", "Підстава скарги")) },
                                    supportingText = {
                                        Text(tr(language, "Mindestens 20 Zeichen · höchstens 5.000", "Щонайменше 20 символів · щонайбільше 5 000"))
                                    },
                                    minLines = 4,
                                    maxLines = 8,
                                )
                            }
                            item {
                                Button(
                                    { confirmSubmit = true },
                                    Modifier.testTag("dsa-review-submit"),
                                    enabled = !state.submitting &&
                                        runCatching { AndroidDsaAppealCharacters.review(reason) }.isSuccess,
                                ) { Text(tr(language, "Beschwerde einreichen", "Подати скаргу")) }
                            }
                            if (state.submitting) item {
                                LinearProgressIndicator(Modifier.fillMaxWidth().testTag("dsa-review-submitting"))
                            }
                        }
                    }
                if (state.submitted == null) item {
                    OutlinedButton(onRefresh, Modifier.testTag("dsa-review-refresh")) {
                        Text(tr(language, "Erneut prüfen", "Перевірити знову"))
                    }
                }
            }
        }
    }
    if (confirmSubmit && onSubmit != null && state.review != null && !state.submitting) {
        AlertDialog(
            onDismissRequest = { confirmSubmit = false },
            title = { Text(tr(language, "Beschwerde einreichen?", "Подати скаргу?")) },
            text = { Text(tr(language,
                "Die Entscheidung und Frist werden vor dem Senden erneut geprüft.",
                "Перед надсиланням рішення та строк буде перевірено повторно.")) },
            confirmButton = {
                TextButton({ confirmSubmit = false; onSubmit(reason) }, Modifier.testTag("dsa-review-confirm")) {
                    Text(tr(language, "Einreichen", "Подати"))
                }
            },
            dismissButton = {
                TextButton({ confirmSubmit = false }) { Text(tr(language, "Abbrechen", "Скасувати")) }
            },
        )
    }
}

private fun dsaAppealReasonErrorText(error: DsaAppealTextFailure, language: String): String =
    when (error) {
        DsaAppealTextFailure.TOO_SHORT -> tr(language, "Mindestens 20 Zeichen erforderlich.", "Потрібно щонайменше 20 символів.")
        DsaAppealTextFailure.TOO_LONG -> tr(language, "Höchstens 5.000 Zeichen erlaubt.", "Дозволено щонайбільше 5 000 символів.")
        else -> tr(language, "Bitte den Text prüfen und erneut versuchen.", "Перевірте текст і спробуйте знову.")
    }

@Composable
private fun ReviewField(label: String, value: String, tag: String) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, style = MaterialTheme.typography.labelLarge)
            SelectionContainer { Text(value, Modifier.testTag(tag)) }
        }
    }
}

private fun reviewYesNo(value: Boolean, language: String) =
    if (value) tr(language, "Ja", "Так") else tr(language, "Nein", "Ні")

fun dsaAppealReviewErrorText(error: DsaAppealReviewFailure, language: String): String =
    when (error) {
        DsaAppealReviewFailure.ACCESS ->
            tr(
                language,
                "Für dieses Konto ist der Zugriff nicht freigegeben.",
                "Цьому обліковому запису доступ не надано.",
            )
        DsaAppealReviewFailure.MISSING ->
            tr(
                language,
                "Keine eigene Anfrage mit dieser Kennung gefunden.",
                "Власного звернення з цим ідентифікатором не знайдено.",
            )
        DsaAppealReviewFailure.INELIGIBLE ->
            tr(
                language,
                "Die Anfrage ist derzeit nicht für diese Vorbereitung verfügbar.",
                "Звернення зараз недоступне для цієї підготовки.",
            )
        DsaAppealReviewFailure.EXPIRED ->
            tr(
                language,
                "Die in der Entscheidung angegebene Beschwerdefrist ist abgelaufen.",
                "Зазначений у рішенні строк подання скарги минув.",
            )
        DsaAppealReviewFailure.OFFLINE ->
            tr(
                language,
                "Eine aktuelle Prüfung war nicht möglich. Verbindung prüfen und erneut versuchen.",
                "Не вдалося перевірити актуальні дані. Перевірте з’єднання та спробуйте знову.",
            )
        DsaAppealReviewFailure.STALE ->
            tr(
                language,
                "Die Entscheidung oder Auswahl hat sich geändert. Bitte erneut prüfen.",
                "Рішення або вибір змінилися. Перевірте знову.",
            )
        DsaAppealReviewFailure.UNCONFIRMED ->
            tr(
                language,
                "Die Antwort konnte nicht bestätigt werden. Bitte die Anfrage erneut laden, bevor du etwas wiederholst.",
                "Не вдалося підтвердити результат. Оновіть звернення, перш ніж повторювати дію.",
            )
        DsaAppealReviewFailure.INVALID,
        DsaAppealReviewFailure.UNKNOWN ->
            tr(
                language,
                "Die Entscheidung konnte nicht zuverlässig gelesen werden.",
                "Не вдалося надійно прочитати рішення.",
            )
    }
