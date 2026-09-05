package at.uac.android.feature.inbox

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.feature.auth.AuthLegalDocument
import at.uac.android.feature.auth.AuthLegalReader
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.safeHttps
import at.uac.android.feature.browse.tr
import at.uac.android.feature.dsastatement.DsaStatementContract
import at.uac.android.feature.feedback.feedbackScope
import java.net.URI
import java.time.Instant

fun availableInboxDestination(destination: InboxDestination): Boolean =
    if (destination.kind == InboxDestinationKind.DSA_STATEMENT)
        destination.target?.let { DsaStatementContract.validId(it) } == true
    else
        destination.kind in
            setOf(
                InboxDestinationKind.NEWS,
                InboxDestinationKind.EVENT,
                InboxDestinationKind.ORGANIZATION,
                InboxDestinationKind.LEGAL,
                InboxDestinationKind.PROFILE,
                InboxDestinationKind.URL,
                InboxDestinationKind.FEEDBACK,
                InboxDestinationKind.ORGANIZATION_REQUEST,
            )

@Composable
fun InboxDestinationScreen(
    route: String,
    language: String,
    snapshot: InboxState,
    authSession: AuthSession,
    auth: AuthStore,
    inbox: InboxViewModel,
    browse: BrowseViewModel,
    localReminders: @Composable () -> Unit = {},
) {
    val session = authSession.inboxScope()
    val state = snapshot.forSession(session)
    var external by remember(session) { mutableStateOf<String?>(null) }
    var legal by remember(session) { mutableStateOf<AuthLegalDocument?>(null) }
    fun current(): Boolean = session != null && auth.state.value.inboxScope() == session
    when (route) {
        "profile/inbox-settings" ->
            InboxPreferencesScreen(
                state,
                language,
                { if (current()) inbox.loadPreferences() },
                { preferences -> if (current()) inbox.savePreferences(preferences) },
                localReminders,
            )
        "profile/legal" ->
            Column(
                Modifier.verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(
                    tr(language, "Rechtliche Dokumente", "Правові документи"),
                    style = MaterialTheme.typography.headlineMedium,
                )
                authSession.legalDocuments.forEach { document ->
                    OutlinedButton({ if (current()) legal = document }, Modifier.fillMaxWidth()) {
                        Text(document.title(language))
                    }
                }
                if (authSession.legalDocuments.isEmpty())
                    Text(
                        tr(
                            language,
                            "Aktuelle Dokumente konnten noch nicht geladen werden.",
                            "Чинні документи ще не вдалося завантажити.",
                        )
                    )
                TextButton({ auth.refresh() }) {
                    Text(tr(language, "Aktuelle Version prüfen", "Перевірити чинну версію"))
                }
                TextButton({ browse.navigate("profile") }) {
                    Text(tr(language, "Zum Kontostatus", "До стану облікового запису"))
                }
            }
        else ->
            InboxScreen(
                state,
                language,
                { more -> if (current()) inbox.refresh(more) },
                inbox::filterUnread,
                { notice, action -> if (current()) inbox.change(notice, action) },
                { action -> if (current()) inbox.changeAll(action) },
                { notice, destination ->
                    val live = auth.state.value
                    val target =
                        resolveInboxNavigation(
                            notice,
                            destination,
                            session,
                            live.inboxScope(),
                            live.feedbackScope()?.canManage == true,
                            Instant.now(),
                        )
                    if (current() && target != null) {
                        inbox.change(notice, InboxMutation.READ)
                        when (target) {
                            is InboxNavigationTarget.Route -> {
                                if (target.publicContent) browse.preference("mode", "emulator")
                                browse.navigate(target.path)
                            }
                            is InboxNavigationTarget.External -> external = target.url
                        }
                    }
                },
                { browse.navigate("profile/inbox-settings") },
                ::availableInboxDestination,
            )
    }
    legal?.let { document ->
        AuthLegalReader(document, language, reference = false) { legal = null }
    }
    external?.let { url ->
        InboxExternalConfirmation(url, language, canOpen = ::current) { external = null }
    }
}

@Composable
fun InboxAccountLink(state: InboxState, language: String, onOpen: () -> Unit) {
    if (state.session == null) return
    OutlinedButton(onOpen, Modifier.fillMaxWidth().testTag("account-open-inbox")) {
        Text(
            tr(
                language,
                "Mitteilungen (${state.unreadCount})",
                "Повідомлення (${state.unreadCount})",
            )
        )
    }
}

@Composable
internal fun InboxExternalConfirmation(
    value: String,
    language: String,
    canOpen: () -> Boolean,
    onDismiss: () -> Unit,
) {
    val url = safeHttps(value) ?: return
    val context = LocalContext.current
    var failed by remember(url) { mutableStateOf(false) }
    val synthetic = URI(url).host.endsWith(".invalid")
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(tr(language, "Externe Website öffnen?", "Відкрити зовнішній сайт?")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SelectionContainer { Text(url) }
                if (synthetic)
                    Text(
                        tr(
                            language,
                            "Erfundener Demo-Link; wird nicht geöffnet.",
                            "Вигадане демо-посилання; відкриття вимкнене.",
                        )
                    )
                if (failed)
                    Text(
                        tr(
                            language,
                            "Keine passende App verfügbar.",
                            "Відповідного застосунку немає.",
                        )
                    )
            }
        },
        confirmButton = {
            TextButton(
                {
                    if (!canOpen()) {
                        onDismiss()
                        return@TextButton
                    }
                    failed =
                        runCatching {
                            context.startActivity(
                                Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                    .addCategory(Intent.CATEGORY_BROWSABLE)
                            )
                        }
                            .isFailure
                    if (!failed) onDismiss()
                },
                enabled = !synthetic,
            ) {
                Text(tr(language, "Öffnen", "Відкрити"))
            }
        },
        dismissButton = { TextButton(onDismiss) { Text(tr(language, "Abbrechen", "Скасувати")) } },
    )
}
