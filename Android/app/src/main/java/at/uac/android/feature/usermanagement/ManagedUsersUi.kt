package at.uac.android.feature.usermanagement

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.core.LocalWindowPrivacy
import at.uac.android.feature.browse.regions
import at.uac.android.feature.browse.tr
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.platformrolemanagement.*
import at.uac.android.feature.userstatusmanagement.*
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

data class ManagedUsersActions(
    val back: () -> Unit = {},
    val account: () -> Unit = {},
    val refresh: () -> Unit = {},
    val more: () -> Unit = {},
    val search: (String) -> Unit = {},
    val filter: (ManagedUsersFilter) -> Unit = {},
    val open: (String) -> Unit = {},
)

@Composable
fun ManagedUsersScreen(
    model: ManagedUsersViewModel,
    session: ModerationSession?,
    language: String,
    onBack: () -> Unit,
    onAccount: () -> Unit,
    interactive: Boolean = true,
    statuses: UserStatusViewModel? = null,
    roles: PlatformRoleViewModel? = null,
) {
    val stored by model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    val privacy = LocalWindowPrivacy.current
    val available = interactive && privacy?.interactionBlocked != true
    val liveAvailable = rememberUpdatedState(available)
    var lease by remember(model) { mutableStateOf<ManagedUsersPresentation?>(null) }
    LifecycleResumeEffect(listOf(session, available, statuses, roles)) {
        val owned =
            if (available)
                model.present {
                    interactive &&
                        privacy?.interactionBlocked != true &&
                        model.currentSession() == session
                }
            else null
        lease = owned
        onPauseOrDispose {
            owned?.let {
                model.dismiss(it)
                statuses?.dismiss(it)
                roles?.dismiss(it)
            }
            if (lease === owned) lease = null
        }
    }
    val projected =
        if (stored.session == session && available) model.snapshot(session, lease)
        else ManagedUsersState(session = session)
    val guarded: (() -> Unit) -> Unit = { if (available && model.owns(lease)) it() }
    val back = {
        if (projected.selectedId != null)
            guarded {
                model.closeTarget()
                statuses?.snapshot(session)
                roles?.snapshot(session)
            }
        else if (available) {
            lease?.let {
                model.dismiss(it)
                statuses?.dismiss(it)
                roles?.dismiss(it)
            }
            onBack()
        }
        Unit
    }
    BackHandler(enabled = available, onBack = back)
    val statusState = statuses?.let { value ->
        val statusStored by
            value.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
        // Sample the live veto even when rendering is masked, so private confirmation memory is
        // revoked too.
        val currentStatus = value.snapshot(session)
        if (statusStored.session == session && projected.visible && available) currentStatus
        else UserStatusState()
    }
    val roleState = roles?.let { value ->
        val roleStored by
            value.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
        val currentRole = value.snapshot(session)
        if (roleStored.session == session && projected.visible && available) currentRole
        else PlatformRoleState()
    }
    // Live callbacks, not captured render booleans: a second tap cannot queue a sibling action.
    val statusGuarded: (() -> Unit) -> Unit = { action ->
        guarded {
            if (roles?.snapshot(session).allowsSiblingStatusAction()) action()
        }
    }
    val roleGuarded: (() -> Unit) -> Unit = { action ->
        guarded {
            if (statuses?.snapshot(session).allowsSiblingRoleAction()) action()
        }
    }
    val reviewed =
        projected.detail?.takeIf {
            projected.visible &&
                !projected.loading &&
                projected.error == null &&
                projected.selectedId == it.id
        }
    SideEffect {
        statuses?.bindView(
            session,
            reviewed?.id,
            lease,
            hostIsCurrent = {
                liveAvailable.value && model.owns(lease) && model.currentSession() == session
            },
            canSubmit = {
                val current = model.snapshot(session, lease)
                liveAvailable.value &&
                    reviewed != null &&
                    current.visible &&
                    !current.loading &&
                    current.error == null &&
                    current.selectedId == reviewed.id &&
                    // Reference identity is only a rendered-detail epoch, NEVER a raw mutation
                    // version.
                    current.detail === reviewed &&
                    // Only the sibling's busy/editing latch, never its private preview. Calling
                    // snapshot here would recursively sample the other target's guard.
                    roles?.state?.value.allowsSiblingStatusAction()
            },
        )
        roles?.bindView(
            session,
            reviewed?.id,
            lease,
            hostIsCurrent = {
                liveAvailable.value && model.owns(lease) && model.currentSession() == session
            },
            canSubmit = {
                val current = model.snapshot(session, lease)
                liveAvailable.value &&
                    reviewed != null &&
                    current.visible &&
                    !current.loading &&
                    current.error == null &&
                    current.selectedId == reviewed.id &&
                    current.detail === reviewed &&
                    statuses?.state?.value.allowsSiblingRoleAction()
            },
        )
    }
    LaunchedEffect(statusState?.completion) {
        if ((statusState?.completion ?: 0) > 0) guarded { model.refresh() }
    }
    LaunchedEffect(roleState?.completion) {
        if ((roleState?.completion ?: 0) > 0) guarded { model.refresh() }
    }
    ManagedUsersContent(
        projected,
        language,
        ManagedUsersActions(
            back,
            {
                if (available) {
                    lease?.let {
                        model.dismiss(it)
                        statuses?.dismiss(it)
                        roles?.dismiss(it)
                    }
                    onAccount()
                }
            },
            { guarded { model.refresh() } },
            { guarded { model.refresh(more = true) } },
            { value -> guarded { model.search(value) } },
            { value -> guarded { model.filter(value) } },
            { target -> guarded { model.open(target) } },
        ),
        actionContent =
            if (statuses != null || roles != null) {
                {
                    if (statuses != null && statusState != null)
                        UserStatusPanel(
                            statusState.copy(
                                busy = statusState.busy || !roleState.allowsSiblingStatusAction()
                            ),
                            language,
                            UserStatusActions(
                                request = { action -> statusGuarded { statuses.request(action) } },
                                editReason = { value ->
                                    statusGuarded { statuses.editReason(value) }
                                },
                                chooseDays = { days ->
                                    statusGuarded { statuses.chooseDays(days) }
                                },
                                confirm = { statusGuarded { statuses.confirm() } },
                                cancel = statuses::cancelConfirmation,
                                refresh = { statusGuarded { statuses.refresh() } },
                                refreshPending = { statusGuarded { statuses.refreshPending() } },
                                reconcile = { entry ->
                                    statusGuarded { statuses.reconcile(entry) }
                                },
                                dismissOutcome = { guarded { statuses.dismissOutcome() } },
                            ),
                        )
                    if (roles != null && roleState != null)
                        PlatformRolePanel(
                            roleState.copy(
                                busy = roleState.busy || !statusState.allowsSiblingRoleAction()
                            ),
                            language,
                            PlatformRoleActions(
                                request = { action -> roleGuarded { roles.request(action) } },
                                editReason = { value -> roleGuarded { roles.editReason(value) } },
                                confirm = { roleGuarded { roles.confirm() } },
                                cancel = roles::cancelConfirmation,
                                refresh = { roleGuarded { roles.refresh() } },
                                refreshPending = { roleGuarded { roles.refreshPending() } },
                                reconcile = { entry -> roleGuarded { roles.reconcile(entry) } },
                                dismissOutcome = { guarded { roles.dismissOutcome() } },
                            ),
                        )
                }
            } else null,
    )
}

@Composable
fun ManagedUsersContent(
    state: ManagedUsersState,
    language: String,
    actions: ManagedUsersActions,
    actionContent: (@Composable () -> Unit)? = null,
) {
    val privileged = state.visible && state.session?.allowed == true
    val confirmed = privileged && !state.loading && state.error == null
    val focus = LocalFocusManager.current
    LazyColumn(
        Modifier.fillMaxSize().imePadding().testTag("managed-users-list"),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item("header") {
            TextButton(
                {
                    focus.clearFocus()
                    actions.back()
                },
                Modifier.heightIn(min = 48.dp).testTag("managed-users-back"),
            ) {
                Text(tr(language, "Zurück", "Назад"))
            }
            Text(
                tr(language, "Nutzerverwaltung", "Керування користувачами"),
                style = MaterialTheme.typography.headlineMedium,
            )
            Text(
                if (actionContent == null)
                    tr(language, "Geschützte Ansicht · nur lesen", "Захищений перегляд · без змін")
                else
                    tr(
                        language,
                        "Geschützte Verwaltung · Änderungen einzeln bestätigen",
                        "Захищене керування · кожну зміну слід підтвердити",
                    ),
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        if (!privileged)
            item("access") {
                val failure =
                    when {
                        state.session == null -> ManagedUsersFailure.SIGN_IN
                        !state.session.ready -> ManagedUsersFailure.NOT_READY
                        else -> ManagedUsersFailure.DENIED
                    }
                Text(
                    managedUsersFailureText(failure, language),
                    Modifier.testTag("managed-users-access"),
                )
                OutlinedButton(
                    actions.account,
                    Modifier.heightIn(min = 48.dp).testTag("managed-users-account"),
                ) {
                    Text(tr(language, "Konto öffnen", "Відкрити акаунт"))
                }
            }
        if (privileged) {
            if (actionContent != null) item("status-actions") { actionContent() }
            item("refresh") {
                OutlinedButton(
                    {
                        focus.clearFocus()
                        actions.refresh()
                    },
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("managed-users-refresh"),
                    enabled = !state.loading,
                ) {
                    Text(tr(language, "Daten und Zugriff aktualisieren", "Оновити дані й доступ"))
                }
            }
            if (state.selectedId == null) {
                item("search") {
                    OutlinedTextField(
                        value = state.query,
                        onValueChange = actions.search,
                        modifier = Modifier.fillMaxWidth().testTag("managed-users-search"),
                        label = {
                            Text(
                                tr(
                                    language,
                                    "Name, E-Mail, Ort oder Kennung",
                                    "Ім’я, email, місто або ідентифікатор",
                                )
                            )
                        },
                        supportingText = {
                            Text(
                                tr(
                                    language,
                                    "Serversuche: 2–120 normalisierte Zeichen, höchstens 100 Treffer.",
                                    "Пошук на сервері: 2–120 нормалізованих символів, щонайбільше 100 збігів.",
                                )
                            )
                        },
                        singleLine = true,
                        keyboardOptions =
                            KeyboardOptions(
                                autoCorrectEnabled = false,
                                imeAction = ImeAction.Search,
                            ),
                        keyboardActions =
                            KeyboardActions(
                                onSearch = {
                                    focus.clearFocus()
                                    actions.refresh()
                                }
                            ),
                    )
                }
                item("filters") {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ManagedUsersFilter.entries.forEach { filter ->
                            FilterChip(
                                selected = state.filter == filter,
                                onClick = { actions.filter(filter) },
                                label = { Text(managedUsersFilterLabel(filter, language)) },
                                modifier =
                                    Modifier.heightIn(min = 48.dp)
                                        .testTag("managed-users-filter-${filter.name}"),
                            )
                        }
                    }
                    Text(
                        tr(
                            language,
                            "Filter gelten nur für die geladenen Ergebnisse.",
                            "Фільтри стосуються лише завантажених результатів.",
                        ),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
            }
            if (state.loading)
                item("loading") {
                    LinearProgressIndicator(
                        Modifier.fillMaxWidth().testTag("managed-users-loading")
                    )
                }
            state.error?.let { failure ->
                item("error") {
                    Text(
                        managedUsersFailureText(failure, language),
                        Modifier.testTag("managed-users-error"),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
            if (confirmed && state.selectedId == null) {
                item("count") {
                    val total = state.totalMatches
                    Text(
                        if (total != null)
                            tr(
                                language,
                                "${state.users.size} Profile geladen · $total Server-Treffer",
                                "Завантажено профілів: ${state.users.size} · збігів на сервері: $total",
                            )
                        else
                            tr(
                                language,
                                "${state.users.size} Profile im geladenen Fenster",
                                "Профілів у завантаженій частині: ${state.users.size}",
                            ),
                        Modifier.testTag("managed-users-count"),
                    )
                    if (state.capped || (total ?: 0) > ManagedUsersContract.SEARCH_LIMIT)
                        Text(
                            tr(
                                language,
                                "Anzeigelimit erreicht. Bitte die Suche eingrenzen; dies ist keine vollständige Nutzerliste.",
                                "Досягнуто межі перегляду. Уточніть пошук; це не повний список користувачів.",
                            ),
                            Modifier.testTag("managed-users-cap"),
                        )
                    if (state.unavailable > 0)
                        Text(
                            tr(
                                language,
                                "Nicht mehr verfügbare Profile: ${state.unavailable}.",
                                "Профілів, що вже недоступні: ${state.unavailable}.",
                            )
                        )
                }
                val shown = state.users.filter { ManagedUsersContract.matches(it, state.filter) }
                if (shown.isEmpty())
                    item("empty") {
                        Text(
                            tr(
                                language,
                                "Keine passenden geladenen Profile.",
                                "Серед завантажених немає відповідних профілів.",
                            ),
                            Modifier.testTag("managed-users-empty"),
                        )
                    }
                items(shown, key = { it.id }) { user ->
                    OutlinedButton(
                        {
                            focus.clearFocus()
                            actions.open(user.id)
                        },
                        Modifier.fillMaxWidth()
                            .heightIn(min = 48.dp)
                            .testTag("managed-user-row-${user.id}"),
                    ) {
                        Column(
                            Modifier.fillMaxWidth(),
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Text(
                                user.displayName.ifBlank {
                                    tr(language, "Ohne Namen", "Без імені")
                                },
                                style = MaterialTheme.typography.titleMedium,
                            )
                            if (user.email.isNotBlank()) Text(user.email)
                            Text(
                                "${managedUsersRoleLabel(user.globalRole, language)} · ${managedUsersStatusLabel(user.accountStatus, language)}"
                            )
                        }
                    }
                }
                if (state.next != null)
                    item("more") {
                        Button(
                            actions.more,
                            Modifier.fillMaxWidth()
                                .heightIn(min = 48.dp)
                                .testTag("managed-users-more"),
                        ) {
                            Text(tr(language, "Weitere 40 laden", "Завантажити ще 40"))
                        }
                    }
            }
            if (confirmed && state.selectedId != null)
                state.detail
                    ?.takeIf { it.id == state.selectedId }
                    ?.let { user ->
                        item("profile") { ManagedUserProfile(user, language) }
                        item("security") {
                            Card(Modifier.fillMaxWidth().testTag("managed-user-security")) {
                                Column(
                                    Modifier.padding(16.dp),
                                    verticalArrangement = Arrangement.spacedBy(12.dp),
                                ) {
                                    Text(
                                        tr(language, "Anmeldesicherheit", "Безпека входу"),
                                        style = MaterialTheme.typography.titleLarge,
                                    )
                                    val metadata = state.security?.takeIf { it.targetId == user.id }
                                    if (metadata != null) {
                                        Metadata(
                                            tr(language, "E-Mail bestätigt", "Email підтверджено"),
                                            yesNo(metadata.emailVerified, language),
                                        )
                                        Metadata(
                                            tr(
                                                language,
                                                "Auth-Konto deaktiviert",
                                                "Auth-акаунт вимкнено",
                                            ),
                                            yesNo(metadata.authDisabled, language),
                                        )
                                        Metadata(
                                            tr(
                                                language,
                                                "Auth-Konto erstellt",
                                                "Auth-акаунт створено",
                                            ),
                                            date(metadata.creationTime, language),
                                        )
                                        Metadata(
                                            tr(language, "Letzte Anmeldung", "Останній вхід"),
                                            date(metadata.lastSignInTime, language),
                                        )
                                        Metadata(
                                            tr(language, "Anmeldeanbieter", "Способи входу"),
                                            metadata.providerIds
                                                .joinToString(" · ") { providerLabel(it, language) }
                                                .ifEmpty { unknown(language) },
                                        )
                                        Text(
                                            tr(
                                                language,
                                                "Eine Anmeldung ist kein Nachweis aktueller Online-Präsenz.",
                                                "Останній вхід не означає, що користувач зараз онлайн.",
                                            ),
                                            style = MaterialTheme.typography.bodySmall,
                                        )
                                    } else
                                        Text(
                                            if (state.securityError == ManagedUsersFailure.MISSING)
                                                tr(
                                                    language,
                                                    "Das Auth-Konto wurde nicht gefunden. Das Profil kann unabhängig davon existieren.",
                                                    "Auth-акаунт не знайдено. Запис профілю може існувати окремо.",
                                                )
                                            else
                                                managedUsersFailureText(
                                                    state.securityError
                                                        ?: ManagedUsersFailure.UNKNOWN,
                                                    language,
                                                ),
                                            Modifier.testTag("managed-user-security-error"),
                                        )
                                }
                            }
                        }
                    }
        }
    }
}

@Composable
private fun ManagedUserProfile(user: ManagedUser, language: String) {
    Card(Modifier.fillMaxWidth().testTag("managed-user-detail")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                user.displayName.ifBlank { tr(language, "Profil", "Профіль") },
                style = MaterialTheme.typography.titleLarge,
            )
            Metadata(tr(language, "Kennung", "Ідентифікатор"), user.id)
            Metadata(
                tr(language, "Vollständiger Name", "Повне ім’я"),
                user.fullName.ifBlank { unknown(language) },
            )
            Metadata("E-Mail", user.email.ifBlank { unknown(language) })
            Metadata("Telegram", user.telegram.ifBlank { unknown(language) })
            val region =
                regions
                    .firstOrNull { it.first == user.region }
                    ?.second
                    ?.split(" / ")
                    ?.getOrNull(if (language == "uk") 1 else 0)
            Metadata(
                tr(language, "Ort / Bundesland", "Місто / земля"),
                listOf(user.city, region.orEmpty())
                    .filter { it.isNotBlank() }
                    .joinToString(" · ")
                    .ifBlank { unknown(language) },
            )
            Metadata(
                tr(language, "Plattformrolle", "Роль на платформі"),
                managedUsersRoleLabel(user.globalRole, language),
            )
            Metadata(
                tr(language, "Kontostatus", "Стан акаунта"),
                managedUsersStatusLabel(user.accountStatus, language),
            )
            Metadata(
                tr(language, "Zugriffsstatus", "Стан доступу"),
                managedUsersStatusLabel(user.blockState, language),
            )
            Metadata(
                tr(language, "Warnungen", "Попередження"),
                user.warningCount?.toString() ?: unknown(language),
            )
            if (user.statusReason.isNotBlank())
                Metadata(tr(language, "Statusbegründung", "Причина зміни стану"), user.statusReason)
            if (user.banExpiresAt != null)
                Metadata(
                    tr(language, "Einschränkung bis", "Обмеження до"),
                    date(user.banExpiresAt, language),
                )
            Metadata(
                tr(language, "Profil erstellt", "Профіль створено"),
                date(user.createdAt, language),
            )
        }
    }
}

@Composable
private fun Metadata(label: String, value: String) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            label,
            style = MaterialTheme.typography.labelLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.bodyLarge)
    }
}

private fun unknown(language: String) = tr(language, "Nicht verfügbar", "Недоступно")

private fun yesNo(value: Boolean, language: String) =
    if (value) tr(language, "Ja", "Так") else tr(language, "Nein", "Ні")

private fun date(value: Instant?, language: String): String = managedUsersDate(value, language)

internal fun managedUsersDate(value: Instant?, language: String): String =
    value?.let {
        runCatching {
            DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT)
                .withLocale(Locale.forLanguageTag(language))
                .withZone(ZoneId.systemDefault())
                .format(it)
        }
            .getOrNull()
    } ?: unknown(language)

private fun providerLabel(value: String, language: String) =
    when (value) {
        "password" -> tr(language, "E-Mail und Passwort", "Email і пароль")
        "google.com" -> "Google"
        "apple.com" -> "Apple"
        "phone" -> tr(language, "Telefon", "Телефон")
        else -> tr(language, "Weiterer Anbieter", "Інший провайдер")
    }

fun managedUsersRoleLabel(value: String, language: String) =
    when (value) {
        "owner" -> tr(language, "App-Inhaber", "Власник застосунку")
        "admin" -> tr(language, "App-Administrator", "Адміністратор застосунку")
        "user" -> tr(language, "Nutzer", "Користувач")
        "topAdmin",
        "moderator",
        "appModerator" ->
            tr(language, "Frühere Rolle ohne Verwaltungsrecht", "Колишня роль без прав керування")
        else -> tr(language, "Unbekannte Rolle", "Невідома роль")
    }

fun managedUsersStatusLabel(value: String, language: String) =
    when (value) {
        "active" -> tr(language, "Aktiv", "Активний")
        "warned" -> tr(language, "Verwarnt", "Попереджено")
        "suspendedUntil",
        "temporarilyBanned",
        "blocked" -> tr(language, "Vorübergehend gesperrt", "Тимчасово обмежено")
        "bannedPermanent",
        "permanentlyBanned" -> tr(language, "Dauerhaft gesperrt", "Заблоковано назавжди")
        "deactivated" -> tr(language, "Deaktiviert", "Деактивовано")
        else -> tr(language, "Unbekannter Status", "Невідомий стан")
    }

private fun managedUsersFilterLabel(value: ManagedUsersFilter, language: String) =
    when (value) {
        ManagedUsersFilter.ALL -> tr(language, "Alle geladenen", "Усі завантажені")
        ManagedUsersFilter.ACTIVE -> tr(language, "Aktiv", "Активні")
        ManagedUsersFilter.WARNED -> tr(language, "Verwarnt", "Попереджені")
        ManagedUsersFilter.RESTRICTED -> tr(language, "Eingeschränkt", "Обмежені")
    }

fun managedUsersFailureText(value: ManagedUsersFailure, language: String) =
    when (value) {
        ManagedUsersFailure.SIGN_IN ->
            tr(
                language,
                "Bitte anmelden, um den geschützten Zugang zu prüfen.",
                "Увійдіть, щоб перевірити захищений доступ.",
            )
        ManagedUsersFailure.NOT_READY ->
            tr(
                language,
                "Bitte das Konto und den geschützten TOTP-Zugang bestätigen.",
                "Підтвердьте акаунт і захищений вхід із TOTP.",
            )
        ManagedUsersFailure.DENIED ->
            tr(
                language,
                "Nur aktive App-Inhaber und App-Administratoren haben Zugriff.",
                "Доступ мають лише активні власник та адміністратори застосунку.",
            )
        ManagedUsersFailure.OFFLINE ->
            tr(
                language,
                "Serverzugriff nicht bestätigt. Daten bleiben verborgen; bitte erneut aktualisieren.",
                "Доступ до сервера не підтверджено. Дані приховано; повторіть оновлення.",
            )
        ManagedUsersFailure.INDEX ->
            tr(
                language,
                "Die Serverabfrage ist noch nicht verfügbar. Bitte später erneut versuchen.",
                "Серверний запит поки недоступний. Спробуйте пізніше.",
            )
        ManagedUsersFailure.INVALID ->
            tr(
                language,
                "Die Suche oder Serverantwort ist ungültig. Suchtext prüfen und aktualisieren.",
                "Некоректний пошук або відповідь сервера. Перевірте запит і оновіть.",
            )
        ManagedUsersFailure.MISSING ->
            tr(
                language,
                "Dieses Profil ist nicht mehr verfügbar.",
                "Цей профіль більше недоступний.",
            )
        ManagedUsersFailure.STALE ->
            tr(
                language,
                "Zugriff oder Daten haben sich geändert. Bitte aktualisieren.",
                "Доступ або дані змінилися. Оновіть перегляд.",
            )
        ManagedUsersFailure.UNKNOWN ->
            tr(
                language,
                "Die Daten konnten nicht bestätigt werden. Bitte aktualisieren.",
                "Не вдалося підтвердити дані. Оновіть перегляд.",
            )
    }
