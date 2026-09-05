package at.uac.android.feature.profilemedia

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.core.LocalStorage
import at.uac.android.feature.browse.PublicImage
import at.uac.android.feature.browse.tr

/**
 * Host supplies a session-masked state. Result callbacks retain the account that opened the picker.
 */
@Composable
fun ProfileAvatarEditor(
    state: ProfileMediaState,
    language: String,
    enabled: Boolean,
    currentAvatarUrl: String,
    model: ProfileMediaViewModel,
    onConfirmedUrl: (String) -> Unit,
) {
    LaunchedEffect(state.confirmationDelivered, state.confirmed, currentAvatarUrl) {
        if (
            state.confirmationDelivered &&
                state.confirmed != null &&
                currentAvatarUrl != state.confirmed.draft.avatarUrl
        )
            model.cancel()
    }
    val picker =
        rememberLauncherForActivityResult(PickVisualMedia()) { uri ->
            model.pickerResult(uri?.toString())
        }
    if (
        state.selection == null &&
            state.session != null &&
            LocalStorage.urlMatches(currentAvatarUrl, profileAvatarPath(state.session.uid))
    ) {
        Box(Modifier.size(112.dp).clip(CircleShape).testTag("profile-avatar-current")) {
            PublicImage(
                currentAvatarUrl,
                tr(language, "Aktuelles Profilfoto", "Поточне фото профілю"),
                language,
            )
        }
    }
    ProfileAvatarPanel(
        state,
        language,
        enabled,
        onChoose = {
            if (model.beginPicker()) {
                try {
                    picker.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly))
                } catch (_: Exception) {
                    model.pickerUnavailable()
                }
            }
        },
        onSave = model::save,
        onCancel = model::cancel,
        onConfirmedUrl = {
            onConfirmedUrl(it)
            model.confirmationDelivered()
        },
    )
}

@Composable
fun ProfileAvatarPanel(
    state: ProfileMediaState,
    language: String,
    enabled: Boolean,
    onChoose: () -> Unit,
    onSave: () -> Unit,
    onCancel: () -> Unit,
    onConfirmedUrl: (String) -> Unit,
) {
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    LaunchedEffect(state.session, state.confirmed, state.confirmationDelivered) {
        if (!state.confirmationDelivered)
            state.confirmed?.let { onConfirmedUrl(it.draft.avatarUrl) }
    }
    val preview =
        remember(state.session, state.selection) {
            state.selection?.jpeg?.let {
                BitmapFactory.decodeByteArray(it, 0, it.size)?.asImageBitmap()
            }
        }
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.testTag("profile-avatar-editor"),
    ) {
        Text(
            tr(language, "Profilfoto", "Фото профілю"),
            style = MaterialTheme.typography.titleMedium,
        )
        Text(
            tr(
                language,
                "Wähle ein JPEG-, PNG- oder WebP-Foto. Wir schneiden die Mitte quadratisch zu; prüfe die Vorschau. Metadaten werden entfernt.",
                "Оберіть фото JPEG, PNG або WebP. Ми обріжемо центр до квадрата — перевірте попередній перегляд. Метадані буде видалено.",
            ),
            style = MaterialTheme.typography.bodySmall,
        )
        if (preview != null)
            Image(
                preview,
                tr(
                    language,
                    "Vorschau des ausgewählten Profilfotos",
                    "Попередній перегляд обраного фото",
                ),
                Modifier.size(112.dp).clip(CircleShape).testTag("profile-avatar-preview"),
            )
        if (state.busy) {
            if (state.phase == ProfileMediaPhase.UPLOADING && state.progress != null)
                LinearProgressIndicator(
                    progress = { state.progress },
                    modifier = Modifier.fillMaxWidth(),
                )
            else LinearProgressIndicator(Modifier.fillMaxWidth())
            Text(
                when {
                    state.pickerOpen ->
                        tr(language, "Fotoauswahl geöffnet …", "Відкрито вибір фото…")
                    state.cancelRequested ->
                        tr(language, "Abbruch wird bestätigt …", "Підтверджуємо скасування…")
                    state.phase == ProfileMediaPhase.COMMITTING ->
                        tr(
                            language,
                            "Profil und öffentliches Foto werden geprüft …",
                            "Перевіряємо профіль і публічне фото…",
                        )
                    state.preparing -> tr(language, "Foto wird vorbereitet …", "Готуємо фото…")
                    else -> tr(language, "Foto wird hochgeladen …", "Завантажуємо фото…")
                }
            )
        }
        state.error?.let {
            Text(
                profileMediaFailureText(it, language),
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.testTag("profile-avatar-error"),
            )
        }
        if (state.confirmed != null)
            Text(
                tr(
                    language,
                    "Foto gespeichert; Datei und Profil vom Server bestätigt. Andere Formularänderungen bleiben ungespeichert.",
                    "Фото збережено; файл і профіль підтверджено сервером. Інші зміни у формі ще не збережені.",
                ),
                Modifier.testTag("profile-avatar-confirmed"),
            )
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(
                onClick = {
                    focus.clearFocus()
                    keyboard?.hide()
                    onChoose()
                },
                enabled = enabled && !state.busy && state.session?.ready == true,
                modifier = Modifier.testTag("profile-avatar-choose"),
            ) {
                Text(tr(language, "Foto auswählen", "Обрати фото"))
            }
            if (state.selection != null && state.confirmed == null)
                Button(
                    onClick = {
                        focus.clearFocus()
                        keyboard?.hide()
                        onSave()
                    },
                    enabled = enabled && !state.busy && state.session?.ready == true,
                    modifier = Modifier.testTag("profile-avatar-upload"),
                ) {
                    Text(
                        if (state.error != null)
                            tr(language, "Foto erneut speichern", "Повторити збереження фото")
                        else tr(language, "Nur Foto speichern", "Зберегти лише фото")
                    )
                }
            if (state.selection != null || state.preparing)
                OutlinedButton(
                    onClick = onCancel,
                    enabled = state.phase != ProfileMediaPhase.COMMITTING && !state.cancelRequested,
                    modifier = Modifier.testTag("profile-avatar-cancel"),
                ) {
                    Text(tr(language, "Verwerfen / abbrechen", "Відхилити / скасувати"))
                }
        }
    }
}

fun profileMediaFailureText(reason: ProfileMediaFailure, language: String): String =
    when (reason) {
        ProfileMediaFailure.SIGN_IN,
        ProfileMediaFailure.NOT_READY ->
            tr(
                language,
                "Ein bestätigtes, aktives Konto ist erforderlich.",
                "Потрібен підтверджений активний обліковий запис.",
            )
        ProfileMediaFailure.INVALID ->
            tr(
                language,
                "Dieses Foto konnte nicht sicher verarbeitet werden. Bitte wähle ein anderes.",
                "Не вдалося безпечно обробити це фото. Оберіть інше.",
            )
        ProfileMediaFailure.TOO_LARGE ->
            tr(
                language,
                "Das Original ist zu groß (maximal 20 MB und 100 Megapixel). Bitte wähle eine kleinere Datei.",
                "Оригінал завеликий (до 20 МБ і 100 мегапікселів). Оберіть менший файл.",
            )
        ProfileMediaFailure.UNSUPPORTED ->
            tr(
                language,
                "Bitte ein unbewegtes JPEG-, PNG- oder WebP-Foto wählen. Animationen werden nicht übernommen.",
                "Оберіть статичне фото JPEG, PNG або WebP. Анімація не підтримується.",
            )
        ProfileMediaFailure.UNREADABLE ->
            tr(
                language,
                "Das ausgewählte Foto ist nicht mehr zugänglich. Bitte wähle es erneut aus.",
                "Обране фото більше недоступне. Оберіть його ще раз.",
            )
        ProfileMediaFailure.DENIED ->
            tr(
                language,
                "Der Server hat die Änderung nicht erlaubt. Prüfe deinen Kontostatus.",
                "Сервер не дозволив зміну. Перевірте статус облікового запису.",
            )
        ProfileMediaFailure.OFFLINE,
        ProfileMediaFailure.UNCONFIRMED ->
            tr(
                language,
                "Die vollständige Speicherung ist noch nicht bestätigt. Das Foto kann bereits hochgeladen sein. Prüfe die Verbindung und versuche dieselbe Auswahl erneut.",
                "Повне збереження ще не підтверджено. Фото вже могло завантажитися. Перевірте з’єднання та повторіть спробу з тим самим фото.",
            )
        ProfileMediaFailure.CANCELLED ->
            tr(
                language,
                "Abgebrochen. Eine bereits übertragene Datei kann schon ersetzt worden sein; ein alter Avatar wird nicht automatisch gelöscht.",
                "Скасовано. Уже переданий файл міг замінити попередній; старий аватар автоматично не видаляється.",
            )
    }
