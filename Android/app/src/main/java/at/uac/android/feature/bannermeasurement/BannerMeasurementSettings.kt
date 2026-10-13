package at.uac.android.feature.bannermeasurement

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.core.ProtectedAlertDialog
import at.uac.android.feature.browse.tr
import kotlinx.coroutines.launch

@Composable
fun BannerMeasurementSettings(
    authority: BannerMeasurementAuthority?,
    language: String,
    controller: BannerMeasurementController,
) {
    val state by controller.state.collectAsState()
    if (authority?.ready != true || (!state.available && !state.error)) return
    val scope = rememberCoroutineScope()
    var confirming by remember(authority.uid) { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth().testTag("banner-measurement-settings"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(tr(language, "Optionale Bannermessung", "Необов’язкове вимірювання банерів"),
            style = MaterialTheme.typography.titleMedium)
        Text(tr(language,
            "Getrennt von der Nutzungsanalyse. Sichtbare Einblendungen und Aufrufe werden je Banner und Bereich zusammengefasst.",
            "Окремо від аналітики використання. Видимі покази й натискання підсумовуються за банером і розділом."),
            style = MaterialTheme.typography.bodySmall)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically) {
            Text(if (state.enabled) tr(language, "Einwilligung erteilt", "Згоду надано")
                else tr(language, "Nicht eingewilligt", "Згоди не надано"))
            if (state.busy) CircularProgressIndicator()
            else Switch(
                checked = state.enabled,
                enabled = state.available,
                modifier = Modifier.testTag("banner-measurement-switch"),
                onCheckedChange = { enabled ->
                    if (enabled) confirming = true
                    else scope.launch { controller.setEnabled(false, language) }
                },
            )
        }
        if (state.error) {
            Text(tr(language, "Der Serverstatus konnte nicht bestätigt werden. Die Messung bleibt aus.",
                "Серверний стан не підтверджено. Вимірювання вимкнено."),
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.testTag("banner-measurement-error"))
            TextButton(onClick = { scope.launch { controller.refresh() } },
                modifier = Modifier.testTag("banner-measurement-retry")) {
                Text(tr(language, "Erneut versuchen", "Спробувати ще раз"))
            }
        }
    }
    if (confirming) ProtectedAlertDialog(
        onDismissRequest = { confirming = false },
        title = { Text(tr(language, "Bannermessung erlauben?", "Дозволити вимірювання банерів?")) },
        text = { Text(tr(language,
            "Optional: UAC misst sichtbare Einblendungen und Aufrufe seiner Banner je Banner und App-Bereich für zusammengefasste Berichte an den Plattforminhaber. Eine Einblendung zählt nach mindestens einer Sekunde bei mindestens 50 % Sichtbarkeit; ein Tippen zählt als Aufruf. Die Wahl gilt für dieses Konto auf allen angemeldeten Geräten. Für Berechtigung und Deduplizierung werden Konto-, Zustimmungs- und Ereigniskennungen verarbeitet. Ereignisbelege werden nach 72 Stunden zur Löschung fällig; Zustimmungsnachweise bleiben gemäß Datenschutzerklärung erhalten. Keine Werbe-ID, kein Tracking zwischen Apps und keine Teilnehmerlisten für Werbepartner. Jederzeit in den Einstellungen widerrufbar.",
            "Необов’язково: UAC вимірює видимі покази та натискання своїх банерів за банером і розділом застосунку для зведених звітів власнику платформи. Показ зараховується після щонайменше однієї секунди за видимості не менш ніж 50 %; натискання зараховується окремо. Вибір діє для цього акаунта на всіх пристроях, де виконано вхід. Для перевірки прав і захисту від дублювання обробляються ID акаунта, згоди та події. Квитанції подій підлягають видаленню через 72 години; докази згоди зберігаються відповідно до політики приватності. Без рекламного ID, відстеження між застосунками й списків користувачів для рекламодавців. Згоду можна відкликати в налаштуваннях будь-коли.")) },
        confirmButton = {
            TextButton(onClick = {
                confirming = false
                scope.launch { controller.setEnabled(true, language) }
            }, modifier = Modifier.testTag("banner-measurement-confirm")) {
                Text(tr(language, "Erlauben", "Дозволити"))
            }
        },
        dismissButton = {
            TextButton(onClick = { confirming = false }) {
                Text(tr(language, "Abbrechen", "Скасувати"))
            }
        },
    )
}
