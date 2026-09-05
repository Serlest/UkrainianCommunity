package at.uac.android.feature.auth

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.design.UacCard
import at.uac.android.design.UacSectionCard
import at.uac.android.feature.browse.Choice
import at.uac.android.feature.browse.regions

@Composable
fun AccountScreen(
    store: AuthStore,
    language: String,
    initialPage: String = "login",
    onNavigateAuth: ((String) -> Unit)? = null,
    personalContent: (@Composable (AuthSession) -> Unit)? = null,
) {
    val session by store.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val referenceDocuments = remember(context) { bundledReferenceLegal(context) }
    var document by remember { mutableStateOf<AuthLegalDocument?>(null) }
    var reference by remember { mutableStateOf(true) }
    var page by
        rememberSaveable(initialPage) {
            mutableStateOf(
                initialPage.takeIf { it in setOf("login", "register", "reset") } ?: "login"
            )
        }
    var showLocalTools by rememberSaveable { mutableStateOf(false) }
    // Passwords, action codes and email addresses never enter SavedStateHandle/Bundle.
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var repeated by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    LaunchedEffect(session.stage) {
        if (session.stage != AuthStage.GUEST) {
            password = ""
            repeated = ""
            code = ""
        }
    }
    LaunchedEffect(session.notice) {
        if (session.notice == AuthNotice.PASSWORD_CHANGED) {
            password = ""
            repeated = ""
            code = ""
            page = "login"
        }
    }
    Column(
        Modifier.widthIn(max = 760.dp).fillMaxWidth().testTag("account-screen"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (session.stage == AuthStage.GUEST) {
            val title =
                when (page) {
                    "register" -> authText(language, "Konto erstellen", "Створити акаунт")
                    "reset" -> authText(language, "Passwort zurücksetzen", "Відновити пароль")
                    else -> authText(language, "Anmelden", "Увійти")
                }
            val subtitle =
                when (page) {
                    "register" ->
                        authText(
                            language,
                            "Ein Konto für Ihre Community. Bitte bestätigen Sie die erforderlichen Angaben und Dokumente.",
                            "Акаунт для вашої спільноти. Підтвердьте потрібні дані та документи.",
                        )
                    "reset" ->
                        authText(
                            language,
                            "Fordern Sie mit Ihrer Konto-E-Mail einen Wiederherstellungslink an.",
                            "Запросіть посилання для відновлення на електронну пошту акаунта.",
                        )
                    else ->
                        authText(
                            language,
                            "Verwenden Sie Ihre Konto-E-Mail und Ihr Passwort.",
                            "Використайте електронну пошту та пароль акаунта.",
                        )
                }
            UacSectionCard(title, subtitle)
        } else
            Text(
                authText(language, "Dein Konto", "Ваш акаунт"),
                Modifier.semantics { heading() },
                style = MaterialTheme.typography.headlineSmall,
            )
        Text(
            authText(
                language,
                "Lokaler Kontotest · nur erfundene .invalid-Adressen",
                "Локальна перевірка акаунта · лише вигадані адреси .invalid",
            ),
            style = MaterialTheme.typography.labelMedium,
        )
        if (session.busy) LinearProgressIndicator(Modifier.fillMaxWidth().testTag("auth-loading"))
        session.error?.let { problem ->
            Text(
                problem.message(language),
                Modifier.testTag("auth-error").semantics { liveRegion = LiveRegionMode.Polite },
                color = MaterialTheme.colorScheme.error,
            )
        }
        session.notice?.let { notice ->
            Text(
                notice.message(language),
                Modifier.testTag("auth-notice").semantics { liveRegion = LiveRegionMode.Polite },
            )
        }
        when (session.stage) {
            AuthStage.RESTORING,
            AuthStage.AUTHENTICATING -> {
                Text(
                    authText(
                        language,
                        "Deine Sitzung wird sicher geprüft…",
                        "Безпечна перевірка вашого сеансу…",
                    ),
                    Modifier.testTag("auth-restoring"),
                )
                TextButton({ store.signOut() }, Modifier.testTag("auth-cancel")) {
                    Text(authText(language, "Abbrechen und abmelden", "Скасувати та вийти"))
                }
            }
            AuthStage.GUEST -> {
                UacCard {
                    if (onNavigateAuth == null)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            for ((route, de, uk) in
                                listOf(
                                    Triple("login", "Anmelden", "Увійти"),
                                    Triple("register", "Registrieren", "Реєстрація"),
                                    Triple("reset", "Passwort vergessen", "Забули пароль"),
                                )) {
                                FilterChip(
                                    page == route,
                                    {
                                        page = route
                                        store.clearMessage()
                                        password = ""
                                        repeated = ""
                                        code = ""
                                    },
                                    { Text(authText(language, de, uk)) },
                                    Modifier.testTag("auth-tab-$route"),
                                    enabled = !session.busy,
                                )
                            }
                        }
                    AuthField(
                        email,
                        { email = it },
                        authText(language, "E-Mail-Adresse", "Електронна пошта"),
                        "auth-email",
                        session.busy,
                        KeyboardType.Email,
                    )
                    if (page != "reset") {
                        AuthPassword(
                            password,
                            { password = it },
                            authText(language, "Passwort", "Пароль"),
                            "auth-password",
                            session.busy,
                        )
                    }
                    when (page) {
                        "register" -> {
                            AuthPassword(
                                repeated,
                                { repeated = it },
                                authText(language, "Passwort wiederholen", "Повторіть пароль"),
                                "auth-password-repeat",
                                session.busy,
                            )
                            Text(
                                authText(
                                    language,
                                    "10–128 Zeichen. Keine automatische Analyse oder Datenerfassung aktiviert.",
                                    "10–128 символів. Автоматичну аналітику або збір даних не ввімкнено.",
                                ),
                                style = MaterialTheme.typography.bodySmall,
                            )
                            RegistrationFields(
                                session.busy,
                                language,
                                referenceDocuments,
                                {
                                    document = it
                                    reference = true
                                },
                            ) { draft ->
                                store.register(
                                    draft.copy(email = email),
                                    password,
                                    repeated,
                                    language,
                                )
                            }
                        }
                        "reset" -> {
                            Button(
                                { store.sendPasswordReset(email, language) },
                                Modifier.fillMaxWidth()
                                    .heightIn(min = 48.dp)
                                    .testTag("auth-reset-submit"),
                                enabled = !session.busy,
                            ) {
                                Text(
                                    authText(
                                        language,
                                        "Link zum Zurücksetzen anfordern",
                                        "Запросити відновлення пароля",
                                    )
                                )
                            }
                            TextButton({ showLocalTools = !showLocalTools }) {
                                Text(
                                    authText(
                                        language,
                                        "Lokalen Wiederherstellungslink verwenden",
                                        "Використати локальне посилання відновлення",
                                    )
                                )
                            }
                            if (showLocalTools) {
                                AuthField(
                                    code,
                                    { code = it },
                                    authText(
                                        language,
                                        "Lokaler Link oder Code",
                                        "Локальне посилання або код",
                                    ),
                                    "auth-reset-code",
                                    session.busy,
                                )
                                AuthPassword(
                                    password,
                                    { password = it },
                                    authText(language, "Neues Passwort", "Новий пароль"),
                                    "auth-new-password",
                                    session.busy,
                                )
                                AuthPassword(
                                    repeated,
                                    { repeated = it },
                                    authText(language, "Passwort wiederholen", "Повторіть пароль"),
                                    "auth-new-password-repeat",
                                    session.busy,
                                )
                                Button(
                                    { store.confirmPasswordReset(code, password, repeated) },
                                    Modifier.testTag("auth-confirm-reset"),
                                    enabled = !session.busy,
                                ) {
                                    Text(
                                        authText(
                                            language,
                                            "Neues Passwort speichern",
                                            "Зберегти новий пароль",
                                        )
                                    )
                                }
                            }
                        }
                        else ->
                            Button(
                                { store.signIn(email, password) },
                                Modifier.fillMaxWidth()
                                    .heightIn(min = 48.dp)
                                    .testTag("auth-login-submit"),
                                enabled = !session.busy,
                            ) {
                                Text(authText(language, "Anmelden", "Увійти"))
                            }
                    }
                    if (onNavigateAuth != null) {
                        Column(
                            Modifier.fillMaxWidth(),
                            horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally,
                        ) {
                            for ((destination, de, uk) in
                                listOf(
                                    Triple("login", "Anmelden", "Увійти"),
                                    Triple("reset", "Passwort vergessen?", "Забули пароль?"),
                                    Triple(
                                        "register",
                                        "Sie brauchen ein Konto? Jetzt erstellen",
                                        "Ще немає акаунта? Створіть зараз",
                                    ),
                                )) {
                                if (destination != page)
                                    TextButton(
                                        {
                                            store.clearMessage()
                                            password = ""
                                            repeated = ""
                                            code = ""
                                            onNavigateAuth(destination)
                                        },
                                        Modifier.heightIn(min = 48.dp)
                                            .testTag("auth-tab-$destination"),
                                        enabled = !session.busy,
                                    ) {
                                        Text(authText(language, de, uk))
                                    }
                            }
                        }
                    }
                    Text(
                        authText(
                            language,
                            "Öffentliche Inhalte kannst du ohne Anmeldung lesen.",
                            "Публічні матеріали можна читати без входу.",
                        )
                    )
                }
            }
            AuthStage.VERIFICATION_PENDING -> {
                Text(
                    authText(
                        language,
                        "E-Mail-Adresse bestätigen",
                        "Підтвердьте електронну адресу",
                    ),
                    style = MaterialTheme.typography.titleLarge,
                )
                Text(session.identity?.email.orEmpty(), Modifier.testTag("auth-verification-email"))
                Text(
                    authText(
                        language,
                        "Nach der Bestätigung bleibt dein Konto auf diesem Gerät angemeldet. Persönliche Aktionen sind bis dahin gesperrt.",
                        "Після підтвердження акаунт залишиться в системі на цьому пристрої. Особисті дії поки недоступні.",
                    )
                )
                Button(
                    { store.checkVerification() },
                    Modifier.fillMaxWidth().testTag("auth-check-verification"),
                    enabled = !session.busy,
                ) {
                    Text(
                        authText(
                            language,
                            "Ich habe bestätigt · erneut prüfen",
                            "Я підтвердив(-ла) · перевірити",
                        )
                    )
                }
                OutlinedButton(
                    { store.resendVerification(language) },
                    Modifier.fillMaxWidth().testTag("auth-resend"),
                    enabled = !session.busy,
                ) {
                    Text(
                        authText(
                            language,
                            "Bestätigungslink erneut anfordern",
                            "Надіслати підтвердження ще раз",
                        )
                    )
                }
                TextButton({ showLocalTools = !showLocalTools }) {
                    Text(
                        authText(
                            language,
                            "Lokalen Bestätigungslink verwenden",
                            "Використати локальне посилання підтвердження",
                        )
                    )
                }
                if (showLocalTools) {
                    AuthField(
                        code,
                        { code = it },
                        authText(language, "Lokaler Link oder Code", "Локальне посилання або код"),
                        "auth-verification-code",
                        session.busy,
                    )
                    Button(
                        { store.applyVerificationCode(code) },
                        Modifier.testTag("auth-apply-verification"),
                        enabled = !session.busy,
                    ) {
                        Text(authText(language, "Bestätigen", "Підтвердити"))
                    }
                }
                SignOutButton(store, language)
            }
            AuthStage.SESSION_UNAVAILABLE -> {
                Text(
                    authText(
                        language,
                        "Sitzung vorübergehend nicht verfügbar",
                        "Сеанс тимчасово недоступний",
                    ),
                    Modifier.testTag("auth-unavailable"),
                    style = MaterialTheme.typography.titleLarge,
                )
                Text(
                    authText(
                        language,
                        "Dein Konto ist noch angemeldet, aber Profil und Berechtigungen konnten nicht sicher geladen werden. Es werden keine privaten Daten aus einer alten Sitzung angezeigt.",
                        "Ви ще в системі, але профіль і дозволи не вдалося безпечно завантажити. Приватні дані старого сеансу не показуються.",
                    )
                )
                Button(
                    { store.retryUnavailable() },
                    Modifier.testTag("auth-recover"),
                    enabled = !session.busy,
                ) {
                    Text(authText(language, "Sitzung wiederherstellen", "Відновити сеанс"))
                }
                SignOutButton(store, language)
            }
            AuthStage.MFA_CHALLENGE ->
                MfaChallengeFields(
                    session,
                    language,
                    { factor, value -> store.completeMfaChallenge(factor, value) },
                    { store.cancelMfa() },
                )
            AuthStage.AUTHENTICATED -> {
                Text(
                    session.profile?.displayName.orEmpty(),
                    Modifier.testTag("auth-profile-name"),
                    style = MaterialTheme.typography.titleLarge,
                )
                Text(session.profile?.email.orEmpty())
                when (session.gate) {
                    AuthGate.READY -> {
                        Text(
                            authText(
                                language,
                                "Angemeldet · E-Mail bestätigt",
                                "Вхід виконано · пошту підтверджено",
                            ),
                            Modifier.testTag("auth-ready"),
                        )
                        personalContent?.invoke(session)
                    }
                    AuthGate.RESTRICTED -> {
                        Text(
                            authText(
                                language,
                                "Dieses Konto ist eingeschränkt. Persönliche Aktionen sind nicht verfügbar.",
                                "Акаунт має обмеження. Особисті дії недоступні.",
                            ),
                            Modifier.testTag("auth-restricted"),
                        )
                        (session.profile?.statusReason ?: session.profile?.statusMessage)?.let {
                            Text(it)
                        }
                    }
                    AuthGate.MFA_REQUIRED ->
                        Text(
                            authText(
                                language,
                                "Geschütztes Konto: TOTP-Anmeldung und Aktivierung sind erforderlich. Lokale Tests ersetzen keinen echten zweiten Faktor.",
                                "Захищений акаунт: потрібні вхід TOTP та активація. Локальні тести не замінюють справжній другий фактор.",
                            ),
                            Modifier.testTag("auth-mfa-required"),
                        )
                    AuthGate.LEGAL_REQUIRED -> {
                        Text(
                            authText(
                                language,
                                "Bitte lies die aktuellen Dokumente. Persönliche Aktionen werden erst nach der serverseitigen Bestätigung freigegeben.",
                                "Прочитайте чинні документи. Особисті дії стануть доступними лише після підтвердження на сервері.",
                            ),
                            Modifier.testTag("auth-legal-required"),
                        )
                        LegalAcceptanceFields(
                            session,
                            language,
                            {
                                document = it
                                reference = false
                            },
                            { store.acceptLegalDocuments(it, language) },
                            { store.signOut() },
                        )
                    }
                    AuthGate.LEGAL_UNAVAILABLE ->
                        Text(
                            authText(
                                language,
                                "Die aktuelle rechtliche Version konnte nicht geprüft werden. Persönliche Aktionen bleiben bis zur Prüfung gesperrt.",
                                "Не вдалося перевірити чинну юридичну версію. Особисті дії заблоковані до перевірки.",
                            ),
                            Modifier.testTag("auth-legal-unavailable"),
                        )
                }
                if (session.profile?.active == true) AuthMfaPanel(store, session, language)
                OutlinedButton(
                    { store.refresh() },
                    Modifier.testTag("auth-refresh"),
                    enabled = !session.busy,
                ) {
                    Text(authText(language, "Sitzung aktualisieren", "Оновити сеанс"))
                }
                SignOutButton(store, language)
            }
        }
        HorizontalDivider()
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val useReference = session.legalDocuments.isEmpty()
            val readerDocuments = if (useReference) referenceDocuments else session.legalDocuments
            readerDocuments.take(2).forEach { legal ->
                TextButton(
                    {
                        document = legal
                        reference = useReference
                    },
                    Modifier.testTag("auth-legal-${legal.type}"),
                ) {
                    Text(legal.title(language))
                }
            }
        }
    }
    document?.let { AuthLegalReader(it, language, reference) { document = null } }
}

@Composable
internal fun LegalAcceptanceFields(
    session: AuthSession,
    language: String,
    read: (AuthLegalDocument) -> Unit,
    accept: (Map<String, String>) -> Unit,
    decline: () -> Unit,
) {
    val documents = session.requiredLegalDocuments()
    val versions = documents.associate { it.type to it.version }
    var confirmations by
        remember(session.identity?.uid, versions) { mutableStateOf(emptySet<String>()) }
    for (document in documents) {
        TextButton({ read(document) }, Modifier.testTag("auth-required-${document.type}-read")) {
            Text("${document.title(language)} · ${document.version}")
        }
        ConsentRow(
            document.type in confirmations,
            { selected ->
                confirmations =
                    if (selected) confirmations + document.type else confirmations - document.type
            },
            authText(
                language,
                "Ich stimme diesem Dokument zu (${document.version}).",
                "Я погоджуюся з цим документом (${document.version}).",
            ),
            "auth-accept-${document.type}",
            session.busy,
        )
    }
    Button(
        { accept(versions) },
        Modifier.fillMaxWidth().testTag("auth-legal-submit"),
        enabled =
            !session.busy && versions.isNotEmpty() && versions.keys.all { it in confirmations },
    ) {
        Text(authText(language, "Zustimmung sicher bestätigen", "Безпечно підтвердити згоду"))
    }
    TextButton(decline, Modifier.testTag("auth-legal-decline")) {
        Text(authText(language, "Ablehnen und abmelden", "Відмовитися та вийти"))
    }
}

@Composable
private fun RegistrationFields(
    busy: Boolean,
    language: String,
    documents: List<AuthLegalDocument>,
    read: (AuthLegalDocument) -> Unit,
    submit: (AuthRegistration) -> Unit,
) {
    var name by remember { mutableStateOf("") }
    var telegram by remember { mutableStateOf("") }
    var region by remember { mutableStateOf("") }
    var terms by remember { mutableStateOf(false) }
    var privacy by remember { mutableStateOf(false) }
    var age by remember { mutableStateOf(false) }
    AuthField(
        name,
        { name = it },
        authText(language, "Anzeigename", "Ім’я для показу"),
        "auth-name",
        busy,
    )
    AuthField(
        telegram,
        { telegram = it },
        authText(language, "Telegram (optional)", "Telegram (необов’язково)"),
        "auth-telegram",
        busy,
    )
    Choice(
        authText(language, "Bundesland", "Федеральна земля"),
        region,
        listOf("" to authText(language, "Bitte auswählen", "Оберіть")) + regions,
        "auth-region",
        { region = it },
    )
    for (legal in documents.take(2)) TextButton({ read(legal) }) { Text(legal.title(language)) }
    ConsentRow(
        terms,
        { terms = it },
        authText(
            language,
            "Ich akzeptiere die Nutzungsbedingungen (lokaler Test).",
            "Я погоджуюся з умовами користування (локальний тест).",
        ),
        "auth-terms",
        busy,
    )
    ConsentRow(
        privacy,
        { privacy = it },
        authText(
            language,
            "Ich habe die Datenschutzhinweise gelesen.",
            "Я ознайомився(-лась) з політикою конфіденційності.",
        ),
        "auth-privacy",
        busy,
    )
    ConsentRow(
        age,
        { age = it },
        authText(language, "Ich bin mindestens 14 Jahre alt.", "Мені щонайменше 14 років."),
        "auth-age",
        busy,
    )
    Button(
        { submit(AuthRegistration("", name, region, telegram, terms, privacy, age)) },
        Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("auth-register-submit"),
        enabled = !busy,
    ) {
        Text(authText(language, "Konto erstellen", "Створити акаунт"))
    }
}

@Composable
private fun ConsentRow(
    value: Boolean,
    change: (Boolean) -> Unit,
    text: String,
    tag: String,
    busy: Boolean,
) {
    Row(
        Modifier.fillMaxWidth()
            .testTag(tag)
            .toggleable(
                value = value,
                enabled = !busy,
                role = Role.Checkbox,
                onValueChange = change,
            ),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
    ) {
        Checkbox(value, null, enabled = !busy)
        Text(text, Modifier.weight(1f))
    }
}

@Composable
private fun AuthField(
    value: String,
    change: (String) -> Unit,
    label: String,
    tag: String,
    busy: Boolean,
    keyboard: KeyboardType = KeyboardType.Text,
) {
    OutlinedTextField(
        value,
        change,
        Modifier.fillMaxWidth().testTag(tag),
        label = { Text(label) },
        enabled = !busy,
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = keyboard),
    )
}

@Composable
private fun AuthPassword(
    value: String,
    change: (String) -> Unit,
    label: String,
    tag: String,
    busy: Boolean,
) {
    OutlinedTextField(
        value,
        change,
        Modifier.fillMaxWidth().testTag(tag),
        label = { Text(label) },
        enabled = !busy,
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
    )
}

@Composable
private fun SignOutButton(store: AuthStore, language: String) {
    TextButton({ store.signOut() }, Modifier.testTag("auth-signout")) {
        Text(authText(language, "Abmelden", "Вийти"))
    }
}
