package at.uac.android.feature.community

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.displayTime
import at.uac.android.feature.browse.tr
import java.time.Instant

/**
 * Embed only for a server-confirmed emulator detail; currentTarget also guards stale click
 * closures.
 */
@Composable
fun CommunityDetailPanel(
    content: Content,
    language: String,
    model: CommunityViewModel,
    session: CommunitySession?,
    onAccount: () -> Unit,
    currentTarget: () -> Boolean,
    visibleAuthor: (String?) -> Boolean = { true },
    commentActions: (@Composable (CommunityComment) -> Unit)? = null,
) {
    val target =
        remember(content.kind, content.id) {
            runCatching { CommunityTarget(content.kind, content.id) }.getOrNull()
        } ?: return
    val snapshot by
        model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    val state =
        if (snapshot.session == session && snapshot.target == target) snapshot
        else CommunityState(session, target)
    LifecycleResumeEffect(target, session) {
        if (currentTarget()) model.show(target)
        onPauseOrDispose { model.hide(target) }
    }
    fun guarded(action: () -> Unit) {
        if (currentTarget() && model.state.value.session == session) action()
    }
    Column(
        Modifier.fillMaxWidth().testTag("community-panel"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (target.type == "event")
            EventRegistrationPanel(
                state,
                language,
                onRefresh = { guarded(model::refreshRegistration) },
                onChange = { selected -> guarded { model.setRegistration(selected) } },
                onAccount = onAccount,
            )
        CommentsPanel(
            state,
            language,
            onDraft = { value -> guarded { model.draft(value) } },
            onSend = { guarded(model::addComment) },
            onDelete = { id -> guarded { model.deleteComment(id) } },
            onRefresh = { guarded(model::refreshComments) },
            onAcknowledge = { guarded(model::acknowledgeUncertainSend) },
            onAccount = onAccount,
            visibleAuthor = visibleAuthor,
            commentActions = commentActions,
        )
    }
}

@Composable
fun EventRegistrationPanel(
    state: CommunityState,
    language: String,
    onRefresh: () -> Unit,
    onChange: (Boolean) -> Unit,
    onAccount: () -> Unit,
) {
    var confirmCancellation by remember(state.target, state.session) { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            tr(language, "Meine Teilnahme", "Моя участь"),
            style = MaterialTheme.typography.titleMedium,
        )
        if (state.session?.ready != true) {
            AccountPrompt(language, onAccount)
        } else {
            val participation = state.participation
            participation?.let {
                Text(
                    if (it.registered) tr(language, "Du bist angemeldet.", "Ви зареєстровані.")
                    else tr(language, "Du bist nicht angemeldet.", "Ви не зареєстровані."),
                    Modifier.testTag("registration-state"),
                )
                Text(
                    tr(language, "Bestätigte Anmeldungen: ", "Підтверджених реєстрацій: ") +
                        it.count +
                        (it.capacity?.let { cap -> " / $cap" } ?: "")
                )
                val unavailable = it.unavailable(Instant.now())
                unavailable?.let { reason -> FailureText(reason, language) }
                Button(
                    onClick = { if (it.registered) confirmCancellation = true else onChange(true) },
                    modifier = Modifier.testTag("registration-toggle"),
                    enabled = !state.registrationBusy && unavailable == null,
                ) {
                    Text(
                        if (it.registered) tr(language, "Teilnahme absagen", "Скасувати участь")
                        else tr(language, "Verbindlich anmelden", "Підтвердити участь")
                    )
                }
            }
            if (state.registrationBusy)
                CircularProgressIndicator(Modifier.testTag("registration-busy"))
            state.registrationError?.let {
                if (it == CommunityFailure.UNCONFIRMED)
                    Text(
                        tr(
                            language,
                            "Die Teilnahme wurde noch nicht bestätigt. Bitte den aktuellen Stand laden.",
                            "Участь ще не підтверджено. Завантажте актуальний стан.",
                        ),
                        color = MaterialTheme.colorScheme.error,
                    )
                else FailureText(it, language)
            }
            TextButton(
                onRefresh,
                enabled = !state.registrationBusy,
                modifier = Modifier.testTag("registration-refresh"),
            ) {
                Text(tr(language, "Teilnahme aktualisieren", "Оновити участь"))
            }
        }
    }
    if (confirmCancellation)
        AlertDialog(
            onDismissRequest = { confirmCancellation = false },
            title = { Text(tr(language, "Teilnahme absagen?", "Скасувати участь?")) },
            text = {
                Text(
                    tr(
                        language,
                        "Dein Platz wird wieder freigegeben.",
                        "Ваше місце знову стане доступним.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        confirmCancellation = false
                        onChange(false)
                    },
                    Modifier.testTag("registration-confirm-cancel"),
                ) {
                    Text(tr(language, "Teilnahme absagen", "Скасувати участь"))
                }
            },
            dismissButton = {
                TextButton({ confirmCancellation = false }) {
                    Text(tr(language, "Behalten", "Залишити"))
                }
            },
        )
}

@Composable
fun CommentsPanel(
    state: CommunityState,
    language: String,
    onDraft: (String) -> Unit,
    onSend: () -> Unit,
    onDelete: (String) -> Unit,
    onRefresh: () -> Unit,
    onAcknowledge: () -> Unit,
    onAccount: () -> Unit,
    visibleAuthor: (String?) -> Boolean = { true },
    commentActions: (@Composable (CommunityComment) -> Unit)? = null,
) {
    var deleting by
        remember(state.target, state.session) { mutableStateOf<CommunityComment?>(null) }
    Column(
        Modifier.fillMaxWidth().testTag("comments-panel"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        HorizontalDivider()
        Text(tr(language, "Diskussion", "Обговорення"), style = MaterialTheme.typography.titleLarge)
        Text(
            tr(
                language,
                "Die letzten 100 Kommentare, älteste zuerst.",
                "Останні 100 коментарів, спочатку давніші.",
            ),
            style = MaterialTheme.typography.bodySmall,
        )
        if (state.commentsLoading) CircularProgressIndicator(Modifier.testTag("comments-loading"))
        state.commentsError?.let { FailureText(it, language) }
        state.page?.let { page ->
            if (page.cached)
                Text(
                    tr(
                        language,
                        "Gespeicherter Stand – Verbindung wird geprüft.",
                        "Збережена версія — перевіряємо з’єднання.",
                    ),
                    Modifier.testTag("comments-cached"),
                )
            val visible = page.comments.filter { visibleAuthor(it.authorId) }
            if (visible.isEmpty())
                Text(
                    tr(
                        language,
                        "Noch keine sichtbaren Kommentare.",
                        "Поки немає видимих коментарів.",
                    )
                )
            visible.forEach { comment ->
                Card(Modifier.fillMaxWidth().testTag("comment-${comment.id}")) {
                    Column(
                        Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(comment.authorName, style = MaterialTheme.typography.titleSmall)
                        Text(
                            displayTime(comment.createdAt, language),
                            style = MaterialTheme.typography.labelSmall,
                        )
                        SelectionContainer { Text(comment.text) }
                        if (!page.cached) commentActions?.invoke(comment)
                        if (state.canModerate && !page.cached)
                            TextButton(
                                { deleting = comment },
                                enabled = comment.id !in state.deleting,
                                modifier = Modifier.testTag("comment-delete-${comment.id}"),
                            ) {
                                Text(
                                    tr(language, "Als Moderation löschen", "Видалити як модератор")
                                )
                            }
                    }
                }
            }
        }
        TextButton(onRefresh, Modifier.testTag("comments-refresh")) {
            Text(tr(language, "Diskussion aktualisieren", "Оновити обговорення"))
        }
        if (state.target?.acceptsNewComments == false) {
            Text(
                tr(
                    language,
                    "Für diesen Eintrag ist das Veröffentlichen neuer Kommentare nicht verfügbar.",
                    "Для цього запису публікація нових коментарів недоступна.",
                )
            )
        } else if (state.session?.ready == true) {
            OutlinedTextField(
                value = state.draft,
                onValueChange = onDraft,
                label = { Text(tr(language, "Dein Kommentar", "Ваш коментар")) },
                modifier = Modifier.fillMaxWidth().testTag("comment-draft"),
                minLines = 3,
                maxLines = 8,
                isError = state.draft.trim().length > CommunityContract.MAX_COMMENT_LENGTH,
                supportingText = {
                    Text("${state.draft.trim().length} / ${CommunityContract.MAX_COMMENT_LENGTH}")
                },
            )
            state.actionError?.let { FailureText(it, language) }
            if (state.uncertain) {
                if (state.actionError != CommunityFailure.UNCONFIRMED)
                    FailureText(CommunityFailure.UNCONFIRMED, language)
                OutlinedButton(
                    onAcknowledge,
                    enabled = state.page?.cached == false && !state.sending,
                    modifier = Modifier.testTag("comment-acknowledge"),
                ) {
                    Text(
                        tr(
                            language,
                            "Diskussion geprüft – erneutes Senden erlauben",
                            "Обговорення перевірено — дозволити повтор",
                        )
                    )
                }
            }
            if (state.sentId != null)
                Text(
                    tr(
                        language,
                        "Veröffentlicht und vom Server bestätigt.",
                        "Опубліковано та підтверджено сервером.",
                    ),
                    Modifier.testTag("comment-confirmed"),
                )
            Button(
                onSend,
                enabled =
                    !state.sending &&
                        !state.uncertain &&
                        state.page?.cached == false &&
                        state.draft.trim().length in 1..CommunityContract.MAX_COMMENT_LENGTH,
                modifier = Modifier.testTag("comment-send"),
            ) {
                Text(
                    if (state.sending) tr(language, "Wird gesendet …", "Надсилаємо …")
                    else tr(language, "Veröffentlichen", "Опублікувати")
                )
            }
        } else AccountPrompt(language, onAccount)
    }
    deleting?.let { comment ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text(tr(language, "Kommentar löschen?", "Видалити коментар?")) },
            text = {
                Text(
                    tr(
                        language,
                        "Diese Moderationsaktion entfernt den Kommentar dauerhaft.",
                        "Ця дія модератора остаточно видалить коментар.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        deleting = null
                        onDelete(comment.id)
                    },
                    Modifier.testTag("comment-confirm-delete"),
                ) {
                    Text(tr(language, "Löschen", "Видалити"))
                }
            },
            dismissButton = {
                TextButton({ deleting = null }) { Text(tr(language, "Abbrechen", "Скасувати")) }
            },
        )
    }
}

@Composable
private fun AccountPrompt(language: String, onAccount: () -> Unit) {
    Text(
        tr(
            language,
            "Dafür brauchst du ein bestätigtes, aktives Konto und aktuelle Zustimmungen.",
            "Для цього потрібні підтверджений активний акаунт та актуальні згоди.",
        )
    )
    TextButton(onAccount) { Text(tr(language, "Konto öffnen", "Відкрити акаунт")) }
}

@Composable
private fun FailureText(failure: CommunityFailure, language: String) {
    Text(communityFailureText(failure, language), color = MaterialTheme.colorScheme.error)
}

fun communityFailureText(failure: CommunityFailure, language: String): String =
    when (failure) {
        CommunityFailure.SIGN_IN ->
            tr(language, "Bitte zuerst anmelden.", "Спочатку увійдіть в акаунт.")
        CommunityFailure.NOT_READY ->
            tr(
                language,
                "Bitte Kontostatus, Bestätigung und Sicherheitsanforderungen prüfen.",
                "Перевірте стан акаунта, підтвердження та вимоги безпеки.",
            )
        CommunityFailure.OFFLINE ->
            tr(
                language,
                "Server nicht erreichbar. Bitte Verbindung prüfen und aktualisieren.",
                "Сервер недоступний. Перевірте з’єднання та оновіть.",
            )
        CommunityFailure.DENIED ->
            tr(language, "Für diese Aktion fehlt die Berechtigung.", "Немає дозволу на цю дію.")
        CommunityFailure.MISSING,
        CommunityFailure.NOT_APPROVED ->
            tr(
                language,
                "Dieser Inhalt ist nicht mehr verfügbar.",
                "Цей матеріал більше недоступний.",
            )
        CommunityFailure.INVALID ->
            tr(
                language,
                "Ungültige Serverdaten. Bitte aktualisieren; es wird kein Erfolg angenommen.",
                "Некоректні дані сервера. Оновіть; успіх не підтверджено.",
            )
        CommunityFailure.FULL -> tr(language, "Alle Plätze sind belegt.", "Усі місця зайняті.")
        CommunityFailure.PAST ->
            tr(language, "Die Anmeldung ist bereits geschlossen.", "Реєстрацію вже завершено.")
        CommunityFailure.CANCELLED ->
            tr(language, "Die Veranstaltung wurde abgesagt.", "Подію скасовано.")
        CommunityFailure.NOT_REQUIRED ->
            tr(
                language,
                "Für diese Veranstaltung ist keine Anmeldung in der App nötig.",
                "Для цієї події реєстрація в застосунку не потрібна.",
            )
        CommunityFailure.REJECTED_TEXT ->
            tr(
                language,
                "Dieser Text kann nicht veröffentlicht werden. Bitte die Community-Regeln beachten.",
                "Цей текст не можна опублікувати. Дотримуйтеся правил спільноти.",
            )
        CommunityFailure.EMPTY_TEXT ->
            tr(language, "Bitte einen Kommentar eingeben.", "Введіть коментар.")
        CommunityFailure.TEXT_TOO_LONG ->
            tr(
                language,
                "Der Kommentar darf höchstens 1000 Zeichen umfassen.",
                "Коментар може містити щонайбільше 1000 символів.",
            )
        CommunityFailure.UNCONFIRMED ->
            tr(
                language,
                "Das Ergebnis ist unklar. Bitte zuerst aktualisieren und prüfen, ob dein Kommentar schon da ist. Kein automatischer Wiederholungsversuch.",
                "Результат невідомий. Спершу оновіть і перевірте, чи коментар уже з’явився. Автоматичного повтору не буде.",
            )
        CommunityFailure.UNKNOWN ->
            tr(
                language,
                "Die Aktion konnte nicht bestätigt werden. Bitte aktualisieren.",
                "Дію не вдалося підтвердити. Оновіть дані.",
            )
    }
