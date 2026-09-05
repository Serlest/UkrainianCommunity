package at.uac.android.feature.gallery

import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts.PickVisualMedia
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.PublicImage
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.tr
import at.uac.android.feature.organization.OrganizationSession

data class GalleryActions(
    val back: () -> Unit = {},
    val account: () -> Unit = {},
    val refresh: () -> Unit = {},
    val choose: () -> Unit = {},
    val caption: (String) -> Unit = {},
    val upload: () -> Unit = {},
    val discard: () -> Unit = {},
    val remove: (GalleryPhoto) -> Unit = {},
    val preview: (GalleryPhoto) -> Unit = {},
    val dismissPreview: () -> Unit = {},
    val reconcile: (GalleryJournalEntry) -> Unit = {},
    val cleanup: (GalleryJournalEntry) -> Unit = {},
    val confirm: () -> Unit = {},
    val dismiss: () -> Unit = {},
)

/**
 * Management eligibility uses only the freshly confirmed organization supplied by the host, no
 * photo prefetch.
 */
@Composable
fun GalleryAccessPanel(
    content: Content,
    session: OrganizationSession?,
    language: String,
    onOpen: (String) -> Unit,
    currentTarget: () -> Boolean,
) {
    if (
        content.kind != ContentKind.ORGANIZATIONS ||
            !currentTarget() ||
            !GalleryContract.canManage(RawDocument(content.id, content.fields), session)
    )
        return
    OutlinedButton(
        { if (currentTarget()) onOpen(content.id) },
        Modifier.fillMaxWidth().testTag("gallery-open"),
    ) {
        Text(tr(language, "Fotogalerie verwalten", "Керувати фотогалереєю"))
    }
}

@Composable
fun GalleryScreen(
    model: GalleryViewModel,
    organizationId: String,
    session: OrganizationSession?,
    language: String,
    onBack: () -> Unit,
    onAccount: () -> Unit,
) {
    val stored by model.state.collectAsStateWithLifecycle(minActiveState = Lifecycle.State.RESUMED)
    val state = stored.forSession(session, organizationId)
    LifecycleResumeEffect(session, organizationId) {
        model.show(organizationId)
        onPauseOrDispose { model.hide() }
    }
    val picker =
        rememberLauncherForActivityResult(PickVisualMedia()) { uri ->
            model.pickerResult(uri?.toString())
        }
    val focus = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    fun dismissInput() {
        focus.clearFocus()
        keyboard?.hide()
    }
    GalleryContent(
        state,
        language,
        GalleryActions(
            back = {
                model.hide()
                onBack()
            },
            account = {
                model.hide()
                onAccount()
            },
            refresh = model::refresh,
            choose = {
                dismissInput()
                if (model.beginPicker())
                    try {
                        picker.launch(PickVisualMediaRequest(PickVisualMedia.ImageOnly))
                    } catch (_: Exception) {
                        model.pickerUnavailable()
                    }
            },
            caption = model::caption,
            upload = {
                dismissInput()
                model.requestUpload()
            },
            discard = model::discard,
            remove = {
                dismissInput()
                model.requestRemove(it)
            },
            preview = model::preview,
            dismissPreview = model::dismissPreview,
            reconcile = model::reconcile,
            cleanup = model::requestCleanup,
            confirm = {
                dismissInput()
                model.confirm()
            },
            dismiss = model::dismissConfirmation,
        ),
        visibleOrganization = model::visible,
    )
}

@Composable
fun GalleryContent(
    state: GalleryState,
    language: String,
    actions: GalleryActions,
    visibleOrganization: (GallerySnapshot) -> Boolean = { true },
) {
    val snapshot =
        state.snapshot?.takeIf {
            state.visible &&
                state.session?.ready == true &&
                state.fresh &&
                !state.loading &&
                GalleryContract.canManage(it.organization, state.session) &&
                visibleOrganization(it)
        }
    var leaving by remember(state.session?.uid, state.organizationId) { mutableStateOf(false) }
    val back = { if (state.prepared != null || state.busy) leaving = true else actions.back() }
    BackHandler(onBack = back)
    LazyColumn(
        Modifier.fillMaxSize().imePadding().testTag("gallery-list"),
        contentPadding = PaddingValues(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item("header") {
            TextButton(back, Modifier.testTag("gallery-back")) {
                Text(tr(language, "Zurück", "Назад"))
            }
            Text(
                tr(language, "Fotogalerie", "Фотогалерея"),
                style = MaterialTheme.typography.headlineMedium,
            )
            Text(
                tr(
                    language,
                    "Bis zu 30 Fotos. Neue Fotos und ihre Bildunterschrift werden erst nach Ihrer Bestätigung veröffentlicht.",
                    "До 30 фотографій. Нове фото й підпис публікуються лише після вашого підтвердження.",
                )
            )
        }
        if (state.session?.ready != true)
            item("account") {
                Text(
                    galleryFailureText(
                        if (state.session == null) GalleryFailure.SIGN_IN
                        else GalleryFailure.NOT_READY,
                        language,
                    )
                )
                Button(actions.account, Modifier.testTag("gallery-account")) {
                    Text(tr(language, "Konto öffnen", "Відкрити акаунт"))
                }
            }
        else {
            item("refresh") {
                TextButton(
                    actions.refresh,
                    Modifier.testTag("gallery-refresh"),
                    enabled = !state.loading && !state.locked,
                ) {
                    Text(tr(language, "Daten und Rechte prüfen", "Перевірити дані й права"))
                }
            }
            if (state.loading || state.locked)
                item("busy") {
                    LinearProgressIndicator(Modifier.fillMaxWidth().testTag("gallery-loading"))
                    Text(
                        tr(
                            language,
                            "Auswahl, Datei oder Server werden geprüft …",
                            "Перевіряємо вибір, файл або сервер…",
                        )
                    )
                }
            state.error?.let { error ->
                item("error") {
                    Text(
                        galleryFailureText(error, language),
                        Modifier.testTag("gallery-error"),
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
            if (snapshot == null)
                item("unavailable") {
                    Text(
                        tr(
                            language,
                            "Fotos und Änderungen bleiben verborgen, bis aktuelle Rechte und der Serverstand bestätigt sind.",
                            "Фото й редагування приховано до підтвердження актуальних прав і серверного стану.",
                        ),
                        Modifier.testTag("gallery-unavailable"),
                    )
                }
            if (state.confirmed)
                item("confirmed") {
                    Text(
                        tr(
                            language,
                            "Änderung und Serverstand bestätigt.",
                            "Зміну й серверний стан підтверджено.",
                        ),
                        Modifier.testTag("gallery-confirmed"),
                    )
                }
            items(state.pending, key = { "pending-${it.target.photoId}" }) { entry ->
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        tr(
                            language,
                            "Eine unterbrochene Fotoaktion ist noch offen. Es wird nichts automatisch wiederholt oder gelöscht.",
                            "Є незавершена дія з фото. Нічого не повторюється й не видаляється автоматично.",
                        ),
                        Modifier.testTag("gallery-pending-${entry.target.photoId}"),
                    )
                    Button(
                        { actions.reconcile(entry) },
                        Modifier.testTag("gallery-reconcile-${entry.target.photoId}"),
                        enabled = !state.locked && !state.loading,
                    ) {
                        Text(
                            tr(language, "Nur Serverstand prüfen", "Лише перевірити серверний стан")
                        )
                    }
                    if (
                        state.recoveryFor == entry &&
                            state.recovery == GalleryRecovery.CLEANUP_AVAILABLE
                    )
                        OutlinedButton(
                            { actions.cleanup(entry) },
                            Modifier.testTag("gallery-cleanup-${entry.target.photoId}"),
                            enabled = snapshot != null && state.actionable,
                        ) {
                            Text(
                                tr(
                                    language,
                                    "Nicht verknüpfte Datei bereinigen",
                                    "Прибрати неприкріплений файл",
                                )
                            )
                        }
                }
            }
            if (state.recovery == GalleryRecovery.UNRESOLVED)
                item("unresolved") {
                    Text(
                        tr(
                            language,
                            "Der Ausgang ist noch unbestätigt. Auch ein fehlender Eintrag beweist nicht, dass die ursprüngliche Anfrage nicht mehr verarbeitet wird.",
                            "Результат ще не підтверджено. Навіть відсутній запис не доводить, що початковий запит уже не обробляється.",
                        ),
                        Modifier.testTag("gallery-unresolved"),
                    )
                }
            if (snapshot != null) {
                item("organization") {
                    Text(
                        snapshot.content.title(language),
                        style = MaterialTheme.typography.titleLarge,
                    )
                    Text("${snapshot.photos.size} / 30", Modifier.testTag("gallery-count"))
                    if (snapshot.overflow)
                        Text(
                            tr(
                                language,
                                "Es existieren mehr als 30 Einträge. Angezeigt wird nur das erste Fenster; Änderungen benötigen eine gesonderte Prüfung.",
                                "Існує понад 30 записів. Показано лише перше вікно; зміни потребують окремої перевірки.",
                            ),
                            Modifier.testTag("gallery-overflow"),
                        )
                }
                item("editor") {
                    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        if (state.prepared != null) {
                            val bytes = remember(state.prepared) { state.prepared.bytes() }
                            GalleryImage(
                                bytes,
                                tr(
                                    language,
                                    "Vorschau des ausgewählten Fotos",
                                    "Попередній перегляд обраного фото",
                                ),
                                "gallery-prepared",
                            )
                            Text(
                                tr(
                                    language,
                                    "Proportionen bleiben erhalten. Metadaten werden entfernt; transparente Flächen werden weiß.",
                                    "Пропорції збережено. Метадані видаляються, прозорість стає білою.",
                                )
                            )
                            OutlinedTextField(
                                state.caption,
                                actions.caption,
                                Modifier.fillMaxWidth().testTag("gallery-caption"),
                                enabled = !state.locked && state.pending.isEmpty(),
                                label = {
                                    Text(
                                        tr(
                                            language,
                                            "Bildunterschrift (optional)",
                                            "Підпис (необов’язково)",
                                        )
                                    )
                                },
                                supportingText = { Text("${state.caption.length} / 500") },
                                isError = state.caption.length > 500,
                            )
                        }
                        FlowRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            OutlinedButton(
                                actions.choose,
                                Modifier.testTag("gallery-choose"),
                                enabled = state.canChoose,
                            ) {
                                Text(tr(language, "Foto auswählen", "Обрати фото"))
                            }
                            if (state.prepared != null) {
                                Button(
                                    actions.upload,
                                    Modifier.testTag("gallery-upload"),
                                    enabled = state.canUpload,
                                ) {
                                    Text(tr(language, "Foto veröffentlichen", "Опублікувати фото"))
                                }
                                TextButton(
                                    actions.discard,
                                    Modifier.testTag("gallery-discard"),
                                    enabled = !state.locked && state.pending.isEmpty(),
                                ) {
                                    Text(tr(language, "Auswahl verwerfen", "Відкинути вибір"))
                                }
                            }
                        }
                    }
                }
                if (snapshot.photos.isEmpty())
                    item("empty") {
                        Text(
                            tr(language, "Noch keine Fotos.", "Фотографій поки немає."),
                            Modifier.testTag("gallery-empty"),
                        )
                    }
                items(snapshot.photos, key = { it.target.photoId }) { photo ->
                    OutlinedCard(
                        Modifier.fillMaxWidth().testTag("gallery-photo-${photo.target.photoId}")
                    ) {
                        Column(
                            Modifier.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            // Private organization pictures are fetched only through the authorized
                            // SDK preview action.
                            if (snapshot.organization.fields["moderationStatus"] == "approved")
                                PublicImage(
                                    photo.imageUrl,
                                    photo.caption
                                        ?: tr(
                                            language,
                                            "Foto der Organisation",
                                            "Фото організації",
                                        ),
                                    language,
                                    Modifier.fillMaxWidth(),
                                )
                            photo.caption?.let { Text(it) }
                            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                TextButton(
                                    { actions.preview(photo) },
                                    Modifier.testTag("gallery-preview-${photo.target.photoId}"),
                                    enabled = state.readable,
                                ) {
                                    Text(tr(language, "Foto prüfen", "Переглянути фото"))
                                }
                                OutlinedButton(
                                    { actions.remove(photo) },
                                    Modifier.testTag("gallery-remove-${photo.target.photoId}"),
                                    enabled = state.actionable && state.pending.isEmpty(),
                                ) {
                                    Text(tr(language, "Löschen", "Видалити"))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if (snapshot != null && state.confirmation != null)
        AlertDialog(
            onDismissRequest = actions.dismiss,
            title = {
                Text(
                    when (state.confirmation) {
                        is GalleryConfirmation.Upload ->
                            tr(language, "Foto veröffentlichen?", "Опублікувати фото?")
                        is GalleryConfirmation.Remove ->
                            tr(language, "Foto dauerhaft löschen?", "Видалити фото назавжди?")
                        is GalleryConfirmation.Cleanup ->
                            tr(language, "Datei bereinigen?", "Прибрати файл?")
                    }
                )
            },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    if (state.confirmation is GalleryConfirmation.Remove)
                        state.confirmation.photo.caption?.let { Text(it) }
                    Text(
                        tr(
                            language,
                            "Datei und Verknüpfung werden auf dem Server geprüft. Bei unbestätigtem Ergebnis erfolgt keine automatische Wiederholung.",
                            "Файл і посилання перевіряються на сервері. Якщо результат не підтверджено, автоматичного повторення не буде.",
                        )
                    )
                }
            },
            confirmButton = {
                Button(
                    actions.confirm,
                    Modifier.testTag("gallery-confirm"),
                    enabled = !state.busy,
                ) {
                    Text(tr(language, "Bestätigen", "Підтвердити"))
                }
            },
            dismissButton = {
                TextButton(actions.dismiss) { Text(tr(language, "Abbrechen", "Скасувати")) }
            },
        )
    if (snapshot != null && state.preview != null)
        AlertDialog(
            onDismissRequest = actions.dismissPreview,
            title = { Text(tr(language, "Bestätigte Fotodatei", "Перевірений файл фото")) },
            text = {
                val bytes = remember(state.preview) { state.preview.bytes() }
                GalleryImage(bytes, tr(language, "Foto", "Фото"), "gallery-preview-image")
            },
            confirmButton = {
                TextButton(actions.dismissPreview) { Text(tr(language, "Schließen", "Закрити")) }
            },
        )
    if (leaving)
        AlertDialog(
            onDismissRequest = { leaving = false },
            title = { Text(tr(language, "Galerie verlassen?", "Вийти з галереї?")) },
            text = {
                Text(
                    tr(
                        language,
                        "Der lokale Entwurf bleibt nur im Arbeitsspeicher dieses Kontos. Eine laufende Serveraktion wird nicht rückgängig gemacht.",
                        "Локальна чернетка залишається лише в пам’яті цього акаунта. Серверна дія, що вже виконується, не скасовується.",
                    )
                )
            },
            confirmButton = {
                TextButton(
                    {
                        leaving = false
                        actions.back()
                    },
                    Modifier.testTag("gallery-leave-confirm"),
                ) {
                    Text(tr(language, "Verlassen", "Вийти"))
                }
            },
            dismissButton = {
                TextButton({ leaving = false }) { Text(tr(language, "Bleiben", "Залишитися")) }
            },
        )
}

@Composable
private fun GalleryImage(bytes: ByteArray, label: String, tag: String) {
    val bitmap = remember(bytes) { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) }
    if (bitmap != null)
        BoxWithConstraints(Modifier.fillMaxWidth()) {
            // Preserve natural landscape size, but a valid 1×1600 image must not request an
            // unbounded list height.
            val naturalHeight = maxWidth * (bitmap.height.toFloat() / bitmap.width)
            val viewportHeight = naturalHeight.coerceIn(1.dp, 320.dp)
            Image(
                bitmap.asImageBitmap(),
                label,
                Modifier.fillMaxWidth().height(viewportHeight).testTag(tag),
                contentScale = ContentScale.Fit,
            )
        }
}

fun galleryFailureText(error: GalleryFailure, language: String): String =
    when (error) {
        GalleryFailure.SIGN_IN,
        GalleryFailure.NOT_READY ->
            tr(
                language,
                "Ein bestätigtes aktives Konto ist erforderlich.",
                "Потрібен підтверджений активний акаунт.",
            )
        GalleryFailure.DENIED,
        GalleryFailure.POLICY ->
            tr(
                language,
                "Diese Galerie darf mit den aktuellen Rechten nicht verwaltet werden.",
                "Поточні права не дозволяють керувати цією галереєю.",
            )
        GalleryFailure.MISSING ->
            tr(
                language,
                "Organisation oder Foto nicht verfügbar.",
                "Організація або фото недоступні.",
            )
        GalleryFailure.LIMIT ->
            tr(
                language,
                "Die Grenze von 30 Fotos ist erreicht oder das Altarchiv benötigt eine Prüfung.",
                "Досягнуто межі 30 фото або старі записи потребують перевірки.",
            )
        GalleryFailure.OFFLINE ->
            tr(
                language,
                "Der Server ist nicht erreichbar. Es werden keine zwischengespeicherten Rechte verwendet.",
                "Сервер недоступний. Збережені раніше права не використовуються.",
            )
        GalleryFailure.STALE ->
            tr(
                language,
                "Daten oder Rechte wurden geändert. Bitte den Serverstand erneut prüfen.",
                "Дані або права змінилися. Перевірте серверний стан знову.",
            )
        GalleryFailure.JOURNAL ->
            tr(
                language,
                "Der lokale Wiederherstellungsnachweis konnte nicht sicher gespeichert oder gelesen werden. Änderungen sind gesperrt.",
                "Не вдалося безпечно записати або прочитати локальний запис відновлення. Зміни заблоковано.",
            )
        GalleryFailure.CONFLICT ->
            tr(
                language,
                "Datei oder Verknüpfung entspricht nicht dieser Aktion. Es wird nichts überschrieben oder automatisch gelöscht.",
                "Файл або посилання не відповідає цій дії. Нічого не перезаписуємо й не видаляємо автоматично.",
            )
        GalleryFailure.UNCONFIRMED ->
            tr(
                language,
                "Der Ausgang ist unbestätigt. Prüfen Sie den Serverstand; die Aktion wird nicht automatisch wiederholt.",
                "Результат не підтверджено. Перевірте серверний стан; дія автоматично не повторюється.",
            )
        GalleryFailure.CLEANUP_PENDING ->
            tr(
                language,
                "Der Fotoeintrag wurde entfernt; die Bereinigung der Datei ist noch nicht bestätigt.",
                "Запис фото видалено; очищення файлу ще не підтверджено.",
            )
        GalleryFailure.IMAGE_UNAVAILABLE,
        GalleryFailure.UNREADABLE ->
            tr(
                language,
                "Dieses Bild konnte nicht sicher gelesen werden. Wählen Sie ein unterstütztes Foto.",
                "Не вдалося безпечно прочитати зображення. Оберіть підтримуване фото.",
            )
        GalleryFailure.INVALID ->
            tr(language, "Foto oder Bildunterschrift ist ungültig.", "Фото або підпис некоректні.")
        GalleryFailure.INDEX,
        GalleryFailure.UNKNOWN ->
            tr(
                language,
                "Die Serverprüfung ist fehlgeschlagen. Es wurde kein Erfolg angenommen.",
                "Серверна перевірка не вдалася. Успішний результат не припускається.",
            )
    }
