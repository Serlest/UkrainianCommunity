package at.uac.android.feature.subscribers

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.PublicImage
import at.uac.android.feature.browse.PublicMediaPolicy
import at.uac.android.feature.browse.regions
import at.uac.android.feature.browse.tr

data class SubscribersActions(
    val back: () -> Unit = {},
    val account: () -> Unit = {},
    val refresh: () -> Unit = {},
    val more: () -> Unit = {},
    val search: (String) -> Unit = {},
)

/** Eligibility uses the host's confirmed public detail, never a speculative likes/profile fetch. */
@Composable
fun SubscribersAccessPanel(
    content: Content,
    session: SubscriberSession?,
    language: String,
    onOpen: (String) -> Unit,
    onAccount: () -> Unit,
    currentTarget: () -> Boolean,
) {
    if (
        content.kind != ContentKind.ORGANIZATIONS ||
            !SubscribersContract.organizationId(content.id) ||
            content.fields["moderationStatus"] != "approved" ||
            !currentTarget()
    )
        return
    if (session?.ready == true)
        OutlinedButton(
            { if (currentTarget()) onOpen(content.id) },
            Modifier.fillMaxWidth().testTag("subscribers-open"),
        ) {
            Text(tr(language, "Community ansehen", "Переглянути спільноту"))
        }
    else
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                tr(
                    language,
                    "Die öffentliche Teamliste bleibt sichtbar. Für die Community-Liste bitte das Konto bestätigen.",
                    "Публічна команда залишається доступною. Для списку спільноти підтвердьте акаунт.",
                )
            )
            OutlinedButton(
                { if (currentTarget()) onAccount() },
                Modifier.testTag("subscribers-open-account"),
            ) {
                Text(tr(language, "Konto öffnen", "Відкрити акаунт"))
            }
        }
}

@Composable
fun SubscribersScreen(
    model: SubscribersViewModel,
    organizationId: String,
    session: SubscriberSession?,
    language: String,
    onBack: () -> Unit,
    onAccount: () -> Unit,
    visibleOrganization: (Content) -> Boolean,
    visibleAuthor: (String?) -> Boolean,
) {
    val stored by model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    LifecycleResumeEffect(session, organizationId) {
        model.show(organizationId)
        onPauseOrDispose { model.hide() }
    }
    val leave = {
        model.hide()
        onBack()
    }
    BackHandler(onBack = leave)
    SubscribersContent(
        stored.forSession(session, organizationId),
        language,
        SubscribersActions(
            leave,
            {
                model.hide()
                onAccount()
            },
            { model.refresh() },
            { model.refresh(more = true) },
            model::search,
        ),
        visibleOrganization,
        visibleAuthor,
    )
}

@Composable
fun SubscribersContent(
    state: SubscribersState,
    language: String,
    actions: SubscribersActions,
    visibleOrganization: (Content) -> Boolean,
    visibleAuthor: (String?) -> Boolean,
) {
    val page = state.visiblePage(visibleOrganization, visibleAuthor)
    val people =
        page
            ?.let { SubscribersContract.visible(it.members, state.search, language, visibleAuthor) }
            .orEmpty()
    LazyColumn(
        Modifier.fillMaxSize().imePadding().testTag("subscribers-list"),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item("header") {
            TextButton(actions.back, Modifier.testTag("subscribers-back")) {
                Text(tr(language, "Zurück", "Назад"))
            }
            Text(
                tr(language, "Community", "Спільнота"),
                style = MaterialTheme.typography.headlineMedium,
            )
            Text(
                tr(
                    language,
                    "Öffentliche Profile des Teams und der Abonnierenden. Hier werden keine Organisationsrollen geändert.",
                    "Публічні профілі команди та підписників. Тут не змінюються ролі в організації.",
                )
            )
        }
        if (state.session?.ready != true)
            item("account") {
                Text(
                    subscribersFailureText(
                        if (state.session == null) SubscribersFailure.SIGN_IN
                        else SubscribersFailure.NOT_READY,
                        language,
                    )
                )
                Button(actions.account, Modifier.testTag("subscribers-account")) {
                    Text(tr(language, "Konto öffnen", "Відкрити акаунт"))
                }
            }
        else {
            item("refresh") {
                TextButton(
                    actions.refresh,
                    Modifier.testTag("subscribers-refresh"),
                    enabled = !state.loading,
                ) {
                    Text(tr(language, "Liste und Zugriff aktualisieren", "Оновити список і доступ"))
                }
            }
            if (state.loading)
                item("loading") {
                    LinearProgressIndicator(Modifier.fillMaxWidth().testTag("subscribers-loading"))
                }
            state.error?.let { failure ->
                item("error") {
                    Text(
                        subscribersFailureText(failure, language),
                        Modifier.testTag("subscribers-error"),
                        color = MaterialTheme.colorScheme.error,
                    )
                    TextButton(
                        actions.refresh,
                        Modifier.testTag("subscribers-retry"),
                        enabled = !state.loading,
                    ) {
                        Text(tr(language, "Erneut prüfen", "Перевірити знову"))
                    }
                }
            }
            if (page == null && state.page != null && !state.loading && state.error == null)
                item("policy") {
                    Text(
                        subscribersFailureText(SubscribersFailure.POLICY, language),
                        Modifier.testTag("subscribers-policy"),
                    )
                }
            if (page != null) {
                item("organization") {
                    Text(
                        page.organization.content.title(language),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    Text(
                        tr(
                            language,
                            "${page.references.size} Abonnements geladen",
                            "Завантажено підписок: ${page.references.size}",
                        ),
                        Modifier.testTag("subscribers-loaded-count"),
                    )
                    Text(
                        tr(
                            language,
                            "Die Suche erfasst nur geladene, sichtbare öffentliche Namen. Rollen stehen vor Abonnierenden; neue Abonnements zuerst.",
                            "Пошук охоплює лише завантажені видимі публічні імена. Спочатку команда, потім нові підписки.",
                        ),
                        Modifier.testTag("subscribers-loaded-only"),
                    )
                    if (page.capped)
                        Text(
                            tr(
                                language,
                                "Das erste Fenster mit 200 Abonnements ist geladen. Weitere Einträge sind nicht in dieser Ansicht enthalten.",
                                "Завантажено перше вікно з 200 підписок. Інші записи не входять до цього перегляду.",
                            ),
                            Modifier.testTag("subscribers-cap"),
                        )
                    else if (page.next != null)
                        Text(
                            tr(
                                language,
                                "Weitere Abonnements können geladen werden.",
                                "Можна завантажити інші підписки.",
                            ),
                            Modifier.testTag("subscribers-partial"),
                        )
                    else
                        Text(
                            tr(
                                language,
                                "Alle derzeit verfügbaren Abonnement-Einträge sind geladen; nicht jedes Profil ist sichtbar.",
                                "Усі наразі доступні записи підписок завантажено; не кожен профіль видимий.",
                            ),
                            Modifier.testTag("subscribers-complete"),
                        )
                    if (page.organization.teamTruncated)
                        Text(
                            tr(
                                language,
                                "Angezeigt werden höchstens 200 offizielle Teamprofile. Die Serverrollen bleiben unverändert.",
                                "Показано не більше 200 офіційних профілів команди. Ролі на сервері не змінено.",
                            ),
                            Modifier.testTag("subscribers-team-cap"),
                        )
                }
                item("search") {
                    OutlinedTextField(
                        state.search,
                        actions.search,
                        Modifier.fillMaxWidth().testTag("subscribers-search"),
                        label = {
                            Text(
                                tr(
                                    language,
                                    "Geladene Namen durchsuchen",
                                    "Пошук у завантажених іменах",
                                )
                            )
                        },
                        singleLine = true,
                    )
                }
                if (page.unavailable > 0)
                    item("unavailable") {
                        Text(
                            tr(
                                language,
                                "Einige öffentliche Profile sind nicht verfügbar. Die Abonnements wurden nicht geändert.",
                                "Деякі публічні профілі недоступні. Підписки не змінено.",
                            ),
                            Modifier.testTag("subscribers-unavailable"),
                        )
                    }
                if (people.isEmpty())
                    item("empty") {
                        Text(
                            if (state.search.isBlank())
                                tr(
                                    language,
                                    "Keine sichtbaren öffentlichen Profile.",
                                    "Немає видимих публічних профілів.",
                                )
                            else
                                tr(
                                    language,
                                    "Keine passenden geladenen Namen.",
                                    "Серед завантажених імен збігів немає.",
                                ),
                            Modifier.testTag("subscribers-empty"),
                        )
                    }
                items(people, key = { it.userId }) { person -> SubscriberCard(person, language) }
                if (page.next != null)
                    item("more") {
                        Button(actions.more, Modifier.fillMaxWidth().testTag("subscribers-more")) {
                            Text(tr(language, "Weitere laden", "Завантажити ще"))
                        }
                    }
            }
        }
    }
}

@Composable
private fun SubscriberCard(person: SubscriberMember, language: String) {
    val profile = person.profile
    val name = profile?.displayName ?: tr(language, "Profil nicht verfügbar", "Профіль недоступний")
    OutlinedCard(Modifier.fillMaxWidth().testTag("subscriber-${person.userId}")) {
        Row(
            Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Surface(
                Modifier.size(48.dp),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.secondaryContainer,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    val avatar = profile?.avatarUrl
                    if (avatar != null && PublicMediaPolicy.address(avatar) != null)
                        PublicImage(
                            avatar,
                            name,
                            language,
                            Modifier.size(48.dp).clip(CircleShape),
                            compact = true,
                        )
                    else
                        Text(
                            name.substring(0, name.offsetByCodePoints(0, 1)).uppercase(),
                            style = MaterialTheme.typography.titleLarge,
                        )
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(name, style = MaterialTheme.typography.titleMedium)
                if (profile == null)
                    Text(
                        tr(
                            language,
                            "Offizielle Rolle; öffentliches Profil fehlt.",
                            "Офіційна роль; публічний профіль відсутній.",
                        )
                    )
                else {
                    val region =
                        regions
                            .firstOrNull { it.first == profile.region }
                            ?.second
                            ?.let {
                                if (language == "uk") it.substringAfter(" / ")
                                else it.substringBefore(" / ")
                            }
                    listOfNotNull(profile.city.takeIf(String::isNotBlank), region)
                        .joinToString(", ")
                        .takeIf(String::isNotBlank)
                        ?.let {
                            Text(it, style = MaterialTheme.typography.bodyMedium)
                        }
                }
                Text(
                    subscriberRoleText(person.role, language),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.testTag("subscriber-role-${person.userId}"),
                )
            }
        }
    }
}

fun subscriberRoleText(role: SubscriberRole, language: String) =
    when (role) {
        SubscriberRole.OWNER -> tr(language, "Inhaber:in", "Власник / власниця")
        SubscriberRole.ADMIN -> tr(language, "Administrator:in", "Адміністратор / адміністраторка")
        SubscriberRole.MODERATOR -> tr(language, "Moderator:in", "Модератор / модераторка")
        SubscriberRole.SUBSCRIBER -> tr(language, "Mitglied", "Учасник / учасниця")
    }

fun subscribersFailureText(failure: SubscribersFailure, language: String) =
    when (failure) {
        SubscribersFailure.SIGN_IN ->
            tr(
                language,
                "Bitte anmelden, um die Community-Liste zu öffnen.",
                "Увійдіть, щоб відкрити список спільноти.",
            )
        SubscribersFailure.NOT_READY ->
            tr(
                language,
                "Bestätigung, Kontostatus oder Sicherheitsanforderungen sind noch offen. Bitte das Konto prüfen.",
                "Не завершено підтвердження акаунта або вимоги безпеки. Перевірте акаунт.",
            )
        SubscribersFailure.DENIED,
        SubscribersFailure.MISSING ->
            tr(
                language,
                "Die Organisation oder der Zugriff auf ihre Community ist nicht mehr verfügbar.",
                "Організація або доступ до її спільноти більше не доступні.",
            )
        SubscribersFailure.POLICY ->
            tr(
                language,
                "Die Sichtbarkeit ist noch nicht bestätigt oder die Organisation ist ausgeblendet.",
                "Видимість ще не підтверджено або організацію приховано.",
            )
        SubscribersFailure.STALE ->
            tr(
                language,
                "Die Liste hat sich während des Ladens geändert. Bitte erneut prüfen.",
                "Список змінився під час завантаження. Перевірте знову.",
            )
        SubscribersFailure.OFFLINE ->
            tr(
                language,
                "Der Server ist nicht erreichbar. Die Community-Liste bleibt verborgen, bis der Zugriff bestätigt ist.",
                "Сервер недоступний. Список спільноти приховано до підтвердження доступу.",
            )
        SubscribersFailure.INDEX ->
            tr(
                language,
                "Die Serverabfrage ist noch nicht verfügbar. Bitte später erneut prüfen.",
                "Серверний запит поки недоступний. Спробуйте пізніше.",
            )
        SubscribersFailure.INVALID,
        SubscribersFailure.UNKNOWN ->
            tr(
                language,
                "Die Liste konnte nicht sicher bestätigt werden. Bitte erneut prüfen.",
                "Не вдалося безпечно підтвердити список. Перевірте знову.",
            )
    }
