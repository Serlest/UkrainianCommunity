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
    DsaAppealReviewScreen(snapshot, reportId, language, Instant.now(), model::refresh, onAccount)
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
) {
    val ready = snapshot.session?.ready == true
    val state =
        if (snapshot.visible && snapshot.reportId == reportId && ready)
            snapshot.forSession(snapshot.session, now)
        else DsaAppealReviewState(session = snapshot.session, loading = ready)
    LazyColumn(
        Modifier.testTag("dsa-review-list"),
        contentPadding = PaddingValues(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(
                tr(
                    language,
                    "Entscheidung vor einer Beschwerde prüfen",
                    "Перевірка рішення перед скаргою",
                ),
                style = MaterialTheme.typography.headlineSmall,
            )
        }
        item {
            Text(
                tr(
                    language,
                    "Nur Ansicht. Das Einreichen einer Beschwerde ist in dieser lokalen Android-Version noch nicht verfügbar. Es wird nichts gesendet.",
                    "Лише перегляд. Подання скарги в цій локальній версії Android ще недоступне. Нічого не надсилається.",
                ),
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
                            it.snapshot.reporterUid == state.session?.uid
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
                                    "Dies ist eine aktuelle Lesekopie, keine Reservierung oder Bestätigung einer Einreichung. Vor einer späteren Aktion muss erneut geprüft werden.",
                                    "Це поточна копія для перегляду, а не резервування чи підтвердження подання. Перед подальшою дією потрібна повторна перевірка.",
                                ),
                                Modifier.testTag("dsa-review-not-receipt"),
                            )
                        }
                    }
                item {
                    OutlinedButton(onRefresh, Modifier.testTag("dsa-review-refresh")) {
                        Text(tr(language, "Erneut prüfen", "Перевірити знову"))
                    }
                }
            }
        }
    }
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
        DsaAppealReviewFailure.INVALID,
        DsaAppealReviewFailure.UNKNOWN ->
            tr(
                language,
                "Die Entscheidung konnte nicht zuverlässig gelesen werden.",
                "Не вдалося надійно прочитати рішення.",
            )
    }
