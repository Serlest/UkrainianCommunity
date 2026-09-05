package at.uac.android.feature.accountstatus

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.core.ProtectedDialog
import at.uac.android.feature.browse.tr
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

@Composable
fun AccountStatusHost(
    model: AccountStatusViewModel,
    session: AccountStatusSession?,
    language: String,
    interactive: Boolean,
    onVerification: () -> Unit,
    onMfa: () -> Unit,
) {
    val stored by model.state.collectAsStateWithLifecycle()
    LifecycleResumeEffect(model, interactive) {
        model.setVisible(interactive)
        onPauseOrDispose { model.setVisible(false) }
    }
    val shown = stored.takeIf { it.session == session && interactive && it.visible }
    if (shown != null) {
        AccountStatusDialog(
            shown,
            language,
            model::acknowledge,
            model::reconcile,
            model::requestSignOut,
            onAuthenticate = {
                if (model.escapeForAuthentication()) {
                    if (session?.needsMfa == true) onMfa() else onVerification()
                }
            },
        )
    }
}

@Composable
fun AccountStatusDialog(
    state: AccountStatusState,
    language: String,
    onAcknowledge: () -> Unit,
    onReconcile: () -> Unit,
    onSignOut: () -> Unit,
    onAuthenticate: () -> Unit,
) {
    val notice = state.notice ?: return
    val session = state.session ?: return
    if (!state.visible || session.uid != notice.uid) return
    val title =
        when (notice.kind) {
            AccountStatusKind.WARNED ->
                tr(language, "Hinweis zu deinem Konto", "Попередження щодо акаунта")
            AccountStatusKind.SUSPENDED ->
                tr(language, "Konto vorübergehend eingeschränkt", "Акаунт тимчасово обмежено")
            AccountStatusKind.BANNED -> tr(language, "Konto gesperrt", "Акаунт заблоковано")
            AccountStatusKind.DEACTIVATED ->
                tr(language, "Konto deaktiviert", "Акаунт деактивовано")
            AccountStatusKind.RESTORED ->
                tr(language, "Kontozugriff wiederhergestellt", "Доступ до акаунта відновлено")
            null -> return
        }
    ProtectedDialog(
        onDismissRequest = {},
        properties =
            DialogProperties(
                dismissOnBackPress = false,
                dismissOnClickOutside = false,
                usePlatformDefaultWidth = false,
                decorFitsSystemWindows = false,
            ),
    ) {
        Surface(Modifier.fillMaxSize()) {
            Column(
                Modifier.fillMaxSize()
                    .safeDrawingPadding()
                    .imePadding()
                    .verticalScroll(rememberScrollState())
                    .padding(20.dp)
                    .testTag("account-status-notice"),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    title,
                    Modifier.semantics { heading() }.testTag("account-status-title"),
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(
                    if (notice.requiresSignOut)
                        tr(
                            language,
                            "Persönliche Aktionen sind gesperrt. Bitte melde dich ab.",
                            "Особисті дії заблоковано. Вийдіть з акаунта.",
                        )
                    else
                        tr(
                            language,
                            "Bitte lies diese aktuelle Mitteilung zu deinem Konto.",
                            "Прочитайте це актуальне повідомлення щодо акаунта.",
                        )
                )
                notice.message?.trim()?.takeIf(String::isNotEmpty)?.let {
                    Text(it, Modifier.testTag("account-status-message"))
                }
                notice.reason?.trim()?.takeIf(String::isNotEmpty)?.let {
                    Text(
                        tr(language, "Begründung", "Причина"),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(it, Modifier.testTag("account-status-reason"))
                }
                if (notice.kind == AccountStatusKind.SUSPENDED)
                    notice.expiresAt?.let {
                        val date = accountStatusExpiryText(it, language)
                        Text(
                            tr(language, "Bis: ", "До: ") + date,
                            Modifier.testTag("account-status-expiry"),
                        )
                    }
                state.failure?.let {
                    Text(
                        statusFailureText(it, language),
                        Modifier.testTag("account-status-error"),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
                if (state.busy) CircularProgressIndicator(Modifier.testTag("account-status-busy"))
                if (
                    !notice.requiresSignOut &&
                        (state.pending != null || state.failure == AccountStatusFailure.STALE)
                ) {
                    Button(
                        onReconcile,
                        Modifier.fillMaxWidth().testTag("account-status-reconcile"),
                        enabled = !state.busy,
                    ) {
                        Text(tr(language, "Bestätigung prüfen", "Перевірити підтвердження"))
                    }
                } else if (!notice.requiresSignOut && session.canAcknowledge) {
                    Button(
                        onAcknowledge,
                        Modifier.fillMaxWidth().testTag("account-status-acknowledge"),
                        enabled = !state.busy,
                    ) {
                        Text(tr(language, "Verstanden", "Зрозуміло"))
                    }
                } else if (!notice.requiresSignOut) {
                    Text(
                        tr(
                            language,
                            "Zuerst ist die sichere Anmeldung zu vervollständigen.",
                            "Спочатку завершіть захищений вхід.",
                        )
                    )
                    Button(
                        onAuthenticate,
                        Modifier.fillMaxWidth().testTag("account-status-authenticate"),
                        enabled = !state.busy,
                    ) {
                        Text(
                            if (session.needsMfa)
                                tr(
                                    language,
                                    "Zweiten Faktor bestätigen",
                                    "Підтвердити другий фактор",
                                )
                            else tr(language, "E-Mail bestätigen", "Підтвердити пошту")
                        )
                    }
                }
                OutlinedButton(
                    onSignOut,
                    Modifier.fillMaxWidth().testTag("account-status-sign-out"),
                    enabled = !state.busy,
                ) {
                    Text(tr(language, "Abmelden", "Вийти"))
                }
            }
        }
    }
}

internal fun accountStatusExpiryText(value: Instant, language: String): String = runCatching {
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM)
        .withLocale(Locale.forLanguageTag(if (language == "uk") "uk-UA" else "de-AT"))
        .withZone(ZoneId.systemDefault())
        .format(value)
}
    .getOrElse { if (language == "uk") "Дата недоступна" else "Zeitpunkt nicht verfügbar" }

private fun statusFailureText(reason: AccountStatusFailure, language: String): String =
    when (reason) {
        AccountStatusFailure.STALE ->
            tr(
                language,
                "Der Kontostatus hat sich geändert. Bitte lade die aktuelle Mitteilung.",
                "Стан акаунта змінився. Завантажте актуальне повідомлення.",
            )
        AccountStatusFailure.UNCONFIRMED ->
            tr(
                language,
                "Bestätigung noch nicht nachgewiesen. Prüfe zuerst den Serverstatus.",
                "Підтвердження ще не перевірено. Спочатку перевірте стан на сервері.",
            )
        AccountStatusFailure.OFFLINE ->
            tr(
                language,
                "Keine bestätigte Serververbindung. Bitte erneut prüfen.",
                "Немає підтвердженого зв’язку із сервером. Перевірте ще раз.",
            )
        AccountStatusFailure.SIGN_OUT_FAILED ->
            tr(
                language,
                "Die Abmeldung wurde nicht bestätigt. Bitte erneut versuchen.",
                "Вихід не підтверджено. Спробуйте ще раз.",
            )
        AccountStatusFailure.DENIED ->
            tr(
                language,
                "Diese Bestätigung ist für die aktuelle Sitzung nicht erlaubt.",
                "Це підтвердження недоступне для поточного сеансу.",
            )
        AccountStatusFailure.INVALID ->
            tr(
                language,
                "Der Kontodatensatz kann nicht sicher bestätigt werden.",
                "Дані акаунта неможливо безпечно підтвердити.",
            )
        AccountStatusFailure.UNKNOWN ->
            tr(
                language,
                "Die Aktion wurde nicht bestätigt. Bitte prüfe den aktuellen Zustand.",
                "Дію не підтверджено. Перевірте поточний стан.",
            )
    }
