package at.uac.android.feature.legalmanagement

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.design.LocalEmbeddedNavigation
import at.uac.android.design.UacDesign
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.feature.auth.AuthLegalDocument
import at.uac.android.feature.auth.AuthLegalReader
import at.uac.android.feature.browse.tr
import at.uac.android.feature.moderation.ModerationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

private fun label(type: String, language: String) = when (type) {
    "terms" -> tr(language, "Nutzungsbedingungen", "Умови користування")
    "privacy" -> tr(language, "Datenschutzerklärung", "Політика конфіденційності")
    else -> tr(language, "Organisationsregeln", "Правила організацій")
}

private fun summaryPart(summary: String?, key: String): String {
    val prefix = "$key:"
    return summary?.lineSequence()?.firstOrNull { it.startsWith(prefix) }
        ?.removePrefix(prefix)?.trim().orEmpty()
}

@Composable
fun LegalManagementScreen(
    session: ModerationSession?, language: String, source: LegalManagementSource,
    onBack: () -> Unit,
) {
    if (session?.ready != true || session.role != "owner") {
        Text(tr(language, "Nur für Eigentümer", "Лише для власника"),
            Modifier.padding(UacDesign.pageInset).testTag("legal-management-denied"))
        return
    }
    var documents by remember(session) { mutableStateOf<List<ManagedLegalDocument>?>(null) }
    var selected by remember(session) { mutableStateOf<ManagedLegalDocument?>(null) }
    var loading by remember(session) { mutableStateOf(true) }
    var error by remember(session) { mutableStateOf<String?>(null) }
    var busy by remember(session) { mutableStateOf(false) }
    var preview by remember(session) { mutableStateOf(false) }
    var confirm by remember(session) { mutableStateOf(false) }
    var titleDe by remember(session) { mutableStateOf("") }
    var titleUk by remember(session) { mutableStateOf("") }
    var markdownDe by remember(session) { mutableStateOf("") }
    var markdownUk by remember(session) { mutableStateOf("") }
    var summaryDe by remember(session) { mutableStateOf("") }
    var summaryUk by remember(session) { mutableStateOf("") }
    var savedHash by remember(session) { mutableStateOf<String?>(null) }
    var baseline by remember(session) { mutableStateOf<LegalDraftInput?>(null) }
    val scope = rememberCoroutineScope()

    fun open(document: ManagedLegalDocument) {
        val draft = document.draft ?: document.active
        titleDe = draft.locales["de"]?.title.orEmpty()
        titleUk = draft.locales["uk"]?.title.orEmpty()
        markdownDe = draft.locales["de"]?.markdown.orEmpty()
        markdownUk = draft.locales["uk"]?.markdown.orEmpty()
        summaryDe = summaryPart(document.draft?.summary, "DE")
        summaryUk = summaryPart(document.draft?.summary, "UK")
        savedHash = document.draft?.contentHash
        selected = document
        val next = LegalDraftContract.next(document.active)
        baseline = LegalDraftInput(document.active.type, document.draft?.version ?: next.first,
            document.draft?.versionNumber ?: next.second, document.active.version, savedHash,
            mapOf("de" to LegalLocale(titleDe, markdownDe),
                "uk" to LegalLocale(titleUk, markdownUk)), summaryDe, summaryUk)
    }

    fun input(document: ManagedLegalDocument): LegalDraftInput {
        val next = LegalDraftContract.next(document.active)
        return LegalDraftInput(document.active.type, document.draft?.version ?: next.first,
            document.draft?.versionNumber ?: next.second, document.active.version, savedHash,
            mapOf("de" to LegalLocale(titleDe, markdownDe),
                "uk" to LegalLocale(titleUk, markdownUk)), summaryDe, summaryUk)
    }

    suspend fun reload() {
        documents = null
        loading = true
        error = null
        try { documents = source.load(session) }
        catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { error = tr(language, "Dokumente konnten nicht geladen werden.",
            "Не вдалося завантажити документи.") }
        finally { loading = false }
    }

    fun saveDraft(exitAfterSave: Boolean = false) {
        val document = selected ?: return
        if (busy) return
        val draft = runCatching { input(document) }.getOrNull() ?: return
        if (runCatching { LegalDraftContract.requireSaveable(draft) }.isFailure) return
        if (draft == baseline && (savedHash != null || exitAfterSave)) {
            if (exitAfterSave) selected = null
            return
        }
        busy = true
        scope.launch {
            try {
                val persisted = source.save(session, draft)
                val loaded = source.load(session)
                val replacement = loaded.first { it.active.type == draft.type }
                if (replacement.draft?.contentHash != persisted.draft?.contentHash)
                    throw LegalManagementStale()
                documents = loaded
                savedHash = replacement.draft?.contentHash
                selected = if (exitAfterSave) null else replacement
                baseline = draft.copy(sourceHash = savedHash)
                error = null
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { error = tr(language,
                "Speichern nicht bestätigt. Vom Server neu laden.",
                "Збереження не підтверджено. Оновіть дані із сервера.") }
            finally { busy = false }
        }
    }

    fun handleBack() {
        if (selected == null) onBack() else saveDraft(exitAfterSave = true)
    }

    LaunchedEffect(session, source) { reload() }
    BackHandler(enabled = LocalEmbeddedNavigation.current && selected != null) { handleBack() }
    if (preview) {
        val document = selected
        if (document != null) AuthLegalReader(AuthLegalDocument(document.active.type,
            document.draft?.version ?: LegalDraftContract.next(document.active).first, true,
            mapOf("de" to titleDe, "uk" to titleUk),
            mapOf("de" to markdownDe, "uk" to markdownUk)), language, false) { preview = false }
    }
    if (confirm) {
        AlertDialog(onDismissRequest = { confirm = false },
            title = { Text(tr(language, "Neue rechtliche Version veröffentlichen?",
                "Опублікувати нову юридичну версію?")) },
            text = { Text(tr(language,
                "Alle betroffenen Konten müssen die neue Fassung erneut bestätigen.",
                "Усі відповідні облікові записи повинні повторно прийняти нову редакцію.")) },
            confirmButton = { TextButton({
                confirm = false
                val document = selected ?: return@TextButton
                if (busy) return@TextButton
                busy = true
                scope.launch {
                    try {
                        val current = input(document)
                        if (baseline != current || savedHash == null) throw LegalManagementStale()
                        val published = source.publish(session, current)
                        documents = documents.orEmpty().map {
                            if (it.active.type == current.type) published else it
                        }
                        selected = null
                        error = null
                    } catch (cancelled: CancellationException) { throw cancelled }
                    catch (_: Exception) { error = tr(language,
                        "Veröffentlichung nicht bestätigt. Vom Server neu laden.",
                        "Публікацію не підтверджено. Оновіть дані із сервера.") }
                    finally { busy = false }
                }
            }, Modifier.testTag("legal-management-confirm-publish")) {
                Text(tr(language, "Veröffentlichen", "Опублікувати"))
            } },
            dismissButton = { TextButton({ confirm = false }) {
                Text(tr(language, "Abbrechen", "Скасувати"))
            } })
    }
    LazyColumn(Modifier.fillMaxSize().testTag("legal-management-screen"),
        contentPadding = PaddingValues(start = UacDesign.pageInset, end = UacDesign.pageInset,
            bottom = 36.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        item("header") {
            UacSectionHeading(tr(language, "Rechtliche Dokumente", "Юридичні документи"), UacIcon.NEWS)
            TextButton(::handleBack, Modifier.testTag("legal-management-back")) {
                Text(tr(language, "Zurück", "Назад"))
            }
            error?.let { Text(it, Modifier.testTag("legal-management-error"),
                color = MaterialTheme.colorScheme.error) }
            if (loading) CircularProgressIndicator(Modifier.testTag("legal-management-loading"))
            if (documents == null && !loading) OutlinedButton({ scope.launch { reload() } }) {
                Text(tr(language, "Erneut laden", "Спробувати ще"))
            }
        }
        val editing = selected
        if (editing == null) {
            items(documents.orEmpty(), key = { it.active.type }) { document ->
                Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(label(document.active.type, language), style = MaterialTheme.typography.titleMedium)
                    Text(tr(language, "Aktiv: ", "Чинна: ") + document.active.version)
                    document.draft?.let { Text(tr(language, "Entwurf: ", "Чернетка: ") + it.version) }
                    OutlinedButton({ runCatching { open(document) }.onFailure {
                        error = tr(language, "Version ungültig", "Некоректна версія")
                    } }, Modifier.testTag("legal-management-open-${document.active.type}")) {
                        Text(tr(language, "Entwurf bearbeiten", "Редагувати чернетку"))
                    }
                }
            }
        } else {
            item("editor") {
                val current = runCatching { input(editing) }.getOrNull()
                val valid = current != null && runCatching { LegalDraftContract.requireValid(current) }.isSuccess
                val saveable = current != null && runCatching { LegalDraftContract.requireSaveable(current) }.isSuccess
                val unchanged = current != null && current == baseline && savedHash != null
                Column(Modifier.fillMaxWidth().testTag("legal-management-editor"),
                    verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(label(editing.active.type, language), style = MaterialTheme.typography.titleMedium)
                    Text(tr(language, "Neue Version: ", "Нова версія: ") +
                        (editing.draft?.version ?: runCatching { LegalDraftContract.next(editing.active).first }.getOrDefault("?")))
                    Text(tr(language,
                        "Titel, Volltext und Änderung in Deutsch und Ukrainisch sind erforderlich.",
                        "Потрібні назва, повний текст і опис змін німецькою та українською."))
                    OutlinedTextField(titleDe, { titleDe = it }, label = { Text("Titel DE") },
                        modifier = Modifier.fillMaxWidth().testTag("legal-management-title-de"))
                    OutlinedTextField(markdownDe, { markdownDe = it }, label = { Text("Text DE") },
                        minLines = 8, modifier = Modifier.fillMaxWidth().testTag("legal-management-body-de"))
                    OutlinedTextField(titleUk, { titleUk = it }, label = { Text("Назва UK") },
                        modifier = Modifier.fillMaxWidth().testTag("legal-management-title-uk"))
                    OutlinedTextField(markdownUk, { markdownUk = it }, label = { Text("Текст UK") },
                        minLines = 8, modifier = Modifier.fillMaxWidth().testTag("legal-management-body-uk"))
                    OutlinedTextField(summaryDe, { summaryDe = it }, label = { Text("Änderung DE") },
                        modifier = Modifier.fillMaxWidth().testTag("legal-management-summary-de"))
                    OutlinedTextField(summaryUk, { summaryUk = it }, label = { Text("Зміна UK") },
                        modifier = Modifier.fillMaxWidth().testTag("legal-management-summary-uk"))
                    OutlinedButton({ preview = true }, enabled = saveable) {
                        Text(tr(language, "Vorschau", "Перегляд"))
                    }
                    Button({ saveDraft() }, enabled = saveable && !busy && !unchanged,
                        modifier = Modifier.testTag("legal-management-save")) {
                        Text(tr(language, "Entwurf speichern", "Зберегти чернетку"))
                    }
                    OutlinedButton({ confirm = true }, enabled = valid && unchanged && !busy,
                        modifier = Modifier.testTag("legal-management-publish")) {
                        Text(tr(language, "Veröffentlichen", "Опублікувати"))
                    }
                    if (!valid) Text(tr(language, "Für die Veröffentlichung beide Sprachen und Änderungsbeschreibungen ausfüllen.",
                        "Для публікації заповніть обидві мови та описи змін."), color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
}
