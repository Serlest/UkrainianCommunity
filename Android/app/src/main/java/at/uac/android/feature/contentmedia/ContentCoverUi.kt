package at.uac.android.feature.contentmedia

import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.feature.browse.tr
import at.uac.android.feature.organization.OrganizationSession

data class ContentCoverActions(
    val back: () -> Unit = {},
    val account: () -> Unit = {},
    val refresh: () -> Unit = {},
    val choose: () -> Unit = {},
    val upload: () -> Unit = {},
    val remove: () -> Unit = {},
    val discard: () -> Unit = {},
    val confirm: () -> Unit = {},
    val dismiss: () -> Unit = {},
    val recover: () -> Unit = {},
)

@Composable
fun ContentCoverScreen(
    model: ContentCoverViewModel,
    target: ContentCoverTarget,
    session: OrganizationSession?,
    language: String,
    onBack: () -> Unit,
    onAccount: () -> Unit,
) {
    val stored by model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    val state =
        if (stored.session == session && stored.target == target) stored
        else ContentCoverState(session, target)
    LifecycleResumeEffect(session, target) {
        model.show(target)
        onPauseOrDispose { model.hide() }
    }
    val picker =
        rememberLauncherForActivityResult(PickVisualMedia()) { uri ->
            model.pickerResult(uri?.toString())
        }
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    ContentCoverContent(
        state,
        language,
        ContentCoverActions(
            onBack,
            onAccount,
            model::refresh,
            {
                focus.clearFocus()
                keyboard?.hide()
                if (model.beginPicker()) {
                    try {
                        picker.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly))
                    } catch (_: Exception) {
                        model.pickerUnavailable()
                    }
                }
            },
            model::requestUpload,
            model::requestRemove,
            model::discardSelection,
            model::confirm,
            model::dismissConfirmation,
            model::recover,
        ),
    )
}

@Composable
fun ContentCoverContent(state: ContentCoverState, language: String, actions: ContentCoverActions) {
    var leaving by remember(state.session, state.target) { mutableStateOf(false) }
    val back = {
        if (state.prepared != null || state.busy || state.uncertain != null) leaving = true
        else actions.back()
    }
    BackHandler(state.prepared != null || state.busy || state.uncertain != null, back)
    Column(
        Modifier.fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp)
            .testTag("content-cover-screen"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        TextButton(back) { Text(tr(language, "Zurück", "Назад")) }
        Text(
            tr(language, "Titelbild", "Обкладинка"),
            style = MaterialTheme.typography.headlineMedium,
        )
        if (state.session?.ready != true) {
            Text(
                tr(
                    language,
                    "Ein bestätigtes, aktives Konto mit aktuellen Organisationsrechten ist erforderlich.",
                    "Потрібен підтверджений активний акаунт з актуальними правами організації.",
                )
            )
            Button(actions.account, Modifier.testTag("content-cover-account")) {
                Text(tr(language, "Konto öffnen", "Відкрити акаунт"))
            }
        } else {
            Text(
                tr(
                    language,
                    "Der Text ist separat gespeichert. Das Titelbild wird erst nach Ihrer Bestätigung übertragen.",
                    "Текст збережено окремо. Обкладинку буде завантажено лише після вашого підтвердження.",
                )
            )
            state.snapshot
                ?.takeIf { state.fresh }
                ?.let {
                    Text(
                        it.item.content.title(language),
                        style = MaterialTheme.typography.titleLarge,
                    )
                }
            if (state.loading || state.locked) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
                Text(
                    when {
                        state.pickerOpen ->
                            tr(language, "Fotoauswahl geöffnet …", "Відкрито вибір фото…")
                        state.preparing ->
                            tr(
                                language,
                                "Bild wird sicher vorbereitet …",
                                "Безпечно готуємо зображення…",
                            )
                        state.busy ->
                            tr(
                                language,
                                "Server, Datei und Verknüpfung werden geprüft …",
                                "Перевіряємо сервер, файл і посилання…",
                            )
                        else ->
                            tr(
                                language,
                                "Aktuelle Rechte und Daten werden geprüft …",
                                "Перевіряємо актуальні права й дані…",
                            )
                    }
                )
            }
            state.error?.let {
                Text(
                    contentCoverFailureText(it, language),
                    Modifier.testTag("content-cover-error"),
                    color = MaterialTheme.colorScheme.error,
                )
            }
            if (!state.fresh || state.snapshot?.editable == false)
                Text(
                    tr(
                        language,
                        "Änderungen sind gesperrt, bis der aktuelle Serverstand bearbeitet werden darf.",
                        "Зміни заблоковано, доки актуальний серверний стан не дозволятиме редагування.",
                    ),
                    Modifier.testTag("content-cover-readonly"),
                )
            TextButton(
                actions.refresh,
                Modifier.testTag("content-cover-refresh"),
                enabled = !state.loading && !state.locked,
            ) {
                Text(tr(language, "Aktualisieren", "Оновити"))
            }
            if (state.prepared != null) {
                Text(
                    tr(
                        language,
                        "Vorschau · noch nicht hochgeladen",
                        "Попередній перегляд · ще не завантажено",
                    ),
                    style = MaterialTheme.typography.titleMedium,
                )
                Text(
                    tr(
                        language,
                        "Zentraler 16:9-Ausschnitt ohne Verzerrung. Metadaten werden entfernt; transparente Flächen werden weiß. Prüfen Sie den Ausschnitt vor dem Bestätigen.",
                        "Центральний фрагмент 16:9 без викривлення. Метадані видаляються, прозорість стає білою. Перевірте фрагмент перед підтвердженням.",
                    )
                )
                val bytes = remember(state.prepared) { state.prepared.jpeg }
                CoverImage(
                    bytes,
                    tr(
                        language,
                        "Vorschau des ausgewählten Titelbilds",
                        "Попередній перегляд обраної обкладинки",
                    ),
                    "content-cover-preview",
                )
                Text(
                    "${state.prepared.width} × ${state.prepared.height} · ${state.prepared.byteCount / 1024} KiB · JPEG",
                    style = MaterialTheme.typography.bodySmall,
                )
                if (
                    state.fresh &&
                        !state.canUpload &&
                        state.uncertain == null &&
                        !state.locked &&
                        state.confirmation == null
                )
                    Text(
                        tr(
                            language,
                            "Die Rechte oder der Beitrag wurden seit der Auswahl geändert. Dieser Ausschnitt wird nicht über den neuen Stand geschrieben. Wählen Sie nach Prüfung erneut aus.",
                            "Права або матеріал змінилися після вибору. Цей фрагмент не перезапише новий стан. Перевірте дані та оберіть знову.",
                        ),
                        Modifier.testTag("content-cover-selection-stale"),
                    )
            } else if (state.fresh && state.asset != null) {
                Text(
                    tr(language, "Aktuelles Titelbild", "Поточна обкладинка"),
                    style = MaterialTheme.typography.titleMedium,
                )
                val bytes = remember(state.asset) { state.asset.bytes }
                CoverImage(
                    bytes,
                    tr(language, "Aktuelles Titelbild", "Поточна обкладинка"),
                    "content-cover-current",
                )
            } else if (state.fresh && state.snapshot?.imageUrl != null) {
                Text(
                    tr(
                        language,
                        "Die vorhandene Bildverknüpfung konnte lokal nicht vollständig bestätigt werden. Externe Bildadressen werden nicht aufgerufen.",
                        "Не вдалося повністю підтвердити наявне посилання на зображення локально. Зовнішні адреси зображень не відкриваємо.",
                    ),
                    Modifier.testTag("content-cover-image-unavailable"),
                )
            }
            if (state.confirmed)
                Text(
                    if (state.snapshot?.imageUrl == null)
                        tr(
                            language,
                            "Bildverknüpfung entfernt und vom Server bestätigt. Der Beitrag bleibt erhalten; die gespeicherte Datei wurde nicht gelöscht.",
                            "Посилання на обкладинку прибрано та підтверджено сервером. Матеріал збережено; файл не видалявся.",
                        )
                    else
                        tr(
                            language,
                            "Datei, Bildverknüpfung und unveränderte Beitragsdaten vom Server bestätigt.",
                            "Файл, посилання та незмінені дані матеріалу підтверджено сервером.",
                        ),
                    Modifier.testTag("content-cover-confirmed"),
                )
            if (state.uncertain != null) {
                Text(
                    contentCoverFailureText(ContentCoverFailure.UNCONFIRMED, language),
                    Modifier.testTag("content-cover-uncertain"),
                )
                Button(
                    actions.recover,
                    Modifier.testTag("content-cover-recover"),
                    enabled = !state.loading && !state.locked,
                ) {
                    Text(tr(language, "Nur Serverstand prüfen", "Лише перевірити серверний стан"))
                }
                if (state.recoveryChecked)
                    Text(
                        tr(
                            language,
                            "Der aktuelle Zustand bestätigt diese Änderung noch nicht. Es wird nichts automatisch erneut hochgeladen, entfernt oder zurückgesetzt.",
                            "Поточний стан ще не підтверджує цю зміну. Нічого не завантажуємо, не прибираємо й не відкочуємо автоматично.",
                        ),
                        Modifier.testTag("content-cover-unresolved"),
                    )
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                OutlinedButton(
                    actions.choose,
                    Modifier.testTag("content-cover-choose"),
                    enabled = state.canChoose,
                ) {
                    Text(tr(language, "Foto auswählen", "Обрати фото"))
                }
                if (state.prepared != null) {
                    Button(
                        actions.upload,
                        Modifier.testTag("content-cover-upload"),
                        enabled = state.canUpload,
                    ) {
                        Text(tr(language, "Diesen Ausschnitt speichern", "Зберегти цей фрагмент"))
                    }
                    TextButton(
                        actions.discard,
                        Modifier.testTag("content-cover-discard"),
                        enabled = !state.locked && state.uncertain == null,
                    ) {
                        Text(tr(language, "Auswahl verwerfen", "Відкинути вибір"))
                    }
                } else if (state.snapshot?.removable == true)
                    OutlinedButton(
                        actions.remove,
                        Modifier.testTag("content-cover-remove"),
                        enabled = state.canRemove,
                    ) {
                        Text(
                            tr(
                                language,
                                "Bildverknüpfung entfernen",
                                "Прибрати посилання на обкладинку",
                            )
                        )
                    }
            }
        }
    }
    if (leaving)
        AlertDialog(
            onDismissRequest = { leaving = false },
            title = { Text(tr(language, "Zurück zum Beitrag?", "Повернутися до матеріалу?")) },
            text = {
                Text(
                    tr(
                        language,
                        "Eine bereits gesendete Änderung lässt sich durch Zurückgehen nicht abbrechen. Die lokale Auswahl bleibt nur für dieses Konto in dieser App-Sitzung erhalten.",
                        "Повернення назад не скасовує вже надісланої зміни. Локальний вибір лишається лише для цього акаунта в поточній сесії застосунку.",
                    )
                )
            },
            confirmButton = {
                TextButton({
                    leaving = false
                    actions.back()
                }) {
                    Text(tr(language, "Zurück", "Назад"))
                }
            },
            dismissButton = {
                TextButton({ leaving = false }) {
                    Text(tr(language, "Hier bleiben", "Залишитися тут"))
                }
            },
        )
    state.confirmation
        ?.takeIf { state.session?.ready == true }
        ?.let { intent ->
            AlertDialog(
                onDismissRequest = actions.dismiss,
                title = {
                    Text(
                        if (intent is ContentCoverIntent.Remove)
                            tr(
                                language,
                                "Bildverknüpfung entfernen?",
                                "Прибрати посилання на обкладинку?",
                            )
                        else tr(language, "Titelbild speichern?", "Зберегти обкладинку?")
                    )
                },
                text = {
                    Text(
                        if (intent is ContentCoverIntent.Remove)
                            tr(
                                language,
                                "Nur die Bildverknüpfung dieser Nachricht wird entfernt. Text, Reaktionen und die gespeicherte Datei bleiben bestehen.",
                                "Буде прибрано лише посилання на обкладинку цієї новини. Текст, реакції та збережений файл залишаться.",
                            )
                        else
                            tr(
                                language,
                                "Der gezeigte Ausschnitt ersetzt die Datei dieses Beitrags. Datei und Datenbank werden nacheinander gespeichert; bei einer unklaren Antwort prüfen wir den Stand ohne automatische Wiederholung.",
                                "Показаний фрагмент замінить файл цього матеріалу. Файл і база зберігаються послідовно; за невизначеної відповіді перевіримо стан без автоматичного повтору.",
                            )
                    )
                },
                confirmButton = {
                    TextButton(
                        actions.confirm,
                        Modifier.testTag("content-cover-confirm"),
                        enabled = state.actionable,
                    ) {
                        Text(tr(language, "Bestätigen", "Підтвердити"))
                    }
                },
                dismissButton = {
                    TextButton(actions.dismiss) { Text(tr(language, "Abbrechen", "Скасувати")) }
                },
            )
        }
}

@Composable
private fun CoverImage(bytes: ByteArray, description: String, tag: String) {
    val bitmap =
        remember(bytes) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap() }
    if (bitmap != null)
        Image(
            bitmap,
            description,
            Modifier.fillMaxWidth().aspectRatio(16f / 9f).testTag(tag),
            contentScale = ContentScale.Fit,
        )
}

fun contentCoverFailureText(reason: ContentCoverFailure, language: String): String =
    when (reason) {
        ContentCoverFailure.SIGN_IN,
        ContentCoverFailure.NOT_READY ->
            tr(
                language,
                "Bitte zuerst das Konto und seine Sicherheitsanforderungen bestätigen.",
                "Спочатку підтвердьте акаунт і його вимоги безпеки.",
            )
        ContentCoverFailure.DENIED ->
            tr(
                language,
                "Die aktuellen Organisationsrechte erlauben diese Änderung nicht.",
                "Актуальні права організації не дозволяють цю зміну.",
            )
        ContentCoverFailure.INVALID,
        ContentCoverFailure.INVALID_IMAGE ->
            tr(
                language,
                "Dieses Bild oder dieser Auftrag konnte nicht sicher verarbeitet werden.",
                "Не вдалося безпечно обробити це зображення або запит.",
            )
        ContentCoverFailure.TOO_LARGE ->
            tr(
                language,
                "Bitte ein kleineres Original wählen (bis 20 MB und 100 Megapixel). Die vorbereitete JPEG-Datei muss kleiner als 3 MB sein.",
                "Оберіть менший оригінал (до 20 МБ і 100 мегапікселів). Підготовлений JPEG має бути меншим за 3 МБ.",
            )
        ContentCoverFailure.UNSUPPORTED ->
            tr(
                language,
                "Bitte ein unbewegtes JPEG-, PNG- oder WebP-Foto wählen.",
                "Оберіть статичне фото JPEG, PNG або WebP.",
            )
        ContentCoverFailure.UNREADABLE ->
            tr(
                language,
                "Dieses Foto ist nicht mehr zugänglich. Bitte erneut auswählen.",
                "Це фото більше недоступне. Оберіть його знову.",
            )
        ContentCoverFailure.MISSING ->
            tr(language, "Der Beitrag ist nicht mehr verfügbar.", "Матеріал більше недоступний.")
        ContentCoverFailure.READ_ONLY ->
            tr(
                language,
                "Dieser Beitrag ist in diesem Bereich schreibgeschützt.",
                "У цьому розділі матеріал доступний лише для перегляду.",
            )
        ContentCoverFailure.STALE ->
            tr(
                language,
                "Beitrag oder Rechte wurden geändert. Bitte den neuen Stand prüfen.",
                "Матеріал або права змінилися. Перевірте новий стан.",
            )
        ContentCoverFailure.OFFLINE ->
            tr(
                language,
                "Der lokale Server ist nicht erreichbar. Es wurde kein neuer Stand bestätigt.",
                "Локальний сервер недоступний. Новий стан не підтверджено.",
            )
        ContentCoverFailure.UNCONFIRMED ->
            tr(
                language,
                "Die vollständige Änderung ist nicht bestätigt. Die Datei kann bereits ersetzt worden sein. Wir senden nichts automatisch erneut; prüfen Sie den Serverstand.",
                "Повну зміну не підтверджено. Файл уже міг змінитися. Ми нічого не надсилаємо повторно автоматично; перевірте серверний стан.",
            )
        ContentCoverFailure.IMAGE_UNAVAILABLE ->
            tr(
                language,
                "Datei und Bildverknüpfung konnten nicht gemeinsam bestätigt werden.",
                "Не вдалося разом підтвердити файл і посилання на зображення.",
            )
        ContentCoverFailure.UNKNOWN ->
            tr(
                language,
                "Die Änderung konnte nicht bestätigt werden. Bitte den aktuellen Stand prüfen.",
                "Не вдалося підтвердити зміну. Перевірте актуальний стан.",
            )
    }
