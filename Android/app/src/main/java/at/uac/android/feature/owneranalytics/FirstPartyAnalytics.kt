package at.uac.android.feature.owneranalytics

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.feature.analyticsconsent.AnalyticsConsentAuthority
import at.uac.android.feature.analyticsconsent.AnalyticsConsentReceipt
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.personal.PersonalAction
import at.uac.android.feature.personal.PersonalTarget
import com.google.firebase.auth.FirebaseAuth
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

fun firstPartyAnalytics(context: Context, current: () -> AnalyticsConsentAuthority?) =
    FirstPartyAnalytics(
        AppBackend.callables(context),
        AppBackend.auth(context),
        context.applicationContext.getSharedPreferences(
            "analytics-view-receipts-v1",
            Context.MODE_PRIVATE,
        ),
        current,
    )

/**
 * Consent/session-fenced delivery for the same aggregate callable used by iOS. Only the stable
 * content id is sent; display metadata is resolved canonically on the server.
 */
class FirstPartyAnalytics(
    private val callables: CallableGateway,
    private val auth: FirebaseAuth,
    private val receipts: android.content.SharedPreferences,
    private val current: () -> AnalyticsConsentAuthority?,
    private val day: () -> LocalDate = { LocalDate.now(ZoneId.of("Europe/Vienna")) },
    private val clock: () -> Long = System::currentTimeMillis,
) {
    suspend fun trackView(
        authority: AnalyticsConsentAuthority,
        receipt: AnalyticsConsentReceipt?,
        content: Content,
    ): Boolean {
        if (!eligible(authority, receipt)) return false
        val name =
            when (content.kind) {
                ContentKind.NEWS -> "news_view"
                ContentKind.EVENTS -> "event_view"
                ContentKind.ORGANIZATIONS -> "organization_view"
            }
        return deliver(authority, requireNotNull(receipt), name, content.id)
    }

    suspend fun trackConfirmedAction(
        authority: AnalyticsConsentAuthority,
        receipt: AnalyticsConsentReceipt?,
        target: PersonalTarget,
        action: PersonalAction,
    ): Boolean {
        if (!eligible(authority, receipt)) return false
        val name =
            when (action) {
                PersonalAction.LIKE ->
                    if (target.kind == ContentKind.NEWS) "news_like" else return false
                PersonalAction.BOOKMARK ->
                    when (target.kind) {
                        ContentKind.NEWS -> "news_bookmark"
                        ContentKind.EVENTS -> "event_bookmark"
                        ContentKind.ORGANIZATIONS -> "organization_bookmark"
                    }
                PersonalAction.SUBSCRIBE ->
                    if (target.kind == ContentKind.ORGANIZATIONS) "organization_follow"
                    else return false
            }
        return deliver(authority, requireNotNull(receipt), name, target.id)
    }

    suspend fun trackConfirmedEventRegistration(
        authority: AnalyticsConsentAuthority,
        receipt: AnalyticsConsentReceipt?,
        eventId: String,
    ): Boolean {
        if (!eligible(authority, receipt) || !Regex("[A-Za-z0-9._:-]{1,128}").matches(eventId))
            return false
        return deliver(authority, requireNotNull(receipt), "event_register", eventId)
    }

    private suspend fun deliver(
        authority: AnalyticsConsentAuthority,
        receipt: AnalyticsConsentReceipt,
        name: String,
        contentId: String,
    ): Boolean {
        val key = digest(listOf(authority.principalId, day().toString(), name, contentId))
        if (receipts.getBoolean(key, false)) return false
        val capturedConsent = receipt.consentId
        val response =
            try {
                withTimeout(70_000) {
                    callables
                        .getHttpsCallable("trackAnalyticsEvent")
                        .withTimeout(60, TimeUnit.SECONDS)
                        .call(
                            mapOf(
                                "name" to name,
                                "parameters" to mapOf("content_id" to contentId),
                                "consentID" to capturedConsent,
                                "occurredAtMilliseconds" to clock(),
                            )
                        )
                        .await()
                        .data
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // A transport failure is ambiguous. Server-side deterministic receipts make a later
                // foreground/navigation delivery safe, but this call is never looped automatically.
                return false
            }
        if (!eligible(authority, receipt) || current() != authority) return false
        val map = response as? Map<*, *> ?: return false
        if (map.keys != setOf("tracked") || map["tracked"] !is Boolean) return false
        receipts.edit().putBoolean(key, true).apply()
        prune()
        return map["tracked"] as Boolean
    }

    private fun eligible(
        authority: AnalyticsConsentAuthority,
        receipt: AnalyticsConsentReceipt?,
    ): Boolean =
        authority.ready &&
            receipt?.enabled == true &&
            receipt.privacyVersion == "2026.12" &&
            receipt.disclosureVersion == "2026-08-25.1" &&
            current() == authority &&
            auth.currentUser?.uid == authority.principalId &&
            auth.currentUser?.isAnonymous == false &&
            auth.currentUser?.isEmailVerified == true

    private fun prune() {
        if (receipts.all.size <= 400) return
        // Keys contain only hashes. Clearing merely permits an idempotent server re-check.
        receipts.edit().clear().apply()
    }

    private fun digest(parts: List<String>): String =
        MessageDigest.getInstance("SHA-256")
            .digest(parts.joinToString("\u0000").toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 255) }
}
