package at.uac.android

import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.UacTheme
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.legalmanagement.FirebaseLegalManagementSource
import at.uac.android.feature.legalmanagement.LegalManagementScreen
import at.uac.android.feature.legalevidence.LegalEvidenceAccountsScreen
import at.uac.android.feature.legalevidence.evidenceAccountsSource
import at.uac.android.feature.moderation.moderationScope
import at.uac.android.core.backend.AppBackend
import com.google.firebase.firestore.Source
import kotlinx.coroutines.tasks.await
import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class StagingLegalManagementJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val args get() = InstrumentationRegistry.getArguments()
    private fun visible(tag: String) = runCatching {
        compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }.getOrDefault(false)

    private fun totp(secret: String, period: Int, digits: Int): String {
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = 0
        var count = 0
        val bytes = ArrayList<Byte>()
        secret.trimEnd('=').forEach { char ->
            val digit = alphabet.indexOf(char)
            require(digit >= 0)
            bits = (bits shl 5) or digit
            count += 5
            if (count >= 8) { count -= 8; bytes += ((bits shr count) and 255).toByte() }
        }
        val counter = System.currentTimeMillis() / 1_000 / period
        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec(bytes.toByteArray(), "HmacSHA1"))
        val hash = mac.doFinal(ByteBuffer.allocate(8).putLong(counter).array())
        val offset = hash.last().toInt() and 15
        val number = ((hash[offset].toInt() and 127) shl 24) or
            ((hash[offset + 1].toInt() and 255) shl 16) or
            ((hash[offset + 2].toInt() and 255) shl 8) or
            (hash[offset + 3].toInt() and 255)
        var divisor = 1
        repeat(digits) { divisor *= 10 }
        return (number % divisor).toString().padStart(digits, '0')
    }

    private fun login(role: String, expectedGate: AuthGate = AuthGate.READY) {
        assertEquals("at.serlest.ukrainiancommunity.staging", compose.activity.packageName)
        val email = args.getString("legal${role}Email").orEmpty()
        val password = args.getString("legal${role}Password").orEmpty()
        assertTrue(email.matches(Regex("legal-step3-[a-f0-9]{16}-(owner|reader)@example\\.invalid")))
        assertTrue(password.length >= 20)
        val auth = LocalAuthSession.get(compose.activity)
        compose.runOnIdle { auth.signOut() }
        compose.waitUntil(60_000) { visible("auth-login-submit") }
        compose.onNodeWithTag("auth-email").performScrollTo().performTextInput(email)
        compose.onNodeWithTag("auth-password").performScrollTo().performTextInput(password)
        compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
        if (role == "Owner") {
            compose.waitUntil(60_000) { auth.state.value.stage == AuthStage.MFA_CHALLENGE &&
                visible("auth-mfa-code") }
            val secret = args.getString("legalOwnerSecret").orEmpty()
            val period = args.getString("legalOwnerPeriod").orEmpty().toInt()
            val digits = args.getString("legalOwnerDigits").orEmpty().toInt()
            val used = args.getString("legalOwnerUsedCounter").orEmpty().toLong()
            assertTrue(secret.matches(Regex("[A-Z2-7]+=*")) && period in 15..120 && digits in 6..8)
            compose.waitUntil(60_000) { System.currentTimeMillis() / 1_000 / period > used }
            compose.onNodeWithTag("auth-mfa-code").performTextInput(totp(secret, period, digits))
            compose.onNodeWithTag("auth-mfa-submit").performClick()
        }
        compose.waitUntil(60_000) { auth.state.value.let {
            it.stage == AuthStage.AUTHENTICATED && it.gate == expectedGate || !it.busy && it.error != null
        } }
        assertEquals(expectedGate, auth.state.value.gate)
    }

    @Test fun readerCannotOpenOwnerLegalManagement() {
        login("Reader")
        val session = LocalAuthSession.get(compose.activity).state.value.moderationScope()
        val source = FirebaseLegalManagementSource(compose.activity, LocalAuthSession.get(compose.activity))
        compose.runOnIdle { compose.activity.setContent {
            UacTheme("light") { LegalManagementScreen(session, "de", source, {}) }
        } }
        compose.onNodeWithTag("legal-management-denied").assertExists()
    }

    @Test fun ownerSavesLegalDraft() {
        login("Owner")
        val auth = LocalAuthSession.get(compose.activity)
        val session = auth.state.value.moderationScope()!!
        assertTrue(session.ready && session.role == "owner")
        val source = FirebaseLegalManagementSource(compose.activity, auth)
        compose.runOnIdle { compose.activity.setContent {
            UacTheme("light") { LegalManagementScreen(session, "de", source, {}) }
        } }
        val type = args.getString("legalType").orEmpty()
        assertTrue(type in setOf("terms", "privacy"))
        compose.waitUntil(60_000) { visible("legal-management-open-$type") || visible("legal-management-error") }
        if (!visible("legal-management-open-$type"))
            throw AssertionError("Legal management load failed")
        compose.onNodeWithTag("legal-management-screen").performScrollToNode(hasTestTag("legal-management-open-$type"))
        compose.onNodeWithTag("legal-management-open-$type").performClick()
        compose.onNodeWithTag("legal-management-screen").performScrollToNode(hasTestTag("legal-management-summary-de"))
        compose.onNodeWithTag("legal-management-summary-de").performTextInput("Staging Schritt 3: unveränderter Inhalt")
        compose.onNodeWithTag("legal-management-screen").performScrollToNode(hasTestTag("legal-management-summary-uk"))
        compose.onNodeWithTag("legal-management-summary-uk").performTextInput("Staging крок 3: незмінний текст")
        compose.onNodeWithTag("legal-management-screen").performScrollToNode(hasTestTag("legal-management-save"))
        compose.onNodeWithTag("legal-management-save").assertIsEnabled().performClick()
        compose.waitUntil(60_000) {
            runCatching { compose.onNodeWithTag("legal-management-publish").assertIsEnabled() }.isSuccess ||
                visible("legal-management-error")
        }
        if (visible("legal-management-error")) throw AssertionError("Legal draft save failed")
        compose.onNodeWithTag("legal-management-publish").assertIsEnabled()
    }

    @Test fun ownerRejectsStaleDraftAndPublishes() {
        login("Owner")
        val auth = LocalAuthSession.get(compose.activity)
        val session = auth.state.value.moderationScope()!!
        val type = args.getString("legalType").orEmpty()
        val source = FirebaseLegalManagementSource(compose.activity, auth)
        val managed = kotlinx.coroutines.runBlocking { source.load(session).first { it.active.type == type } }
        val draft = managed.draft ?: throw AssertionError("Draft missing")
        val input = at.uac.android.feature.legalmanagement.LegalDraftInput(type, draft.version,
            draft.versionNumber, managed.active.version, "0".repeat(64), draft.locales,
            "Staging Schritt 3: unveränderter Inhalt", "Staging крок 3: незмінний текст")
        val stale = runCatching { kotlinx.coroutines.runBlocking { source.save(session, input) } }.exceptionOrNull()
        assertTrue("stale hash must be rejected", stale != null)
        compose.runOnIdle { compose.activity.setContent {
            UacTheme("light") { LegalManagementScreen(session, "de", source, {}) }
        } }
        compose.waitUntil(60_000) { visible("legal-management-open-$type") || visible("legal-management-error") }
        if (!visible("legal-management-open-$type")) throw AssertionError("Legal management load failed")
        compose.onNodeWithTag("legal-management-screen").performScrollToNode(hasTestTag("legal-management-open-$type"))
        compose.onNodeWithTag("legal-management-open-$type").performClick()
        compose.onNodeWithTag("legal-management-screen").performScrollToNode(hasTestTag("legal-management-publish"))
        compose.onNodeWithTag("legal-management-publish").assertIsEnabled().performClick()
        compose.onNodeWithTag("legal-management-confirm-publish").performClick()
        val db = AppBackend.firestore(compose.activity)
        compose.waitUntil(60_000) {
            runCatching { kotlinx.coroutines.runBlocking {
                db.collection("legalDocuments").document(type).get(Source.SERVER).await()
                    .getString("activeVersion") == draft.version
            } }.getOrDefault(false)
        }
        assertTrue("Publication not visible on server", kotlinx.coroutines.runBlocking {
            db.collection("legalDocuments").document(type).get(Source.SERVER).await()
                .getString("activeVersion") == draft.version
        })
    }

    @Test fun ownerOpensCommonEvidenceList() {
        login("Owner")
        val session = LocalAuthSession.get(compose.activity).state.value.moderationScope()!!
        val source = evidenceAccountsSource(compose.activity)
        val target = args.getString("legalReaderUid").orEmpty()
        assertTrue(target.isNotBlank())
        var opened: String? = null
        compose.runOnIdle { compose.activity.setContent {
            UacTheme("light") { LegalEvidenceAccountsScreen(session, "de", source, {}, { opened = it }) }
        } }
        compose.waitUntil(60_000) { visible("legal-evidence-account-$target") ||
            visible("legal-evidence-accounts-error") }
        if (visible("legal-evidence-accounts-error")) throw AssertionError("Evidence account list failed")
        compose.onNodeWithTag("legal-evidence-accounts").performScrollToNode(hasTestTag("legal-evidence-account-$target"))
        compose.onNodeWithTag("legal-evidence-account-$target").performClick()
        assertEquals(target, opened)
    }

    @Test fun readerReacceptsNewLegalVersion() {
        login("Reader", AuthGate.LEGAL_REQUIRED)
        val auth = LocalAuthSession.get(compose.activity)
        val type = args.getString("legalType").orEmpty()
        compose.waitUntil(60_000) { visible("auth-legal-required") && visible("auth-accept-$type") }
        compose.onNodeWithTag("auth-accept-$type").performScrollTo().performClick()
        compose.onNodeWithTag("auth-legal-submit").performScrollTo().assertIsEnabled().performClick()
        compose.waitUntil(60_000) { auth.state.value.gate == AuthGate.READY ||
            !auth.state.value.busy && auth.state.value.error != null }
        assertEquals(AuthGate.READY, auth.state.value.gate)
    }
}
