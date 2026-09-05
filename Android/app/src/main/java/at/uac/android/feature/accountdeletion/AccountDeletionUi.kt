package at.uac.android.feature.accountdeletion

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.SecureFlagPolicy
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.feature.browse.tr

/**
 * Small embeddable panel; the host owns its ordinary screen scroll. Password and TOTP never enter a
 * Bundle or ViewModel.
 */
@Composable
fun AccountDeletionPanel(
    state: AccountDeletionState,
    language: String,
    model: AccountDeletionViewModel,
    onAccount: () -> Unit,
    onOrganizations: () -> Unit,
) {
    LaunchedEffect(state.session) {
        if (state.session != null && state.policy == null) model.load()
    }
    AccountDeletionControls(
        state,
        language,
        model::load,
        model::begin,
        model::verifySecondFactor,
        model::reconcile,
        model::cancelBeforeSubmission,
        onAccount,
        onOrganizations,
    )
}

@Composable
fun AccountDeletionControls(
    state: AccountDeletionState,
    language: String,
    onRefresh: () -> Unit,
    onSubmit: (String, Boolean) -> Unit,
    onMfa: (String, String) -> Unit,
    onReconcile: () -> Unit,
    onCancel: () -> Unit,
    onAccount: () -> Unit,
    onOrganizations: () -> Unit,
) {
    var open by remember(state.session) { mutableStateOf(false) }
    val blocked = state.policy?.platformOwner == true || state.policy?.ownsOrganization == true
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.testTag("account-delete-panel"),
    ) {
        Text(
            tr(language, "Konto löschen", "Видалення облікового запису"),
            style = MaterialTheme.typography.titleLarge,
        )
        Text(
            tr(
                language,
                "Die Löschung ist unwiderruflich. Der Server prüft zuerst, ob du eine Organisation oder die Plattform besitzt.",
                "Видалення незворотне. Сервер спочатку перевірить, чи належить вам організація або платформа.",
            )
        )
        if (state.session == null)
            TextButton(onClick = onAccount) {
                Text(tr(language, "Zum Konto", "До облікового запису"))
            }
        else {
            if (!open) DeletionStatus(state, language)
            if (state.policy == null && !state.busy)
                OutlinedButton(
                    onClick = onRefresh,
                    modifier = Modifier.testTag("account-delete-refresh"),
                ) {
                    Text(tr(language, "Voraussetzungen prüfen", "Перевірити умови"))
                }
            if (blocked)
                TextButton(
                    onClick = onOrganizations,
                    modifier = Modifier.testTag("account-delete-organizations"),
                ) {
                    Text(
                        tr(
                            language,
                            "Eigentum zuerst übertragen",
                            "Спочатку передати право власності",
                        )
                    )
                }
            if (state.unresolved && !open)
                OutlinedButton(
                    onClick = onReconcile,
                    enabled = !state.busy,
                    modifier = Modifier.testTag("account-delete-check"),
                ) {
                    Text(tr(language, "Löschstatus prüfen", "Перевірити стан видалення"))
                }
            Button(
                onClick = { open = true },
                enabled =
                    state.policy != null &&
                        !blocked &&
                        !state.busy &&
                        state.receipt == null &&
                        (!state.unresolved || state.retryAllowed),
                colors =
                    ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error),
                modifier = Modifier.testTag("account-delete-open"),
            ) {
                Text(
                    if (state.unresolved)
                        tr(
                            language,
                            "Erneute Löschung bestätigen",
                            "Підтвердити повторне видалення",
                        )
                    else
                        tr(
                            language,
                            "Konto unwiderruflich löschen",
                            "Назавжди видалити обліковий запис",
                        )
                )
            }
        }
    }
    if (open)
        AccountDeletionDialog(
            state,
            language,
            onSubmit,
            onMfa,
            onReconcile,
            onCancel,
            onClose = { open = false },
        )
}

@Composable
private fun AccountDeletionDialog(
    state: AccountDeletionState,
    language: String,
    onSubmit: (String, Boolean) -> Unit,
    onMfa: (String, String) -> Unit,
    onReconcile: () -> Unit,
    onCancel: () -> Unit,
    onClose: () -> Unit,
) {
    var password by remember(state.session) { mutableStateOf("") }
    var confirmation by remember(state.session) { mutableStateOf("") }
    var acknowledged by remember(state.session) { mutableStateOf(false) }
    var code by remember(state.session) { mutableStateOf("") }
    var factor by
        remember(state.session, state.factors) {
            mutableStateOf(state.factors.firstOrNull()?.id.orEmpty())
        }
    var closeAfterCancel by remember(state.session) { mutableStateOf(false) }
    val word = tr(language, "LÖSCHEN", "ВИДАЛИТИ")
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    LaunchedEffect(state.phase) {
        if (state.busy) {
            password = ""
            code = ""
            focus.clearFocus()
            keyboard?.hide()
        }
    }
    LaunchedEffect(state.busy, closeAfterCancel) { if (!state.busy && closeAfterCancel) onClose() }
    val close = {
        if (
            state.phase !in setOf(AccountDeletionPhase.DELETING, AccountDeletionPhase.RECONCILING)
        ) {
            password = ""
            code = ""
            onCancel()
            if (state.busy) closeAfterCancel = true else onClose()
        }
    }
    AlertDialog(
        onDismissRequest = close,
        modifier = Modifier.testTag("account-delete-dialog"),
        properties =
            DialogProperties(
                dismissOnClickOutside = false,
                dismissOnBackPress = !state.busy,
                securePolicy = SecureFlagPolicy.SecureOn,
            ),
        title = {
            Text(tr(language, "Konto endgültig löschen?", "Назавжди видалити обліковий запис?"))
        },
        text = {
            Column(
                Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    tr(
                        language,
                        "Profil und private Listen werden entfernt. Öffentliche Beiträge können anonymisiert erhalten bleiben; bestimmte rechtliche Nachweise bleiben erhalten. Eine Wiederherstellung ist nicht möglich.",
                        "Профіль і приватні списки буде видалено. Публічні дописи можуть залишитися знеособленими; окремі юридичні записи зберігаються. Відновлення неможливе.",
                    ),
                    Modifier.testTag("account-delete-warning"),
                )
                DeletionStatus(state, language)
                if (state.phase == AccountDeletionPhase.MFA) {
                    Text(
                        tr(
                            language,
                            "Bestätige mit deinem echten Authenticator-Code.",
                            "Підтвердьте справжнім кодом вашого автентифікатора.",
                        )
                    )
                    state.factors.forEachIndexed { index, value ->
                        Row {
                            RadioButton(
                                selected = factor == value.id,
                                onClick = { factor = value.id },
                                modifier = Modifier.testTag("account-delete-factor-$index"),
                            )
                            Text(value.label)
                        }
                    }
                    OutlinedTextField(
                        code,
                        { code = it.filter(Char::isDigit).take(6) },
                        label = { Text(tr(language, "Authenticator-Code", "Код автентифікатора")) },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions =
                            KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        singleLine = true,
                        enabled = !state.busy,
                        modifier = Modifier.fillMaxWidth().testTag("account-delete-code"),
                    )
                } else if (state.receipt == null && (!state.unresolved || state.retryAllowed)) {
                    OutlinedTextField(
                        password,
                        { password = it.take(128) },
                        label = { Text(tr(language, "Aktuelles Passwort", "Поточний пароль")) },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        singleLine = true,
                        enabled = !state.busy,
                        modifier = Modifier.fillMaxWidth().testTag("account-delete-password"),
                    )
                    OutlinedTextField(
                        confirmation,
                        { confirmation = it.take(24) },
                        label = { Text(tr(language, "Tippe $word", "Введіть $word")) },
                        singleLine = true,
                        enabled = !state.busy,
                        modifier = Modifier.fillMaxWidth().testTag("account-delete-confirmation"),
                    )
                    Row {
                        Checkbox(
                            acknowledged,
                            { acknowledged = it },
                            enabled = !state.busy,
                            modifier = Modifier.testTag("account-delete-acknowledge"),
                        )
                        Text(
                            tr(
                                language,
                                "Ich verstehe, dass die Löschung unwiderruflich ist.",
                                "Я розумію, що видалення незворотне.",
                            )
                        )
                    }
                }
            }
        },
        confirmButton = {
            when {
                state.receipt != null ->
                    TextButton(onClick = onClose) { Text(tr(language, "Schließen", "Закрити")) }
                state.phase == AccountDeletionPhase.MFA ->
                    Button(
                        onClick = {
                            val submitted = code
                            code = ""
                            focus.clearFocus()
                            keyboard?.hide()
                            onMfa(factor, submitted)
                        },
                        enabled = !state.busy && factor.isNotBlank() && code.length == 6,
                        modifier = Modifier.testTag("account-delete-mfa-submit"),
                    ) {
                        Text(tr(language, "Bestätigen", "Підтвердити"))
                    }
                state.unresolved && !state.retryAllowed ->
                    OutlinedButton(
                        onClick = onReconcile,
                        enabled = !state.busy,
                        modifier = Modifier.testTag("account-delete-check"),
                    ) {
                        Text(tr(language, "Status prüfen", "Перевірити стан"))
                    }
                else ->
                    Button(
                        onClick = {
                            val submitted = password
                            password = ""
                            focus.clearFocus()
                            keyboard?.hide()
                            onSubmit(submitted, acknowledged && confirmation == word)
                        },
                        enabled =
                            !state.busy &&
                                password.isNotEmpty() &&
                                acknowledged &&
                                confirmation == word,
                        colors =
                            ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.error
                            ),
                        modifier = Modifier.testTag("account-delete-submit"),
                    ) {
                        Text(tr(language, "Endgültig löschen", "Назавжди видалити"))
                    }
            }
        },
        dismissButton = {
            TextButton(
                onClick = close,
                enabled =
                    state.phase !in
                        setOf(AccountDeletionPhase.DELETING, AccountDeletionPhase.RECONCILING) &&
                        !state.cancelRequested,
                modifier = Modifier.testTag("account-delete-cancel"),
            ) {
                Text(tr(language, "Abbrechen", "Скасувати"))
            }
        },
    )
}

@Composable
private fun DeletionStatus(state: AccountDeletionState, language: String) {
    if (state.busy) {
        LinearProgressIndicator(Modifier.fillMaxWidth())
        Text(
            when (state.phase) {
                AccountDeletionPhase.DELETING ->
                    tr(
                        language,
                        "Der Server löscht dein Konto. Dies kann bis zu fünf Minuten dauern und lässt sich nach dem Absenden nicht zurückrufen.",
                        "Сервер видаляє ваш обліковий запис. Це може тривати до п’яти хвилин; надісланий запит уже неможливо скасувати.",
                    )
                AccountDeletionPhase.REAUTHENTICATING ->
                    tr(
                        language,
                        "Identität wird erneut bestätigt …",
                        "Повторно підтверджуємо особу…",
                    )
                AccountDeletionPhase.RECONCILING ->
                    tr(
                        language,
                        "Der tatsächliche Kontostatus wird geprüft …",
                        "Перевіряємо фактичний стан облікового запису…",
                    )
                else -> tr(language, "Voraussetzungen werden geprüft …", "Перевіряємо умови…")
            }
        )
    }
    state.receipt?.let {
        Text(
            tr(language, "Die Löschung ist bestätigt.", "Видалення підтверджено."),
            Modifier.testTag("account-delete-confirmed"),
        )
        if (!it.journalCleared)
            Text(
                tr(
                    language,
                    "Die Löschung ist abgeschlossen; der lokale Prüfvermerk konnte noch nicht entfernt werden.",
                    "Видалення завершено; локальну позначку перевірки ще не вдалося прибрати.",
                )
            )
    }
    state.error?.let {
        Text(
            accountDeletionFailureText(it, language, state.freshnessDiagnostic),
            color = MaterialTheme.colorScheme.error,
            modifier = Modifier.testTag("account-delete-error"),
        )
    }
    if (state.policy?.platformOwner == true)
        Text(accountDeletionFailureText(AccountDeletionFailure.PLATFORM_OWNER, language))
    if (state.policy?.ownsOrganization == true)
        Text(accountDeletionFailureText(AccountDeletionFailure.ORGANIZATION_OWNER, language))
    if (state.unresolved && !state.busy)
        Text(
            tr(
                language,
                "Eine frühere Anfrage ist noch nicht abschließend bestätigt. Wir senden sie nicht automatisch erneut. Prüfe zuerst den Status; ein bewusst bestätigter neuer Versuch ist frühestens nach fünf Minuten möglich.",
                "Попередній запит ще не підтверджено остаточно. Ми не надсилаємо його повторно автоматично. Спочатку перевірте стан; нова свідомо підтверджена спроба можлива не раніше ніж через п’ять хвилин.",
            )
        )
    if (
        state.status in
            setOf(AccountDeletionIdentityStatus.PRESENT, AccountDeletionIdentityStatus.PARTIAL)
    )
        Text(
            tr(
                language,
                "Die Anmeldung besteht noch. Das ist kein Nachweis einer abgeschlossenen Löschung.",
                "Вхід ще існує. Це не є підтвердженням завершеного видалення.",
            )
        )
}

fun accountDeletionFailureText(
    reason: AccountDeletionFailure,
    language: String,
    diagnostic: AccountDeletionFreshnessDiagnostic? = null,
): String =
    if (
        reason == AccountDeletionFailure.RECENT_AUTH_REQUIRED &&
            diagnostic?.reason in
                setOf(
                    AccountDeletionFreshnessReason.FUTURE,
                    AccountDeletionFreshnessReason.WAIT_LIMIT_REACHED,
                )
    )
        tr(
            language,
            "Die Gerätezeit stimmt noch nicht mit der Anmeldung überein. Es wurde keine Löschung gesendet. Prüfe Datum und Uhrzeit und bestätige danach erneut selbst.",
            "Час пристрою ще не узгоджений із підтвердженням входу. Запит на видалення не надіслано. Перевірте дату й час, а потім повторно підтвердьте дію самостійно.",
        )
    else
        when (reason) {
            AccountDeletionFailure.SIGN_IN ->
                tr(
                    language,
                    "Melde dich mit dem betroffenen Konto an.",
                    "Увійдіть саме до цього облікового запису.",
                )
            AccountDeletionFailure.LOCAL_ONLY ->
                tr(
                    language,
                    "Diese lokale Version unterstützt ausschließlich synthetische Testkonten.",
                    "Ця локальна версія підтримує лише вигадані тестові облікові записи.",
                )
            AccountDeletionFailure.PASSWORD_REQUIRED ->
                tr(language, "Gib dein aktuelles Passwort ein.", "Введіть поточний пароль.")
            AccountDeletionFailure.INVALID_CREDENTIALS ->
                tr(
                    language,
                    "Das Passwort konnte nicht bestätigt werden.",
                    "Не вдалося підтвердити пароль.",
                )
            AccountDeletionFailure.RECENT_AUTH_REQUIRED ->
                tr(
                    language,
                    "Eine neue Anmeldung ist erforderlich. Bestätige dein Passwort erneut.",
                    "Потрібне свіже підтвердження входу. Повторно підтвердьте пароль.",
                )
            AccountDeletionFailure.PLATFORM_OWNER ->
                tr(
                    language,
                    "Das Konto des Plattforminhabers kann hier nicht gelöscht werden.",
                    "Обліковий запис власника платформи тут видалити неможливо.",
                )
            AccountDeletionFailure.ORGANIZATION_OWNER ->
                tr(
                    language,
                    "Übertrage zuerst das Eigentum an deinen Organisationen.",
                    "Спочатку передайте право власності на ваші організації.",
                )
            AccountDeletionFailure.MFA_REQUIRED ->
                tr(
                    language,
                    "Dieses privilegierte Konto benötigt eine echte TOTP-bestätigte Sitzung.",
                    "Цей привілейований обліковий запис потребує справжнього підтвердження TOTP.",
                )
            AccountDeletionFailure.MFA_INVALID ->
                tr(
                    language,
                    "Der Authenticator-Code wurde nicht bestätigt. Prüfe einen aktuellen Code.",
                    "Код автентифікатора не підтверджено. Перевірте актуальний код.",
                )
            AccountDeletionFailure.MFA_UNSUPPORTED ->
                tr(
                    language,
                    "Der erforderliche Sicherheitsfaktor wird hier nicht unterstützt.",
                    "Потрібний засіб підтвердження безпеки тут не підтримується.",
                )
            AccountDeletionFailure.DENIED ->
                tr(
                    language,
                    "Der Server hat die Löschung nicht erlaubt.",
                    "Сервер не дозволив видалення.",
                )
            AccountDeletionFailure.PRECONDITION ->
                tr(
                    language,
                    "Prüfe Organisationseigentum und die erforderliche TOTP-Bestätigung, bevor du fortfährst.",
                    "Перед продовженням перевірте право власності на організації та потрібне підтвердження TOTP.",
                )
            AccountDeletionFailure.OFFLINE ->
                tr(
                    language,
                    "Die Serverprüfung ist momentan nicht erreichbar. Eine ausstehende Löschung wird nicht automatisch wiederholt.",
                    "Перевірка сервера зараз недоступна. Незавершене видалення не буде повторено автоматично.",
                )
            AccountDeletionFailure.RATE_LIMITED ->
                tr(
                    language,
                    "Zu viele Versuche. Warte vor der nächsten Bestätigung.",
                    "Забагато спроб. Зачекайте перед наступним підтвердженням.",
                )
            AccountDeletionFailure.CHECKPOINT ->
                tr(
                    language,
                    "Der lokale Sicherheitsvermerk konnte nicht bestätigt werden. Es wird keine neue Löschung gestartet.",
                    "Не вдалося підтвердити локальну контрольну позначку. Нове видалення не запускається.",
                )
            AccountDeletionFailure.INVALID ->
                tr(
                    language,
                    "Die Voraussetzungen konnten nicht sicher bestätigt werden.",
                    "Не вдалося надійно підтвердити умови.",
                )
            AccountDeletionFailure.UNCONFIRMED ->
                tr(
                    language,
                    "Das Ergebnis ist noch unbestätigt. Die Löschung kann bereits laufen oder teilweise abgeschlossen sein. Prüfe den Status.",
                    "Результат ще не підтверджено. Видалення вже може тривати або бути частково завершеним. Перевірте стан.",
                )
        }
