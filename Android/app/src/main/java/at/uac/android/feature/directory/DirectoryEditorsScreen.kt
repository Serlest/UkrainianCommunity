package at.uac.android.feature.directory

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
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
import at.uac.android.design.UacDesign
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.feature.browse.tr
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.usermanagement.ManagedUser
import com.google.firebase.firestore.DocumentSnapshot
import kotlinx.coroutines.delay
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/** Private owner screen. All lists come from the server and are discarded on account change. */
@Composable
fun DirectoryEditorsScreen(
    session: ModerationSession?,
    language: String,
    source: DirectoryEditorsSource,
    onBack: () -> Unit,
) {
    if (session?.ready != true || session.role != "owner") {
        Text(tr(language, "Nur für Eigentümer", "Лише для власника"),
            Modifier.padding(UacDesign.pageInset).testTag("directory-editors-denied"))
        return
    }
    DirectoryEditorsOwnerContent(session, language, source, onBack)
}

@Composable
private fun DirectoryEditorsOwnerContent(
    session: ModerationSession,
    language: String,
    source: DirectoryEditorsSource,
    onBack: () -> Unit,
) {
    var grants by remember(session) { mutableStateOf<List<DirectoryGrant>>(emptyList()) }
    var candidates by remember(session) { mutableStateOf<List<ManagedUser>>(emptyList()) }
    var next by remember(session) { mutableStateOf<DocumentSnapshot?>(null) }
    var results by remember(session) { mutableStateOf<List<ManagedUser>>(emptyList()) }
    var query by remember(session) { mutableStateOf("") }
    var loading by remember(session) { mutableStateOf(true) }
    var searching by remember(session) { mutableStateOf(false) }
    var busy by remember(session) { mutableStateOf<String?>(null) }
    var confirm by remember(session) { mutableStateOf<DirectoryGrant?>(null) }
    var error by remember(session) { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    val refresh: suspend () -> Unit = {
        grants = source.grants(session)
        val first = source.candidates(session)
        candidates = first.users
        next = first.next
    }
    LaunchedEffect(session, source) {
        loading = true
        try { refresh() } catch (_: Exception) {
            error = tr(language, "Laden fehlgeschlagen. Erneut versuchen.",
                "Не вдалося завантажити. Спробуйте ще раз.")
        } finally { loading = false }
    }
    LaunchedEffect(session, query, source) {
        results = emptyList()
        if (query.trim().length < 2) { searching = false; return@LaunchedEffect }
        searching = true
        delay(350)
        try { results = source.search(session, query.trim()) } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            error = tr(language, "Suche fehlgeschlagen", "Пошук не вдався")
        } finally { searching = false }
    }
    val grantIds = grants.mapTo(mutableSetOf()) { it.uid }
    val visible = if (query.trim().length >= 2) results else candidates.filter {
        query.isBlank() || listOf(it.displayName, it.fullName, it.email).any { field ->
            field.contains(query.trim(), ignoreCase = true)
        }
    }
    fun change(uid: String, expected: com.google.firebase.Timestamp?, enable: Boolean) {
        if (busy != null) return
        busy = uid
        error = null
        scope.launch {
            try {
                source.change(session, uid, expected, enable)
                grants = source.grants(session)
            } catch (_: DirectoryGrantStale) {
                error = tr(language, "Zugriff wurde geändert. Liste aktualisieren.",
                    "Доступ уже змінено. Оновіть список.")
                runCatching { grants = source.grants(session) }
            } catch (_: DirectoryGrantInvalid) {
                error = tr(language, "Dieses Konto ist nicht aktiv.",
                    "Цей обліковий запис неактивний.")
            } catch (_: Exception) {
                error = tr(language, "Änderung nicht bestätigt. Liste aktualisieren.",
                    "Зміну не підтверджено. Оновіть список.")
                runCatching { grants = source.grants(session) }
            } finally { busy = null }
        }
    }
    confirm?.let { grant ->
        AlertDialog(
            onDismissRequest = { confirm = null },
            title = { Text(tr(language, "Ratgeberzugriff entziehen?", "Забрати доступ до довідника?")) },
            text = { Text(grant.name) },
            confirmButton = {
                TextButton({ confirm = null; change(grant.uid, grant.grantedAt, false) },
                    Modifier.testTag("directory-editors-confirm-revoke")) {
                    Text(tr(language, "Zugriff entziehen", "Забрати доступ"))
                }
            },
            dismissButton = {
                TextButton({ confirm = null }) { Text(tr(language, "Abbrechen", "Скасувати")) }
            },
        )
    }
    LazyColumn(
        Modifier.fillMaxSize().testTag("directory-editors-screen"),
        contentPadding = PaddingValues(start = UacDesign.pageInset, end = UacDesign.pageInset, bottom = 36.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item("heading") {
            UacSectionHeading(tr(language, "Ratgeberredakteure", "Редактори довідника"), UacIcon.EDIT)
            Text(tr(language,
                "Redakteure können alle Ratgeberinhalte veröffentlichen, ändern und ausblenden. Der Eigentümer behält diesen Zugriff immer.",
                "Редактори можуть публікувати, змінювати й приховувати всі матеріали довідника. Власник завжди має цей доступ."),
                style = MaterialTheme.typography.bodyMedium)
            TextButton(onBack) { Text(tr(language, "Zurück", "Назад")) }
            if (loading) Text(tr(language, "Laden…", "Завантаження…"), Modifier.testTag("directory-editors-loading"))
            error?.let { Text(it, color = MaterialTheme.colorScheme.error,
                modifier = Modifier.testTag("directory-editors-error")) }
            if (error != null) TextButton({
                error = null
                scope.launch { try { refresh() } catch (_: Exception) {
                    error = tr(language, "Laden fehlgeschlagen", "Не вдалося завантажити")
                } }
            }) { Text(tr(language, "Erneut versuchen", "Спробувати ще раз")) }
        }
        item("grants-heading") {
            Text(tr(language, "Mit Zugriff", "Мають доступ"), style = MaterialTheme.typography.titleMedium)
            if (!loading && grants.isEmpty())
                Text(tr(language, "Noch keine Redakteure", "Редакторів поки немає"))
        }
        items(grants, key = { "grant:${it.uid}" }) { grant ->
            Row(Modifier.fillMaxWidth().testTag("directory-grant-${grant.uid}"),
                horizontalArrangement = Arrangement.SpaceBetween) {
                Column(Modifier.weight(1f)) {
                    Text(grant.name)
                    Text(grant.uid, style = MaterialTheme.typography.bodySmall)
                }
                TextButton({ confirm = grant }, enabled = busy == null,
                    modifier = Modifier.testTag("directory-revoke-${grant.uid}")) {
                    Text(tr(language, "Entziehen", "Зняти"))
                }
            }
        }
        item("candidates-heading") {
            Text(tr(language, "Registrierte Nutzer", "Зареєстровані користувачі"),
                style = MaterialTheme.typography.titleMedium)
            OutlinedTextField(query, { query = it },
                label = { Text(tr(language, "Name oder E-Mail", "Ім’я або email")) },
                modifier = Modifier.fillMaxWidth().testTag("directory-editors-search"),
                singleLine = true)
            if (searching) Text(tr(language, "Suche…", "Пошук…"))
        }
        items(visible.filter { it.id != session.uid && it.globalRole != "owner" },
            key = { "user:${it.id}" }) { user ->
            Row(Modifier.fillMaxWidth().testTag("directory-candidate-${user.id}"),
                horizontalArrangement = Arrangement.SpaceBetween) {
                Column(Modifier.weight(1f)) {
                    Text(user.displayName.ifBlank { user.id })
                    Text(user.email, style = MaterialTheme.typography.bodySmall)
                }
                if (user.id in grantIds) Text(tr(language, "Zugriff aktiv", "Має доступ"))
                else OutlinedButton({ change(user.id, null, true) },
                    enabled = busy == null && user.accountStatus in setOf("active", "warned") &&
                        user.blockState in setOf("active", "warned"),
                    modifier = Modifier.testTag("directory-grant-${user.id}")) {
                    Text(tr(language, "Freigeben", "Надати"))
                }
            }
        }
        if (query.isBlank() && next != null) item("more") {
            Button({
                val cursor = next ?: return@Button
                next = null
                scope.launch {
                    try {
                        val page = source.candidates(session, cursor)
                        candidates += page.users.filterNot { user -> candidates.any { it.id == user.id } }
                        next = page.next
                    } catch (_: Exception) { error = tr(language, "Laden fehlgeschlagen", "Не вдалося завантажити") }
                }
            }, modifier = Modifier.testTag("directory-editors-more")) {
                Text(tr(language, "Weitere anzeigen", "Показати ще"))
            }
        }
    }
}
