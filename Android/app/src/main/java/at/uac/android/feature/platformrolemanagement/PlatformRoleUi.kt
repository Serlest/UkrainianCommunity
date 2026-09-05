package at.uac.android.feature.platformrolemanagement

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
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
import at.uac.android.feature.usermanagement.managedUsersRoleLabel

data class PlatformRoleActions(
    val request: (PlatformRoleAction) -> Unit = {},
    val editReason: (String) -> Unit = {},
    val confirm: () -> Unit = {},
    val cancel: () -> Unit = {},
    val refresh: () -> Unit = {},
    val refreshPending: () -> Unit = {},
    val reconcile: (PlatformRolePending) -> Unit = {},
    val dismissOutcome: () -> Unit = {},
)

val PlatformRoleDialogFontScale = SemanticsPropertyKey<Float>("PlatformRoleDialogFontScale")
val PlatformRoleDialogImeVisible = SemanticsPropertyKey<Boolean>("PlatformRoleDialogImeVisible")

/** The caller must provide a live presentation projection, never the unguarded StateFlow value. */
@Composable
fun PlatformRolePanel(state: PlatformRoleState, language: String, actions: PlatformRoleActions) {
    if (state.session?.ready != true || state.session.role != "owner") return
    Column(
        Modifier.fillMaxWidth().testTag("platform-role-panel"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (state.busy || state.loading)
            LinearProgressIndicator(Modifier.fillMaxWidth().testTag("platform-role-progress"))
        state.error
            ?.takeUnless { it == state.attemptOutcome?.failure }
            ?.let {
                Text(
                    platformRoleFailureText(it, language),
                    Modifier.testTag("platform-role-error"),
                    color = MaterialTheme.colorScheme.error,
                )
            }
        state.attemptOutcome?.let { outcome ->
            Card(Modifier.fillMaxWidth().testTag("platform-role-attempt-outcome")) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        tr(language, "Ergebnis dieses Versuchs", "Результат цієї спроби"),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        outcome.targetId + " · " + platformRoleTitle(outcome.action, language),
                        Modifier.testTag("platform-role-outcome-target"),
                    )
                    outcome.observation?.let {
                        Text(
                            platformRoleObservationText(it, language),
                            Modifier.testTag("platform-role-observation"),
                        )
                    }
                    outcome.failure?.let {
                        Text(
                            platformRoleFailureText(it, language),
                            Modifier.testTag("platform-role-attempt-error"),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    TextButton(
                        actions.dismissOutcome,
                        Modifier.fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .testTag("platform-role-outcome-dismiss"),
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
                Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("platform-role-journal"),
                enabled = !state.busy,
            ) {
                Text(tr(language, "Wiederherstellung prüfen", "Перевірити відновлення"))
            }
        }
        state.pending.forEachIndexed { index, entry ->
            Card(Modifier.fillMaxWidth().testTag("platform-role-pending-$index")) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        tr(
                            language,
                            "Ergebnis noch nicht abschließend bestätigt",
                            "Результат ще не підтверджено остаточно",
                        ),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text("${entry.version.targetId} · ${platformRoleTitle(entry.action, language)}")
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
                            .testTag("platform-role-reconcile-$index"),
                        enabled = !state.busy,
                    ) {
                        Text(tr(language, "Ergebnis prüfen", "Перевірити результат"))
                    }
                }
            }
        }
        if (state.targetId != null) {
            Text(
                tr(language, "Plattformrolle verwalten", "Керування роллю на платформі"),
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
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("platform-role-refresh"),
                    enabled = !state.busy && !state.loading,
                ) {
                    Text(tr(language, "Aktuellen Status prüfen", "Перевірити актуальний стан"))
                }
            }
            state.snapshot
                ?.takeIf { state.fresh && it.version.targetId == state.targetId }
                ?.let { snapshot ->
                    Text(
                        tr(language, "Frisch geprüfte Rolle: ", "Щойно перевірена роль: ") +
                            managedUsersRoleLabel(snapshot.target.role, language),
                        Modifier.testTag("platform-role-current"),
                    )
                    if (state.availableActions.isEmpty())
                        Text(
                            tr(
                                language,
                                "Für dieses Ziel ist keine Änderung der Plattformrolle erlaubt.",
                                "Зміна ролі цього акаунта на платформі не дозволена.",
                            ),
                            Modifier.testTag("platform-role-read-only"),
                        )
                    platformRoleAssignmentIssue(state, language)?.let { issue ->
                        Text(
                            issue,
                            Modifier.testTag("platform-role-eligibility"),
                            color = MaterialTheme.colorScheme.error,
                        )
                        OutlinedButton(
                            actions.refresh,
                            Modifier.fillMaxWidth()
                                .heightIn(min = 48.dp)
                                .testTag("platform-role-metadata-refresh"),
                            enabled = !state.busy && !state.loading,
                        ) {
                            Text(tr(language, "Konto erneut prüfen", "Перевірити акаунт знову"))
                        }
                    }
                    state.availableActions.forEach { action ->
                        OutlinedButton(
                            {
                                if (state.canAct && platformRoleEligible(state, action))
                                    actions.request(action)
                            },
                            Modifier.fillMaxWidth()
                                .heightIn(min = 48.dp)
                                .testTag("platform-role-action-${action.name}"),
                            enabled = state.canAct && platformRoleEligible(state, action),
                        ) {
                            Text(platformRoleTitle(action, language))
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
        PlatformRoleConfirmation(state, language, actions)
}

@Composable
private fun PlatformRoleConfirmation(
    state: PlatformRoleState,
    language: String,
    actions: PlatformRoleActions,
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
                    .testTag("platform-role-confirm-scroll")
                    .semantics {
                        this[PlatformRoleDialogFontScale] = density.fontScale
                        this[PlatformRoleDialogImeVisible] = imeVisible
                    },
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    platformRoleTitle(action, language),
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(
                    tr(language, "Zielkonto: ", "Цільовий акаунт: ") + snapshot.version.targetId,
                    Modifier.testTag("platform-role-target"),
                    style = MaterialTheme.typography.titleMedium,
                )
                snapshot.displayName?.let {
                    Text(
                        it,
                        Modifier.testTag("platform-role-target-name"),
                        style = MaterialTheme.typography.titleMedium,
                    )
                }
                snapshot.email?.let {
                    Text(it, Modifier.testTag("platform-role-target-email"))
                }
                Text(
                    managedUsersRoleLabel(snapshot.target.role, language) +
                        " → " +
                        managedUsersRoleLabel(action.newRole, language),
                    Modifier.testTag("platform-role-transition"),
                    style = MaterialTheme.typography.titleMedium,
                )
                platformRoleAssignmentIssue(state, language)?.let { issue ->
                    Text(
                        issue,
                        Modifier.testTag("platform-role-confirm-eligibility"),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                Text(platformRoleEffect(action, language), Modifier.testTag("platform-role-effect"))
                Text(
                    tr(
                        language,
                        "Zugriff und Rohdaten werden vor dem Senden erneut geprüft. Gleichzeitige Serveränderungen sind trotzdem möglich; es gibt keine automatische Wiederholung.",
                        "Перед надсиланням доступ і вихідні дані перевіряються знову. Одночасні зміни на сервері все одно можливі; автоматичного повторення немає.",
                    ),
                    Modifier.testTag("platform-role-race-notice"),
                )
                OutlinedTextField(
                    state.reason,
                    actions.editReason,
                    Modifier.fillMaxWidth()
                        .focusProperties { canFocus = !state.busy }
                        .testTag("platform-role-reason"),
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
                            "Die eingefügte Begründung ist zu lang (höchstens ${PlatformRoleState.MAX_REASON_CHARACTERS} Zeichen). Der bisherige Text wurde nicht ersetzt. Kürzen oder bearbeiten Sie ihn vor dem Bestätigen.",
                            "Вставлена причина задовга (щонайбільше ${PlatformRoleState.MAX_REASON_CHARACTERS} символів). Попередній текст не замінено. Скоротіть або відредагуйте його перед підтвердженням.",
                        ),
                        Modifier.testTag("platform-role-reason-rejected"),
                        color = MaterialTheme.colorScheme.error,
                    )
                if (
                    !state.canConfirm &&
                        !state.busy &&
                        !state.reasonRejected &&
                        platformRoleEligible(state, action)
                )
                    Text(
                        tr(
                            language,
                            "Eine gültige, nicht leere Begründung innerhalb des sicheren Anfrage-Limits ist erforderlich.",
                            "Потрібна коректна непорожня причина в межах безпечного розміру запиту.",
                        ),
                        Modifier.testTag("platform-role-required"),
                    )
                Text(
                    tr(
                        language,
                        "Der Server speichert die Begründung im Auditprotokoll und im Hinweis zum Rollenwechsel. Empfang oder Anzeige des Hinweises wird hier nicht bestätigt.",
                        "Сервер зберігає причину в журналі аудиту та повідомленні про зміну ролі. Отримання чи показ повідомлення тут не підтверджується.",
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
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("platform-role-confirm"),
                    enabled = state.canConfirm,
                ) {
                    Text(platformRoleTitle(action, language))
                }
                TextButton(
                    { if (!state.busy) actions.cancel() },
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("platform-role-cancel"),
                    enabled = !state.busy,
                ) {
                    Text(tr(language, "Abbrechen", "Скасувати"))
                }
            }
        }
    }
}

private fun platformRoleEligible(state: PlatformRoleState, action: PlatformRoleAction): Boolean {
    val session = state.session ?: return false
    val target = state.snapshot?.target ?: return false
    return runCatching {
        PlatformRoleContract.requireTarget(session, target, action, state.targetAuth)
    }
        .isSuccess
}

private fun platformRoleAssignmentIssue(state: PlatformRoleState, language: String): String? {
    if (PlatformRoleAction.ASSIGN !in state.availableActions) return null
    val auth = state.targetAuth
    return when {
        auth == null || auth.targetId != state.targetId ->
            tr(
                language,
                "Die Prüfung des Zielkontos fehlt. Bitte das Konto erneut prüfen.",
                "Перевірка цільового акаунта відсутня. Перевірте акаунт знову.",
            )
        auth.disabled ->
            tr(
                language,
                "Dieses Anmeldekonto ist deaktiviert. Eine Administratorrolle kann nicht zugewiesen werden.",
                "Цей акаунт для входу вимкнено. Призначення адміністратором недоступне.",
            )
        !auth.emailVerified ->
            tr(
                language,
                "Die E-Mail-Adresse des Zielkontos ist nicht bestätigt. Eine Administratorrolle kann noch nicht zugewiesen werden.",
                "Електронну адресу цільового акаунта не підтверджено. Призначення адміністратором поки недоступне.",
            )
        else -> null
    }
}

fun platformRoleTitle(action: PlatformRoleAction, language: String) =
    when (action) {
        PlatformRoleAction.ASSIGN ->
            tr(language, "Als App-Administrator einsetzen", "Призначити адміністратором застосунку")
        PlatformRoleAction.REMOVE ->
            tr(language, "App-Administratorrolle entfernen", "Зняти роль адміністратора застосунку")
    }

fun platformRoleEffect(action: PlatformRoleAction, language: String) =
    when (action) {
        PlatformRoleAction.ASSIGN ->
            tr(
                language,
                "Das Konto erhält die Plattformrolle App-Administrator, keine Eigentümerrolle. Organisationsrollen und Kontobeschränkungen bleiben unverändert. MFA wird nicht automatisch aktiviert; geschützte Aktionen erfordern weiterhin die vollständig bestätigte TOTP-Anmeldung.",
                "Акаунт отримує роль адміністратора застосунку, не власника. Ролі в організаціях та обмеження акаунта не змінюються. MFA не активується автоматично; захищені дії й надалі потребують повністю підтвердженого входу з TOTP.",
            )
        PlatformRoleAction.REMOVE ->
            tr(
                language,
                "Die Plattformrolle wird auf Benutzer zurückgesetzt. Organisationsrollen, Kontobeschränkungen und MFA-Einstellungen bleiben unverändert. Ein fehlendes oder deaktiviertes Anmeldekonto verhindert den Entzug dieser Administratorrolle nicht.",
                "Роль на платформі зміниться на користувача. Ролі в організаціях, обмеження акаунта й налаштування MFA не змінюються. Відсутній або вимкнений акаунт для входу не перешкоджає зняттю цієї ролі адміністратора.",
            )
    }

fun platformRoleFailureText(failure: PlatformRoleFailure, language: String) =
    when (failure) {
        PlatformRoleFailure.ACCESS ->
            tr(
                language,
                "Aktueller Eigentümerzugriff und vollständig bestätigte TOTP-Anmeldung sind erforderlich.",
                "Потрібен чинний доступ власника і повністю підтверджений вхід із TOTP.",
            )
        PlatformRoleFailure.STALE ->
            tr(
                language,
                "Ziel, Zugriff oder Rohdaten haben sich geändert. Bitte den aktuellen Status erneut lesen.",
                "Акаунт, доступ або вихідні дані змінилися. Прочитайте актуальний стан знову.",
            )
        PlatformRoleFailure.INVALID ->
            tr(
                language,
                "Diese Daten oder Eingaben erlauben keine sichere Rollenänderung. Es wurde kein Erfolg bestätigt.",
                "Ці дані або введені значення не дозволяють безпечної зміни ролі. Успіх не підтверджено.",
            )
        PlatformRoleFailure.JOURNAL ->
            tr(
                language,
                "Der Wiederherstellungsbeleg ist nicht bestätigt. Nicht erneut senden; vorhandene Einträge prüfen.",
                "Запис відновлення не підтверджено. Не надсилайте повторно; перевірте наявні записи.",
            )
        PlatformRoleFailure.OFFLINE ->
            tr(
                language,
                "Der Serverstand konnte nicht bestätigt werden. Eine ausstehende Änderung wird nicht erneut gesendet.",
                "Стан сервера не підтверджено. Непідтверджена зміна не надсилатиметься повторно.",
            )
        PlatformRoleFailure.PENDING,
        PlatformRoleFailure.UNCONFIRMED ->
            tr(
                language,
                "Die Änderung ist noch nicht abschließend bestätigt. Nicht erneut senden; nur das Ergebnis prüfen.",
                "Зміна ще не підтверджена остаточно. Не надсилайте повторно; перевірте лише результат.",
            )
    }

fun platformRoleObservationText(value: PlatformRoleObservation, language: String) =
    when (value) {
        PlatformRoleObservation.CONFIRMED_CURRENT ->
            tr(
                language,
                "Änderung bestätigt und aktueller Status geprüft.",
                "Зміну підтверджено, поточний стан перевірено.",
            )
        PlatformRoleObservation.CONFIRMED_CHANGED ->
            tr(
                language,
                "Änderung bestätigt; der Serverstand hat sich inzwischen geändert. Bitte erneut lesen.",
                "Зміну підтверджено; стан сервера вже змінився. Прочитайте його знову.",
            )
        PlatformRoleObservation.CONFIRMED_UNAVAILABLE ->
            tr(
                language,
                "Ausführung bestätigt, aktueller Status nicht verfügbar. Der Beleg bleibt für eine reine Leseprüfung erhalten.",
                "Виконання підтверджено, поточний стан недоступний. Запис збережено для перевірки лише читанням.",
            )
        PlatformRoleObservation.OBSERVED_WITHOUT_RECEIPT ->
            tr(
                language,
                "Passender Status sichtbar, aber kein eindeutiger Beleg für diesen Versuch. Nicht erneut senden.",
                "Відповідний стан видно, але однозначного підтвердження цієї спроби немає. Не надсилайте повторно.",
            )
        PlatformRoleObservation.UNCONFIRMED,
        PlatformRoleObservation.UNAVAILABLE ->
            tr(
                language,
                "Keine eindeutige Bestätigung verfügbar. Wiederholung bleibt gesperrt; nur den Serverstand prüfen.",
                "Однозначне підтвердження недоступне. Повторення заблоковано; перевірте лише стан сервера.",
            )
    }
