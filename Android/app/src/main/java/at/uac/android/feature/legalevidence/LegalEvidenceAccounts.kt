package at.uac.android.feature.legalevidence

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
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
import at.uac.android.core.backend.AppBackend
import at.uac.android.design.LocalEmbeddedNavigation
import at.uac.android.design.UacDesign
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSectionHeading
import at.uac.android.feature.browse.tr
import at.uac.android.feature.moderation.ModerationSession
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

data class EvidenceAccount(val userId: String, val displayName: String?, val email: String?,
    val createdAt: Instant?)
data class EvidenceAccountCursor(val userId: String, val createdAt: String,
    val seconds: Long, val nanoseconds: Int)
data class EvidenceAccountsPage(val accounts: List<EvidenceAccount>,
    val cursor: EvidenceAccountCursor?, val totalMatches: Int?)

object EvidenceAccountsContract {
    fun request(query: String, cursor: EvidenceAccountCursor?): Map<String, Any?> {
        val trimmed = query.trim()
        require(trimmed.isEmpty() || trimmed.length in 2..120)
        require(trimmed.isEmpty() || cursor == null)
        return mapOf("query" to trimmed, "limit" to 50,
            "cursor" to cursor?.let { mapOf("userId" to it.userId, "createdAt" to it.createdAt,
                "seconds" to it.seconds, "nanoseconds" to it.nanoseconds) })
    }

    fun decode(raw: Any?): EvidenceAccountsPage {
        val data = raw as? Map<*, *> ?: error("Invalid account response")
        val rows = data["accounts"] as? List<*> ?: error("Invalid accounts")
        val accounts = rows.map { value ->
            val account = value as? Map<*, *> ?: error("Invalid account")
            EvidenceAccount(account["userId"] as? String ?: error("Missing userId"),
                account["displayName"] as? String, account["email"] as? String,
                (account["createdAt"] as? String)?.let(Instant::parse))
        }
        require(accounts.map { it.userId }.distinct().size == accounts.size)
        val next = (data["nextCursor"] as? Map<*, *>)?.let {
            EvidenceAccountCursor(it["userId"] as? String ?: error("Missing cursor user"),
                it["createdAt"] as? String ?: error("Missing cursor date"),
                (it["seconds"] as? Number)?.toLong() ?: error("Missing seconds"),
                (it["nanoseconds"] as? Number)?.toInt() ?: error("Missing nanoseconds"))
        }
        return EvidenceAccountsPage(accounts, next,
            (data["totalMatches"] as? Number)?.toInt())
    }
}

fun interface EvidenceAccountsSource {
    suspend fun page(query: String, cursor: EvidenceAccountCursor?): EvidenceAccountsPage
}

fun evidenceAccountsSource(context: Context): EvidenceAccountsSource {
    val callables = AppBackend.callables(context)
    return EvidenceAccountsSource { query, cursor ->
        EvidenceAccountsContract.decode(callables.getHttpsCallable("listLegalEvidenceAccounts")
            .withTimeout(20, TimeUnit.SECONDS)
            .call(EvidenceAccountsContract.request(query, cursor)).await().data)
    }
}

@Composable
fun LegalEvidenceAccountsScreen(session: ModerationSession?, language: String,
    source: EvidenceAccountsSource, onBack: () -> Unit, onAccount: (String) -> Unit) {
    if (session?.ready != true || session.role != "owner") {
        Text(tr(language, "Nur für Eigentümer", "Лише для власника"),
            Modifier.padding(UacDesign.pageInset).testTag("legal-evidence-accounts-denied"))
        return
    }
    var query by remember(session) { mutableStateOf("") }
    var accounts by remember(session) { mutableStateOf<List<EvidenceAccount>>(emptyList()) }
    var next by remember(session) { mutableStateOf<EvidenceAccountCursor?>(null) }
    var total by remember(session) { mutableStateOf<Int?>(null) }
    var loading by remember(session) { mutableStateOf(true) }
    var error by remember(session) { mutableStateOf(false) }
    var revision by remember(session) { mutableStateOf(0) }
    val scope = rememberCoroutineScope()
    suspend fun load(more: Boolean = false) {
        if (query.trim().length == 1 || loading && more) return
        loading = true
        error = false
        try {
            val page = source.page(query.trim(), if (more) next else null)
            accounts = if (more) (accounts + page.accounts).distinctBy { it.userId }
                else page.accounts
            next = page.cursor
            total = page.totalMatches
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { error = true; if (!more) { accounts = emptyList(); next = null } }
        finally { loading = false }
    }
    LaunchedEffect(session, query, revision, source) {
        if (query.trim().length == 1) { accounts = emptyList(); next = null; loading = false; return@LaunchedEffect }
        if (query.isNotBlank()) delay(350)
        load()
    }
    BackHandler(enabled = LocalEmbeddedNavigation.current, onBack = onBack)
    LazyColumn(Modifier.fillMaxSize().testTag("legal-evidence-accounts"),
        contentPadding = PaddingValues(start = UacDesign.pageInset, end = UacDesign.pageInset,
            bottom = 36.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item("header") {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                UacSectionHeading(tr(language, "Rechtliche Nachweise", "Юридичні підтвердження"),
                    UacIcon.NEWS)
                TextButton(onBack) { Text(tr(language, "Zurück", "Назад")) }
                Text(tr(language, "Unveränderliche Bestätigungen je Konto. Suche ab zwei Zeichen.",
                    "Незмінні підтвердження за обліковими записами. Пошук від двох символів."))
                OutlinedTextField(query, { query = it },
                    label = { Text(tr(language, "Name oder E-Mail", "Ім’я або пошта")) },
                    modifier = Modifier.fillMaxWidth().testTag("legal-evidence-account-search"))
                total?.let { Text(tr(language, "Treffer: $it", "Знайдено: $it")) }
                if (loading) CircularProgressIndicator(Modifier.testTag("legal-evidence-accounts-loading"))
                if (error) {
                    Text(tr(language, "Laden fehlgeschlagen", "Помилка завантаження"),
                        modifier = Modifier.testTag("legal-evidence-accounts-error"),
                        color = MaterialTheme.colorScheme.error)
                    TextButton({ revision++ }) { Text(tr(language, "Erneut laden", "Спробувати ще")) }
                }
                if (query.trim().length == 1) Text(tr(language, "Mindestens zwei Zeichen eingeben.",
                    "Введіть щонайменше два символи."))
            }
        }
        items(accounts, key = { it.userId }) { account ->
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(account.displayName?.takeIf(String::isNotBlank) ?: account.userId,
                    style = MaterialTheme.typography.titleSmall)
                account.email?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                OutlinedButton({ onAccount(account.userId) },
                    Modifier.testTag("legal-evidence-account-${account.userId}")) {
                    Text(tr(language, "Bestätigungen öffnen", "Відкрити підтвердження"))
                }
            }
        }
        if (!loading && accounts.isEmpty() && !error && query.trim().length != 1)
            item("empty") { Text(tr(language, "Keine Konten gefunden.", "Облікових записів не знайдено.")) }
        if (next != null && !loading) item("more") {
            OutlinedButton({ scope.launch { load(true) } }, Modifier.testTag("legal-evidence-load-more")) {
                Text(tr(language, "Mehr laden", "Завантажити ще"))
            }
        }
    }
}
