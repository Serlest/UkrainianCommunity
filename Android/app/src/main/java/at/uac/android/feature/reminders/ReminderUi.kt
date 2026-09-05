package at.uac.android.feature.reminders

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.feature.browse.tr

/**
 * Embeddable in the host settings scroll container; no permission or preference mutation on
 * composition.
 */
@Composable
fun ReminderSettingsCard(
    state: ReminderState,
    language: String,
    onRequestPermission: () -> Unit,
    onOpenSettings: () -> Unit,
    onRetry: () -> Unit,
    onLocalTest: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Card(modifier.fillMaxWidth().testTag("reminders-settings")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                tr(language, "Lokale Veranstaltungserinnerungen", "Локальні нагадування про події"),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                tr(
                    language,
                    "Android kann Erinnerungen verzögert zustellen. Vor der Anzeige werden die aktuellen Angaben am Testserver geprüft. Offline erscheint keine Erinnerung.",
                    "Android може показати нагадування із затримкою. Перед показом перевіряються актуальні дані тестового сервера. Без мережі нагадування не з’явиться.",
                )
            )
            Text(
                when (state.permission) {
                    ReminderPermission.APP_DENIED ->
                        tr(
                            language,
                            "Systembenachrichtigungen sind nicht erlaubt.",
                            "Системні сповіщення не дозволено.",
                        )
                    ReminderPermission.CHANNEL_DENIED ->
                        tr(
                            language,
                            "Der Erinnerungskanal ist ausgeschaltet.",
                            "Канал нагадувань вимкнено.",
                        )
                    ReminderPermission.ALLOWED ->
                        tr(
                            language,
                            "Systembenachrichtigungen sind erlaubt.",
                            "Системні сповіщення дозволено.",
                        )
                },
                Modifier.testTag("reminders-permission"),
            )
            if (state.permission == ReminderPermission.APP_DENIED) {
                Button(
                    onRequestPermission,
                    Modifier.fillMaxWidth().testTag("reminders-permission-request"),
                ) {
                    Text(tr(language, "Systemerlaubnis anfragen", "Запросити системний дозвіл"))
                }
            }
            if (state.permission != ReminderPermission.ALLOWED) {
                OutlinedButton(
                    onOpenSettings,
                    Modifier.fillMaxWidth().testTag("reminders-system-settings"),
                ) {
                    Text(tr(language, "Benachrichtigungseinstellungen", "Налаштування сповіщень"))
                }
            }
            Text(
                when (state.stage) {
                    ReminderStage.CHECKING ->
                        tr(
                            language,
                            "Aktuelle Anmeldungen werden geprüft …",
                            "Перевіряємо актуальні реєстрації…",
                        )
                    ReminderStage.SCHEDULED ->
                        tr(
                            language,
                            "Geplant: ${state.scheduled}. Dies bestätigt noch keine Zustellung.",
                            "Заплановано: ${state.scheduled}. Це ще не підтверджує доставку.",
                        )
                    ReminderStage.DISABLED ->
                        tr(language, "Erinnerungen sind ausgeschaltet.", "Нагадування вимкнено.")
                    ReminderStage.IDLE ->
                        tr(
                            language,
                            "Für dieses Konto ist noch kein Zeitplan bestätigt.",
                            "Для цього облікового запису розклад ще не підтверджено.",
                        )
                    ReminderStage.FAILED ->
                        when (state.error) {
                            ReminderFailure.LIMIT ->
                                tr(
                                    language,
                                    "Zu viele Einträge: Es wurde kein unvollständiger Zeitplan aktiviert.",
                                    "Забагато записів: неповний розклад не активовано.",
                                )
                            ReminderFailure.STORAGE ->
                                tr(
                                    language,
                                    "Der lokale Prüfvermerk konnte nicht sicher gespeichert werden.",
                                    "Не вдалося надійно зберегти локальну позначку перевірки.",
                                )
                            else ->
                                tr(
                                    language,
                                    "Der Zeitplan konnte nicht bestätigt werden. Bitte erneut prüfen.",
                                    "Не вдалося підтвердити розклад. Перевірте ще раз.",
                                )
                        }
                },
                Modifier.testTag("reminders-status"),
            )
            OutlinedButton(
                onRetry,
                Modifier.fillMaxWidth().testTag("reminders-retry"),
                enabled = state.stage != ReminderStage.CHECKING,
            ) {
                Text(tr(language, "Zeitplan erneut prüfen", "Перевірити розклад ще раз"))
            }
            Button(
                onLocalTest,
                Modifier.fillMaxWidth().testTag("reminders-local-test"),
                enabled =
                    state.permission == ReminderPermission.ALLOWED &&
                        state.stage == ReminderStage.SCHEDULED,
            ) {
                Text(tr(language, "Lokale Erinnerung testen", "Перевірити локальне нагадування"))
            }
            if (state.localTestRequested)
                Text(
                    tr(
                        language,
                        "Lokaler Test angefordert. Android bestimmt den Zeitpunkt; dies ist kein Cloud-Push-Test.",
                        "Локальну перевірку запитано. Час визначає Android; це не перевірка хмарного push.",
                    ),
                    Modifier.testTag("reminders-local-test-requested"),
                )
        }
    }
}
