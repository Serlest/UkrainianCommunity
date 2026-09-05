package at.uac.android.feature.personal

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.core.ProtectedDropdownMenu as DropdownMenu
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.regions
import at.uac.android.feature.browse.time
import at.uac.android.feature.browse.tr
import java.time.Instant
import java.util.Locale

fun personalFailureText(reason: PersonalFailure, language: String): String =
    when (reason) {
        PersonalFailure.SIGN_IN ->
            tr(language, "Bitte zuerst anmelden.", "Спочатку увійдіть в обліковий запис.")
        PersonalFailure.NOT_READY ->
            tr(
                language,
                "Bitte bestätige deine E-Mail und schließe die Kontoprüfung ab.",
                "Підтвердьте email та завершіть перевірку облікового запису.",
            )
        PersonalFailure.DENIED ->
            tr(
                language,
                "Diese Aktion ist für das aktuelle Konto nicht erlaubt. Bitte prüfe den Kontostatus.",
                "Ця дія недоступна для поточного облікового запису. Перевірте його статус.",
            )
        PersonalFailure.OFFLINE ->
            tr(
                language,
                "Keine Verbindung zum lokalen Server. Der Erfolg ist noch nicht bestätigt. Erneutes Versuchen erzeugt keine Duplikate.",
                "Немає зв’язку з локальним сервером. Успіх ще не підтверджено. Повторна спроба не створить дублікати.",
            )
        PersonalFailure.MISSING ->
            tr(language, "Der Datensatz ist nicht mehr verfügbar.", "Запис більше недоступний.")
        PersonalFailure.INVALID ->
            tr(
                language,
                "Bitte prüfe die Eingaben. Die Daten sind unvollständig oder ungültig.",
                "Перевірте введені дані. Дані неповні або некоректні.",
            )
        PersonalFailure.UNKNOWN ->
            tr(
                language,
                "Die Aktion konnte nicht bestätigt werden. Bitte erneut versuchen.",
                "Не вдалося підтвердити виконання дії. Спробуйте ще раз.",
            )
    }

@Composable
private fun PersonalError(failure: PersonalFailure?, language: String, retry: () -> Unit) {
    if (failure == null) return
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(personalFailureText(failure, language), color = MaterialTheme.colorScheme.error)
        TextButton(onClick = retry) { Text(tr(language, "Erneut versuchen", "Спробувати ще раз")) }
    }
}

/**
 * Embeddable panel: the parent supplies scrolling/navigation and the authoritative session gate.
 */
@Composable
fun PersonalProfilePanel(
    state: PersonalState,
    language: String,
    onRefresh: () -> Unit,
    onSave: (ProfileDraft) -> Unit,
    avatarBusy: Boolean = false,
    avatarEditor: (@Composable (String, Boolean, (String) -> Unit) -> Unit)? = null,
    editor: PersonalProfileEditorViewModel? = null,
) {
    val profile = state.profile
    LaunchedEffect(state.session?.uid, state.session?.revision) {
        if (state.session != null) onRefresh()
    }
    var fallbackDraft by
        remember(state.session?.uid, state.session?.revision) {
            mutableStateOf(profile?.draft ?: ProfileDraft())
        }
    var baseline by
        remember(state.session?.uid, state.session?.revision) {
            mutableStateOf(profile?.draft ?: ProfileDraft())
        }
    var fallbackAttempted by
        remember(state.session?.uid, state.session?.revision) { mutableStateOf(false) }
    var regionMenu by
        remember(state.session?.uid, state.session?.revision) { mutableStateOf(false) }
    val stored = editor?.state?.collectAsStateWithLifecycle()?.value?.forSession(state.session)
    val draft = stored?.draft ?: fallbackDraft
    val attempted = stored?.attempted ?: fallbackAttempted
    fun change(value: ProfileDraft) {
        if (editor != null) editor.change(state.session, value) else fallbackDraft = value
    }
    LaunchedEffect(
        profile,
        state.session,
        state.profileSaved,
        state.profileLoading,
        state.profileSaving,
    ) {
        profile?.let {
            if (editor != null) {
                if (!state.profileLoading && !state.profileSaving)
                    editor.accept(state.session, it, state.profileSaved)
            } else {
                fallbackDraft =
                    if (state.profileSaved && fallbackDraft.normalized() == it.draft) it.draft
                    else mergeProfileDraft(baseline, fallbackDraft, it.draft)
                baseline = it.draft
            }
        }
    }
    Column(
        Modifier.fillMaxWidth().testTag("personal-profile"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            tr(language, "Mein Profil", "Мій профіль"),
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.semantics { heading() },
        )
        if (state.profileLoading || state.profileSaving)
            LinearProgressIndicator(Modifier.fillMaxWidth())
        PersonalError(state.profileError, language) {
            if (!avatarBusy) {
                if (profile == null) onRefresh()
                else if (editor != null) editor.attemptSave(state.session)?.let(onSave)
                else onSave(draft)
            }
        }
        if (profile != null) {
            Text(profile.email, style = MaterialTheme.typography.bodyMedium)
            Text(
                tr(
                    language,
                    "Dein Anzeigename, Wohnort, Bundesland und Profilbild sind öffentlich. E-Mail und Biografie bleiben im privaten Profil.",
                    "Відображуване ім’я, місто, федеральна земля та фото профілю є публічними. Email і біографія залишаються у приватному профілі.",
                ),
                style = MaterialTheme.typography.bodySmall,
            )
            val editable =
                state.session?.ready == true &&
                    !state.profileSaving &&
                    !state.profileLoading &&
                    !avatarBusy &&
                    (editor == null || stored?.confirmedSession == state.session)
            ProfileField(
                draft.fullName,
                { change(draft.copy(fullName = it)) },
                tr(language, "Vollständiger Name", "Повне ім’я"),
                "profile-full-name",
                editable,
                attempted && draft.fullName.trim().length !in 1..160,
                160,
            )
            ProfileField(
                draft.displayName,
                { change(draft.copy(displayName = it)) },
                tr(language, "Anzeigename", "Відображуване ім’я"),
                "profile-display-name",
                editable,
                attempted && draft.displayName.trim().length !in 1..160,
                160,
            )
            ProfileField(
                draft.city,
                { change(draft.copy(city = it)) },
                tr(language, "Stadt", "Місто"),
                "profile-city",
                editable,
                attempted && draft.city.trim().length > 160,
                160,
            )
            Column {
                OutlinedButton(
                    onClick = { regionMenu = true },
                    enabled = editable,
                    modifier = Modifier.testTag("profile-region"),
                ) {
                    val title = regions.firstOrNull { it.first == draft.federalState }?.second
                    Text(title ?: tr(language, "Bundesland auswählen", "Оберіть федеральну землю"))
                }
                DropdownMenu(expanded = regionMenu, onDismissRequest = { regionMenu = false }) {
                    regions.forEach { (key, title) ->
                        DropdownMenuItem(
                            text = { Text(title) },
                            onClick = {
                                change(draft.copy(federalState = key))
                                regionMenu = false
                            },
                        )
                    }
                }
            }
            ProfileField(
                draft.bio,
                { change(draft.copy(bio = it)) },
                tr(language, "Über mich", "Про мене"),
                "profile-bio",
                editable,
                attempted && draft.bio.trim().length > 2_000,
                2_000,
                multiline = true,
            )
            ProfileField(
                draft.telegramUsername,
                { change(draft.copy(telegramUsername = it)) },
                "Telegram",
                "profile-telegram",
                editable,
                attempted && draft.telegramUsername.trim().length > 80,
                80,
            )
            if (avatarEditor != null)
                avatarEditor(
                    draft.avatarUrl,
                    !state.profileSaving &&
                        !state.profileLoading &&
                        (editor == null || stored?.confirmedSession == state.session),
                ) { url ->
                    if (validProfileAvatar(url, state.session?.uid))
                        change(draft.copy(avatarUrl = url))
                }
            else
                ProfileField(
                    draft.avatarUrl,
                    { change(draft.copy(avatarUrl = it)) },
                    tr(language, "Profilbild: HTTPS-Adresse", "Фото профілю: HTTPS-адреса"),
                    "profile-avatar-url",
                    editable,
                    attempted &&
                        (draft.avatarUrl.trim().length > 2_048 ||
                            !validProfileAvatar(draft.avatarUrl.trim(), state.session?.uid)),
                    2_048,
                    url = true,
                )
            if (draft.avatarUrl.isNotEmpty())
                TextButton(onClick = { change(draft.copy(avatarUrl = "")) }, enabled = editable) {
                    Text(tr(language, "Profilbild entfernen", "Прибрати фото профілю"))
                }
            if (attempted && !draft.validFor(state.session?.uid))
                Text(
                    personalFailureText(PersonalFailure.INVALID, language),
                    color = MaterialTheme.colorScheme.error,
                )
            if (state.session?.ready != true)
                Text(personalFailureText(PersonalFailure.NOT_READY, language))
            Button(
                onClick = {
                    if (editor != null) editor.attemptSave(state.session)?.let(onSave)
                    else {
                        fallbackAttempted = true
                        if (draft.validFor(state.session?.uid)) onSave(draft)
                    }
                },
                enabled = editable,
                modifier = Modifier.testTag("profile-save"),
            ) {
                Text(tr(language, "Änderungen speichern", "Зберегти зміни"))
            }
            if (state.profileSaved && draft.normalized() == profile.draft)
                Text(
                    tr(
                        language,
                        "Gespeichert und vom Server bestätigt.",
                        "Збережено та підтверджено сервером.",
                    ),
                    modifier = Modifier.testTag("profile-saved"),
                )
        }
    }
}

/**
 * Refresh untouched fields, but never erase local edits merely because updatedAt or another field
 * changed.
 */
fun mergeProfileDraft(
    previous: ProfileDraft,
    local: ProfileDraft,
    server: ProfileDraft,
): ProfileDraft =
    ProfileDraft(
        fullName = if (local.fullName == previous.fullName) server.fullName else local.fullName,
        displayName =
            if (local.displayName == previous.displayName) server.displayName
            else local.displayName,
        city = if (local.city == previous.city) server.city else local.city,
        bio = if (local.bio == previous.bio) server.bio else local.bio,
        telegramUsername =
            if (local.telegramUsername == previous.telegramUsername) server.telegramUsername
            else local.telegramUsername,
        federalState =
            if (local.federalState == previous.federalState) server.federalState
            else local.federalState,
        avatarUrl =
            if (local.avatarUrl == previous.avatarUrl) server.avatarUrl else local.avatarUrl,
    )

@Composable
private fun ProfileField(
    value: String,
    change: (String) -> Unit,
    label: String,
    tag: String,
    enabled: Boolean,
    invalid: Boolean,
    maximum: Int,
    multiline: Boolean = false,
    url: Boolean = false,
) {
    OutlinedTextField(
        value = value,
        onValueChange = change,
        label = { Text(label) },
        enabled = enabled,
        isError = invalid,
        singleLine = !multiline,
        minLines = if (multiline) 3 else 1,
        keyboardOptions =
            KeyboardOptions(keyboardType = if (url) KeyboardType.Uri else KeyboardType.Text),
        supportingText = { Text("${value.length} / $maximum") },
        modifier = Modifier.fillMaxWidth().testTag(tag),
    )
}

@Composable
fun PersonalActionsRow(
    target: PersonalTarget,
    state: PersonalState,
    language: String,
    onLoad: () -> Unit,
    onChange: (PersonalAction, Boolean) -> Unit,
    onAccount: () -> Unit,
) {
    val ready = state.session?.ready == true
    val selected = state.actions[target]
    val pending = target in state.actionsPending || target in state.actionsLoading
    LaunchedEffect(target, state.session?.uid, state.session?.revision) { if (ready) onLoad() }
    Column(
        Modifier.fillMaxWidth().testTag("personal-actions"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (!ready) {
            TextButton(onClick = onAccount) {
                Text(
                    tr(
                        language,
                        "Zum Konto: speichern, liken und folgen",
                        "До облікового запису: збереження, вподобання та підписки",
                    )
                )
            }
        } else {
            if (pending) LinearProgressIndicator(Modifier.fillMaxWidth())
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val actions =
                    if (target.kind == ContentKind.ORGANIZATIONS) PersonalAction.entries
                    else listOf(PersonalAction.LIKE, PersonalAction.BOOKMARK)
                actions.forEach { action ->
                    val active = selected?.selected(action) == true
                    val title =
                        when (action) {
                            PersonalAction.LIKE ->
                                if (active) tr(language, "Gefällt dir", "Вам подобається")
                                else tr(language, "Gefällt mir", "Подобається")
                            PersonalAction.BOOKMARK ->
                                if (active) tr(language, "Gespeichert", "Збережено")
                                else tr(language, "Speichern", "Зберегти")
                            PersonalAction.SUBSCRIBE ->
                                if (active) tr(language, "Abonniert", "Ви підписані")
                                else tr(language, "Abonnieren", "Підписатися")
                        }
                    FilterChip(
                        selected = active,
                        onClick = { onChange(action, !active) },
                        label = { Text(title) },
                        enabled = !pending && selected != null,
                        modifier =
                            Modifier.testTag("personal-${action.name.lowercase(Locale.ROOT)}"),
                    )
                }
            }
            PersonalError(state.actionErrors[target], language, onLoad)
        }
    }
}

enum class PersonalSort {
    NEWEST,
    OLDEST,
    NAME_ASCENDING,
    NAME_DESCENDING,
}

fun sortedPersonalContent(
    items: List<Content>,
    language: String,
    sort: PersonalSort,
): List<Content> {
    fun date(item: Content): Instant =
        when (item.kind) {
            ContentKind.NEWS -> item.publishedAt
            ContentKind.EVENTS -> item.fields.time("startDate") ?: Instant.EPOCH
            ContentKind.ORGANIZATIONS -> item.fields.time("updatedAt") ?: Instant.EPOCH
        }
    val order =
        when (sort) {
            PersonalSort.NEWEST -> compareByDescending<Content>(::date)
            PersonalSort.OLDEST -> compareBy<Content>(::date)
            PersonalSort.NAME_ASCENDING ->
                compareBy<Content> { it.title(language).lowercase(Locale.forLanguageTag(language)) }
            PersonalSort.NAME_DESCENDING ->
                compareByDescending<Content> {
                    it.title(language).lowercase(Locale.forLanguageTag(language))
                }
        }
    return items.sortedWith(order.thenBy { it.kind.name }.thenBy { it.id })
}

@Composable
fun PersonalSavedScreen(
    state: PersonalState,
    language: String,
    onLoad: (Boolean) -> Unit,
    onOpen: (Content) -> Unit,
) {
    var selected by remember(state.session?.uid) { mutableStateOf<ContentKind?>(null) }
    var sort by remember(state.session?.uid) { mutableStateOf(PersonalSort.NEWEST) }
    var sortMenu by remember { mutableStateOf(false) }
    LaunchedEffect(state.session?.uid, state.session?.revision) { onLoad(false) }
    val pages = state.saved.filterKeys { selected == null || selected == it }.values
    val items = sortedPersonalContent(pages.flatMap { it.items }, language, sort)
    LazyColumn(
        Modifier.fillMaxWidth().testTag("personal-saved-list"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    tr(language, "Gespeicherte Inhalte", "Збережені матеріали"),
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.semantics { heading() },
                )
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    FilterChip(
                        selected == null,
                        { selected = null },
                        label = { Text(tr(language, "Alle", "Усі")) },
                    )
                    ContentKind.entries.forEach { kind ->
                        FilterChip(
                            selected == kind,
                            { selected = kind },
                            label = { Text(kind.label(language)) },
                        )
                    }
                }
                Column {
                    TextButton(onClick = { sortMenu = true }) {
                        Text(tr(language, "Sortieren", "Сортувати"))
                    }
                    DropdownMenu(sortMenu, { sortMenu = false }) {
                        PersonalSort.entries.forEach { option ->
                            DropdownMenuItem(
                                text = {
                                    Text(
                                        when (option) {
                                            PersonalSort.NEWEST ->
                                                tr(language, "Neueste zuerst", "Спочатку нові")
                                            PersonalSort.OLDEST ->
                                                tr(language, "Älteste zuerst", "Спочатку старі")
                                            PersonalSort.NAME_ASCENDING ->
                                                tr(language, "Name A–Z", "Назва А–Я")
                                            PersonalSort.NAME_DESCENDING ->
                                                tr(language, "Name Z–A", "Назва Я–А")
                                        }
                                    )
                                },
                                onClick = {
                                    sort = option
                                    sortMenu = false
                                },
                            )
                        }
                    }
                }
                if (state.savedLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
                PersonalError(state.savedError, language) { onLoad(false) }
                if (!state.savedLoading && state.savedError == null && items.isEmpty())
                    Text(
                        tr(
                            language,
                            "Hier erscheinen deine gespeicherten Nachrichten, Veranstaltungen und Organisationen.",
                            "Тут з’являться збережені новини, події та організації.",
                        )
                    )
                if (pages.sumOf { it.unavailable } > 0)
                    Text(
                        tr(
                            language,
                            "Einige gespeicherte Inhalte sind aktuell nicht sichtbar. Ihre Lesezeichen bleiben erhalten.",
                            "Деякі збережені матеріали зараз недоступні. Закладки залишаються збереженими.",
                        )
                    )
                if (state.saved.values.any { it.hasMore })
                    Text(
                        tr(
                            language,
                            "Die Sortierung gilt für geladene Inhalte. Weitere Einträge kannst du unten laden.",
                            "Сортування застосовується до завантажених матеріалів. Нижче можна завантажити решту.",
                        ),
                        style = MaterialTheme.typography.bodySmall,
                    )
            }
        }
        items(items, key = { "${it.kind}/${it.id}" }) { PersonalContentCard(it, language, onOpen) }
        item {
            if (state.saved.values.any { it.hasMore })
                Button(onClick = { onLoad(true) }, enabled = !state.savedLoading) {
                    Text(tr(language, "Mehr laden", "Завантажити ще"))
                }
            TextButton(onClick = { onLoad(false) }, enabled = !state.savedLoading) {
                Text(tr(language, "Aktualisieren", "Оновити"))
            }
        }
    }
}

@Composable
fun PersonalSubscriptionsScreen(
    state: PersonalState,
    language: String,
    onLoad: (Boolean) -> Unit,
    onOpen: (Content) -> Unit,
) {
    LaunchedEffect(state.session?.uid, state.session?.revision) { onLoad(false) }
    LazyColumn(
        Modifier.fillMaxWidth().testTag("personal-subscriptions-list"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    tr(language, "Meine Abonnements", "Мої підписки"),
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.semantics { heading() },
                )
                if (state.subscriptionsLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
                PersonalError(state.subscriptionsError, language) { onLoad(false) }
                if (
                    !state.subscriptionsLoading &&
                        state.subscriptionsError == null &&
                        state.subscriptions?.items.isNullOrEmpty()
                )
                    Text(
                        tr(
                            language,
                            "Noch keine sichtbaren Abonnements auf dieser Seite.",
                            "На цій сторінці поки немає доступних підписок.",
                        )
                    )
                if ((state.subscriptions?.unavailable ?: 0) > 0)
                    Text(
                        tr(
                            language,
                            "Einige abonnierte Organisationen sind derzeit nicht öffentlich sichtbar.",
                            "Деякі організації, на які ви підписані, зараз не є публічно доступними.",
                        )
                    )
            }
        }
        items(state.subscriptions?.items.orEmpty(), key = { it.id }) {
            PersonalContentCard(it, language, onOpen)
        }
        item {
            if (state.subscriptions?.hasMore == true)
                Button(onClick = { onLoad(true) }, enabled = !state.subscriptionsLoading) {
                    Text(tr(language, "Mehr laden", "Завантажити ще"))
                }
            TextButton(onClick = { onLoad(false) }, enabled = !state.subscriptionsLoading) {
                Text(tr(language, "Aktualisieren", "Оновити"))
            }
        }
    }
}

@Composable
private fun PersonalContentCard(item: Content, language: String, onOpen: (Content) -> Unit) {
    Card(onClick = { onOpen(item) }, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(item.kind.label(language), style = MaterialTheme.typography.labelMedium)
            Text(item.title(language), style = MaterialTheme.typography.titleMedium)
            Text(item.summary(language), style = MaterialTheme.typography.bodyMedium, maxLines = 3)
        }
    }
}
