package at.uac.android.feature.moderation

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.feature.browse.tr

data class ModerationDecisionActions(
    val request: (ModerationDecision) -> Unit = {},
    val confirm: () -> Unit = {},
    val cancel: () -> Unit = {},
    val reconcile: (ModerationPending) -> Unit = {},
    val refreshJournal: () -> Unit = {},
)

/** Inline in the private preview's LazyColumn: no nested scroll or additional Dialog window. */
@Composable
fun ModerationDecisionPanel(
    state: ModerationDecisionState,
    version: ModerationReviewVersion?,
    language: String,
    actions: ModerationDecisionActions,
) {
    if (state.session?.allowed != true) return
    Column(
        Modifier.fillMaxWidth().testTag("moderation-decisions"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (state.busy) {
            LinearProgressIndicator(Modifier.fillMaxWidth().testTag("moderation-decision-busy"))
            Text(
                tr(
                    language,
                    "Die Prüfung läuft. Ein bereits gesendeter Vorgang wird auch beim Verlassen sicher abgeschlossen.",
                    "Триває перевірка. Уже надіслана операція дочекається завершення, навіть якщо ви вийдете з екрана.",
                )
            )
        }
        state.error?.let {
            Text(
                decisionFailureText(it, language),
                Modifier.testTag("moderation-decision-error"),
                color = MaterialTheme.colorScheme.error,
            )
        }
        state.observation?.let {
            Text(observationText(it, language), Modifier.testTag("moderation-decision-observation"))
        }
        if (!state.journalReady && !state.busy)
            OutlinedButton(actions.refreshJournal, Modifier.testTag("moderation-journal-retry")) {
                Text(tr(language, "Wiederherstellung prüfen", "Перевірити відновлення"))
            }
        state.pending.forEachIndexed { index, pending ->
            Card(Modifier.fillMaxWidth().testTag("moderation-pending-$index")) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        tr(
                            language,
                            "Nicht abschließend bestätigte Entscheidung",
                            "Рішення ще не підтверджене остаточно",
                        ),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        "${if (pending.version.target.kind == ModerationKind.NEWS) tr(language, "Nachricht", "Новина") else tr(language, "Veranstaltung", "Подія")} · ${decisionTitle(pending.decision, language)}"
                    )
                    Text(
                        tr(
                            language,
                            "Nicht erneut senden. Nur das vorhandene Ergebnis wird vom Server gelesen.",
                            "Не надсилайте повторно. Буде прочитано лише наявний результат на сервері.",
                        )
                    )
                    OutlinedButton(
                        { actions.reconcile(pending) },
                        enabled = !state.busy,
                        modifier = Modifier.testTag("moderation-reconcile-$index"),
                    ) {
                        Text(tr(language, "Ergebnis prüfen", "Перевірити результат"))
                    }
                }
            }
        }
        val canDecide =
            version != null &&
                version.target.kind in setOf(ModerationKind.NEWS, ModerationKind.EVENT) &&
                state.journalReady &&
                !state.busy &&
                state.pending.none { it.version.target == version.target }
        if (canDecide) {
            state.confirmation?.let { decision ->
                Card(Modifier.fillMaxWidth().testTag("moderation-decision-confirmation")) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(
                            tr(
                                language,
                                "Diese vollständig gelesene Version ${if (decision == ModerationDecision.APPROVE) "freigeben" else "ablehnen"}? Änderungen seit der Vorschau verhindern die Entscheidung.",
                                "${if (decision == ModerationDecision.APPROVE) "Схвалити" else "Відхилити"} саме цю повністю прочитану версію? Зміни після перегляду заблокують рішення.",
                            )
                        )
                        Button(
                            actions.confirm,
                            Modifier.fillMaxWidth().testTag("moderation-decision-confirm"),
                        ) {
                            Text(decisionTitle(decision, language))
                        }
                        TextButton(actions.cancel, Modifier.testTag("moderation-decision-cancel")) {
                            Text(tr(language, "Abbrechen", "Скасувати"))
                        }
                    }
                }
            }
                ?: run {
                    Button(
                        { actions.request(ModerationDecision.APPROVE) },
                        Modifier.fillMaxWidth().testTag("moderation-approve"),
                    ) {
                        Text(decisionTitle(ModerationDecision.APPROVE, language))
                    }
                    OutlinedButton(
                        { actions.request(ModerationDecision.REJECT) },
                        Modifier.fillMaxWidth().testTag("moderation-reject"),
                    ) {
                        Text(decisionTitle(ModerationDecision.REJECT, language))
                    }
                }
        }
    }
}

private fun decisionTitle(value: ModerationDecision, language: String) =
    when (value) {
        ModerationDecision.APPROVE -> tr(language, "Freigeben", "Схвалити")
        ModerationDecision.REJECT -> tr(language, "Ablehnen", "Відхилити")
    }

private fun decisionFailureText(value: ModerationDecisionFailure, language: String) =
    when (value) {
        ModerationDecisionFailure.JOURNAL ->
            tr(
                language,
                "Die lokale Wiederherstellung ist nicht sicher lesbar. Es wird keine neue Entscheidung gesendet.",
                "Локальне відновлення недоступне. Нові рішення не надсилатимуться.",
            )
        ModerationDecisionFailure.STALE ->
            tr(
                language,
                "Inhalt oder Vorschau wurde geändert. Bitte neu lesen und bestätigen.",
                "Матеріал або перегляд змінився. Прочитайте актуальну версію та підтвердьте її знову.",
            )
        ModerationDecisionFailure.ACCESS ->
            tr(
                language,
                "Aktueller Zugriff mit vollständiger Anmeldung ist erforderlich.",
                "Потрібен чинний доступ і повністю завершений вхід.",
            )
        ModerationDecisionFailure.INVALID ->
            tr(
                language,
                "Diese Version kann nicht sicher entschieden werden. Die Vorschau bleibt schreibgeschützt.",
                "Для цієї версії безпечне рішення недоступне. Перегляд залишається без змін.",
            )
        ModerationDecisionFailure.OFFLINE ->
            tr(
                language,
                "Server nicht erreichbar. Bitte später den Zugriff prüfen.",
                "Сервер недоступний. Перевірте доступ пізніше.",
            )
        ModerationDecisionFailure.CONFLICT ->
            tr(
                language,
                "Der Beleg stimmt nicht überein. Nicht erneut senden.",
                "Запис підтвердження не збігається. Не надсилайте рішення повторно.",
            )
        else ->
            tr(
                language,
                "Das Ergebnis ist noch nicht bestätigt. Nur das Ergebnis prüfen, nicht erneut senden.",
                "Результат ще не підтверджений. Перевірте його, не надсилаючи рішення повторно.",
            )
    }

private fun observationText(value: ModerationObservation, language: String) =
    when (value) {
        ModerationObservation.CONFIRMED_CURRENT ->
            tr(
                language,
                "Entscheidung und aktueller Inhalt wurden bestätigt.",
                "Рішення та актуальний стан матеріалу підтверджено.",
            )
        ModerationObservation.CONFIRMED_CHANGED ->
            tr(
                language,
                "Die Entscheidung wurde bestätigt. Der Inhalt wurde danach geändert; bitte die neue Vorschau lesen.",
                "Рішення підтверджено. Матеріал після цього змінився; прочитайте актуальний перегляд.",
            )
        ModerationObservation.CONFIRMED_UNAVAILABLE ->
            tr(
                language,
                "Die Entscheidung wurde bestätigt; der Inhalt ist inzwischen nicht mehr verfügbar.",
                "Рішення підтверджено; матеріал більше недоступний.",
            )
        ModerationObservation.OBSERVED_WITHOUT_RECEIPT ->
            tr(
                language,
                "Der gewünschte Zustand ist sichtbar, aber der Beleg fehlt. Der eigene Vorgang bleibt ungeklärt und wird nicht wiederholt.",
                "Потрібний стан видно, але підтвердження операції відсутнє. Її результат залишається невизначеним, повторного надсилання не буде.",
            )
        ModerationObservation.AUTHORITY_LIMITED ->
            tr(
                language,
                "Ihre aktuelle Rolle kann diesen Beleg nicht lesen. Der Vorgang bleibt erhalten; kein erneutes Senden.",
                "Поточна роль не має доступу до цього підтвердження. Операцію збережено; повторного надсилання не буде.",
            )
        ModerationObservation.CONFLICT ->
            decisionFailureText(ModerationDecisionFailure.CONFLICT, language)
        ModerationObservation.UNCONFIRMED ->
            decisionFailureText(ModerationDecisionFailure.UNCONFIRMED, language)
    }
