package at.uac.android.feature.attendees

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
import at.uac.android.core.LocalStorage
import at.uac.android.feature.browse.PublicImage
import at.uac.android.feature.browse.displayTime
import at.uac.android.feature.browse.tr

data class AttendeesActions(
    val back: () -> Unit = {},
    val account: () -> Unit = {},
    val refresh: () -> Unit = {},
    val more: () -> Unit = {},
    val search: (String) -> Unit = {},
    val sort: (AttendeesSort) -> Unit = {},
)

/**
 * Private data exists only while this exact account and event are resumed. No nested scrolling host
 * is required.
 */
@Composable
fun AttendeesScreen(
    model: AttendeesViewModel,
    eventId: String,
    session: AttendeesSession?,
    language: String,
    onBack: () -> Unit,
    onAccount: () -> Unit,
) {
    val stored by model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    val state = stored.forSession(session, eventId)
    LifecycleResumeEffect(session, eventId) {
        model.show(eventId)
        onPauseOrDispose { model.hide() }
    }
    AttendeesContent(
        state,
        language,
        AttendeesActions(
            onBack,
            onAccount,
            { model.refresh() },
            { model.refresh(more = true) },
            model::search,
            model::sort,
        ),
    )
}

@Composable
fun AttendeesContent(state: AttendeesState, language: String, actions: AttendeesActions) {
    // A populated stale state is never sufficient to show attendee names, even when supplied by a
    // host.
    val page =
        state.page?.takeIf {
            state.visible &&
                state.session?.ready == true &&
                it.session == state.session &&
                it.event.id == state.eventId &&
                !state.loading &&
                state.error == null
        }
    val people =
        page
            ?.let { AttendeesContract.visible(it.people, state.search, state.sort, language) }
            .orEmpty()
    LazyColumn(
        Modifier.fillMaxSize().testTag("attendees-list"),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item("header") {
            TextButton(actions.back, Modifier.testTag("attendees-back")) {
                Text(tr(language, "Zurück", "Назад"))
            }
            Text(
                tr(language, "Teilnehmende", "Учасники"),
                style = MaterialTheme.typography.headlineMedium,
            )
            Text(
                tr(
                    language,
                    "Nur für die berechtigte Veranstaltungsverwaltung. Angezeigt werden öffentliche Namen und Anmeldezeitpunkte.",
                    "Лише для уповноважених організаторів. Показано публічні імена й час реєстрації.",
                ),
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        if (state.session?.ready != true) {
            item("account") {
                Text(
                    attendeesFailureText(
                        if (state.session == null) AttendeesFailure.SIGN_IN
                        else AttendeesFailure.NOT_READY,
                        language,
                    )
                )
                Button(actions.account, Modifier.testTag("attendees-account")) {
                    Text(tr(language, "Konto öffnen", "Відкрити акаунт"))
                }
            }
        } else {
            item("refresh") {
                TextButton(
                    actions.refresh,
                    Modifier.testTag("attendees-refresh"),
                    enabled = !state.loading,
                ) {
                    Text(
                        tr(
                            language,
                            "Berechtigung und Liste aktualisieren",
                            "Оновити права та список",
                        )
                    )
                }
            }
            if (state.loading)
                item("loading") {
                    LinearProgressIndicator(Modifier.fillMaxWidth().testTag("attendees-loading"))
                }
            state.error?.let { failure ->
                item("error") {
                    Text(
                        attendeesFailureText(failure, language),
                        Modifier.testTag("attendees-error"),
                        color = MaterialTheme.colorScheme.error,
                    )
                    Text(
                        tr(
                            language,
                            "Die vorherige Liste bleibt verborgen, bis der Server den Zugriff erneut bestätigt.",
                            "Попередній список приховано до повторного підтвердження доступу сервером.",
                        )
                    )
                    TextButton(
                        actions.refresh,
                        Modifier.testTag("attendees-retry"),
                        enabled = !state.loading,
                    ) {
                        Text(tr(language, "Erneut prüfen", "Перевірити знову"))
                    }
                }
            }
            if (page != null) {
                item("event") {
                    Text(page.event.title(language), style = MaterialTheme.typography.titleLarge)
                    Text(
                        tr(
                            language,
                            "${page.people.size} Anmeldungen geladen",
                            "Завантажено реєстрацій: ${page.people.size}",
                        ),
                        Modifier.testTag("attendees-loaded-count"),
                    )
                    page.event.capacity?.let {
                        Text(tr(language, "Kapazität: $it", "Місткість: $it"))
                    }
                    if (page.next != null)
                        Text(
                            tr(
                                language,
                                "Suche und Sortierung beziehen sich nur auf bereits geladene Personen. Weitere Anmeldungen sind verfügbar.",
                                "Пошук і сортування стосуються лише завантажених учасників. Є ще реєстрації.",
                            ),
                            Modifier.testTag("attendees-partial"),
                        )
                    else
                        Text(
                            tr(
                                language,
                                "Alle verfügbaren Anmeldungen sind geladen.",
                                "Усі доступні реєстрації завантажено.",
                            ),
                            Modifier.testTag("attendees-complete"),
                        )
                }
                item("search") {
                    OutlinedTextField(
                        state.search,
                        actions.search,
                        Modifier.fillMaxWidth().testTag("attendees-search"),
                        label = {
                            Text(
                                tr(
                                    language,
                                    "In geladenen Namen suchen",
                                    "Пошук серед завантажених імен",
                                )
                            )
                        },
                        singleLine = true,
                    )
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AttendeesSort.entries.forEach { sort ->
                            FilterChip(
                                state.sort == sort,
                                { actions.sort(sort) },
                                { Text(attendeesSortText(sort, language)) },
                                modifier =
                                    Modifier.testTag("attendees-sort-${sort.name.lowercase()}"),
                            )
                        }
                    }
                }
                if (page.invalid > 0)
                    item("invalid") {
                        Text(
                            tr(
                                language,
                                "Einige unvollständige Einträge konnten nicht angezeigt werden. Es wurde nichts geändert.",
                                "Деякі неповні записи неможливо показати. Дані не змінено.",
                            ),
                            Modifier.testTag("attendees-unavailable"),
                        )
                    }
                if (people.isEmpty())
                    item("empty") {
                        Text(
                            if (state.search.isBlank())
                                tr(
                                    language,
                                    "Noch keine sichtbaren Anmeldungen.",
                                    "Видимих реєстрацій поки немає.",
                                )
                            else
                                tr(
                                    language,
                                    "Keine passenden geladenen Namen.",
                                    "Серед завантажених імен збігів немає.",
                                ),
                            Modifier.testTag("attendees-empty"),
                        )
                    }
                items(people, key = { it.id }) { person -> AttendeeCard(person, language) }
                if (page.next != null)
                    item("more") {
                        Button(actions.more, Modifier.fillMaxWidth().testTag("attendees-more")) {
                            Text(
                                tr(
                                    language,
                                    "Weitere Anmeldungen laden",
                                    "Завантажити інші реєстрації",
                                )
                            )
                        }
                    }
            }
        }
    }
}

@Composable
private fun AttendeeCard(person: Attendee, language: String) {
    val name =
        person.displayName?.takeIf(String::isNotBlank)
            ?: tr(language, "Community-Mitglied", "Учасник спільноти")
    OutlinedCard(Modifier.fillMaxWidth().testTag("attendee-${person.id}")) {
        Row(
            Modifier.padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Surface(
                Modifier.size(48.dp),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.secondaryContainer,
            ) {
                Box(contentAlignment = Alignment.Center) {
                    val url = person.avatarUrl
                    if (
                        url != null &&
                            LocalStorage.urlMatches(
                                url,
                                "profileImages/${person.userId}/avatar.jpg",
                            )
                    ) {
                        Box(Modifier.size(48.dp).clip(CircleShape)) {
                            PublicImage(url, name, language)
                        }
                    } else
                        Text(
                            name.substring(0, name.offsetByCodePoints(0, 1)).uppercase(),
                            style = MaterialTheme.typography.titleLarge,
                        )
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(name, style = MaterialTheme.typography.titleMedium)
                Text(
                    person.registeredAt?.let { displayTime(it, language) }
                        ?: tr(
                            language,
                            "Anmeldezeitpunkt nicht verfügbar",
                            "Час реєстрації недоступний",
                        ),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}

fun attendeesSortText(sort: AttendeesSort, language: String): String =
    when (sort) {
        AttendeesSort.OLDEST -> tr(language, "Zuerst angemeldet", "Спочатку найдавніші")
        AttendeesSort.NEWEST -> tr(language, "Zuletzt angemeldet", "Спочатку найновіші")
        AttendeesSort.NAME_ASCENDING -> tr(language, "Name A–Z", "Ім’я А–Я")
        AttendeesSort.NAME_DESCENDING -> tr(language, "Name Z–A", "Ім’я Я–А")
    }

fun attendeesFailureText(failure: AttendeesFailure, language: String): String =
    when (failure) {
        AttendeesFailure.SIGN_IN ->
            tr(
                language,
                "Bitte anmelden, um Verwaltungsrechte prüfen zu lassen.",
                "Увійдіть, щоб перевірити права організатора.",
            )
        AttendeesFailure.NOT_READY ->
            tr(
                language,
                "Bestätigung, Kontostatus oder Sicherheitsanforderungen sind noch offen. Bitte das Konto prüfen.",
                "Не завершено підтвердження, перевірку стану чи вимог безпеки. Перевірте акаунт.",
            )
        AttendeesFailure.DENIED ->
            tr(
                language,
                "Du hast derzeit keine Berechtigung für diese Teilnehmerliste.",
                "Наразі ви не маєте доступу до цього списку учасників.",
            )
        AttendeesFailure.MISSING ->
            tr(
                language,
                "Die Veranstaltung oder Organisation ist nicht mehr verfügbar.",
                "Подія або організація більше не доступна.",
            )
        AttendeesFailure.NOT_APPLICABLE ->
            tr(
                language,
                "Für diese Veranstaltung gibt es keine interne Teilnehmerverwaltung.",
                "Для цієї події немає внутрішнього списку учасників.",
            )
        AttendeesFailure.OFFLINE ->
            tr(
                language,
                "Der Server ist nicht erreichbar. Die private Liste wird nicht aus dem Cache angezeigt.",
                "Сервер недоступний. Приватний список не буде показано з кешу.",
            )
        AttendeesFailure.INDEX ->
            tr(
                language,
                "Die Serverabfrage ist noch nicht verfügbar. Bitte später erneut prüfen.",
                "Серверний запит ще не доступний. Спробуйте пізніше.",
            )
        AttendeesFailure.INVALID,
        AttendeesFailure.UNKNOWN ->
            tr(
                language,
                "Die Liste konnte nicht sicher bestätigt werden. Bitte erneut prüfen.",
                "Не вдалося безпечно підтвердити список. Перевірте знову.",
            )
    }
