package at.uac.android.feature.auth

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.core.WindowSecurity

@Composable
internal fun MfaChallengeFields(
    session: AuthSession,
    language: String,
    submit: (String, String) -> Unit,
    cancel: () -> Unit,
) {
    SecureMfaWindow()
    val factors = session.mfa.factors
    var selected by
        remember(session.revision, factors) { mutableStateOf(factors.singleOrNull()?.id.orEmpty()) }
    var code by remember(session.revision) { mutableStateOf("") }
    Text(
        authText(language, "Mit Authenticator bestätigen", "Підтвердьте через аутентифікатор"),
        Modifier.testTag("auth-mfa-challenge").semantics { heading() },
        style = MaterialTheme.typography.titleLarge,
    )
    Text(
        authText(
            language,
            "Du kannst zur Authenticator-App wechseln. Diese Anfrage bleibt geöffnet, bis du sie bestätigst oder ausdrücklich abbrichst.",
            "Можна перейти до застосунку-аутентифікатора. Цей запит зберігається, доки ви не підтвердите або явно не скасуєте його.",
        )
    )
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        factors.forEach { factor ->
            FilterChip(
                selected == factor.id,
                {
                    selected = factor.id
                    code = ""
                },
                { Text(factor.name) },
                Modifier.testTag("auth-mfa-factor-${factor.id}"),
                enabled = !session.busy,
            )
        }
    }
    MfaCodeField(code, { code = it }, language, session.busy, 6)
    Button(
        {
            val value = code
            code = ""
            submit(selected, value)
        },
        Modifier.fillMaxWidth().testTag("auth-mfa-submit"),
        enabled =
            !session.busy && selected.isNotEmpty() && runCatching { totpCode(code) }.isSuccess,
    ) {
        Text(
            authText(language, "Code bestätigen · erneut versuchen", "Підтвердити код · повторити")
        )
    }
    TextButton(cancel, Modifier.testTag("auth-mfa-cancel")) {
        Text(authText(language, "Anfrage abbrechen", "Скасувати запит"))
    }
}

@Composable
internal fun AuthMfaPanel(store: AuthStore, session: AuthSession, language: String) {
    val context = LocalContext.current
    MfaSecurityFields(
        session,
        language,
        { store.loadMfa() },
        { store.beginTotpEnrollment(it) },
        { store.verifyMfaSignIn(it) },
        { id, password -> store.removeTotpFactor(id, password) },
        { store.completeTotpEnrollment(it) },
        { store.cancelMfa() },
        { store.activateMfaProtection() },
        { openAuthenticator(context, it) },
    )
}

@Composable
internal fun MfaSecurityFields(
    session: AuthSession,
    language: String,
    load: () -> Unit,
    begin: (String) -> Unit,
    verify: (String) -> Unit,
    remove: (String, String) -> Unit,
    complete: (String) -> Unit,
    cancel: () -> Unit,
    activate: () -> Unit,
    openAuthenticator: (String) -> Boolean,
) {
    val mfa = session.mfa
    val profile = session.profile ?: return
    var password by remember(session.identity?.uid, session.revision) { mutableStateOf("") }
    var removal by
        remember(session.identity?.uid, session.revision) { mutableStateOf<AuthTotpFactor?>(null) }
    Column(
        Modifier.fillMaxWidth().testTag("auth-security"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        HorizontalDivider()
        Text(
            authText(language, "Kontosicherheit", "Безпека акаунта"),
            Modifier.semantics { heading() },
            style = MaterialTheme.typography.titleLarge,
        )
        Text(
            authText(
                language,
                "Lokale Entwicklung: Ein echter Cloud-TOTP-Test steht separat aus.",
                "Локальна розробка: справжню перевірку хмарного TOTP ще потрібно виконати окремо.",
            ),
            style = MaterialTheme.typography.bodySmall,
        )
        val setup = mfa.setup
        if (setup != null) {
            TotpSetupFields(setup, session.busy, language, complete, cancel, openAuthenticator)
        } else {
            OutlinedButton(
                load,
                Modifier.fillMaxWidth().testTag("auth-mfa-load"),
                enabled = !session.busy,
            ) {
                Text(authText(language, "Sicherheitsstatus prüfen", "Перевірити стан безпеки"))
            }
            if (mfa.unconfirmed)
                Text(
                    AuthProblem.MFA_UNCONFIRMED.message(language),
                    Modifier.testTag("auth-mfa-unconfirmed"),
                )
            if (mfa.loaded && !mfa.unconfirmed) {
                Text(
                    if (mfa.factors.isEmpty())
                        authText(
                            language,
                            "Kein Authenticator verbunden.",
                            "Аутентифікатор не підключений.",
                        )
                    else
                        authText(
                            language,
                            "Verbundene Authenticator",
                            "Підключені аутентифікатори",
                        ),
                    Modifier.testTag("auth-mfa-factor-status"),
                )
                OutlinedTextField(
                    password,
                    { password = it },
                    Modifier.fillMaxWidth().testTag("auth-mfa-password"),
                    label = { Text(authText(language, "Aktuelles Passwort", "Поточний пароль")) },
                    enabled = !session.busy,
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                )
                if (mfa.factors.isEmpty()) {
                    Button(
                        {
                            val value = password
                            password = ""
                            begin(value)
                        },
                        Modifier.fillMaxWidth().testTag("auth-mfa-begin"),
                        enabled = !session.busy && password.isNotEmpty(),
                    ) {
                        Text(
                            authText(
                                language,
                                "Authenticator verbinden",
                                "Підключити аутентифікатор",
                            )
                        )
                    }
                } else {
                    Button(
                        {
                            val value = password
                            password = ""
                            verify(value)
                        },
                        Modifier.fillMaxWidth().testTag("auth-mfa-verify"),
                        enabled = !session.busy && password.isNotEmpty(),
                    ) {
                        Text(
                            authText(
                                language,
                                "Anmeldung mit Authenticator prüfen",
                                "Перевірити вхід з аутентифікатором",
                            )
                        )
                    }
                    mfa.factors.forEach { factor ->
                        Text(factor.name)
                        TextButton(
                            { removal = factor },
                            Modifier.testTag("auth-mfa-remove-${factor.id}"),
                            enabled =
                                !session.busy &&
                                    password.isNotEmpty() &&
                                    canRemoveTotp(profile, mfa.factors, factor.id),
                        ) {
                            Text(
                                authText(
                                    language,
                                    "Diesen Authenticator entfernen",
                                    "Видалити цей аутентифікатор",
                                )
                            )
                        }
                    }
                    if (
                        profile.privileged &&
                            profile.requiresMultiFactorAuth &&
                            mfa.factors.size == 1
                    ) {
                        Text(
                            AuthProblem.MFA_LAST_FACTOR.message(language),
                            Modifier.testTag("auth-mfa-last-factor"),
                        )
                    }
                }
            }
            if (profile.privileged && !profile.requiresMultiFactorAuth) {
                Button(
                    activate,
                    Modifier.fillMaxWidth().testTag("auth-mfa-activate"),
                    enabled = !session.busy && !mfa.unconfirmed && session.totpAuthenticated,
                ) {
                    Text(
                        authText(
                            language,
                            "Administrationsschutz aktivieren",
                            "Активувати адміністративний захист",
                        )
                    )
                }
            }
        }
    }
    removal?.let { factor ->
        at.uac.android.core.PreserveAuthRemediationSurface()
        AlertDialog(
            onDismissRequest = { removal = null },
            title = {
                Text(authText(language, "Authenticator entfernen?", "Видалити аутентифікатор?"))
            },
            text = {
                Text(
                    authText(
                        language,
                        "${factor.name}: Bestätige nur, wenn du danach weiterhin sicher auf dein Konto zugreifen kannst.",
                        "${factor.name}: підтверджуйте лише тоді, коли збережете безпечний доступ до акаунта.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        val value = password
                        password = ""
                        removal = null
                        remove(factor.id, value)
                    },
                    Modifier.testTag("auth-mfa-remove-confirm"),
                    enabled = !session.busy,
                ) {
                    Text(authText(language, "Entfernen", "Видалити"))
                }
            },
            dismissButton = {
                TextButton({ removal = null }) {
                    Text(authText(language, "Abbrechen", "Скасувати"))
                }
            },
        )
    }
}

@Composable
private fun TotpSetupFields(
    setup: AuthTotpSetup,
    busy: Boolean,
    language: String,
    complete: (String) -> Unit,
    cancel: () -> Unit,
    openAuthenticator: (String) -> Boolean,
) {
    SecureMfaWindow()
    var reveal by remember(setup) { mutableStateOf(false) }
    var code by remember(setup) { mutableStateOf("") }
    var unavailable by remember(setup) { mutableStateOf(false) }
    Text(
        authText(
            language,
            "1. Authenticator öffnen oder den Schlüssel dort manuell hinzufügen.",
            "1. Відкрийте аутентифікатор або додайте до нього ключ вручну.",
        )
    )
    OutlinedButton(
        { unavailable = !openAuthenticator(setup.otpAuthUri) },
        Modifier.fillMaxWidth().testTag("auth-mfa-open-app"),
        enabled = !busy,
    ) {
        Text(authText(language, "In Authenticator öffnen", "Відкрити в аутентифікаторі"))
    }
    if (unavailable)
        Text(
            authText(
                language,
                "Keine passende App gefunden. Den Schlüssel bitte manuell in einer vertrauenswürdigen Authenticator-App eingeben.",
                "Відповідного застосунку не знайдено. Введіть ключ вручну в довіреному аутентифікаторі.",
            ),
            Modifier.testTag("auth-mfa-no-app"),
        )
    TextButton({ reveal = !reveal }, Modifier.testTag("auth-mfa-reveal"), enabled = !busy) {
        Text(
            authText(
                language,
                if (reveal) "Schlüssel ausblenden" else "Manuellen Schlüssel anzeigen",
                if (reveal) "Приховати ключ" else "Показати ключ для ручного введення",
            )
        )
    }
    if (reveal)
        Text(
            setup.sharedKey,
            Modifier.testTag("auth-mfa-secret"),
            fontFamily = FontFamily.Monospace,
        )
    Text(
        authText(
            language,
            "Bewahre den Schlüssel vertraulich auf. Er bleibt nur vorübergehend im Arbeitsspeicher und wird nicht in die Zwischenablage kopiert.",
            "Зберігайте ключ у таємниці. Він лише тимчасово перебуває в оперативній пам’яті та не копіюється до буфера обміну.",
        ),
        style = MaterialTheme.typography.bodySmall,
    )
    Text(
        authText(
            language,
            "2. Den aktuellen Code aus dem Authenticator bestätigen.",
            "2. Підтвердьте поточний код з аутентифікатора.",
        )
    )
    MfaCodeField(code, { code = it }, language, busy, setup.digits)
    Button(
        {
            val value = code
            code = ""
            complete(value)
        },
        Modifier.fillMaxWidth().testTag("auth-mfa-enroll-submit"),
        enabled = !busy && runCatching { totpCode(code, setup.digits) }.isSuccess,
    ) {
        Text(authText(language, "Verbindung bestätigen", "Підтвердити підключення"))
    }
    TextButton(cancel, Modifier.testTag("auth-mfa-setup-cancel"), enabled = !busy) {
        Text(authText(language, "Einrichtung abbrechen", "Скасувати налаштування"))
    }
}

@Composable
private fun MfaCodeField(
    value: String,
    change: (String) -> Unit,
    language: String,
    busy: Boolean,
    digits: Int,
) {
    OutlinedTextField(
        value,
        change,
        Modifier.fillMaxWidth().testTag("auth-mfa-code"),
        label = {
            Text(
                authText(language, "Einmalcode ($digits Ziffern)", "Одноразовий код ($digits цифр)")
            )
        },
        enabled = !busy,
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
    )
}

@Composable
private fun SecureMfaWindow() {
    val context = LocalContext.current
    DisposableEffect(context) {
        val lease = context.activity()?.window?.let(WindowSecurity::acquire)
        onDispose { lease?.close() }
    }
}

private fun Context.activity(): Activity? =
    when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.takeIf { it !== this }?.activity()
        else -> null
    }

private fun openAuthenticator(context: Context, value: String): Boolean {
    if (!safeOtpAuthUri(value)) return false
    return try {
        // Only an explicit tap shares the SDK-generated local otpauth URI. There
        // is no web QR service, automatic Play Store fallback, or clipboard write.
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(value)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (_: SecurityException) {
        false
    }
}
