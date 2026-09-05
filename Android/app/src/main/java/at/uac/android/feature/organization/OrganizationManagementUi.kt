package at.uac.android.feature.organization

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.core.PickerLocale
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.core.ProtectedDialog
import at.uac.android.core.ProtectedDropdownMenu as DropdownMenu
import at.uac.android.feature.authoring.AuthoringContract
import at.uac.android.feature.browse.ContentKind
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

data class OrganizationManagementActions(
    val back: () -> Unit = {},
    val account: () -> Unit = {},
    val publicProfile: () -> Unit = {},
    val refresh: () -> Unit = {},
    val more: () -> Unit = {},
    val edit: () -> Unit = {},
    val change: ((OrganizationInformationDraft) -> OrganizationInformationDraft) -> Unit = {},
    val logo: () -> Unit = {},
    val removeLogo: () -> Unit = {},
    val closeEditor: () -> Unit = {},
    val save: () -> Unit = {},
    val choose: (String, OrganizationTeamAction) -> Unit = { _, _ -> },
    val confirm: () -> Unit = {},
    val dismiss: () -> Unit = {},
    val acknowledge: () -> Unit = {},
    val authoring: ((ContentKind) -> Unit)? = null,
)

@Composable
fun OrganizationManagementScreen(
    model: OrganizationManagementViewModel,
    organizationId: String,
    session: OrganizationSession?,
    language: String,
    onBack: () -> Unit,
    onAccount: () -> Unit,
    onOpenOrganization: (String) -> Unit,
    onAuthoring: ((ContentKind) -> Unit)? = null,
) {
    val stored by model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    val state =
        if (stored.session == session && stored.organizationId == organizationId) stored
        else OrganizationManagementState(session, organizationId)
    val context = LocalContext.current
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) {
            model.pickerResult(context, it)
        }
    LifecycleResumeEffect(session, organizationId) {
        model.show(organizationId)
        onPauseOrDispose { model.hide() }
    }
    OrganizationManagementContent(
        state,
        language,
        OrganizationManagementActions(
            onBack,
            onAccount,
            { onOpenOrganization(organizationId) },
            model::refresh,
            model::more,
            model::edit,
            model::change,
            {
                if (model.beginPicker())
                    try {
                        picker.launch(
                            PickVisualMediaRequest(
                                ActivityResultContracts.PickVisualMedia.ImageOnly
                            )
                        )
                    } catch (_: Exception) {
                        model.pickerUnavailable()
                    }
            },
            model::removeLogo,
            model::closeEditor,
            model::save,
            model::choose,
            model::confirm,
            model::dismissConfirmation,
            model::acknowledgeUncertain,
            onAuthoring,
        ),
    )
}

@Composable
fun OrganizationManagementContent(
    state: OrganizationManagementState,
    language: String,
    actions: OrganizationManagementActions,
) {
    var close by remember(state.session, state.organizationId) { mutableStateOf(false) }
    val session = state.session
    val snapshot = state.snapshot
    Column(
        Modifier.fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
            .testTag("organization-management"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        TextButton(actions.back) { Text(om(language, "Zurück", "Назад")) }
        Text(
            om(language, "Organisation verwalten", "Керування організацією"),
            style = MaterialTheme.typography.headlineMedium,
        )
        if (session?.ready != true) {
            Text(
                om(
                    language,
                    "Ein bestätigtes, aktives Konto mit erfüllten Sicherheitsanforderungen ist erforderlich.",
                    "Потрібен підтверджений активний акаунт з виконаними вимогами безпеки.",
                )
            )
            Button(actions.account, Modifier.testTag("organization-management-account")) {
                Text(om(language, "Konto öffnen", "Відкрити акаунт"))
            }
        } else {
            state.error?.let {
                Text(
                    organizationManagementFailureText(it, language),
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.testTag("organization-management-error"),
                )
            }
            if (state.loading || state.busy) CircularProgressIndicator()
            TextButton(
                actions.refresh,
                enabled = !state.busy && !state.loading,
                modifier = Modifier.testTag("organization-management-refresh"),
            ) {
                Text(om(language, "Aktualisieren", "Оновити"))
            }
            if (snapshot != null) {
                Text(snapshot.organization.name, style = MaterialTheme.typography.titleLarge)
                TextButton(actions.publicProfile) {
                    Text(om(language, "Öffentliches Profil", "Публічний профіль"))
                }
                if (
                    state.draft == null &&
                        actions.authoring != null &&
                        runCatching { AuthoringContract.authority(snapshot.organization, session) }
                            .isSuccess
                ) {
                    AuthoringContract.kinds.forEach { kind ->
                        OutlinedButton(
                            { actions.authoring.invoke(kind) },
                            enabled = state.actionable,
                            modifier =
                                Modifier.testTag("organization-authoring-${kind.collection}"),
                        ) {
                            Text(kind.label(language))
                        }
                    }
                }
                if (!state.fresh)
                    Text(
                        om(
                            language,
                            "Aktionen bleiben gesperrt, bis der Server den aktuellen Stand bestätigt.",
                            "Дії заблоковано до підтвердження актуального стану сервером.",
                        )
                    )
                if (state.confirmed)
                    Text(
                        om(
                            language,
                            "Aktueller Stand vom Server bestätigt.",
                            "Актуальний стан підтверджено сервером.",
                        ),
                        Modifier.testTag("organization-management-confirmed"),
                    )
                if (OrganizationManagementContract.canEdit(snapshot.organization, session)) {
                    Button(
                        actions.edit,
                        enabled = state.editable,
                        modifier = Modifier.testTag("organization-management-edit"),
                    ) {
                        Text(
                            if (state.draft == null)
                                om(language, "Informationen bearbeiten", "Редагувати інформацію")
                            else
                                om(
                                    language,
                                    "Aktuelle Version neu öffnen",
                                    "Відкрити актуальну версію знову",
                                )
                        )
                    }
                }
                state.draft?.let { draft ->
                    HorizontalDivider()
                    Text(
                        om(language, "Organisationsprofil", "Профіль організації"),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    if (!state.draftWritable && !state.busy)
                        Text(
                            om(
                                language,
                                "Diese Formularversion ist schreibgeschützt. Aktuellen Stand laden und erneut öffnen; ungespeicherter Text bleibt sichtbar.",
                                "Ця версія форми лише для перегляду. Завантажте актуальний стан і відкрийте знову; незбережений текст залишається видимим.",
                            ),
                            Modifier.testTag("organization-management-readonly"),
                        )
                    OrganizationEditor(draft.basics, language, !state.draftWritable) { transform ->
                        actions.change { it.copy(basics = transform(it.basics)) }
                    }
                    OrganizationInformationExtras(
                        draft,
                        language,
                        state.draftWritable,
                        actions.change,
                    )
                    TextButton(
                        actions.logo,
                        enabled = state.draftWritable && !state.imageLoading,
                        modifier = Modifier.testTag("organization-management-logo"),
                    ) {
                        Text(om(language, "Logo auswählen", "Обрати логотип"))
                    }
                    if (state.imageLoading) CircularProgressIndicator()
                    state.logoPreview?.let { selected ->
                        val preview =
                            remember(selected) {
                                selected.copyBytes().let {
                                    BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap()
                                }
                            }
                        preview?.let {
                            Image(
                                it,
                                om(
                                    language,
                                    "Vorbereitete Logo-Vorschau",
                                    "Перегляд підготовленого логотипа",
                                ),
                                Modifier.size(160.dp)
                                    .testTag("organization-management-logo-preview"),
                            )
                        }
                        TextButton(actions.removeLogo, enabled = !state.busy) {
                            Text(om(language, "Auswahl entfernen", "Прибрати вибране"))
                        }
                    }
                    if (state.logoIncomplete)
                        Text(
                            om(
                                language,
                                "Informationen gespeichert. Logo nicht bestätigt; bitte aktuellen Stand prüfen und bei Bedarf erneut auswählen.",
                                "Інформацію збережено. Логотип не підтверджено; перевірте актуальний стан та за потреби оберіть знову.",
                            )
                        )
                    Button(
                        actions.save,
                        enabled =
                            state.draftWritable &&
                                !state.imageLoading &&
                                state.base?.let {
                                    runCatching {
                                        OrganizationManagementContract.informationFields(
                                            draft,
                                            it,
                                        )
                                    }
                                        .isSuccess
                                } == true,
                        modifier = Modifier.testTag("organization-management-save"),
                    ) {
                        Text(om(language, "Änderungen speichern", "Зберегти зміни"))
                    }
                    TextButton({ close = true }, enabled = !state.busy) {
                        Text(om(language, "Formular schließen", "Закрити форму"))
                    }
                }
                HorizontalDivider()
                Text(
                    om(language, "Team und Abonnenten", "Команда та підписники"),
                    style = MaterialTheme.typography.titleLarge,
                )
                Text(
                    om(
                        language,
                        "Rollen stammen aus dem aktuellen Organisationsprofil. Es werden nur öffentliche Namen und Orte angezeigt.",
                        "Ролі взято з актуального профілю організації. Показано лише публічні імена та міста.",
                    ),
                    style = MaterialTheme.typography.bodySmall,
                )
                state.uncertain?.let {
                    Text(
                        organizationManagementFailureText(
                            OrganizationManagementFailure.UNCONFIRMED,
                            language,
                        ),
                        Modifier.testTag("organization-management-uncertain"),
                    )
                    TextButton(
                        actions.acknowledge,
                        enabled = state.actionable,
                        modifier = Modifier.testTag("organization-management-new-decision"),
                    ) {
                        Text(
                            om(
                                language,
                                "Aktuellen Stand geprüft · neue Entscheidung",
                                "Актуальний стан перевірено · нове рішення",
                            )
                        )
                    }
                }
                if (snapshot.teamTruncated)
                    Text(
                        om(
                            language,
                            "Die ersten 200 Teamprofile werden angezeigt. Die vollständigen Rollen bleiben serverseitig unverändert.",
                            "Показано перші 200 профілів команди. Повні ролі на сервері не змінюються.",
                        )
                    )
                snapshot.members.forEach { member ->
                    Card(
                        Modifier.fillMaxWidth().testTag("organization-team-${member.profile.id}")
                    ) {
                        Column(
                            Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Text(
                                member.profile.displayName
                                    ?: om(
                                        language,
                                        "Profil nicht verfügbar",
                                        "Профіль недоступний",
                                    ),
                                style = MaterialTheme.typography.titleMedium,
                            )
                            member.profile.city?.let { Text(it) }
                            Text(organizationTeamRoleText(member.role, language))
                            if (
                                OrganizationManagementContract.canManage(
                                    snapshot.organization,
                                    session,
                                )
                            ) {
                                val enabled = state.actionable && state.uncertain == null
                                if (
                                    member.role != OrganizationTeamRole.OWNER &&
                                        member.profile.displayName != null
                                ) {
                                    if (member.role != OrganizationTeamRole.ADMIN)
                                        TextButton(
                                            {
                                                actions.choose(
                                                    member.profile.id,
                                                    OrganizationTeamAction.ADMIN,
                                                )
                                            },
                                            enabled = enabled,
                                            modifier =
                                                Modifier.testTag(
                                                    "organization-team-admin-${member.profile.id}"
                                                ),
                                        ) {
                                            Text(
                                                om(
                                                    language,
                                                    "Als Administrator einsetzen",
                                                    "Призначити адміністратором",
                                                )
                                            )
                                        }
                                    if (member.role != OrganizationTeamRole.MODERATOR)
                                        TextButton(
                                            {
                                                actions.choose(
                                                    member.profile.id,
                                                    OrganizationTeamAction.MODERATOR,
                                                )
                                            },
                                            enabled = enabled,
                                            modifier =
                                                Modifier.testTag(
                                                    "organization-team-moderator-${member.profile.id}"
                                                ),
                                        ) {
                                            Text(
                                                om(
                                                    language,
                                                    "Als Moderator einsetzen",
                                                    "Призначити модератором",
                                                )
                                            )
                                        }
                                }
                                if (
                                    member.role in
                                        setOf(
                                            OrganizationTeamRole.ADMIN,
                                            OrganizationTeamRole.MODERATOR,
                                        )
                                )
                                    TextButton(
                                        {
                                            actions.choose(
                                                member.profile.id,
                                                OrganizationTeamAction.REMOVE,
                                            )
                                        },
                                        enabled = enabled,
                                        modifier =
                                            Modifier.testTag(
                                                "organization-team-remove-${member.profile.id}"
                                            ),
                                    ) {
                                        Text(
                                            om(
                                                language,
                                                "Organisationsrolle entfernen",
                                                "Зняти роль в організації",
                                            )
                                        )
                                    }
                                if (
                                    member.role != OrganizationTeamRole.OWNER &&
                                        member.profile.displayName != null &&
                                        OrganizationManagementContract.canTransfer(
                                            snapshot.organization,
                                            session,
                                        )
                                )
                                    TextButton(
                                        {
                                            actions.choose(
                                                member.profile.id,
                                                OrganizationTeamAction.TRANSFER,
                                            )
                                        },
                                        enabled = enabled,
                                        modifier =
                                            Modifier.testTag(
                                                "organization-team-transfer-${member.profile.id}"
                                            ),
                                    ) {
                                        Text(
                                            om(
                                                language,
                                                "Inhaberschaft übertragen",
                                                "Передати володіння",
                                            )
                                        )
                                    }
                            }
                        }
                    }
                }
                if (snapshot.next != null)
                    TextButton(
                        actions.more,
                        enabled = state.actionable,
                        modifier = Modifier.testTag("organization-management-more"),
                    ) {
                        Text(
                            om(
                                language,
                                "Weitere Abonnenten laden",
                                "Завантажити інших підписників",
                            )
                        )
                    }
                if (snapshot.members.isEmpty())
                    Text(
                        om(
                            language,
                            "Noch keine öffentlichen Team- oder Abonnentenprofile.",
                            "Поки немає публічних профілів команди або підписників.",
                        )
                    )
            }
        }
    }
    state.confirmation?.let { intent ->
        val member = snapshot?.members?.firstOrNull { it.profile.id == intent.targetId }
        AlertDialog(
            onDismissRequest = actions.dismiss,
            title = {
                Text(om(language, "Organisationsrolle ändern?", "Змінити роль в організації?"))
            },
            text = {
                Text(
                    (member?.profile?.displayName
                        ?: om(language, "Profil nicht verfügbar", "Профіль недоступний")) +
                        "\n" +
                        when (intent.action) {
                            OrganizationTeamAction.TRANSFER ->
                                om(
                                    language,
                                    "Die bisherige Inhaberschaft endet. Der bisherige Inhaber erhält keine automatische Ersatzrolle. Diese Übertragung wird protokolliert.",
                                    "Повноваження попереднього власника завершаться без автоматичної заміни іншою роллю. Передачу буде записано в журналі.",
                                )
                            OrganizationTeamAction.REMOVE ->
                                om(
                                    language,
                                    "Die aktuelle Administrator- oder Moderatorrolle dieser Person wird vollständig entfernt, auch wenn sie seit dem Öffnen geändert wurde. Eine Inhaberrolle wird hier nicht entfernt.",
                                    "Поточну роль адміністратора або модератора буде повністю знято, навіть якщо її змінили після відкриття. Роль власника тут не знімається.",
                                )
                            else ->
                                om(language, "Neue Rolle: ", "Нова роль: ") +
                                    organizationTeamRoleText(
                                        OrganizationManagementContract.desired(intent),
                                        language,
                                    )
                        }
                )
            },
            confirmButton = {
                TextButton(
                    actions.confirm,
                    enabled = state.actionable,
                    modifier = Modifier.testTag("organization-management-confirm-role"),
                ) {
                    Text(om(language, "Bestätigen", "Підтвердити"))
                }
            },
            dismissButton = {
                TextButton(actions.dismiss) { Text(om(language, "Abbrechen", "Скасувати")) }
            },
        )
    }
    if (close)
        AlertDialog(
            onDismissRequest = { close = false },
            title = { Text(om(language, "Formular schließen?", "Закрити форму?")) },
            text = {
                Text(
                    om(
                        language,
                        "Ungespeicherte Änderungen werden verworfen.",
                        "Незбережені зміни буде втрачено.",
                    )
                )
            },
            confirmButton = {
                TextButton({
                    close = false
                    actions.closeEditor()
                }) {
                    Text(om(language, "Schließen", "Закрити"))
                }
            },
            dismissButton = {
                TextButton({ close = false }) {
                    Text(om(language, "Weiter bearbeiten", "Продовжити редагування"))
                }
            },
        )
}

@Composable
private fun OrganizationInformationExtras(
    d: OrganizationInformationDraft,
    language: String,
    enabled: Boolean,
    change: ((OrganizationInformationDraft) -> OrganizationInformationDraft) -> Unit,
) {
    var expanded by remember(d.basics.id) { mutableStateOf(false) }
    TextButton({ expanded = !expanded }) {
        Text(
            om(
                language,
                "Weitere Angaben, Leistungen und Übersetzungen",
                "Інші відомості, послуги та переклади",
            )
        )
    }
    if (!expanded) return
    fun field(
        label: String,
        value: String,
        tag: String,
        multiline: Boolean = false,
        update: (OrganizationInformationDraft, String) -> OrganizationInformationDraft,
    ): @Composable () -> Unit = {
        OutlinedTextField(
            value,
            { value -> change { update(it, value) } },
            enabled = enabled,
            label = { Text(label) },
            modifier = Modifier.fillMaxWidth().testTag(tag),
            minLines = if (multiline) 2 else 1,
            maxLines = if (multiline) 6 else 2,
        )
    }
    InformationChoice(
        om(language, "Kategorie", "Категорія"),
        d.category,
        OrganizationManagementContract.categories,
        enabled,
        { categoryLabel(it, language) },
    ) { value ->
        change { it.copy(category = value) }
    }
    field(
        om(language, "Gründungsjahr", "Рік заснування"),
        d.foundedYear,
        "organization-info-year",
    ) { old, value ->
        old.copy(foundedYear = value, foundedMonth = if (value.isBlank()) "" else old.foundedMonth)
    }()
    field(
        om(language, "Gründungsmonat · 1–12", "Місяць заснування · 1–12"),
        d.foundedMonth,
        "organization-info-month",
    ) { old, value ->
        old.copy(foundedMonth = value)
    }()
    field(
        om(language, "Sprachen · durch Komma getrennt", "Мови · через кому"),
        d.languages,
        "organization-info-languages",
    ) { old, value ->
        old.copy(languages = value)
    }()
    field(om(language, "Mission", "Місія"), d.mission, "organization-info-mission", true) {
        old,
        value ->
        old.copy(mission = value)
    }()
    field(
        om(language, "Kontaktperson", "Контактна особа"),
        d.contactPerson,
        "organization-info-contact",
    ) { old, value ->
        old.copy(contactPerson = value)
    }()
    OrganizationManagementContract.linkFields.forEach { key ->
        field(linkLabel(key), d.links[key].orEmpty(), "organization-info-$key") { old, value ->
            old.copy(links = old.links + (key to value))
        }()
    }
    Text(
        om(language, "Leistungen und Öffnungszeiten", "Послуги та години роботи"),
        style = MaterialTheme.typography.titleMedium,
    )
    val secondary =
        d.directory.secondaryCategories
            .split(',')
            .map(String::trim)
            .filter(String::isNotEmpty)
            .toSet()
    OrganizationManagementContract.categories
        .filter { it != d.category }
        .forEach { value ->
            Row {
                Checkbox(
                    value in secondary,
                    { checked ->
                        change { current ->
                            val selected =
                                current.directory.secondaryCategories
                                    .split(',')
                                    .map(String::trim)
                                    .filter(String::isNotEmpty)
                                    .toSet()
                            current.copy(
                                directory =
                                    current.directory.copy(
                                        secondaryCategories =
                                            (if (checked) selected + value else selected - value)
                                                .joinToString(", ")
                                    )
                            )
                        }
                    },
                    enabled = enabled && (value in secondary || secondary.size < 2),
                )
                Text(categoryLabel(value, language), Modifier.padding(top = 12.dp))
            }
        }
    OrganizationManagementContract.serviceModes.forEach { value ->
        Row {
            Checkbox(
                value in d.directory.serviceModes,
                { checked ->
                    change {
                        it.copy(
                            directory =
                                it.directory.copy(
                                    serviceModes =
                                        if (checked) it.directory.serviceModes + value
                                        else it.directory.serviceModes - value
                                )
                        )
                    }
                },
                enabled = enabled,
            )
            Text(serviceModeLabel(value, language), Modifier.padding(top = 12.dp))
        }
    }
    field(
        om(language, "Einzugsgebiet", "Територія обслуговування"),
        d.directory.serviceArea,
        "organization-info-area",
    ) { old, value ->
        old.copy(directory = old.directory.copy(serviceArea = value))
    }()
    OrganizationManagementContract.weekdays.forEachIndexed { index, key ->
        val closed = d.directory.regularHours[key] == "closed"
        val title =
            (if (language == "uk")
                listOf("Понеділок", "Вівторок", "Середа", "Четвер", "П’ятниця", "Субота", "Неділя")
            else
                listOf(
                    "Montag",
                    "Dienstag",
                    "Mittwoch",
                    "Donnerstag",
                    "Freitag",
                    "Samstag",
                    "Sonntag",
                ))[index]
        Row {
            Checkbox(
                closed,
                { value ->
                    change {
                        it.copy(
                            directory =
                                it.directory.copy(
                                    regularHours =
                                        it.directory.regularHours +
                                            (key to if (value) "closed" else "")
                                )
                        )
                    }
                },
                enabled = enabled,
            )
            Text(
                title + " · " + om(language, "geschlossen", "зачинено"),
                Modifier.padding(top = 12.dp),
            )
        }
        if (!closed)
            field(
                "$title · HH:mm-HH:mm",
                d.directory.regularHours[key].orEmpty(),
                "organization-info-hours-$key",
            ) { old, value ->
                old.copy(
                    directory =
                        old.directory.copy(
                            regularHours = old.directory.regularHours + (key to value)
                        )
                )
            }()
    }
    field(
        om(language, "Hinweise zu Öffnungszeiten", "Примітки до годин роботи"),
        d.directory.specialHoursNote,
        "organization-info-hours-note",
        true,
    ) { old, value ->
        old.copy(directory = old.directory.copy(specialHoursNote = value))
    }()
    field(
        om(language, "Bis zu 8 Leistungen · eine je Zeile", "До 8 послуг · одна на рядок"),
        d.directory.services,
        "organization-info-services",
        true,
    ) { old, value ->
        old.copy(directory = old.directory.copy(services = value))
    }()
    field(
        om(language, "Bestellseite", "Сторінка замовлення"),
        d.directory.orderUrl,
        "organization-info-order",
    ) { old, value ->
        old.copy(directory = old.directory.copy(orderUrl = value))
    }()
    field(
        om(language, "Buchungsseite", "Сторінка бронювання"),
        d.directory.bookingUrl,
        "organization-info-booking",
    ) { old, value ->
        old.copy(directory = old.directory.copy(bookingUrl = value))
    }()
    field(
        om(language, "Aktuelles Angebot", "Поточна пропозиція"),
        d.directory.offerTitle,
        "organization-info-offer",
    ) { old, value ->
        old.copy(directory = old.directory.copy(offerTitle = value))
    }()
    field(
        om(language, "Angebotsdetails", "Деталі пропозиції"),
        d.directory.offerDetails,
        "organization-info-offer-details",
        true,
    ) { old, value ->
        old.copy(directory = old.directory.copy(offerDetails = value))
    }()
    field(
        om(language, "Angebotsseite", "Сторінка пропозиції"),
        d.directory.offerUrl,
        "organization-info-offer-url",
    ) { old, value ->
        old.copy(directory = old.directory.copy(offerUrl = value))
    }()
    OrganizationOfferDate(d.directory.offerUntil, language, enabled) { value ->
        change { it.copy(directory = it.directory.copy(offerUntil = value)) }
    }
    Text(
        om(
            language,
            "Weitere deutsche Übersetzungen (optional)",
            "Інші переклади німецькою (необов’язково)",
        ),
        style = MaterialTheme.typography.titleMedium,
    )
    field("Mission · Deutsch", d.german.mission, "organization-info-de-mission", true) { old, value
        ->
        old.copy(german = old.german.copy(mission = value))
    }()
    field("Einzugsgebiet · Deutsch", d.german.serviceArea, "organization-info-de-area") { old, value
        ->
        old.copy(german = old.german.copy(serviceArea = value))
    }()
    field(
        "Öffnungszeiten-Hinweis · Deutsch",
        d.german.hoursNote,
        "organization-info-de-hours",
        true,
    ) { old, value ->
        old.copy(german = old.german.copy(hoursNote = value))
    }()
    field("Leistungen · Deutsch", d.german.services, "organization-info-de-services", true) {
        old,
        value ->
        old.copy(german = old.german.copy(services = value))
    }()
    field("Angebot · Deutsch", d.german.offerTitle, "organization-info-de-offer") { old, value ->
        old.copy(german = old.german.copy(offerTitle = value))
    }()
    field(
        "Angebotsdetails · Deutsch",
        d.german.offerDetails,
        "organization-info-de-offer-details",
        true,
    ) { old, value ->
        old.copy(german = old.german.copy(offerDetails = value))
    }()
}

@Composable
private fun InformationChoice(
    label: String,
    value: String,
    options: List<String>,
    enabled: Boolean,
    title: (String) -> String,
    change: (String) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        OutlinedButton({ open = true }, enabled = enabled) {
            Text("$label: ${if (value.isBlank()) "—" else title(value)}")
        }
        DropdownMenu(open, { open = false }) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(title(option)) },
                    onClick = {
                        open = false
                        change(option)
                    },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun OrganizationOfferDate(
    value: String,
    language: String,
    enabled: Boolean,
    change: (String) -> Unit,
) {
    var open by remember(language) { mutableStateOf(false) }
    val instant = runCatching { Instant.parse(value) }.getOrNull()
    val title = om(language, "Angebot gültig bis", "Пропозиція чинна до")
    TextButton(
        { open = true },
        enabled = enabled,
        modifier = Modifier.testTag("organization-offer-date"),
    ) {
        Text(
            title +
                ": " +
                (instant?.let {
                    DateTimeFormatter.ofPattern("dd.MM.yyyy")
                        .withZone(ZoneId.systemDefault())
                        .format(it)
                } ?: "—")
        )
    }
    if (value.isNotEmpty())
        TextButton(
            { change("") },
            enabled = enabled,
            modifier = Modifier.testTag("organization-offer-date-clear"),
        ) {
            Text(om(language, "Datum entfernen", "Прибрати дату"))
        }
    if (open) {
        PickerLocale(language) {
            val picker =
                rememberDatePickerState(
                    initialSelectedDateMillis =
                        instant?.let {
                            OrganizationOfferCalendar.pickerMillis(it, ZoneId.systemDefault())
                        }
                )
            ProtectedDialog(
                onDismissRequest = { open = false },
                properties = DialogProperties(usePlatformDefaultWidth = false),
            ) {
                // Reapply resources inside the new dialog owner; the state was localized above.
                PickerLocale(language) {
                    Surface(
                        Modifier.padding(20.dp).widthIn(max = 560.dp).fillMaxWidth(),
                        shape = MaterialTheme.shapes.extraLarge,
                    ) {
                        Column(Modifier.verticalScroll(rememberScrollState())) {
                            DatePicker(picker)
                            Row(
                                Modifier.fillMaxWidth().padding(12.dp),
                                horizontalArrangement = Arrangement.End,
                            ) {
                                TextButton({ open = false }, Modifier.heightIn(min = 48.dp)) {
                                    Text(om(language, "Abbrechen", "Скасувати"))
                                }
                                TextButton(
                                    {
                                        picker.selectedDateMillis?.let { selected ->
                                            change(
                                                OrganizationOfferCalendar.inclusiveEnd(
                                                        selected,
                                                        ZoneId.systemDefault(),
                                                    )
                                                    .toString()
                                            )
                                        }
                                        open = false
                                    },
                                    modifier = Modifier.heightIn(min = 48.dp),
                                    enabled = picker.selectedDateMillis != null,
                                ) {
                                    Text(om(language, "Übernehmen", "Застосувати"))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private fun linkLabel(key: String) =
    when (key) {
        "donationURL" -> "Spenden / Пожертви · URL"
        else -> key.removeSuffix("URL").replaceFirstChar(Char::uppercase) + " · URL"
    }

private fun categoryLabel(value: String, language: String): String {
    val labels =
        if (language == "uk")
            listOf(
                "Українські продукти",
                "Їжа та напої",
                "Торгівля",
                "Краса та здоров’я",
                "Право та фінанси",
                "Робота та бізнес",
                "Освіта",
                "Діти та сім’я",
                "Культура",
                "Підтримка",
                "Інтеграція",
                "Дім і транспорт",
                "Медіа",
                "Публічна установа",
                "Інше",
            )
        else
            listOf(
                "Ukrainische Produkte",
                "Essen und Trinken",
                "Einzelhandel",
                "Schönheit und Gesundheit",
                "Recht und Finanzen",
                "Arbeit und Wirtschaft",
                "Bildung",
                "Kinder und Familie",
                "Kultur",
                "Unterstützung",
                "Integration",
                "Wohnen und Verkehr",
                "Medien",
                "Öffentliche Einrichtung",
                "Sonstiges",
            )
    return labels.getOrNull(OrganizationManagementContract.categories.indexOf(value)) ?: value
}

private fun serviceModeLabel(value: String, language: String): String =
    when (value) {
        "inStore" -> om(language, "Vor Ort im Geschäft", "У закладі")
        "pickup" -> om(language, "Abholung", "Самовивіз")
        "delivery" -> om(language, "Lieferung", "Доставка")
        "online" -> om(language, "Online", "Онлайн")
        else -> om(language, "Außeneinsatz", "Виїзд до клієнта")
    }

fun organizationTeamRoleText(role: OrganizationTeamRole, language: String): String =
    when (role) {
        OrganizationTeamRole.OWNER -> om(language, "Inhaber", "Власник")
        OrganizationTeamRole.ADMIN -> om(language, "Administrator", "Адміністратор")
        OrganizationTeamRole.MODERATOR -> om(language, "Moderator", "Модератор")
        OrganizationTeamRole.MEMBER -> om(language, "Abonnent", "Підписник")
    }

fun organizationManagementFailureText(
    failure: OrganizationManagementFailure,
    language: String,
): String =
    when (failure) {
        OrganizationManagementFailure.SIGN_IN ->
            om(language, "Bitte anmelden.", "Увійдіть в акаунт.")
        OrganizationManagementFailure.NOT_READY ->
            om(
                language,
                "Bitte Konto, E-Mail, Zustimmungen und Sicherheitsanforderungen prüfen.",
                "Перевірте акаунт, пошту, згоди та вимоги безпеки.",
            )
        OrganizationManagementFailure.INVALID ->
            om(
                language,
                "Angaben, Links und Zeitformate prüfen. Es wurde kein bestätigter Erfolg gemeldet.",
                "Перевірте дані, посилання та час. Підтвердженого успіху немає.",
            )
        OrganizationManagementFailure.DENIED ->
            om(
                language,
                "Die aktuellen Organisationsrechte erlauben diese Aktion nicht.",
                "Поточні права в організації не дозволяють цю дію.",
            )
        OrganizationManagementFailure.MISSING ->
            om(
                language,
                "Diese genehmigte Organisation ist nicht mehr verfügbar.",
                "Ця схвалена організація більше недоступна.",
            )
        OrganizationManagementFailure.STALE ->
            om(
                language,
                "Die Organisation oder Rolle wurde geändert. Bitte aktualisieren und eine neue Entscheidung treffen.",
                "Організацію або роль змінено. Оновіть дані та ухваліть нове рішення.",
            )
        OrganizationManagementFailure.OFFLINE ->
            om(
                language,
                "Server nicht erreichbar. Es wird nichts automatisch erneut gesendet.",
                "Сервер недоступний. Нічого не надсилається автоматично повторно.",
            )
        OrganizationManagementFailure.TARGET_UNAVAILABLE ->
            om(
                language,
                "Konto oder Zielkonto erfüllt die Voraussetzungen nicht. Bitte Verfügbarkeit, Bestätigung und Sicherheitsstatus prüfen.",
                "Акаунт або цільовий акаунт не відповідає вимогам. Перевірте доступність, підтвердження та стан безпеки.",
            )
        OrganizationManagementFailure.UNCONFIRMED ->
            om(
                language,
                "Ergebnis noch nicht bestätigt. Zuerst den Serverstand aktualisieren; keine automatische Wiederholung.",
                "Результат ще не підтверджено. Спочатку оновіть стан із сервера; автоматичного повтору немає.",
            )
        OrganizationManagementFailure.UNKNOWN ->
            om(
                language,
                "Aktion nicht bestätigt. Aktuellen Stand prüfen.",
                "Дію не підтверджено. Перевірте актуальний стан.",
            )
    }

private fun om(language: String, de: String, uk: String) = if (language == "uk") uk else de
