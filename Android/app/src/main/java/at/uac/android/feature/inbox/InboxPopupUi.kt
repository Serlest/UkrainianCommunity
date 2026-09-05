package at.uac.android.feature.inbox

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import at.uac.android.core.ProtectedDialog as Dialog
import at.uac.android.feature.browse.tr
import java.time.Instant

/** Dialog content scrolls as one column: every action stays reachable at 200% text. */
@Composable
fun InboxPopupHost(
    state: InboxPopupState,
    language: String,
    onDismiss: (String) -> Unit,
    onOpen: (String) -> Unit,
    onClearError: () -> Unit,
    onInbox: (() -> Unit)? = null,
    destinationAvailable: (InboxDestination) -> Boolean = { true },
    now: () -> Instant = Instant::now,
) {
    if (state.account.session == null || state.mutating) return
    val notice =
        state.active?.takeIf {
            state.confirmed && it.uid == state.account.uid && it.eligibleForPopup(now())
        }
    if (notice == null && state.error == null) return
    fun dismiss() {
        if (notice != null) onDismiss(notice.id) else onClearError()
    }
    Dialog(
        onDismissRequest = ::dismiss,
        properties = DialogProperties(dismissOnClickOutside = false),
    ) {
        Surface(
            shape = MaterialTheme.shapes.extraLarge,
            modifier = Modifier.fillMaxWidth().testTag("inbox-popup"),
        ) {
            Column(
                Modifier.verticalScroll(rememberScrollState())
                    .padding(24.dp)
                    .testTag("inbox-popup-scroll"),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    tr(language, "Wichtige Mitteilung", "Важливе повідомлення"),
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.error,
                )
                if (notice != null) {
                    Text(
                        notice.displayTitle(language),
                        style = MaterialTheme.typography.headlineSmall,
                        modifier = Modifier.testTag("inbox-popup-title"),
                    )
                    Text(
                        notice.displayBody(language),
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.testTag("inbox-popup-body"),
                    )
                }
                if (state.error != null) {
                    Text(
                        if (state.acknowledgementFailed)
                            tr(
                                language,
                                "Die Bestätigung konnte nicht vollständig gespeichert werden. Die Mitteilung bleibt im Posteingang verfügbar.",
                                "Не вдалося повністю зберегти підтвердження. Повідомлення залишається доступним у списку.",
                            )
                        else
                            tr(
                                language,
                                "Neue wichtige Mitteilungen können gerade nicht geprüft werden. Dein Posteingang bleibt erreichbar.",
                                "Зараз не вдалося перевірити нові важливі повідомлення. Список повідомлень залишається доступним.",
                            ),
                        color = MaterialTheme.colorScheme.error,
                        modifier = Modifier.testTag("inbox-popup-error"),
                    )
                    Text(
                        inboxError(state.error, language),
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    if (onInbox != null)
                        TextButton(
                            onClick = {
                                onClearError()
                                onInbox()
                            },
                            modifier = Modifier.fillMaxWidth().testTag("inbox-popup-inbox"),
                        ) {
                            Text(tr(language, "Zum Posteingang", "До списку повідомлень"))
                        }
                }
                val destination = notice?.destination(now())
                if (notice != null && destination != null && destinationAvailable(destination)) {
                    Button(
                        onClick = {
                            if (
                                notice.eligibleForPopup(now()) &&
                                    notice.destination(now())?.let(destinationAvailable) == true
                            )
                                onOpen(notice.id)
                        },
                        modifier = Modifier.fillMaxWidth().testTag("inbox-popup-open"),
                    ) {
                        Text(tr(language, "Öffnen", "Відкрити"))
                    }
                }
                OutlinedButton(
                    onClick = ::dismiss,
                    modifier = Modifier.fillMaxWidth().testTag("inbox-popup-dismiss"),
                ) {
                    Text(tr(language, "OK", "Гаразд"))
                }
            }
        }
    }
}
