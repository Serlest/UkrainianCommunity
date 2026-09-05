package at.uac.android.feature.contentlifecycle

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.OrganizationSession

data class ContentLifecycleActions(
    val back: () -> Unit = {},
    val account: () -> Unit = {},
    val refresh: () -> Unit = {},
    val request: () -> Unit = {},
    val confirm: () -> Unit = {},
    val dismiss: () -> Unit = {},
    val recover: () -> Unit = {},
)

@Composable
fun ContentLifecycleScreen(
    model: ContentLifecycleViewModel,
    target: ContentLifecycleTarget,
    session: OrganizationSession?,
    language: String,
    onBack: () -> Unit,
    onAccount: () -> Unit,
) {
    val stored by model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    val state =
        if (stored.session == session && stored.target == target) stored
        else ContentLifecycleState(session, target)
    LifecycleResumeEffect(session, target) {
        model.show(target)
        onPauseOrDispose { model.hide() }
    }
    ContentLifecycleContent(
        state,
        language,
        ContentLifecycleActions(
            onBack,
            onAccount,
            model::refresh,
            model::request,
            model::confirm,
            model::dismiss,
            model::recover,
        ),
    )
}

@Composable
fun ContentLifecycleContent(
    state: ContentLifecycleState,
    language: String,
    actions: ContentLifecycleActions,
) {
    var leaving by remember(state.session, state.target) { mutableStateOf(false) }
    val back = { if (state.busy || state.uncertain != null) leaving = true else actions.back() }
    BackHandler(state.session?.ready == true, back)
    val event = state.target?.kind == ContentKind.EVENTS
    Column(
        Modifier.fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
            .testTag("content-lifecycle-screen"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        TextButton(back) { Text(lc(language, "Zurück", "Назад")) }
        Text(
            if (event) lc(language, "Veranstaltung absagen", "Скасувати подію")
            else lc(language, "Nachricht löschen", "Видалити новину"),
            style = MaterialTheme.typography.headlineMedium,
        )
        if (state.session?.ready != true) {
            Text(
                lc(
                    language,
                    "Bitte zuerst Ihr aktives Konto und alle Sicherheitsanforderungen bestätigen.",
                    "Спочатку підтвердьте активний акаунт і всі вимоги безпеки.",
                )
            )
            Button(actions.account, Modifier.testTag("content-lifecycle-account")) {
                Text(lc(language, "Konto öffnen", "Відкрити акаунт"))
            }
        } else {
            state.snapshot?.let { snapshot ->
                Text(snapshot.organization.name, style = MaterialTheme.typography.titleMedium)
                snapshot.item?.let {
                    Text(it.content.title(language), style = MaterialTheme.typography.titleLarge)
                }
            }
            state.error?.let {
                Text(
                    contentLifecycleFailureText(it, language),
                    Modifier.testTag("content-lifecycle-error"),
                    color = MaterialTheme.colorScheme.error,
                )
            }
            if (state.loading || state.busy)
                CircularProgressIndicator(Modifier.testTag("content-lifecycle-progress"))
            if (state.busy)
                Text(
                    lc(
                        language,
                        "Der Server bearbeitet den einmal gesendeten Auftrag. Zurückgehen bricht ihn nicht ab.",
                        "Сервер обробляє одноразово надісланий запит. Повернення назад його не скасовує.",
                    )
                )
            TextButton(
                actions.refresh,
                Modifier.testTag("content-lifecycle-refresh"),
                enabled = !state.loading && !state.busy,
            ) {
                Text(lc(language, "Aktualisieren", "Оновити"))
            }
            if (!state.fresh)
                Text(
                    lc(
                        language,
                        "Aktionen bleiben bis zur aktuellen Serverprüfung gesperrt.",
                        "Дії заблоковано до актуальної серверної перевірки.",
                    )
                )
            state.confirmed?.let { result ->
                Text(
                    if (result.receipt is ContentLifecycleReceipt.Deleted)
                        lc(
                            language,
                            "Löschung vom Server bestätigt; der Beitrag ist in dieser Organisation nicht mehr vorhanden.",
                            "Видалення підтверджено сервером; матеріалу більше немає в цій організації.",
                        )
                    else
                        lc(
                            language,
                            "Absage vom Server bestätigt. Bestehende Anmeldungen bleiben erhalten. Die Zustellung einzelner Hinweise wird hier nicht nachgewiesen.",
                            "Скасування підтверджено сервером. Наявні реєстрації збережено. Доставку окремих сповіщень тут не підтверджуємо.",
                        ),
                    Modifier.testTag("content-lifecycle-confirmed"),
                )
            }
            if (state.uncertain != null) {
                Text(
                    contentLifecycleFailureText(ContentLifecycleFailure.UNCONFIRMED, language),
                    Modifier.testTag("content-lifecycle-uncertain"),
                )
                Button(
                    actions.recover,
                    Modifier.testTag("content-lifecycle-recover"),
                    enabled = !state.loading && !state.busy,
                ) {
                    Text(lc(language, "Nur Serverstand prüfen", "Лише перевірити серверний стан"))
                }
                state.observed?.let {
                    Text(
                        contentLifecycleObservedText(it, language),
                        Modifier.testTag("content-lifecycle-observed"),
                    )
                }
            }
            if (
                state.fresh &&
                    state.snapshot?.item == null &&
                    state.confirmed == null &&
                    state.uncertain == null
            )
                Text(
                    lc(
                        language,
                        "Dieser Beitrag ist hier nicht verfügbar. Daraus folgt keine Bestätigung früherer Aufträge.",
                        "Матеріал тут недоступний. Це не підтверджує виконання попередніх запитів.",
                    ),
                    Modifier.testTag("content-lifecycle-missing"),
                )
            if (
                state.snapshot?.item != null &&
                    !state.actionable &&
                    state.uncertain == null &&
                    state.confirmed == null
            )
                Text(
                    lc(
                        language,
                        "Dieser Stand ist schreibgeschützt. Geplante Entwürfe und bereits abgesagte Veranstaltungen werden hier nicht geändert.",
                        "Цей стан лише для перегляду. Заплановані чернетки та вже скасовані події тут не змінюємо.",
                    ),
                    Modifier.testTag("content-lifecycle-readonly"),
                )
            if (state.confirmed == null) {
                Text(
                    if (event)
                        lc(
                            language,
                            "Der Server entscheidet anhand echter Anmeldungen: Ohne Anmeldungen wird die Veranstaltung gelöscht; sonst wird sie abgesagt und für angemeldete Personen erhalten. Angezeigte Zähler sind dafür nicht maßgeblich.",
                            "Сервер вирішує за реальними реєстраціями: без них подію видалить; інакше скасує та збереже для зареєстрованих людей. Показаний лічильник не визначає результат.",
                        )
                    else
                        lc(
                            language,
                            "Diese Nachricht und ihre vom Server verwalteten Verknüpfungen werden entfernt. Eine Wiederherstellung wird hier nicht angeboten.",
                            "Цю новину та пов’язані дані, якими керує сервер, буде прибрано. Відновлення тут не передбачене.",
                        )
                )
                Button(
                    actions.request,
                    Modifier.fillMaxWidth().testTag("content-lifecycle-request"),
                    enabled = state.actionable,
                    colors =
                        ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.error
                        ),
                ) {
                    Text(
                        if (event) lc(language, "Absage prüfen", "Перевірити скасування")
                        else lc(language, "Löschung prüfen", "Перевірити видалення")
                    )
                }
            }
        }
    }
    if (leaving && state.session?.ready == true)
        AlertDialog(
            onDismissRequest = { leaving = false },
            title = { Text(lc(language, "Zurückgehen?", "Повернутися назад?")) },
            text = {
                Text(
                    lc(
                        language,
                        "Ein gesendeter Auftrag läuft weiter. Wir wiederholen ihn nicht automatisch. Ein unklarer Ausgang muss vor weiteren Änderungen geprüft werden.",
                        "Надісланий запит продовжується. Автоматичного повтору не буде. Невизначений результат потрібно перевірити перед подальшими змінами.",
                    )
                )
            },
            confirmButton = {
                TextButton({
                    leaving = false
                    actions.back()
                }) {
                    Text(lc(language, "Zurück", "Назад"))
                }
            },
            dismissButton = {
                TextButton({ leaving = false }) {
                    Text(lc(language, "Hier bleiben", "Залишитися тут"))
                }
            },
        )
    if (state.confirmation != null && state.session?.ready == true)
        AlertDialog(
            onDismissRequest = actions.dismiss,
            title = {
                Text(
                    if (event)
                        lc(
                            language,
                            "Veranstaltung verbindlich absagen?",
                            "Остаточно скасувати подію?",
                        )
                    else lc(language, "Nachricht endgültig löschen?", "Остаточно видалити новину?")
                )
            },
            text = {
                Text(
                    lc(
                        language,
                        "Es wird genau ein Auftrag gesendet. Der Server prüft Ihre aktuellen Eigentümerrechte erneut. Eine unklare Antwort löst keine automatische Wiederholung aus.",
                        "Буде надіслано рівно один запит. Сервер повторно перевірить актуальні права власника. Невизначена відповідь не спричинить автоматичного повтору.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    actions.confirm,
                    Modifier.testTag("content-lifecycle-confirm"),
                    enabled = state.actionable,
                ) {
                    Text(lc(language, "Bestätigen", "Підтвердити"))
                }
            },
            dismissButton = {
                TextButton(actions.dismiss) { Text(lc(language, "Abbrechen", "Скасувати")) }
            },
        )
}

private fun lc(language: String, de: String, uk: String) = if (language == "de") de else uk

fun contentLifecycleFailureText(reason: ContentLifecycleFailure, language: String): String =
    when (reason) {
        ContentLifecycleFailure.SIGN_IN,
        ContentLifecycleFailure.NOT_READY ->
            lc(
                language,
                "Bitte das Konto und seine Sicherheitsanforderungen bestätigen.",
                "Підтвердьте акаунт та його вимоги безпеки.",
            )
        ContentLifecycleFailure.DENIED ->
            lc(
                language,
                "Nur die aktuellen Eigentümerrechte erlauben diese Aktion. Team-Bearbeitungsrechte reichen nicht aus.",
                "Цю дію дозволяють лише актуальні права власника. Прав редактора команди недостатньо.",
            )
        ContentLifecycleFailure.MISSING ->
            lc(language, "Der Beitrag ist nicht mehr verfügbar.", "Матеріал більше недоступний.")
        ContentLifecycleFailure.READ_ONLY ->
            lc(
                language,
                "Dieser Beitrag kann hier nicht geändert werden.",
                "Цей матеріал тут не можна змінювати.",
            )
        ContentLifecycleFailure.STALE ->
            lc(
                language,
                "Beitrag oder Rechte haben sich geändert. Bitte den neuen Stand prüfen.",
                "Матеріал або права змінилися. Перевірте новий стан.",
            )
        ContentLifecycleFailure.INVALID ->
            lc(
                language,
                "Dieser Auftrag konnte nicht sicher geprüft werden.",
                "Не вдалося безпечно перевірити цей запит.",
            )
        ContentLifecycleFailure.OFFLINE ->
            lc(
                language,
                "Der Server ist nicht erreichbar. Es wurde kein aktueller Zustand bestätigt.",
                "Сервер недоступний. Актуальний стан не підтверджено.",
            )
        ContentLifecycleFailure.INDEX ->
            lc(
                language,
                "Diese sichere Serverabfrage ist noch nicht verfügbar.",
                "Цей безпечний серверний запит поки недоступний.",
            )
        ContentLifecycleFailure.UNCONFIRMED,
        ContentLifecycleFailure.UNKNOWN ->
            lc(
                language,
                "Der Auftrag ist nicht vollständig bestätigt und kann bereits teilweise ausgeführt sein. Wir senden ihn nicht erneut. Prüfen Sie nur den Serverstand; ein fehlender Beitrag beweist keine vollständige Bereinigung.",
                "Повне виконання запиту не підтверджено; він уже міг виконатися частково. Повтору не буде. Лише перевірте серверний стан: відсутність матеріалу не доводить повного очищення.",
            )
    }

fun contentLifecycleObservedText(value: ContentLifecycleObserved, language: String): String =
    when (value) {
        ContentLifecycleObserved.UNAVAILABLE_CLEANUP_UNCONFIRMED ->
            lc(
                language,
                "Beitrag nicht verfügbar; vollständige Bereinigung bleibt unbestätigt.",
                "Матеріал недоступний; повне очищення лишається непідтвердженим.",
            )
        ContentLifecycleObserved.CANCELLED_NOTICES_UNCONFIRMED ->
            lc(
                language,
                "Absagestatus vorhanden; der Abschluss aller Benachrichtigungen bleibt unbestätigt.",
                "Статус скасування є; завершення всіх сповіщень лишається непідтвердженим.",
            )
        ContentLifecycleObserved.UNCHANGED ->
            lc(
                language,
                "Noch unveränderter Stand. Der frühere Auftrag wird trotzdem nicht erneut gesendet.",
                "Стан поки не змінився. Попередній запит усе одно не надсилаємо повторно.",
            )
        ContentLifecycleObserved.DIFFERENT ->
            lc(
                language,
                "Ein anderer Zustand wurde gelesen; der frühere Auftrag bleibt ungeklärt.",
                "Прочитано інший стан; результат попереднього запиту не з’ясовано.",
            )
    }
