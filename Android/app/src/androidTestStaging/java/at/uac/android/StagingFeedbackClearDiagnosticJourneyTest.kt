package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.semantics.SemanticsActions
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.backend.AppBackend
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.feedback.feedbackScope
import at.uac.android.feature.feedback.FeedbackViewModel
import at.uac.android.feature.feedback.FeedbackInboxClearViewModel
import at.uac.android.feature.moderation.moderationScope
import at.uac.android.feature.systemlogs.ClientDiagnosticOperation
import at.uac.android.feature.systemlogs.FirebaseClientDiagnosticWriter
import at.uac.android.feature.feedback.FeedbackFailure
import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import com.google.firebase.firestore.Source
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class StagingFeedbackClearDiagnosticJourneyTest {
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

    private fun login(role: String) {
        assertEquals("at.serlest.ukrainiancommunity.staging", compose.activity.packageName)
        val email = args.getString("feedback${role}Email").orEmpty()
        val password = args.getString("feedback${role}Password").orEmpty()
        assertTrue(email.matches(Regex("feedback-step4-[a-f0-9]{16}-(owner|reader)@example\\.invalid")))
        assertTrue(password.length >= 20)
        val auth = LocalAuthSession.get(compose.activity)
        compose.runOnIdle { auth.signOut() }
        compose.waitUntil(60_000) { visible("auth-login-submit") }
        compose.onNodeWithTag("auth-email").performScrollTo().performTextInput(email)
        compose.onNodeWithTag("auth-password").performScrollTo().performTextInput(password)
        compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
        if (role == "Owner") {
            compose.waitUntil(60_000) { auth.state.value.stage == AuthStage.MFA_CHALLENGE && visible("auth-mfa-code") }
            val secret = args.getString("feedbackOwnerSecret").orEmpty()
            val period = args.getString("feedbackOwnerPeriod").orEmpty().toInt()
            val digits = args.getString("feedbackOwnerDigits").orEmpty().toInt()
            val used = args.getString("feedbackOwnerUsedCounter").orEmpty().toLong()
            assertTrue(secret.matches(Regex("[A-Z2-7]+=*")) && period in 15..120 && digits in 6..8)
            compose.waitUntil(60_000) { System.currentTimeMillis() / 1_000 / period > used }
            compose.onNodeWithTag("auth-mfa-code").performTextInput(totp(secret, period, digits))
            compose.onNodeWithTag("auth-mfa-submit").performClick()
        }
        compose.waitUntil(60_000) { auth.state.value.let {
            it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY || !it.busy && it.error != null
        } }
        assertEquals(AuthGate.READY, auth.state.value.gate)
    }

    @Test fun readerCannotClearAndWritesMinimalDiagnostic() {
        login("Reader")
        // Either route guard or screen guard must keep the owner action unavailable.
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/support") }
        compose.waitForIdle()
        compose.onNodeWithTag("feedback-clear-inbox").assertDoesNotExist()
        val session = LocalAuthSession.get(compose.activity).state.value.feedbackScope()!!
        runBlocking {
            FirebaseClientDiagnosticWriter(
                AppBackend.auth(compose.activity), AppBackend.callables(compose.activity),
            ).write(session, ClientDiagnosticOperation.FEEDBACK_READ, FeedbackFailure.UNKNOWN)
        }
    }

    @Test fun ownerClearsOrdinaryFeedbackViaRealScreen() {
        login("Owner")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/support") }
        try {
            compose.waitUntil(30_000) { visible("feedback-clear-inbox") }
        } catch (cause: Throwable) {
            val auth = LocalAuthSession.get(compose.activity).state.value
            val feedback = ViewModelProvider(compose.activity)[FeedbackViewModel::class.java].state.value
            val sdkCount = runCatching { runBlocking {
                AppBackend.firestore(compose.activity).collection("feedback")
                    .get(Source.SERVER).await().size()
            } }.getOrElse { -1 }
            throw AssertionError(
                "Owner clear UI unavailable: route=${browse.state.value.route}; " +
                    "moderationReady=${auth.moderationScope()?.ready}; " +
                    "feedbackManager=${auth.feedbackScope()?.canManage}; " +
                    "list=${visible("feedback-list")}; audience=${feedback.audience}; selected=${feedback.selectedId != null}; " +
                    "page=${feedback.page?.items?.size}; invalid=${feedback.page?.invalid}; sdkCount=$sdkCount; " +
                    "loading=${feedback.loading}; error=${feedback.error}", cause,
            )
        }
        compose.onNodeWithTag("feedback-list").performScrollToNode(hasTestTag("feedback-clear-inbox"))
        compose.onNodeWithTag("feedback-clear-inbox", useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.OnClick)
        compose.waitUntil(10_000) { visible("feedback-clear-confirm") }
        compose.onNodeWithTag("feedback-clear-cancel").assertExists()
        compose.onNodeWithTag("feedback-clear-confirm").performClick()
        compose.waitUntil(90_000) { visible("feedback-clear-receipt") || visible("feedback-clear-pending") || visible("feedback-clear-error") }
        val clear = ViewModelProvider(compose.activity)[FeedbackInboxClearViewModel::class.java].state.value
        assertTrue("Unexpected clear state: $clear", clear.deletedCount == 2)
        val receipt = compose.onNodeWithTag("feedback-clear-receipt").printToString()
        assertTrue("Unexpected server receipt: $receipt", receipt.contains("2 Anfragen"))
        compose.onNodeWithTag("feedback-clear-pending").assertDoesNotExist()
    }
}
