package at.uac.android.feature.userstatusmanagement

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
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
import at.uac.android.feature.usermanagement.managedUsersDate
import at.uac.android.feature.usermanagement.managedUsersRoleLabel
import at.uac.android.feature.usermanagement.managedUsersStatusLabel

data class UserStatusActions(
    val request: (UserStatusAction) -> Unit = {},
    val editReason: (String) -> Unit = {},
    val chooseDays: (Int) -> Unit = {},
    val confirm: () -> Unit = {},
    val cancel: () -> Unit = {},
    val refresh: () -> Unit = {},
    val refreshPending: () -> Unit = {},
    val reconcile: (UserStatusPending) -> Unit = {},
    val dismissOutcome: () -> Unit = {},
)

val UserStatusDialogFontScale = SemanticsPropertyKey<Float>("UserStatusDialogFontScale")
val UserStatusDialogImeVisible = SemanticsPropertyKey<Boolean>("UserStatusDialogImeVisible")

/** The caller must provide a live presentation projection, never the unguarded StateFlow value. */
@Composable
fun UserStatusPanel(state: UserStatusState, language: String, actions: UserStatusActions) {
    if (state.session?.allowed != true) return
    Column(
        Modifier.fillMaxWidth().testTag("user-status-panel"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (state.busy || state.loading)
            LinearProgressIndicator(Modifier.fillMaxWidth().testTag("user-status-progress"))
        state.error
            ?.takeUnless { it == state.attemptOutcome?.failure }
            ?.let {
                Text(
                    userStatusFailureText(it, language),
                    Modifier.testTag("user-status-error"),
                    color = MaterialTheme.colorScheme.error,
                )
            }
        state.attemptOutcome?.let { outcome ->
            Card(Modifier.fillMaxWidth().testTag("user-status-attempt-outcome")) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        tr(language, "Ergebnis dieses Versuchs", "Результат цієї спроби"),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        outcome.targetId + " · " + userStatusTitle(outcome.action, language),
                        Modifier.testTag("user-status-outcome-target"),
                    )
                    outcome.observation?.let {
                        Text(
                            userStatusObservationText(it, language),
                            Modifier.testTag("user-status-observation"),
                        )
                    }
                    outcome.failure?.let {
                        Text(
                            userStatusFailureText(it, language),
                            Modifier.testTag("user-status-attempt-error"),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    TextButton(
                        actions.dismissOutcome,
                        Modifier.fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .testTag("user-status-outcome-dismiss"),
                    ) {
                        Text(tr(language, "Hinweis schließen", "Закрити повідомлення"))
                    }
                }
            }
        }
        if (!state.journalReady) {
            Text(
                tr(
                    language,
                    "Vor weiteren Änderungen muss der Wiederherstellungsstand bestätigt sein.",
                    "Перед наступними змінами потрібно перевірити записи відновлення.",
                )
            )
            OutlinedButton(
                actions.refreshPending,
                Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("user-status-journal"),
                enabled = !state.busy,
            ) {
                Text(tr(language, "Wiederherstellung prüfen", "Перевірити відновлення"))
            }
        }
        state.pending.forEachIndexed { index, entry ->
            Card(Modifier.fillMaxWidth().testTag("user-status-pending-$index")) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        tr(
                            language,
                            "Ergebnis noch nicht abschließend bestätigt",
                            "Результат ще не підтверджено остаточно",
                        ),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text("${entry.version.targetId} · ${userStatusTitle(entry.action, language)}")
                    Text(
                        tr(
                            language,
                            "Nicht erneut senden. Diese Prüfung liest nur den Serverstand; ein passender Status allein beweist nicht, dass dieser Versuch ausgeführt wurde.",
                            "Не надсилайте повторно. Перевірка лише читає стан сервера; відповідний статус сам по собі не доводить виконання цієї спроби.",
                        )
                    )
                    OutlinedButton(
                        { actions.reconcile(entry) },
                        Modifier.fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .testTag("user-status-reconcile-$index"),
                        enabled = !state.busy,
                    ) {
                        Text(tr(language, "Ergebnis prüfen", "Перевірити результат"))
                    }
                }
            }
        }
        if (state.targetId != null) {
            Text(
                tr(language, "Kontostatus verwalten", "Керування станом акаунта"),
                style = MaterialTheme.typography.titleLarge,
            )
            if (!state.fresh) {
                Text(
                    tr(
                        language,
                        "Änderungen sind bis zur frischen Zugriffs- und Statusprüfung gesperrt.",
                        "Зміни недоступні до нової перевірки доступу та стану.",
                    )
                )
                OutlinedButton(
                    actions.refresh,
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("user-status-refresh"),
                    enabled = !state.busy && !state.loading,
                ) {
                    Text(tr(language, "Aktuellen Status prüfen", "Перевірити актуальний стан"))
                }
            }
            state.snapshot
                ?.takeIf { state.fresh && it.version.targetId == state.targetId }
                ?.let { snapshot ->
                    Text(
                        tr(language, "Frisch geprüfter Status: ", "Щойно перевірений стан: ") +
                            managedUsersStatusLabel(snapshot.accountStatus, language),
                        Modifier.testTag("user-status-current"),
                    )
                    if (state.availableActions.isEmpty())
                        Text(
                            tr(
                                language,
                                "Für dieses Ziel sind keine Statusänderungen erlaubt.",
                                "Зміни стану цього акаунта не дозволені.",
                            ),
                            Modifier.testTag("user-status-read-only"),
                        )
                    state.availableActions.forEach { action ->
                        OutlinedButton(
                            { if (state.canAct) actions.request(action) },
                            Modifier.fillMaxWidth()
                                .heightIn(min = 48.dp)
                                .testTag("user-status-action-${action.name}"),
                            enabled = state.canAct,
                        ) {
                            Text(userStatusTitle(action, language))
                        }
                    }
                }
        }
    }
    if (
        state.confirmation != null &&
            state.snapshot != null &&
            state.fresh &&
            (state.canAct || state.busy) &&
            state.confirmation in state.availableActions
    )
        UserStatusConfirmation(state, language, actions)
}

@Composable
private fun UserStatusConfirmation(
    state: UserStatusState,
    language: String,
    actions: UserStatusActions,
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
            Column(
                Modifier.fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp)
                    .testTag("user-status-confirm-scroll")
                    .semantics {
                        this[UserStatusDialogFontScale] = density.fontScale
                        this[UserStatusDialogImeVisible] = imeVisible
                    },
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    userStatusTitle(action, language),
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(
                    tr(language, "Zielkonto: ", "Цільовий акаунт: ") + snapshot.version.targetId,
                    Modifier.testTag("user-status-target"),
                    style = MaterialTheme.typography.titleMedium,
                )
                snapshot.displayName?.let {
                    Text(
                        it,
                        Modifier.testTag("user-status-target-name"),
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
                snapshot.email?.let {
                    Text(it, Modifier.testTag("user-status-target-email"))
                }
                Text(managedUsersRoleLabel(snapshot.role, language))
                Text(
                    tr(language, "Kontostatus: ", "Стан акаунта: ") +
                        managedUsersStatusLabel(snapshot.accountStatus, language)
                )
                Text(
                    tr(language, "Zugriffsstatus: ", "Стан доступу: ") +
                        managedUsersStatusLabel(snapshot.blockState, language)
                )
                Text(tr(language, "Warnungen: ", "Попередження: ") + snapshot.warningCount)
                snapshot.statusReason
                    ?.takeIf { it.isNotEmpty() }
                    ?.let {
                        Text(
                            tr(language, "Bisherige Begründung: ", "Попередня причина: ") + it,
                            Modifier.testTag("user-status-previous-reason"),
                        )
                    }
                snapshot.banExpiresAt?.let {
                    Text(
                        tr(language, "Bisher eingeschränkt bis: ", "Попереднє обмеження до: ") +
                            managedUsersDate(it, language)
                    )
                }
                Text(userStatusEffect(action, language), Modifier.testTag("user-status-effect"))
                Text(
                    tr(
                        language,
                        "Zugriff und Rohdaten werden vor dem Senden erneut geprüft. Gleichzeitige Serveränderungen sind trotzdem möglich; es gibt keine automatische Wiederholung.",
                        "Перед надсиланням доступ і вихідні дані перевіряються знову. Одночасні зміни на сервері все одно можливі; автоматичного повторення немає.",
                    ),
                    Modifier.testTag("user-status-race-notice"),
                )
                if (action == UserStatusAction.SUSPEND) {
                    Text(
                        tr(language, "Dauer in Kalendertagen", "Тривалість у календарних днях"),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    FlowRow(
                        Modifier.fillMaxWidth().selectableGroup().testTag("user-status-days"),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        UserStatusContract.suspensionOptions.forEach { days ->
                            FilterChip(
                                selected = state.suspensionDays == days,
                                onClick = { if (!state.busy) actions.chooseDays(days) },
                                label = { Text(userStatusDays(days, language)) },
                                enabled = !state.busy,
                                modifier =
                                    Modifier.heightIn(min = 48.dp)
                                        .testTag("user-status-days-$days"),
                            )
                        }
                    }
                    Text(tr(language, "Zeitzone: ", "Часовий пояс: ") + state.suspensionZoneId.id)
                    Text(
                        tr(
                            language,
                            "Sommer- und Winterzeit werden berücksichtigt. Ein Kalendertag ist nicht immer 24 Stunden; der Zeitraum beginnt beim Absenden.",
                            "Перехід на літній і зимовий час враховується. Календарний день не завжди має 24 години; відлік починається під час надсилання.",
                        ),
                        Modifier.testTag("user-status-calendar-notice"),
                    )
                }
                OutlinedTextField(
                    state.reason,
                    actions.editReason,
                    Modifier.fillMaxWidth()
                        .focusProperties { canFocus = !state.busy }
                        .testTag("user-status-reason"),
                    enabled = !state.busy,
                    isError = state.reasonRejected,
                    minLines = 3,
                    maxLines = 8,
                    label = {
                        Text(tr(language, "Begründung (erforderlich)", "Причина (обов’язково)"))
                    },
                )
                if (state.reasonRejected)
                    Text(
                        tr(
                            language,
                            "Die eingefügte Begründung ist zu lang (höchstens ${UserStatusState.MAX_REASON_CHARACTERS} Zeichen). Der bisherige Text wurde nicht ersetzt. Kürzen oder bearbeiten Sie ihn vor dem Bestätigen.",
                            "Вставлена причина задовга (щонайбільше ${UserStatusState.MAX_REASON_CHARACTERS} символів). Попередній текст не замінено. Скоротіть або відредагуйте його перед підтвердженням.",
                        ),
                        Modifier.testTag("user-status-reason-rejected"),
                        color = MaterialTheme.colorScheme.error,
                    )
                if (!state.canConfirm && !state.busy && !state.reasonRejected)
                    Text(
                        tr(
                            language,
                            "Eine gültige, nicht leere Begründung innerhalb des sicheren Anfrage-Limits ist erforderlich.",
                            "Потрібна коректна непорожня причина в межах безпечного розміру запиту.",
                        ),
                        Modifier.testTag("user-status-required"),
                    )
                Text(
                    tr(
                        language,
                        "Die Begründung wird protokolliert und dem betroffenen Konto mitgeteilt.",
                        "Причину буде записано в журнал і повідомлено відповідному акаунту.",
                    )
                )
                if (state.busy) {
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                    Text(
                        tr(
                            language,
                            "Die gesendete Änderung wird abgeschlossen. Nicht erneut senden.",
                            "Надіслана зміна завершується. Не надсилайте повторно.",
                        )
                    )
                }
                Button(
                    { if (state.canConfirm) actions.confirm() },
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("user-status-confirm"),
                    enabled = state.canConfirm,
                ) {
                    Text(userStatusTitle(action, language))
                }
                TextButton(
                    { if (!state.busy) actions.cancel() },
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("user-status-cancel"),
                    enabled = !state.busy,
                ) {
                    Text(tr(language, "Abbrechen", "Скасувати"))
                }
            }
        }
    }
}

fun userStatusTitle(action: UserStatusAction, language: String) =
    when (action) {
        UserStatusAction.WARN -> tr(language, "Verwarnung aussprechen", "Видати попередження")
        UserStatusAction.SUSPEND -> tr(language, "Vorübergehend sperren", "Тимчасово обмежити")
        UserStatusAction.BAN -> tr(language, "Dauerhaft sperren", "Заблокувати назавжди")
        UserStatusAction.DEACTIVATE -> tr(language, "Konto deaktivieren", "Деактивувати акаунт")
        UserStatusAction.RESTORE -> tr(language, "Zugang wiederherstellen", "Відновити доступ")
    }

fun userStatusDays(days: Int, language: String) =
    tr(
        language,
        if (days == 1) "1 Tag" else "$days Tage",
        if (days == 1) "1 день" else "$days днів",
    )

fun userStatusEffect(action: UserStatusAction, language: String) =
    when (action) {
        UserStatusAction.WARN ->
            tr(
                language,
                "Eine Verwarnung erhält den Zugang. Sie hebt auch eine vorhandene Sperre und deren Ablaufdatum auf – selbst wenn die Sperre erst nach dieser Vorschau gesetzt wurde. Der Warnungszähler steigt um eins.",
                "Попередження зберігає доступ. Воно також знімає наявне обмеження та його строк — навіть якщо обмеження з’явилося після цього перегляду. Лічильник попереджень збільшується на один.",
            )
        UserStatusAction.SUSPEND ->
            tr(
                language,
                "Der Zugang wird befristet gesperrt. Der Server veranlasst den Widerruf aktiver Sitzungen; bestehende Inhalte bleiben erhalten.",
                "Доступ буде тимчасово обмежено. Сервер ініціює відкликання активних сеансів; наявний контент залишиться.",
            )
        UserStatusAction.BAN ->
            tr(
                language,
                "Der Zugang wird unbefristet gesperrt. Der Server veranlasst den Widerruf aktiver Sitzungen; bestehende Inhalte bleiben erhalten.",
                "Доступ буде заблоковано безстроково. Сервер ініціює відкликання активних сеансів; наявний контент залишиться.",
            )
        UserStatusAction.DEACTIVATE ->
            tr(
                language,
                "Der Zugang wird deaktiviert. Der Server veranlasst den Widerruf aktiver Sitzungen. Profil und Urheberschaft bestehender Inhalte bleiben erhalten.",
                "Доступ буде деактивовано. Сервер ініціює відкликання активних сеансів. Профіль та авторство наявного контенту залишаться.",
            )
        UserStatusAction.RESTORE ->
            tr(
                language,
                "Die Kontobeschränkung und ihr Ablaufdatum werden entfernt. Der Zugang kann nach den weiterhin geltenden Anmeldeprüfungen wiederhergestellt werden.",
                "Обмеження акаунта та його строк буде знято. Доступ можна буде відновити після чинних перевірок входу.",
            )
    }

fun userStatusFailureText(failure: UserStatusFailure, language: String) =
    when (failure) {
        UserStatusFailure.ACCESS ->
            tr(
                language,
                "Aktueller Verwaltungszugriff und vollständig bestätigte TOTP-Anmeldung sind erforderlich.",
                "Потрібен чинний адміністративний доступ і повністю підтверджений вхід із TOTP.",
            )
        UserStatusFailure.STALE ->
            tr(
                language,
                "Ziel, Zugriff oder Rohdaten haben sich geändert. Bitte den aktuellen Status erneut lesen.",
                "Акаунт, доступ або вихідні дані змінилися. Прочитайте актуальний стан знову.",
            )
        UserStatusFailure.INVALID ->
            tr(
                language,
                "Diese Daten oder Eingaben erlauben keine sichere Statusänderung. Es wurde kein Erfolg bestätigt.",
                "Ці дані або введені значення не дозволяють безпечної зміни стану. Успіх не підтверджено.",
            )
        UserStatusFailure.JOURNAL ->
            tr(
                language,
                "Der Wiederherstellungsbeleg ist nicht bestätigt. Nicht erneut senden; vorhandene Einträge prüfen.",
                "Запис відновлення не підтверджено. Не надсилайте повторно; перевірте наявні записи.",
            )
        UserStatusFailure.OFFLINE ->
            tr(
                language,
                "Der Serverstand konnte nicht bestätigt werden. Eine ausstehende Änderung wird nicht erneut gesendet.",
                "Стан сервера не підтверджено. Непідтверджена зміна не надсилатиметься повторно.",
            )
        UserStatusFailure.PENDING,
        UserStatusFailure.UNCONFIRMED ->
            tr(
                language,
                "Die Änderung ist noch nicht abschließend bestätigt. Nicht erneut senden; nur das Ergebnis prüfen.",
                "Зміна ще не підтверджена остаточно. Не надсилайте повторно; перевірте лише результат.",
            )
    }

fun userStatusObservationText(value: UserStatusObservation, language: String) =
    when (value) {
        UserStatusObservation.CONFIRMED_CURRENT ->
            tr(
                language,
                "Änderung bestätigt und aktueller Status geprüft.",
                "Зміну підтверджено, поточний стан перевірено.",
            )
        UserStatusObservation.CONFIRMED_CHANGED ->
            tr(
                language,
                "Änderung bestätigt; der Serverstand hat sich inzwischen geändert. Bitte erneut lesen.",
                "Зміну підтверджено; стан сервера вже змінився. Прочитайте його знову.",
            )
        UserStatusObservation.CONFIRMED_UNAVAILABLE ->
            tr(
                language,
                "Ausführung bestätigt, aktueller Status nicht verfügbar. Der Beleg bleibt für eine reine Leseprüfung erhalten.",
                "Виконання підтверджено, поточний стан недоступний. Запис збережено для перевірки лише читанням.",
            )
        UserStatusObservation.OBSERVED_WITHOUT_RECEIPT ->
            tr(
                language,
                "Passender Status sichtbar, aber kein eindeutiger Beleg für diesen Versuch. Nicht erneut senden.",
                "Відповідний стан видно, але однозначного підтвердження цієї спроби немає. Не надсилайте повторно.",
            )
        UserStatusObservation.UNCONFIRMED,
        UserStatusObservation.UNAVAILABLE ->
            tr(
                language,
                "Keine eindeutige Bestätigung verfügbar. Wiederholung bleibt gesperrt; nur den Serverstand prüfen.",
                "Однозначне підтвердження недоступне. Повторення заблоковано; перевірте лише стан сервера.",
            )
    }
