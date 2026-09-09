package at.uac.android.feature.analyticsconsent

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.browse.tr
import java.security.MessageDigest
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

data class AnalyticsConsentAuthority(val principalId: String, val revision: Long, val ready: Boolean)

fun AuthSession.analyticsConsentAuthority(): AnalyticsConsentAuthority? =
    identity?.takeUnless { it.anonymous }?.takeIf { profile?.uid == it.uid }?.let {
        AnalyticsConsentAuthority(it.uid, revision, readyForActions)
    }

data class AnalyticsConsentReceipt(
    val enabled: Boolean,
    val consentId: String,
    val privacyVersion: String,
    val disclosureVersion: String,
)

interface AnalyticsConsentReceiptStore {
    fun read(principalId: String): AnalyticsConsentReceipt?

    fun write(principalId: String, receipt: AnalyticsConsentReceipt)
}

class SharedPreferencesAnalyticsConsentStore(context: Context) : AnalyticsConsentReceiptStore {
    private val preferences =
        context.applicationContext.getSharedPreferences("analytics-consent-v2", Context.MODE_PRIVATE)

    private fun key(principalId: String) =
        MessageDigest.getInstance("SHA-256")
            .digest(principalId.toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 255) }

    override fun read(principalId: String): AnalyticsConsentReceipt? {
        val prefix = key(principalId)
        val id = preferences.getString("$prefix.id", null) ?: return null
        val privacy = preferences.getString("$prefix.privacy", null) ?: return null
        val disclosure = preferences.getString("$prefix.disclosure", null) ?: return null
        if (
            runCatching { UUID.fromString(id).toString() }.getOrNull() != id.lowercase() ||
                privacy != AnalyticsConsentV2Contract.PRIVACY_VERSION ||
                disclosure != AnalyticsConsentV2Contract.DISCLOSURE_VERSION
        )
            return null
        return AnalyticsConsentReceipt(
            preferences.getBoolean("$prefix.enabled", false),
            id,
            privacy,
            disclosure,
        )
    }

    override fun write(principalId: String, receipt: AnalyticsConsentReceipt) {
        val prefix = key(principalId)
        preferences.edit()
            .putBoolean("$prefix.enabled", receipt.enabled)
            .putString("$prefix.id", receipt.consentId)
            .putString("$prefix.privacy", receipt.privacyVersion)
            .putString("$prefix.disclosure", receipt.disclosureVersion)
            .apply()
    }
}

class AnalyticsConsentSettingsController(
    private val synchronizer: AnalyticsConsentSynchronizer,
    private val receipts: AnalyticsConsentReceiptStore,
    private val current: () -> AnalyticsConsentAuthority?,
) {
    fun read(authority: AnalyticsConsentAuthority): AnalyticsConsentReceipt? =
        receipts.read(authority.principalId).takeIf { authority.ready }

    suspend fun change(
        authority: AnalyticsConsentAuthority,
        enabled: Boolean,
        locale: String,
        appVersion: String,
    ): AnalyticsConsentReceipt {
        require(authority.ready && current() == authority)
        val previous = receipts.read(authority.principalId)
        if (!enabled && previous?.enabled != true)
            return previous
                ?: AnalyticsConsentReceipt(
                    false,
                    UUID.randomUUID().toString(),
                    AnalyticsConsentV2Contract.PRIVACY_VERSION,
                    AnalyticsConsentV2Contract.DISCLOSURE_VERSION,
                )
        val receipt =
            AnalyticsConsentReceipt(
                enabled,
                if (enabled) UUID.randomUUID().toString() else requireNotNull(previous).consentId,
                AnalyticsConsentV2Contract.PRIVACY_VERSION,
                AnalyticsConsentV2Contract.DISCLOSURE_VERSION,
            )
        val confirmed =
            synchronizer.synchronize(
                AnalyticsConsentV2(
                    authority.principalId,
                    enabled,
                    receipt.consentId,
                    locale,
                    appVersion,
                    receipt.privacyVersion,
                    receipt.disclosureVersion,
                )
            )
        if (confirmed != enabled || current() != authority) throw CancellationException()
        receipts.write(authority.principalId, receipt)
        return receipt
    }
}

@Composable
fun AnalyticsConsentSettings(
    authority: AnalyticsConsentAuthority?,
    language: String,
    appVersion: String,
    controller: AnalyticsConsentSettingsController,
) {
    var receipt by remember(authority) { mutableStateOf<AnalyticsConsentReceipt?>(null) }
    var loaded by remember(authority) { mutableStateOf(false) }
    var busy by remember(authority) { mutableStateOf(false) }
    var failed by remember(authority) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(authority) {
        receipt = authority?.let(controller::read)
        loaded = true
        failed = false
    }
    Column(
        Modifier.fillMaxWidth().testTag("analytics-consent-settings"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            tr(language, "Optionale Nutzungsanalyse", "Необов’язкова аналітика використання"),
            style = MaterialTheme.typography.titleMedium,
        )
        Text(
            tr(
                language,
                "Mit Ihrer freiwilligen Einwilligung darf UAC Nutzungs- und technische Diagnosedaten für die Verbesserung der App verarbeiten. Die Funktion bleibt ohne Einwilligung aus. Sie können die Einwilligung jederzeit hier widerrufen.",
                "За вашою добровільною згодою UAC може обробляти дані про використання та технічну діагностику для покращення застосунку. Без згоди функція вимкнена. Тут згоду можна відкликати будь-коли.",
            ),
            style = MaterialTheme.typography.bodySmall,
        )
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                if (receipt?.enabled == true)
                    tr(language, "Einwilligung erteilt", "Згоду надано")
                else tr(language, "Nicht eingewilligt", "Згоди не надано")
            )
            if (!loaded || busy) CircularProgressIndicator()
            else
                Switch(
                    checked = receipt?.enabled == true,
                    enabled = authority?.ready == true,
                    modifier = Modifier.testTag("analytics-consent-switch"),
                    onCheckedChange = { enabled ->
                        val captured = authority ?: return@Switch
                        busy = true
                        failed = false
                        scope.launch {
                            try {
                                receipt =
                                    controller.change(captured, enabled, language, appVersion)
                            } catch (error: CancellationException) {
                                throw error
                            } catch (_: Exception) {
                                failed = true
                            } finally {
                                busy = false
                            }
                        }
                    },
                )
        }
        if (authority?.ready != true)
            Text(
                tr(
                    language,
                    "Bestätigen Sie zuerst Konto, Rechtstexte und erforderliche Anmeldungssicherheit.",
                    "Спочатку підтвердьте акаунт, юридичні документи й потрібний захист входу.",
                )
            )
        if (failed) {
            Text(
                tr(
                    language,
                    "Die Änderung wurde nicht bestätigt und daher nicht übernommen.",
                    "Зміну не підтверджено, тому її не застосовано.",
                ),
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.testTag("analytics-consent-error"),
            )
            TextButton(
                onClick = {
                    receipt = authority?.let(controller::read)
                    failed = false
                }
            ) {
                Text(tr(language, "Status erneut laden", "Оновити стан"))
            }
        }
        Text(
            "${AnalyticsConsentV2Contract.PRIVACY_VERSION} · ${AnalyticsConsentV2Contract.DISCLOSURE_VERSION}",
            style = MaterialTheme.typography.labelSmall,
        )
    }
}
