package at.uac.android.feature.applock

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import at.uac.android.feature.browse.tr

@Composable
fun AppLockSettingsSection(state: AppLockState, language: String, onEnabled: (Boolean) -> Unit) {
    Card(Modifier.fillMaxWidth().testTag("app-lock-settings")) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                tr(language, "App-Sperre", "Блокування застосунку"),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                tr(
                    language,
                    "Schütze den Zugriff auf dieses Konto auf diesem Gerät mit einem starken biometrischen Merkmal oder deinem Gerätecode. " +
                        "Nach dem Abmelden bleiben E-Mail und Passwort erforderlich.",
                    "Захистіть доступ до цього акаунту на цьому пристрої сильною біометрією або кодом пристрою. Після виходу потрібні email і пароль.",
                )
            )
            Switch(
                checked = state.enabled,
                onCheckedChange = onEnabled,
                enabled =
                    state.session != null &&
                        state.foreground &&
                        !state.authenticating &&
                        state.availability.available,
                modifier = Modifier.testTag("app-lock-toggle"),
            )
            if (!state.availability.available)
                Text(appLockError(AppLockProblem.UNAVAILABLE, language))
            state.error?.let {
                Text(
                    appLockError(it, language),
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.testTag("app-lock-settings-error"),
                )
            }
            if (state.authenticating)
                CircularProgressIndicator(Modifier.testTag("app-lock-progress"))
        }
    }
}

/** Content for the root-owned window shield; this alone is not a window/recents shield. */
@Composable
fun AppLockScreen(
    state: AppLockState,
    language: String,
    onUnlock: () -> Unit,
    onPasswordSignIn: () -> Unit,
    onCancelAuthentication: () -> Unit,
    signingOut: Boolean = false,
) {
    Column(
        Modifier.fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(28.dp)
            .testTag("app-lock-screen"),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        Text("UAC", style = MaterialTheme.typography.headlineLarge)
        if (state.foreground && state.locked) {
            Text(
                tr(language, "Zugriff gesperrt", "Доступ заблоковано"),
                style = MaterialTheme.typography.headlineMedium,
            )
            Text(
                tr(
                    language,
                    "Entsperre die App mit einem starken biometrischen Merkmal oder deinem Gerätecode.",
                    "Розблокуйте застосунок сильною біометрією або кодом пристрою.",
                )
            )
            state.error?.let {
                Text(
                    appLockError(it, language),
                    color = MaterialTheme.colorScheme.error,
                    modifier =
                        Modifier.testTag("app-lock-error").semantics {
                            liveRegion = LiveRegionMode.Polite
                        },
                )
            }
            Button(
                onUnlock,
                enabled = !state.authenticating && !signingOut && state.availability.available,
                modifier = Modifier.fillMaxWidth().testTag("app-lock-unlock"),
            ) {
                Text(tr(language, "Entsperren", "Розблокувати"))
            }
            if (state.authenticating) {
                CircularProgressIndicator()
                TextButton(
                    onCancelAuthentication,
                    enabled = !signingOut,
                    modifier = Modifier.fillMaxWidth().testTag("app-lock-cancel"),
                ) {
                    Text(tr(language, "Abbrechen", "Скасувати"))
                }
            }
            TextButton(
                onPasswordSignIn,
                enabled = !signingOut && !state.authenticating,
                modifier = Modifier.fillMaxWidth().testTag("app-lock-password"),
            ) {
                Text(tr(language, "Mit Passwort anmelden", "Увійти з паролем"))
            }
            Text(
                tr(
                    language,
                    "Dabei wird die aktuelle Sitzung beendet. Nicht gespeicherte Änderungen können verloren gehen.",
                    "Це завершить поточний сеанс. Незбережені зміни може бути втрачено.",
                ),
                style = MaterialTheme.typography.bodySmall,
            )
            if (signingOut) CircularProgressIndicator()
        } else if (state.foreground && state.authenticating) {
            Text(
                tr(language, "Sichere Bestätigung läuft", "Триває безпечне підтвердження"),
                style = MaterialTheme.typography.headlineMedium,
            )
            CircularProgressIndicator(Modifier.testTag("app-lock-confirmation-progress"))
            TextButton(
                onCancelAuthentication,
                enabled = !signingOut,
                modifier = Modifier.fillMaxWidth().testTag("app-lock-cancel"),
            ) {
                Text(tr(language, "Abbrechen", "Скасувати"))
            }
        }
    }
}

fun appLockError(problem: AppLockProblem, language: String): String =
    when (problem) {
        AppLockProblem.UNAVAILABLE ->
            tr(
                language,
                "Auf diesem Gerät ist derzeit keine sichere Bestätigung verfügbar. Richte bei Bedarf in den Geräteeinstellungen einen Gerätecode oder eine starke Biometrie ein.",
                "На цьому пристрої зараз немає безпечного способу підтвердження. За потреби налаштуйте код пристрою або сильну біометрію в системних параметрах.",
            )
        AppLockProblem.FAILED ->
            tr(
                language,
                "Der Zugriff wurde nicht bestätigt. Versuche es erneut oder melde dich mit Passwort an.",
                "Доступ не підтверджено. Спробуйте знову або увійдіть із паролем.",
            )
        AppLockProblem.LOCKED_OUT ->
            tr(
                language,
                "Die Biometrie ist vorübergehend gesperrt. Nutze den Gerätecode oder melde dich mit Passwort an.",
                "Біометрію тимчасово заблоковано. Скористайтеся кодом пристрою або увійдіть із паролем.",
            )
        AppLockProblem.STORAGE ->
            tr(
                language,
                "Die Schutzeinstellung konnte nicht sicher gespeichert oder gelesen werden. Der Zugriff bleibt geschützt.",
                "Не вдалося безпечно зберегти або прочитати налаштування захисту. Доступ залишається захищеним.",
            )
        AppLockProblem.BUSY ->
            tr(
                language,
                "Die vorige Systemabfrage wird noch beendet. Schließe sie und versuche es erneut.",
                "Попереднє системне підтвердження ще завершується. Закрийте його та спробуйте знову.",
            )
        AppLockProblem.SIGN_OUT ->
            tr(
                language,
                "Die Sitzung konnte nicht beendet werden. Der Zugriff bleibt gesperrt. Versuche es erneut.",
                "Не вдалося завершити сеанс. Доступ залишається заблокованим. Спробуйте ще раз.",
            )
    }
