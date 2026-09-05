package at.uac.android.feature.registrations

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.feature.browse.*
import at.uac.android.feature.personal.personalFailureText
import java.time.Instant

@Composable
fun RegistrationsScreen(
    state: RegistrationsState,
    language: String,
    onRefresh: (Boolean) -> Unit,
    onSegment: (RegistrationSegment) -> Unit,
    onOpen: (Content) -> Unit,
    onAccount: () -> Unit,
) {
    LaunchedEffect(state.session) { if (state.session?.ready == true) onRefresh(false) }
    val now = Instant.now()
    val items = registrationEvents(state.items, state.segment, now)
    LazyColumn(
        Modifier.fillMaxSize().testTag("registrations-list"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        contentPadding = PaddingValues(bottom = 32.dp),
    ) {
        item("header") {
            Heading(tr(language, "Meine Veranstaltungen", "Мої події"))
            Text(
                tr(
                    language,
                    "Deine Anmeldungen. Öffne eine Veranstaltung, um die Teilnahme zu verwalten.",
                    "Ваші реєстрації. Відкрийте подію, щоб керувати участю.",
                )
            )
        }
        if (state.session?.ready != true)
            item("account") {
                Text(
                    tr(
                        language,
                        "Bestätige deinen Kontostatus, um Anmeldungen zu sehen.",
                        "Підтвердьте стан облікового запису, щоб переглянути реєстрації.",
                    )
                )
                Button(onAccount, Modifier.testTag("registrations-account")) {
                    Text(tr(language, "Zum Konto", "До облікового запису"))
                }
            }
        else {
            item("filters") {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    RegistrationSegment.entries.forEach { segment ->
                        val label =
                            when (segment) {
                                RegistrationSegment.ALL -> tr(language, "Alle", "Усі")
                                RegistrationSegment.UPCOMING ->
                                    tr(language, "Heute & künftig", "Сьогодні й майбутні")
                                RegistrationSegment.PAST -> tr(language, "Vergangen", "Минулі")
                            }
                        FilterChip(
                            state.segment == segment,
                            { onSegment(segment) },
                            {
                                Text(
                                    "$label: ${registrationEvents(state.items, segment, now).size}"
                                )
                            },
                            modifier =
                                Modifier.testTag(
                                    "registrations-filter-${segment.name.lowercase()}"
                                ),
                        )
                    }
                }
                if (state.hasMore)
                    Text(
                        tr(
                            language,
                            "Die Zahlen beziehen sich auf die bisher geladenen Anmeldungen.",
                            "Кількість стосується вже завантажених реєстрацій.",
                        ),
                        style = MaterialTheme.typography.bodySmall,
                    )
                TextButton(
                    { onRefresh(false) },
                    enabled = !state.loading,
                    modifier = Modifier.testTag("registrations-refresh"),
                ) {
                    Text(tr(language, "Aktualisieren", "Оновити"))
                }
            }
            if (state.loading)
                item("loading") {
                    LinearProgressIndicator(
                        Modifier.fillMaxWidth().testTag("registrations-loading")
                    )
                }
            state.error?.let { failure ->
                item("error") {
                    Text(
                        personalFailureText(failure, language),
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.testTag("registrations-error"),
                    )
                    if (state.items.isNotEmpty())
                        Text(
                            tr(
                                language,
                                "Zuletzt bestätigte Anmeldungen; Änderungen sind möglicherweise noch nicht sichtbar.",
                                "Останні підтверджені реєстрації; нові зміни можуть ще не відображатися.",
                            )
                        )
                }
            }
            if (state.unavailable > 0)
                item("unavailable") {
                    Text(
                        tr(
                            language,
                            "Einige Veranstaltungen sind nicht mehr öffentlich verfügbar. Deine Anmeldungen wurden nicht verändert.",
                            "Деякі події більше не доступні публічно. Ваші реєстрації не змінено.",
                        ),
                        Modifier.testTag("registrations-unavailable"),
                    )
                }
            items(items, key = { it.id }) { event ->
                OutlinedCard(
                    onClick = { onOpen(event) },
                    modifier = Modifier.fillMaxWidth().testTag("registration-${event.id}"),
                ) {
                    Column(
                        Modifier.padding(18.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(event.title(language), style = MaterialTheme.typography.titleMedium)
                        Text(displayTime(event.fields.time("startDate")!!, language))
                        Text(
                            event.fields.string("city"),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        if (event.fields.string("cancellationState") == "cancelled")
                            Text(
                                tr(language, "Abgesagt", "Скасовано"),
                                color = MaterialTheme.colorScheme.error,
                            )
                        Text(
                            tr(language, "Anmeldung bestätigt", "Реєстрацію підтверджено"),
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                }
            }
            if (state.loaded && !state.loading && state.error == null && items.isEmpty())
                item("empty") {
                    Text(
                        tr(
                            language,
                            "In dieser Auswahl gibt es keine Anmeldungen.",
                            "У цьому розділі немає реєстрацій.",
                        ),
                        Modifier.testTag("registrations-empty"),
                    )
                }
            if (state.hasMore)
                item("more") {
                    Button(
                        { onRefresh(true) },
                        enabled = !state.loading,
                        modifier = Modifier.testTag("registrations-more"),
                    ) {
                        Text(
                            tr(language, "Weitere Anmeldungen laden", "Завантажити інші реєстрації")
                        )
                    }
                }
        }
    }
}
