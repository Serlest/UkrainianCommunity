package at.uac.android.feature.organization

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.error
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.core.ProtectedDropdownMenu as DropdownMenu
import at.uac.android.feature.auth.AuthLegalReader
import at.uac.android.feature.auth.AuthValidation
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun OrganizationScreen(
    model: OrganizationViewModel,
    session: OrganizationSession?,
    language: String,
    onBack: () -> Unit,
    onAccount: () -> Unit,
    onOpenOrganization: (String) -> Unit,
    initialRequestId: String? = null,
    onManageOrganization: ((String) -> Unit)? = null,
) {
    val snapshot by
        model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    val state = if (snapshot.session == session) snapshot else OrganizationState(session)
    val context = LocalContext.current
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
            model.pickerResult(context, uri)
        }
    LifecycleResumeEffect(session, initialRequestId) {
        model.show(initialRequestId)
        onPauseOrDispose { model.hide() }
    }
    OrganizationContent(
        state,
        language,
        onBack,
        onAccount,
        onOpenOrganization,
        { model.refresh() },
        model::create,
        model::edit,
        model::change,
        model::consent,
        {
            if (model.beginPicker())
                try {
                    picker.launch(
                        PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                    )
                } catch (_: Exception) {
                    model.pickerUnavailable()
                }
        },
        model::removeLogoSelection,
        model::closeDraft,
        { model.submit(language) },
        model::discard,
        onManageOrganization,
    )
}

@Composable
fun OrganizationContent(
    state: OrganizationState,
    language: String,
    onBack: () -> Unit,
    onAccount: () -> Unit,
    onOpenOrganization: (String) -> Unit,
    onRefresh: () -> Unit,
    onCreate: () -> Unit,
    onEdit: (OrganizationRecord) -> Unit,
    onChange: ((OrganizationDraft) -> OrganizationDraft) -> Unit,
    onConsent: (Boolean) -> Unit,
    onLogo: () -> Unit,
    onRemoveLogo: () -> Unit,
    onCloseDraft: () -> Unit,
    onSubmit: () -> Unit,
    onDiscard: (OrganizationRecord) -> Unit,
    onManageOrganization: ((String) -> Unit)? = null,
) {
    var discard by remember(state.session) { mutableStateOf<OrganizationRecord?>(null) }
    var closeDraft by remember(state.session) { mutableStateOf(false) }
    var reader by remember(state.session) { mutableStateOf(false) }
    Column(
        Modifier.fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
            .testTag("organization-hub"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        TextButton(onBack) { Text(tr(language, "Zurück", "Назад")) }
        Text(
            tr(language, "Meine Organisationen", "Мої організації"),
            style = MaterialTheme.typography.headlineMedium,
        )
        if (state.session?.ready != true) {
            Text(
                tr(
                    language,
                    "Für eigene Anträge benötigst du ein bestätigtes, aktives Konto und aktuelle Zustimmungen.",
                    "Для власних заявок потрібні підтверджений активний акаунт та актуальні згоди.",
                )
            )
            Button(onAccount, Modifier.testTag("organization-account")) {
                Text(tr(language, "Konto öffnen", "Відкрити акаунт"))
            }
        } else {
            state.error?.let {
                Text(
                    organizationFailureText(it, language),
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.testTag("organization-error"),
                )
            }
            if (state.loading || state.busy)
                CircularProgressIndicator(Modifier.testTag("organization-loading"))
            TextButton(
                onRefresh,
                enabled = !state.busy,
                modifier = Modifier.testTag("organization-refresh"),
            ) {
                Text(tr(language, "Aktualisieren", "Оновити"))
            }
            if (state.targetId != null)
                Card(Modifier.fillMaxWidth().testTag("organization-target")) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            tr(language, "Antrag aus der Mitteilung", "Заявка з повідомлення"),
                            style = MaterialTheme.typography.titleMedium,
                        )
                        if (state.loading)
                            Text(
                                tr(
                                    language,
                                    "Aktuellen Antrag prüfen…",
                                    "Перевірка актуальної заявки…",
                                )
                            )
                        else if (state.targetFailure != null)
                            Text(
                                organizationFailureText(state.targetFailure, language),
                                modifier = Modifier.testTag("organization-target-unavailable"),
                            )
                        else
                            state.target?.let { target ->
                                Text(target.name)
                                if (target.status == "approved") {
                                    Text(
                                        tr(
                                            language,
                                            "Genehmigt. Dieser Antrag ist nur noch lesbar.",
                                            "Схвалено. Ця заявка доступна лише для перегляду.",
                                        ),
                                        modifier = Modifier.testTag("organization-target-approved"),
                                    )
                                    TextButton(
                                        { onOpenOrganization(target.id) },
                                        Modifier.testTag("organization-target-public"),
                                    ) {
                                        Text(
                                            tr(language, "Öffentliches Profil", "Публічний профіль")
                                        )
                                    }
                                } else if (target.editable(state.session))
                                    TextButton(
                                        { onEdit(target) },
                                        enabled = !state.busy,
                                        modifier = Modifier.testTag("organization-target-edit"),
                                    ) {
                                        Text(
                                            tr(
                                                language,
                                                "Aktuellen Antrag öffnen",
                                                "Відкрити актуальну заявку",
                                            )
                                        )
                                    }
                            }
                    }
                }
            state.hub?.let { hub ->
                if (hub.truncated)
                    Text(
                        tr(
                            language,
                            "Es werden bis zu 50 Einträge je Bereich angezeigt.",
                            "Показано до 50 записів кожного розділу.",
                        )
                    )
                if (hub.managed.isNotEmpty()) {
                    Text(
                        tr(language, "Zuständigkeiten", "Повноваження"),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    hub.managed.forEach { row ->
                        Card(Modifier.fillMaxWidth()) {
                            Column(
                                Modifier.padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(row.name, style = MaterialTheme.typography.titleMedium)
                                Text(authorityText(row.authority, language))
                                Text(
                                    tr(
                                        language,
                                        "Rolle aus dem aktuellen Organisationsprofil.",
                                        "Роль з актуального профілю організації.",
                                    ),
                                    style = MaterialTheme.typography.bodySmall,
                                )
                                TextButton({ onOpenOrganization(row.id) }) {
                                    Text(tr(language, "Öffentliches Profil", "Публічний профіль"))
                                }
                                onManageOrganization?.let { manage ->
                                    TextButton(
                                        { manage(row.id) },
                                        enabled = !state.loading && !state.busy,
                                        modifier =
                                            Modifier.testTag("organization-manage-${row.id}"),
                                    ) {
                                        Text(
                                            tr(language, "Verwaltung öffnen", "Відкрити керування")
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                Text(
                    tr(language, "Meine Anträge", "Мої заявки"),
                    style = MaterialTheme.typography.titleLarge,
                )
                if (hub.requests.isEmpty())
                    Text(tr(language, "Keine offenen Anträge.", "Немає відкритих заявок."))
                hub.requests.forEach { row ->
                    OrganizationRequestCard(
                        row,
                        state.session,
                        language,
                        state.busy,
                        { onEdit(row) },
                        { discard = row },
                    )
                }
                Button(
                    onCreate,
                    enabled = !state.busy && state.draft == null && hub.requests.size < 3,
                    modifier = Modifier.testTag("organization-create"),
                ) {
                    Text(tr(language, "Organisation beantragen", "Подати заявку організації"))
                }
                if (hub.requests.size >= 3)
                    Text(organizationFailureText(OrganizationFailure.LIMIT, language))
            }
            state.draft?.let { draft ->
                val formIssues = remember(draft) { organizationFormIssues(draft) }
                HorizontalDivider()
                Text(
                    if (state.base == null) tr(language, "Neuer Antrag", "Нова заявка")
                    else tr(language, "Antrag überarbeiten", "Виправити заявку"),
                    style = MaterialTheme.typography.titleLarge,
                )
                state.editorFailure?.let {
                    Text(
                        organizationFailureText(it, language),
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.testTag("organization-editor-readonly"),
                    )
                }
                OrganizationEditor(draft, language, state.busy || !state.editorWritable, onChange)
                TextButton(
                    onLogo,
                    enabled = state.editorWritable && !state.busy && !state.imageLoading,
                    modifier = Modifier.testTag("organization-logo"),
                ) {
                    Text(
                        tr(language, "Logo auswählen (optional)", "Обрати логотип (необов’язково)")
                    )
                }
                if (state.imageLoading) CircularProgressIndicator()
                if (state.logoSelected) {
                    val preview =
                        remember(state.logoPreview) {
                            state.logoPreview?.copyBytes()?.let {
                                BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap()
                            }
                        }
                    preview?.let {
                        Image(
                            it,
                            tr(
                                language,
                                "Vorschau des vorbereiteten Logos",
                                "Попередній перегляд підготовленого логотипа",
                            ),
                            Modifier.size(160.dp).testTag("organization-logo-preview"),
                        )
                    }
                    Text(
                        tr(
                            language,
                            "Logo vorbereitet; Metadaten werden nicht hochgeladen.",
                            "Логотип підготовлено; метадані не завантажуються.",
                        )
                    )
                    TextButton(onRemoveLogo, enabled = !state.busy) {
                        Text(tr(language, "Auswahl entfernen", "Прибрати вибране"))
                    }
                }
                if (state.base == null) {
                    state.rules?.let { rules ->
                        TextButton(
                            { reader = true },
                            Modifier.testTag("organization-rules-reader"),
                        ) {
                            Text(rules.title(language) + " · " + rules.version)
                        }
                        val consentEnabled = !state.busy && state.editorWritable
                        val consentChecked = draft.acceptedRulesVersion == rules.version
                        Row(
                            Modifier.fillMaxWidth()
                                .heightIn(min = 48.dp)
                                .testTag("organization-consent")
                                .toggleable(
                                    value = consentChecked,
                                    enabled = consentEnabled,
                                    role = Role.Checkbox,
                                    onValueChange = onConsent,
                                ),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Checkbox(
                                consentChecked,
                                onCheckedChange = null,
                                enabled = consentEnabled,
                            )
                            Text(
                                tr(
                                    language,
                                    "Ich habe diese Organisationsregeln gelesen und stimme ihnen für diesen Antrag zu.",
                                    "Я прочитав(-ла) ці правила організацій і погоджуюся з ними для цієї заявки.",
                                ),
                                Modifier.weight(1f).padding(vertical = 12.dp),
                            )
                        }
                    } ?: Text(organizationFailureText(OrganizationFailure.LEGAL_CHANGED, language))
                }
                if (state.logoIncomplete)
                    Text(organizationFailureText(OrganizationFailure.LOGO_INCOMPLETE, language))
                if (state.confirmedId == draft.id)
                    Text(
                        tr(
                            language,
                            "Antrag vom Server bestätigt.",
                            "Заявку підтверджено сервером.",
                        ),
                        Modifier.testTag("organization-confirmed"),
                    )
                if (
                    state.editorWritable &&
                        !state.busy &&
                        !state.imageLoading &&
                        (state.base != null ||
                            (state.rules != null &&
                                draft.acceptedRulesVersion == state.rules.version))
                ) {
                    formIssues.values.firstOrNull()?.let { issue ->
                        val message = organizationFormIssueText(issue, language)
                        Text(
                            message,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier =
                                Modifier.testTag("organization-submit-reason").semantics {
                                    error(message)
                                },
                        )
                    }
                }
                Button(
                    onSubmit,
                    enabled =
                        state.editorWritable &&
                            !state.busy &&
                            !state.imageLoading &&
                            (state.base != null || state.rules != null) &&
                            runCatching { OrganizationContract.validate(draft) }.isSuccess &&
                            (state.base != null ||
                                draft.acceptedRulesVersion == state.rules?.version),
                    modifier = Modifier.testTag("organization-submit"),
                ) {
                    Text(
                        if (state.base?.status in setOf("needsRevision", "rejected"))
                            tr(language, "Erneut einreichen", "Надіслати повторно")
                        else if (state.base != null)
                            tr(language, "Änderungen speichern", "Зберегти зміни")
                        else tr(language, "Zur Prüfung einreichen", "Надіслати на перевірку")
                    )
                }
                TextButton(
                    { closeDraft = true },
                    enabled = !state.busy,
                    modifier = Modifier.testTag("organization-close-draft"),
                ) {
                    Text(tr(language, "Formular schließen", "Закрити форму"))
                }
            }
        }
        Spacer(Modifier.height(20.dp))
    }
    if (reader && state.rules != null)
        AuthLegalReader(state.rules, language, reference = true) { reader = false }
    discard?.let { row ->
        AlertDialog(
            onDismissRequest = { discard = null },
            title = {
                Text(tr(language, "Antrag endgültig verwerfen?", "Остаточно видалити заявку?"))
            },
            text = {
                Text(
                    row.name +
                        "\n" +
                        tr(
                            language,
                            "Der Antrag und seine hochgeladenen Dateien werden gelöscht. Diese Aktion ist nicht rückgängig zu machen.",
                            "Заявку та її завантажені файли буде видалено. Цю дію не можна скасувати.",
                        )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        discard = null
                        onDiscard(row)
                    },
                    enabled = !state.busy,
                    modifier = Modifier.testTag("organization-confirm-discard"),
                ) {
                    Text(tr(language, "Verwerfen", "Видалити"))
                }
            },
            dismissButton = {
                TextButton({ discard = null }) { Text(tr(language, "Behalten", "Залишити")) }
            },
        )
    }
    if (closeDraft)
        AlertDialog(
            onDismissRequest = { closeDraft = false },
            title = { Text(tr(language, "Formular schließen?", "Закрити форму?")) },
            text = {
                Text(
                    tr(
                        language,
                        "Ungespeicherte Eingaben werden verworfen. Bereits bestätigte Anträge bleiben erhalten.",
                        "Незбережені зміни буде втрачено. Підтверджені заявки залишаться.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        closeDraft = false
                        onCloseDraft()
                    },
                    Modifier.testTag("organization-confirm-close-draft"),
                ) {
                    Text(tr(language, "Schließen", "Закрити"))
                }
            },
            dismissButton = {
                TextButton({ closeDraft = false }) {
                    Text(tr(language, "Weiter bearbeiten", "Продовжити"))
                }
            },
        )
}

@Composable
private fun OrganizationRequestCard(
    row: OrganizationRecord,
    session: OrganizationSession,
    language: String,
    busy: Boolean,
    edit: () -> Unit,
    discard: () -> Unit,
) {
    Card(Modifier.fillMaxWidth().testTag("organization-request-${row.id}")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(row.name, style = MaterialTheme.typography.titleMedium)
            Text(
                when (row.status) {
                    "pendingReview" -> tr(language, "In Prüfung", "На перевірці")
                    "needsRevision" ->
                        tr(language, "Änderungen erforderlich", "Потрібні виправлення")
                    "rejected" -> tr(language, "Abgelehnt", "Відхилено")
                    else -> tr(language, "Nicht verfügbar", "Недоступно")
                }
            )
            row.reviewMessage?.let { Text(it) }
            row.rejectionReason?.let { Text(it) }
            if (row.status in setOf("needsRevision", "rejected")) {
                Text(
                    tr(
                        language,
                        "Ohne Überarbeitung ist die automatische Löschung ab ",
                        "Без виправлень автоматичне видалення можливе з ",
                    ) +
                        DateTimeFormatter.ofPattern("dd.MM.yyyy")
                            .withZone(ZoneId.systemDefault())
                            .format(row.deletionDueAt),
                    style = MaterialTheme.typography.bodySmall,
                )
                if (row.retention(Instant.now()) != RequestRetention.ACTIVE)
                    Text(
                        tr(
                            language,
                            "Bitte zeitnah überarbeiten oder verwerfen. Der Server entscheidet, ob der Antrag noch verfügbar ist.",
                            "Виправте або видаліть заявку найближчим часом. Її доступність визначає сервер.",
                        ),
                        color = MaterialTheme.colorScheme.error,
                    )
            }
            if (row.editable(session)) {
                TextButton(
                    edit,
                    enabled = !busy,
                    modifier = Modifier.testTag("organization-edit-${row.id}"),
                ) {
                    Text(tr(language, "Überarbeiten", "Виправити"))
                }
                if (session.globalRole != "owner")
                    TextButton(
                        discard,
                        enabled = !busy,
                        modifier = Modifier.testTag("organization-discard-${row.id}"),
                    ) {
                        Text(tr(language, "Antrag verwerfen", "Видалити заявку"))
                    }
            }
        }
    }
}

@Composable
internal fun OrganizationEditor(
    d: OrganizationDraft,
    language: String,
    busy: Boolean,
    change: ((OrganizationDraft) -> OrganizationDraft) -> Unit,
) {
    val issues = remember(d) { organizationFormIssues(d) }
    var touched by remember(d.id) { mutableStateOf(emptySet<OrganizationFormField>()) }
    fun text(
        label: String,
        value: String,
        tag: String,
        lines: Int = 1,
        update: (OrganizationDraft, String) -> OrganizationDraft,
    ): @Composable () -> Unit = {
        val field = OrganizationFormField.entries.first { it.tag == tag }
        val issue = issues[field]?.takeIf { !busy && (field in touched || value.isNotBlank()) }
        val message = issue?.let { organizationFormIssueText(it, language) }
        OutlinedTextField(
            value,
            { value ->
                touched = touched + field
                change { update(it, value) }
            },
            label = { Text(label) },
            enabled = !busy,
            isError = issue != null,
            supportingText =
                if (message == null) null
                else {
                    { Text(message, Modifier.testTag("$tag-issue")) }
                },
            modifier =
                Modifier.fillMaxWidth().testTag(tag).semantics { message?.let { error(it) } },
            minLines = lines,
            maxLines = if (lines > 1) 8 else 2,
        )
    }
    text(
        tr(language, "Name (Ukrainisch / Original)", "Назва (українською / оригінал)"),
        d.name,
        "organization-name",
    ) { old, value ->
        old.copy(name = value)
    }()
    text(
        tr(language, "Kurzbeschreibung · 20–160 Zeichen", "Короткий опис · 20–160 символів"),
        d.summary,
        "organization-summary",
        3,
    ) { old, value ->
        old.copy(summary = value)
    }()
    text(
        tr(
            language,
            "Ausführliche Beschreibung · bis 1200 Zeichen",
            "Повний опис · до 1200 символів",
        ),
        d.details,
        "organization-details",
        3,
    ) { old, value ->
        old.copy(details = value)
    }()
    Choice(
        tr(language, "Bundesland", "Федеральна земля"),
        d.region,
        AuthValidation.regions.toList(),
        !busy,
        displayLabel = { organizationRegionLabel(it, language) },
        tag = OrganizationFormField.REGION.tag,
        issue =
            issues[OrganizationFormField.REGION]
                ?.takeIf { !busy && d.region.isNotEmpty() }
                ?.let { organizationFormIssueText(it, language) },
    ) { value ->
        change { it.copy(region = value) }
    }
    text(tr(language, "Ort", "Місто"), d.city, "organization-city") { old, value ->
        old.copy(city = value)
    }()
    Choice(
        tr(language, "Profilart", "Тип профілю"),
        d.profileKind,
        OrganizationContract.profileKinds,
        !busy,
        displayLabel = { organizationProfileKindLabel(it, language) },
        tag = OrganizationFormField.PROFILE_KIND.tag,
        issue =
            issues[OrganizationFormField.PROFILE_KIND]
                ?.takeIf { !busy }
                ?.let { organizationFormIssueText(it, language) },
    ) { value ->
        change { it.copy(profileKind = value) }
    }
    text("E-Mail", d.email, "organization-email") { old, value -> old.copy(email = value) }()
    text(tr(language, "Telefon", "Телефон"), d.phone, "organization-phone") { old, value ->
        old.copy(phone = value)
    }()
    text("Website", d.website, "organization-website") { old, value -> old.copy(website = value) }()
    text(tr(language, "Adresse", "Адреса"), d.address, "organization-address") { old, value ->
        old.copy(address = value)
    }()
    Text(
        tr(language, "Deutsche Übersetzung (optional)", "Переклад німецькою (необов’язково)"),
        style = MaterialTheme.typography.titleMedium,
    )
    text("Name · Deutsch", d.germanName, "organization-de-name") { old, value ->
        old.copy(germanName = value)
    }()
    text("Kurzbeschreibung · Deutsch", d.germanSummary, "organization-de-summary", 2) { old, value
        ->
        old.copy(germanSummary = value)
    }()
    text("Beschreibung · Deutsch", d.germanDetails, "organization-de-details", 3) { old, value ->
        old.copy(germanDetails = value)
    }()
}

@Composable
private fun Choice(
    label: String,
    value: String,
    values: List<String>,
    enabled: Boolean,
    displayLabel: (String) -> String,
    tag: String,
    issue: String? = null,
    change: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth()) {
        Box {
            OutlinedButton(
                { expanded = true },
                enabled = enabled,
                modifier =
                    Modifier.fillMaxWidth().testTag(tag).semantics { issue?.let { error(it) } },
            ) {
                Text("$label: ${displayLabel(value)}")
            }
            DropdownMenu(expanded && enabled, { expanded = false }) {
                values.forEach { entry ->
                    DropdownMenuItem(
                        text = { Text(displayLabel(entry)) },
                        modifier = Modifier.testTag("$tag-$entry"),
                        onClick = {
                            expanded = false
                            change(entry)
                        },
                    )
                }
            }
        }
        issue?.let {
            Text(
                it,
                Modifier.testTag("$tag-issue"),
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
            )
        }
    }
}

fun organizationFailureText(failure: OrganizationFailure, language: String): String =
    when (failure) {
        OrganizationFailure.SIGN_IN -> tr(language, "Bitte anmelden.", "Увійдіть в акаунт.")
        OrganizationFailure.NOT_READY ->
            tr(
                language,
                "Bitte Kontostatus, E-Mail, Zustimmungen und Sicherheitsanforderungen prüfen.",
                "Перевірте стан акаунта, пошту, згоди та вимоги безпеки.",
            )
        OrganizationFailure.INVALID ->
            tr(
                language,
                "Bitte Namen, Beschreibung, Region, Kontaktangaben und Bildformat prüfen.",
                "Перевірте назву, опис, регіон, контакти та формат зображення.",
            )
        OrganizationFailure.DENIED ->
            tr(
                language,
                "Für diesen Antrag ist die Aktion nicht erlaubt.",
                "Цю дію для заявки не дозволено.",
            )
        OrganizationFailure.OFFLINE ->
            tr(
                language,
                "Server nicht erreichbar. Es wird nicht automatisch erneut gesendet.",
                "Сервер недоступний. Автоматичного повторного надсилання немає.",
            )
        OrganizationFailure.MISSING ->
            tr(
                language,
                "Der Antrag ist nicht mehr verfügbar; möglicherweise wurde er gelöscht oder abgelaufen.",
                "Заявка більше недоступна: її могли видалити після завершення строку.",
            )
        OrganizationFailure.STALE ->
            tr(
                language,
                "Der Antrag wurde inzwischen geändert. Bitte aktualisieren und erneut öffnen.",
                "Заявку вже змінено. Оновіть список і відкрийте її знову.",
            )
        OrganizationFailure.LIMIT ->
            tr(
                language,
                "Maximal drei offene Anträge. Bitte zuerst einen bestehenden Antrag klären oder verwerfen.",
                "Максимум три відкриті заявки. Спочатку завершіть або видаліть наявну.",
            )
        OrganizationFailure.LEGAL_CHANGED ->
            tr(
                language,
                "Die aktuellen Organisationsregeln müssen neu geladen und gelesen werden.",
                "Потрібно завантажити й прочитати актуальні правила організацій.",
            )
        OrganizationFailure.CONSENT ->
            tr(
                language,
                "Bitte den angezeigten Organisationsregeln ausdrücklich zustimmen.",
                "Потрібна явна згода з показаними правилами організацій.",
            )
        OrganizationFailure.UNCONFIRMED ->
            tr(
                language,
                "Ergebnis noch nicht bestätigt. Bitte aktualisieren; die gleiche Antragskennung bleibt erhalten.",
                "Результат ще не підтверджено. Оновіть стан; ідентифікатор заявки залишається тим самим.",
            )
        OrganizationFailure.LOGO_INCOMPLETE ->
            tr(
                language,
                "Der Antrag ist gespeichert, das Logo aber noch nicht bestätigt. Auswahl prüfen und ausdrücklich erneut speichern.",
                "Заявку збережено, але логотип ще не підтверджено. Перевірте вибране і явно збережіть повторно.",
            )
        OrganizationFailure.UNKNOWN ->
            tr(
                language,
                "Aktion nicht bestätigt. Bitte den aktuellen Stand laden.",
                "Дію не підтверджено. Завантажте актуальний стан.",
            )
    }

private fun authorityText(authority: OrganizationAuthority, language: String): String =
    when (authority) {
        OrganizationAuthority.PLATFORM_OWNER ->
            tr(language, "Plattforminhaber", "Власник платформи")
        OrganizationAuthority.OWNER -> tr(language, "Organisationsinhaber", "Власник організації")
        OrganizationAuthority.ADMIN ->
            tr(language, "Organisationsadministrator", "Адміністратор організації")
        OrganizationAuthority.MODERATOR ->
            tr(language, "Organisationsmoderator", "Модератор організації")
        OrganizationAuthority.NONE -> tr(language, "Keine Verwaltungsrolle", "Немає ролі керування")
    }

private fun tr(language: String, german: String, ukrainian: String) =
    if (language == "uk") ukrainian else german
