package at.uac.android.feature.organizationreview

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsPropertyKey
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import at.uac.android.core.ProtectedDialog
import at.uac.android.feature.browse.tr

data class OrganizationReviewActions(
    val request: (OrganizationReviewAction) -> Unit = {},
    val editText: (String) -> Unit = {},
    val confirm: () -> Unit = {},
    val cancel: () -> Unit = {},
    val refresh: () -> Unit = {},
    val refreshPending: () -> Unit = {},
    val reconcile: (OrganizationReviewPending) -> Unit = {},
)

val OrganizationReviewDialogFontScale =
    SemanticsPropertyKey<Float>("OrganizationReviewDialogFontScale")
val OrganizationReviewDialogImeVisible =
    SemanticsPropertyKey<Boolean>("OrganizationReviewDialogImeVisible")

/** Inline private queue/preview panel. Pending entries remain available with no selected target. */
@Composable
fun OrganizationReviewPanel(
    state: OrganizationReviewState,
    language: String,
    actions: OrganizationReviewActions,
) {
    if (state.session?.allowed != true) return
    Column(
        Modifier.fillMaxWidth().testTag("organization-review-actions"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (state.busy || state.loading)
            LinearProgressIndicator(Modifier.fillMaxWidth().testTag("organization-review-progress"))
        state.error?.let {
            Text(
                organizationReviewFailureText(it, language),
                Modifier.testTag("organization-review-error"),
                color = MaterialTheme.colorScheme.error,
            )
        }
        state.observation?.let {
            Text(
                state.observationTargetId.orEmpty().let { id ->
                    if (id.isEmpty()) "" else "$id · "
                } + organizationReviewObservationText(it, language),
                Modifier.testTag("organization-review-observation"),
            )
        }
        if (!state.journalReady)
            OutlinedButton(
                actions.refreshPending,
                enabled = !state.busy,
                modifier = Modifier.testTag("organization-review-journal"),
            ) {
                Text(tr(language, "Wiederherstellung prüfen", "Перевірити відновлення"))
            }
        state.pending.forEachIndexed { index, entry ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        tr(
                            language,
                            "Noch nicht abschließend bestätigt",
                            "Рішення ще не підтверджене остаточно",
                        ),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        "${entry.version.organizationId} · ${organizationReviewTitle(entry.action, language)}"
                    )
                    Text(
                        tr(
                            language,
                            "Nicht erneut senden. Die Prüfung liest nur den bestehenden Serverstand.",
                            "Не надсилайте повторно. Перевірка лише читає поточний стан на сервері.",
                        )
                    )
                    OutlinedButton(
                        { actions.reconcile(entry) },
                        enabled = !state.busy,
                        modifier = Modifier.testTag("organization-review-reconcile-$index"),
                    ) {
                        Text(tr(language, "Ergebnis prüfen", "Перевірити результат"))
                    }
                }
            }
        }
        if (state.snapshot != null) {
            if (!state.fresh)
                OutlinedButton(
                    actions.refresh,
                    enabled = !state.busy && !state.loading,
                    modifier = Modifier.testTag("organization-review-refresh"),
                ) {
                    Text(tr(language, "Aktuellen Zugriff prüfen", "Перевірити актуальний доступ"))
                }
            OrganizationReviewAction.entries.forEach { action ->
                OutlinedButton(
                    { if (state.canAct) actions.request(action) },
                    Modifier.fillMaxWidth()
                        .testTag("organization-review-${action.name.lowercase()}"),
                    enabled = state.canAct,
                ) {
                    Text(organizationReviewTitle(action, language))
                }
            }
        }
    }
    if (state.confirmation != null && state.snapshot != null && (state.canAct || state.busy))
        OrganizationReviewConfirmation(state, language, actions)
}

@Composable
private fun OrganizationReviewConfirmation(
    state: OrganizationReviewState,
    language: String,
    actions: OrganizationReviewActions,
) {
    val action = state.confirmation ?: return
    val snapshot = state.snapshot ?: return
    ProtectedDialog(
        onDismissRequest = { if (!state.busy) actions.cancel() },
        properties =
            DialogProperties(
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
                dismissOnBackPress = !state.busy,
                dismissOnClickOutside = false,
            ),
    ) {
        val focus = LocalFocusManager.current
        val keyboard = LocalSoftwareKeyboardController.current
        val density = LocalDensity.current
        val imeVisible = WindowInsets.ime.getBottom(density) > 0
        LaunchedEffect(state.busy) {
            if (state.busy) {
                focus.clearFocus(force = true)
                keyboard?.hide()
            }
        }
        Surface(Modifier.fillMaxSize().safeDrawingPadding().imePadding()) {
            // Whole content scrolls; neither a large title nor the IME can consume a fixed footer.
            Column(
                Modifier.fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp)
                    .testTag("organization-review-confirm-scroll")
                    .semantics {
                        this[OrganizationReviewDialogFontScale] = density.fontScale
                        this[OrganizationReviewDialogImeVisible] = imeVisible
                    },
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    organizationReviewTitle(action, language),
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(snapshot.name, style = MaterialTheme.typography.titleLarge)
                Text(snapshot.version.organizationId)
                Text(
                    tr(language, "Antragsteller-ID: ", "ID заявника: ") + snapshot.submitterId,
                    Modifier.testTag("organization-review-submitter"),
                )
                Text(
                    tr(language, "Aktueller Status: ", "Поточний статус: ") +
                        when (snapshot.status) {
                            "pendingReview" -> tr(language, "In Prüfung", "На розгляді")
                            "needsRevision" ->
                                tr(language, "Ergänzung erforderlich", "Потрібне доповнення")
                            "rejected" -> tr(language, "Abgelehnt", "Відхилено")
                            else -> tr(language, "Nicht verfügbar", "Недоступний")
                        }
                )
                if (action == OrganizationReviewAction.APPROVE)
                    Text(
                        tr(
                            language,
                            "Bei Freigabe wird der Antragsteller zum Eigentümer der Organisation. Eine Benachrichtigung ist nur für ein vorhandenes, berechtigtes Empfängerkonto möglich.",
                            "Після схвалення заявник стане власником організації. Сповіщення можливе лише для наявного облікового запису одержувача з відповідним доступом.",
                        ),
                        Modifier.testTag("organization-review-owner-effect"),
                    )
                Text(
                    tr(
                        language,
                        "Der Zugriff und die Vorschau werden vor dem Senden erneut geprüft. Gleichzeitige Änderungen auf dem Server können dennoch auftreten. Es wird nichts automatisch erneut gesendet.",
                        "Перед надсиланням доступ і перегляд буде перевірено знову. Одночасні зміни на сервері все одно можливі. Автоматичного повторного надсилання немає.",
                    )
                )
                if (action.textField != null) {
                    OutlinedTextField(
                        state.text,
                        actions.editText,
                        Modifier.fillMaxWidth()
                            .focusProperties { canFocus = !state.busy }
                            .testTag("organization-review-text"),
                        enabled = !state.busy,
                        minLines = 3,
                        maxLines = 8,
                        label = {
                            Text(
                                if (action == OrganizationReviewAction.REQUEST_REVISION)
                                    tr(
                                        language,
                                        "Was muss ergänzt werden?",
                                        "Що потрібно доповнити?",
                                    )
                                else tr(language, "Grund der Ablehnung", "Причина відмови")
                            )
                        },
                    )
                    if (!state.canConfirm && !state.busy)
                        Text(
                            tr(
                                language,
                                "Eine nicht leere Nachricht innerhalb des sicheren Anfrage-Limits ist erforderlich.",
                                "Потрібне непорожнє повідомлення в межах безпечного розміру запиту.",
                            ),
                            Modifier.testTag("organization-review-required"),
                        )
                }
                if (state.busy) {
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                    Text(
                        tr(
                            language,
                            "Die gesendete Entscheidung wird abgeschlossen. Bitte nicht erneut senden.",
                            "Надіслане рішення завершується. Не надсилайте його повторно.",
                        )
                    )
                }
                Button(
                    { if (state.canConfirm) actions.confirm() },
                    Modifier.fillMaxWidth().testTag("organization-review-confirm"),
                    enabled = state.canConfirm,
                ) {
                    Text(organizationReviewTitle(action, language))
                }
                TextButton(
                    { if (!state.busy) actions.cancel() },
                    Modifier.fillMaxWidth().testTag("organization-review-cancel"),
                    enabled = !state.busy,
                ) {
                    Text(tr(language, "Abbrechen", "Скасувати"))
                }
            }
        }
    }
}

fun organizationReviewTitle(action: OrganizationReviewAction, language: String) =
    when (action) {
        OrganizationReviewAction.APPROVE ->
            tr(language, "Organisation freigeben", "Схвалити організацію")
        OrganizationReviewAction.REQUEST_REVISION ->
            tr(language, "Ergänzung anfordern", "Запросити доповнення")
        OrganizationReviewAction.REJECT -> tr(language, "Antrag ablehnen", "Відхилити заявку")
    }

fun organizationReviewFailureText(error: OrganizationReviewFailure, language: String) =
    when (error) {
        OrganizationReviewFailure.ACCESS ->
            tr(
                language,
                "Aktueller Verwaltungszugriff mit vollständig bestätigter Anmeldung ist erforderlich.",
                "Потрібен чинний адміністративний доступ із повністю підтвердженим входом.",
            )
        OrganizationReviewFailure.STALE ->
            tr(
                language,
                "Die Vorschau wurde geändert. Bitte die aktuelle Anfrage erneut öffnen und lesen.",
                "Перегляд змінився. Відкрийте й прочитайте актуальну заявку знову.",
            )
        OrganizationReviewFailure.INVALID ->
            tr(
                language,
                "Diese Anfrage kann nicht sicher verarbeitet werden und bleibt schreibgeschützt.",
                "Безпечна обробка цієї заявки недоступна. Доступний лише перегляд.",
            )
        OrganizationReviewFailure.JOURNAL ->
            tr(
                language,
                "Der lokale Wiederherstellungsbeleg konnte nicht bestätigt werden. Nicht erneut senden; den vorhandenen Stand prüfen.",
                "Локальний запис відновлення не вдалося підтвердити. Не надсилайте повторно; перевірте наявний стан.",
            )
        OrganizationReviewFailure.OFFLINE ->
            tr(
                language,
                "Server nicht erreichbar. Ein ausstehender Vorgang wird nicht erneut gesendet.",
                "Сервер недоступний. Непідтверджена операція не надсилатиметься повторно.",
            )
        else ->
            tr(
                language,
                "Das Ergebnis ist noch nicht sicher bestätigt. Nicht erneut senden; nur den vorhandenen Stand prüfen.",
                "Результат ще не підтверджено. Не надсилайте повторно; перевірте лише наявний стан.",
            )
    }

fun organizationReviewObservationText(value: OrganizationReviewObservation, language: String) =
    when (value) {
        OrganizationReviewObservation.CONFIRMED_CURRENT ->
            tr(
                language,
                "Entscheidung bestätigt und aktueller Stand geprüft.",
                "Рішення підтверджено, поточний стан перевірено.",
            )
        OrganizationReviewObservation.CONFIRMED_CHANGED ->
            tr(
                language,
                "Entscheidung ausgeführt; die Anfrage hat sich inzwischen geändert. Bitte erneut prüfen.",
                "Рішення виконано; заявка вже змінилася. Перегляньте її знову.",
            )
        OrganizationReviewObservation.CONFIRMED_UNAVAILABLE ->
            tr(
                language,
                "Entscheidung bestätigt; die Anfrage ist jetzt nicht verfügbar.",
                "Рішення підтверджено; заявка зараз недоступна.",
            )
        OrganizationReviewObservation.OBSERVED_WITHOUT_RECEIPT ->
            tr(
                language,
                "Der passende Serverstand ist sichtbar, aber dieser Versuch hat keinen eindeutigen Beleg. Nicht erneut senden.",
                "На сервері видно відповідний стан, але ця спроба не має однозначного підтвердження. Не надсилайте повторно.",
            )
        else ->
            tr(
                language,
                "Keine eindeutige Bestätigung verfügbar. Die ausstehende Entscheidung bleibt gesperrt.",
                "Однозначного підтвердження немає. Повторне надсилання рішення залишається заблокованим.",
            )
    }
