package at.uac.android.feature.safety

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.core.ProtectedDialog as Dialog
import at.uac.android.feature.browse.tr

/**
 * Call only for a fresh server-confirmed detail. The host must also guard captured target/session
 * callbacks.
 */
@Composable
fun SafetyActions(
    target: SafetyReportTarget,
    state: SafetyState,
    language: String,
    onReport: () -> Unit,
    onUserBlock: (String, Boolean) -> Unit,
    onOrganizationBlock: (String, Boolean) -> Unit,
    onAccount: () -> Unit,
) {
    var confirm by remember(state.session, target.key) { mutableStateOf<String?>(null) }
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.testTag("safety-actions"),
    ) {
        HorizontalDivider()
        Text(tr(language, "Sicherheit", "Безпека"), style = MaterialTheme.typography.titleMedium)
        if (state.session?.ready != true) {
            Text(
                tr(
                    language,
                    "Zum Melden oder Blockieren ist ein bestätigtes, aktives Konto erforderlich.",
                    "Для скарг і блокування потрібен підтверджений активний обліковий запис.",
                )
            )
            TextButton(onClick = onAccount, modifier = Modifier.testTag("safety-account")) {
                Text(tr(language, "Zum Konto", "До облікового запису"))
            }
        } else {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (target.authorId != state.session.uid)
                    OutlinedButton(
                        onClick = onReport,
                        enabled = target.valid(),
                        modifier = Modifier.testTag("safety-report"),
                    ) {
                        Text(tr(language, "Inhalt melden", "Поскаржитися"))
                    }
                val canBlock =
                    state.blocks != null && !state.loading && state.pendingBlocks.isEmpty()
                if (
                    target.authorId?.let(::safetyId) == true && target.authorId != state.session.uid
                ) {
                    val blocked = target.authorId in state.visibility.blockedUserIds
                    OutlinedButton(
                        onClick = { confirm = "user" },
                        enabled = canBlock,
                        modifier = Modifier.testTag("safety-block-user"),
                    ) {
                        Text(
                            if (blocked) tr(language, "Person entsperren", "Розблокувати автора")
                            else tr(language, "Person blockieren", "Заблокувати автора")
                        )
                    }
                }
                if (target.type == SafetyTargetType.ORGANIZATION) {
                    val blocked = target.id in state.visibility.blockedOrganizationIds
                    OutlinedButton(
                        onClick = { confirm = "organization" },
                        enabled = canBlock,
                        modifier = Modifier.testTag("safety-block-organization"),
                    ) {
                        Text(
                            if (blocked)
                                tr(language, "Organisation entsperren", "Розблокувати організацію")
                            else tr(language, "Organisation blockieren", "Заблокувати організацію")
                        )
                    }
                }
            }
            if (state.loading || state.pendingBlocks.isNotEmpty())
                LinearProgressIndicator(Modifier.fillMaxWidth())
            state.error?.let {
                Text(safetyFailureText(it, language), color = MaterialTheme.colorScheme.error)
            }
            listOfNotNull(
                    target.authorId?.let { state.blockErrors["user:$it"] },
                    state.blockErrors["organization:${target.id}"],
                )
                .distinct()
                .forEach {
                    Text(
                        safetyBlockFailureText(it, language),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
        }
    }
    confirm?.let { kind ->
        val id = if (kind == "user") target.authorId!! else target.id
        val blocked =
            if (kind == "user") id in state.visibility.blockedUserIds
            else id in state.visibility.blockedOrganizationIds
        SafetyBlockConfirmation(
            language,
            kind == "organization",
            !blocked,
            target.title,
            onDismiss = { confirm = null },
            onConfirm = {
                confirm = null
                if (kind == "user") onUserBlock(id, !blocked) else onOrganizationBlock(id, !blocked)
            },
        )
    }
}

@Composable
private fun SafetyBlockConfirmation(
    language: String,
    organization: Boolean,
    blocked: Boolean,
    title: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                if (blocked) tr(language, "Für mich ausblenden?", "Приховати для мене?")
                else tr(language, "Blockierung aufheben?", "Скасувати блокування?")
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(title)
                Text(
                    if (!blocked)
                        tr(
                            language,
                            "Öffentliche Inhalte werden wieder sichtbar.",
                            "Публічні матеріали знову будуть видимі.",
                        )
                    else if (organization)
                        tr(
                            language,
                            "Diese Organisation sowie ihre Nachrichten und Veranstaltungen werden nur für dich ausgeblendet. Andere Organisationen und das Konto des Inhabers bleiben unverändert.",
                            "Цю організацію, її новини та події буде приховано лише для вас. Інші організації та обліковий запис власника не зміняться.",
                        )
                    else
                        tr(
                            language,
                            "Organisationen, Nachrichten, Veranstaltungen und Kommentare dieser Person werden nur für dich ausgeblendet.",
                            "Організації, новини, події та коментарі цієї людини буде приховано лише для вас.",
                        )
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onConfirm, modifier = Modifier.testTag("safety-block-confirm")) {
                Text(
                    if (blocked) tr(language, "Blockieren", "Заблокувати")
                    else tr(language, "Entsperren", "Розблокувати")
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(tr(language, "Abbrechen", "Скасувати")) }
        },
    )
}

/** Owns its list; place in a full-height destination, not a vertically scrolling parent. */
@Composable
fun SafetyBlockedScreen(
    state: SafetyState,
    language: String,
    onRefresh: () -> Unit,
    onUserBlock: (String, Boolean) -> Unit,
    onOrganizationBlock: (String, Boolean) -> Unit,
    onAccount: () -> Unit = {},
) {
    var confirm by remember(state.session) { mutableStateOf<Pair<Boolean, String>?>(null) }
    LazyColumn(
        Modifier.fillMaxSize().testTag("safety-blocked-list"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    tr(
                        language,
                        "Blockierte Konten und Organisationen",
                        "Заблоковані користувачі й організації",
                    ),
                    style = MaterialTheme.typography.headlineSmall,
                )
                Text(
                    tr(
                        language,
                        "Blockierungen ändern nur deine Ansicht. Sie ändern keine Rollen, Mitgliedschaften oder Abonnements.",
                        "Блокування змінює лише те, що бачите ви. Ролі, членство та підписки не змінюються.",
                    )
                )
                if (state.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
                state.error?.let {
                    Text(safetyFailureText(it, language), color = MaterialTheme.colorScheme.error)
                }
                if (state.session?.ready == false) {
                    Text(safetyAccessText(state.session.access, language))
                    TextButton(
                        onClick = onAccount,
                        modifier = Modifier.testTag("safety-blocked-account"),
                    ) {
                        Text(tr(language, "Zum Konto", "До облікового запису"))
                    }
                } else if (state.blocks == null && !state.loading)
                    Text(
                        tr(
                            language,
                            "Blockierungen sind noch nicht bestätigt. Inhalte bleiben bis zur Prüfung ausgeblendet.",
                            "Список блокувань ще не підтверджено. Матеріали залишаться прихованими до перевірки.",
                        )
                    )
                if (
                    state.blocks != null &&
                        state.blocks.users.isEmpty() &&
                        state.blocks.organizations.isEmpty()
                )
                    Text(
                        tr(language, "Keine Blockierungen", "Немає блокувань"),
                        Modifier.testTag("safety-no-blocks"),
                    )
                OutlinedButton(
                    onClick = onRefresh,
                    enabled =
                        state.session?.ready == true &&
                            !state.loading &&
                            state.pendingBlocks.isEmpty(),
                    modifier = Modifier.testTag("safety-refresh"),
                ) {
                    Text(tr(language, "Aktualisieren", "Оновити"))
                }
            }
        }
        items(
            state.blocks?.users.orEmpty().sortedByDescending { it.blockedAt },
            key = { "user:${it.id}" },
        ) { user ->
            SafetyBlockRow(
                user.name,
                tr(language, "Person", "Користувач"),
                "user:${user.id}",
                state,
                language,
                onClick = { confirm = false to user.id },
            )
        }
        items(
            state.blocks?.organizations.orEmpty().sortedByDescending { it.blockedAt },
            key = { "organization:${it.id}" },
        ) { organization ->
            SafetyBlockRow(
                organization.name,
                tr(language, "Organisation", "Організація"),
                "organization:${organization.id}",
                state,
                language,
                onClick = { confirm = true to organization.id },
            )
        }
    }
    confirm?.let { (organization, id) ->
        val name =
            if (organization) state.blocks?.organizations?.find { it.id == id }?.name
            else state.blocks?.users?.find { it.id == id }?.name
        if (name != null)
            SafetyBlockConfirmation(
                language,
                organization,
                false,
                name,
                onDismiss = { confirm = null },
                onConfirm = {
                    confirm = null
                    if (organization) onOrganizationBlock(id, false) else onUserBlock(id, false)
                },
            )
    }
}

@Composable
private fun SafetyBlockRow(
    name: String,
    type: String,
    id: String,
    state: SafetyState,
    language: String,
    onClick: () -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(type, style = MaterialTheme.typography.labelLarge)
            Text(name, style = MaterialTheme.typography.titleMedium)
            OutlinedButton(
                onClick = onClick,
                enabled = state.pendingBlocks.isEmpty() && !state.loading,
                modifier = Modifier.testTag("safety-unblock-$id"),
            ) {
                Text(tr(language, "Entsperren", "Розблокувати"))
            }
            state.blockErrors[id]?.let { error ->
                Text(
                    if (id.startsWith("user:") && error == SafetyFailure.MISSING)
                        tr(
                            language,
                            "Dieses Konto ist nicht mehr verfügbar. Der Server kann diese Blockierung derzeit nicht aufheben; sie bleibt erhalten.",
                            "Цей обліковий запис більше недоступний. Сервер наразі не може скасувати це блокування; воно залишається чинним.",
                        )
                    else safetyBlockFailureText(error, language),
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
    }
}

@Composable
fun SafetyReportDialog(
    target: SafetyReportTarget,
    state: SafetyState,
    language: String,
    onSubmit: (SafetyReportDraft) -> Unit,
    onDismiss: () -> Unit,
) {
    key(state.session, target.key) {
        val progress = state.reports[target.key] ?: SafetyReportState()
        var draft by remember { mutableStateOf(SafetyReportDraft()) }
        Dialog(
            onDismissRequest = { if (!progress.pending) onDismiss() },
            properties =
                DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
        ) {
            val focus = LocalFocusManager.current
            val keyboard = LocalSoftwareKeyboardController.current
            LaunchedEffect(progress.pending, progress.receipt) {
                if (progress.pending || progress.receipt != null) {
                    focus.clearFocus(force = true)
                    keyboard?.hide()
                }
            }
            Surface(
                Modifier.fillMaxSize().safeDrawingPadding().imePadding().padding(16.dp),
                shape = MaterialTheme.shapes.large,
            ) {
                Column(
                    Modifier.widthIn(max = 760.dp).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text(
                        tr(language, "Inhalt melden", "Повідомити про порушення"),
                        style = MaterialTheme.typography.headlineSmall,
                    )
                    Column(
                        Modifier.weight(1f)
                            .verticalScroll(rememberScrollState())
                            .testTag("safety-report-scroll"),
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(target.title, style = MaterialTheme.typography.titleMedium)
                        if (progress.receipt != null) {
                            Text(
                                tr(
                                    language,
                                    "Meldung empfangen und vom Server bestätigt.",
                                    "Скаргу отримано та підтверджено сервером.",
                                ),
                                Modifier.testTag("safety-report-confirmed"),
                            )
                            Text(
                                tr(language, "Aktenzeichen: ", "Номер звернення: ") +
                                    progress.receipt.caseNumber
                            )
                        } else {
                            Text(
                                tr(language, "Grund", "Причина"),
                                style = MaterialTheme.typography.titleMedium,
                            )
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                SafetyReason.entries.forEach { reason ->
                                    FilterChip(
                                        selected = draft.reason == reason,
                                        enabled =
                                            !progress.pending &&
                                                progress.error != SafetyFailure.UNCONFIRMED,
                                        onClick = { draft = draft.copy(reason = reason) },
                                        modifier = Modifier.testTag("safety-reason-${reason.wire}"),
                                        label = { Text(tr(language, reason.de, reason.uk)) },
                                    )
                                }
                            }
                            val enabled =
                                !progress.pending && progress.error != SafetyFailure.UNCONFIRMED
                            SafetyReportField(
                                tr(
                                    language,
                                    "Warum ist dieser Inhalt rechtswidrig?",
                                    "Чому цей матеріал протиправний?",
                                ),
                                draft.explanation,
                                5_000,
                                enabled,
                                "safety-explanation",
                            ) {
                                draft = draft.copy(explanation = it)
                            }
                            if (draft.explanation.trim().length < 20)
                                Text(
                                    tr(
                                        language,
                                        "Bitte mindestens 20 Zeichen eingeben.",
                                        "Введіть щонайменше 20 символів.",
                                    )
                                )
                            SafetyReportField(
                                tr(
                                    language,
                                    "Rechtsgrundlage (optional)",
                                    "Правова підстава (необов’язково)",
                                ),
                                draft.legalBasis,
                                1_000,
                                enabled,
                                "safety-legal-basis",
                            ) {
                                draft = draft.copy(legalBasis = it)
                            }
                            SafetyReportField(
                                tr(
                                    language,
                                    "Belege oder Links (optional)",
                                    "Докази або посилання (необов’язково)",
                                ),
                                draft.evidence,
                                5_000,
                                enabled,
                                "safety-evidence",
                            ) {
                                draft = draft.copy(evidence = it)
                            }
                            Row(verticalAlignment = Alignment.Top) {
                                Checkbox(
                                    checked = draft.goodFaith,
                                    enabled = enabled,
                                    onCheckedChange = { draft = draft.copy(goodFaith = it) },
                                    modifier = Modifier.testTag("safety-good-faith"),
                                )
                                Text(
                                    tr(
                                        language,
                                        "Ich bestätige nach bestem Wissen, dass diese Meldung korrekt und vollständig ist und in gutem Glauben erfolgt.",
                                        "Я добросовісно підтверджую, що, наскільки мені відомо, ця скарга є точною та повною.",
                                    ),
                                    Modifier.padding(top = 10.dp),
                                )
                            }
                            Text(
                                tr(
                                    language,
                                    "Die Meldung wird vom zuständigen Team geprüft. Dein Konto und deine Angaben werden zur Bearbeitung zugeordnet.",
                                    "Звернення перевірить відповідальна команда. Для розгляду буде використано ваш обліковий запис і надані відомості.",
                                )
                            )
                        }
                        progress.error?.let {
                            Text(
                                safetyFailureText(it, language),
                                color = MaterialTheme.colorScheme.error,
                                modifier = Modifier.testTag("safety-report-error"),
                            )
                        }
                    }
                    if (progress.pending) LinearProgressIndicator(Modifier.fillMaxWidth())
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (progress.receipt == null)
                            Button(
                                onClick = {
                                    focus.clearFocus(force = true)
                                    keyboard?.hide()
                                    onSubmit(draft.normalized())
                                },
                                enabled =
                                    draft.valid() &&
                                        state.session?.ready == true &&
                                        !progress.pending &&
                                        progress.error != SafetyFailure.UNCONFIRMED &&
                                        target.authorId != state.session.uid,
                                modifier = Modifier.testTag("safety-report-submit"),
                            ) {
                                Text(tr(language, "Meldung senden", "Надіслати скаргу"))
                            }
                        OutlinedButton(
                            onClick = onDismiss,
                            enabled = !progress.pending,
                            modifier = Modifier.testTag("safety-report-close"),
                        ) {
                            Text(tr(language, "Schließen", "Закрити"))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SafetyReportField(
    title: String,
    value: String,
    limit: Int,
    enabled: Boolean,
    tag: String,
    onValue: (String) -> Unit,
) {
    OutlinedTextField(
        value = value,
        onValueChange = { if (it.length <= limit + 1) onValue(it) },
        enabled = enabled,
        label = { Text(title) },
        supportingText = { Text("${value.length} / $limit") },
        isError = value.length > limit,
        minLines = 3,
        // A pending/uncertain report cannot keep or regain editor focus after focus clearing.
        modifier = Modifier.fillMaxWidth().focusProperties { canFocus = enabled }.testTag(tag),
    )
}

fun safetyVisibilityText(reason: SafetyVisibilityReason, language: String): String =
    when (reason) {
        SafetyVisibilityReason.CHECKING ->
            tr(
                language,
                "Deine Blockierungen werden geprüft. Bis dahin bleiben Inhalte ausgeblendet.",
                "Перевіряємо ваші блокування. До завершення матеріали залишаються прихованими.",
            )
        SafetyVisibilityReason.ACCOUNT_REQUIRED ->
            tr(
                language,
                "Deine Blockierungen können noch nicht geprüft werden. Öffne dein Konto, um den Zugang zu klären oder dich abzumelden und als Gast weiterzulesen.",
                "Ваші блокування ще не можна перевірити. Відкрийте обліковий запис, щоб відновити доступ або вийти й читати як гість.",
            )
        SafetyVisibilityReason.AUTHOR_BLOCKED ->
            tr(
                language,
                "Dieser Inhalt ist ausgeblendet, weil du die Person blockiert hast. Blockierungen kannst du in deinem Konto verwalten.",
                "Цей матеріал приховано, оскільки ви заблокували автора. Керуйте блокуваннями у своєму обліковому записі.",
            )
        SafetyVisibilityReason.ORGANIZATION_BLOCKED ->
            tr(
                language,
                "Dieser Inhalt gehört zu einer blockierten Organisation. Blockierungen kannst du in deinem Konto verwalten.",
                "Цей матеріал належить заблокованій організації. Керуйте блокуваннями у своєму обліковому записі.",
            )
    }

fun safetyAccessText(access: SafetyAccess, language: String): String =
    when (access) {
        SafetyAccess.VERIFY_EMAIL ->
            tr(
                language,
                "Bestätige zuerst deine E-Mail-Adresse im Konto. Bis dahin können persönliche Blockierungen nicht geladen werden.",
                "Спочатку підтвердьте електронну адресу в обліковому записі. До цього особисті блокування не можна завантажити.",
            )
        SafetyAccess.RESTRICTED ->
            tr(
                language,
                "Dein Konto ist eingeschränkt. Öffne das Konto für weitere Informationen; du kannst dich auch abmelden und als Gast lesen.",
                "Ваш обліковий запис обмежено. Відкрийте його для подробиць; також можна вийти й читати як гість.",
            )
        SafetyAccess.LEGAL ->
            tr(
                language,
                "Öffne dein Konto und prüfe die erforderlichen rechtlichen Dokumente, bevor persönliche Blockierungen geladen werden.",
                "Відкрийте обліковий запис і перевірте необхідні юридичні документи перед завантаженням особистих блокувань.",
            )
        SafetyAccess.MFA ->
            tr(
                language,
                "Schließe die erforderliche Sicherheitsbestätigung im Konto ab.",
                "Завершіть необхідну перевірку безпеки в обліковому записі.",
            )
        SafetyAccess.UNAVAILABLE ->
            tr(
                language,
                "Der Kontozugang ist noch nicht bestätigt. Prüfe dein Konto oder melde dich ab, um als Gast weiterzulesen.",
                "Доступ до облікового запису ще не підтверджено. Перевірте його або вийдіть, щоб читати як гість.",
            )
        SafetyAccess.READY ->
            tr(
                language,
                "Blockierungen werden vom Server geladen.",
                "Завантажуємо блокування із сервера.",
            )
    }

/** Host-level alternative to an empty feed while authenticated visibility cannot be established. */
@Composable
fun SafetyAvailabilityNotice(
    state: SafetyState,
    language: String,
    onRefresh: () -> Unit,
    onAccount: () -> Unit,
) {
    if (state.visibility.loaded) return
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.testTag("safety-availability"),
    ) {
        if (state.session?.ready == false) {
            Text(safetyAccessText(state.session.access, language))
        } else {
            Text(safetyVisibilityText(SafetyVisibilityReason.CHECKING, language))
            if (state.loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            state.error?.let {
                Text(safetyBlockFailureText(it, language), color = MaterialTheme.colorScheme.error)
            }
            OutlinedButton(
                onClick = onRefresh,
                enabled = !state.loading,
                modifier = Modifier.testTag("safety-availability-retry"),
            ) {
                Text(tr(language, "Erneut prüfen", "Перевірити ще раз"))
            }
        }
        TextButton(
            onClick = onAccount,
            modifier = Modifier.testTag("safety-availability-account"),
        ) {
            Text(tr(language, "Zum Konto", "До облікового запису"))
        }
    }
}

private fun safetyBlockFailureText(error: SafetyFailure, language: String): String =
    if (error == SafetyFailure.UNCONFIRMED)
        tr(
            language,
            "Die Blockierung ist noch nicht bestätigt. Aktualisiere den vollständigen Stand, bevor du fortfährst.",
            "Стан блокування ще не підтверджено. Оновіть повний список, перш ніж продовжити.",
        )
    else safetyFailureText(error, language)

fun safetyFailureText(error: SafetyFailure, language: String): String =
    when (error) {
        SafetyFailure.SIGN_IN -> tr(language, "Bitte zuerst anmelden.", "Спочатку увійдіть.")
        SafetyFailure.NOT_READY ->
            tr(
                language,
                "Diese Aktion benötigt ein bestätigtes, aktives Konto und gültige Sicherheitsfreigaben.",
                "Для цієї дії потрібен підтверджений активний обліковий запис із чинними дозволами безпеки.",
            )
        SafetyFailure.DENIED ->
            tr(language, "Der Server hat diese Aktion nicht erlaubt.", "Сервер не дозволив цю дію.")
        SafetyFailure.MISSING ->
            tr(
                language,
                "Der Inhalt oder das Konto ist nicht mehr verfügbar.",
                "Матеріал або обліковий запис більше недоступний.",
            )
        SafetyFailure.INVALID ->
            tr(
                language,
                "Die Angaben oder die Serverantwort sind ungültig.",
                "Дані або відповідь сервера некоректні.",
            )
        SafetyFailure.OWN_TARGET ->
            tr(
                language,
                "Das eigene Konto oder eigene Inhalte können hier nicht gemeldet oder blockiert werden.",
                "Тут не можна скаржитися на власні матеріали чи блокувати себе.",
            )
        SafetyFailure.LIMIT ->
            tr(
                language,
                "Das Serverlimit wurde erreicht. Der vollständige Stand konnte nicht bestätigt werden.",
                "Досягнуто обмеження сервера. Повний стан не вдалося підтвердити.",
            )
        SafetyFailure.OFFLINE ->
            tr(
                language,
                "Keine bestätigte Serververbindung. Bitte erneut prüfen.",
                "Немає підтвердженого з’єднання із сервером. Перевірте ще раз.",
            )
        SafetyFailure.UNCONFIRMED ->
            tr(
                language,
                "Der Ausgang ist unklar. Nicht erneut senden: Die Meldung könnte bereits vorliegen. Prüfe deine vorhandenen Anfragen, bevor du eine neue Meldung erstellst.",
                "Результат невідомий. Не надсилайте повторно: звернення вже могло надійти. Перевірте наявні звернення перед створенням нової скарги.",
            )
        SafetyFailure.UNKNOWN ->
            tr(language, "Die Aktion konnte nicht bestätigt werden.", "Дію не вдалося підтвердити.")
    }
