package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.dsaowner.DsaOwnerDecisionViewModel
import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Disposable staging owner account with actual TOTP, then the real Android UI/callable. */
@RunWith(AndroidJUnit4::class)
class StagingDsaOwnerJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    private data class Fixture(
        val email: String, val password: String, val secret: String,
        val period: Int, val digits: Int, val usedCounter: Long, val reportId: String,
    )

    private fun fixture(): Fixture {
        val args = InstrumentationRegistry.getArguments()
        val result = Fixture(
            args.getString("dsaOwnerEmail").orEmpty(),
            args.getString("dsaOwnerPassword").orEmpty(),
            args.getString("dsaOwnerSecret").orEmpty(),
            args.getString("dsaOwnerPeriod").orEmpty().toInt(),
            args.getString("dsaOwnerDigits").orEmpty().toInt(),
            args.getString("dsaOwnerUsedCounter").orEmpty().toLong(),
            args.getString("dsaOwnerReportId").orEmpty(),
        )
        assertTrue(result.email.matches(Regex("dsa-owner-smoke-[a-f0-9]{16}-2@example\\.invalid")))
        assertTrue(result.password.length >= 20 && result.secret.matches(Regex("[A-Z2-7]+=*")))
        assertTrue(result.reportId.matches(Regex("dsa-owner-smoke-[a-f0-9]{16}")))
        assertTrue(result.period in 15..120 && result.digits in 6..8)
        return result
    }

    private fun code(fixture: Fixture): String {
        val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var bits = 0
        var count = 0
        val bytes = ArrayList<Byte>()
        fixture.secret.trimEnd('=').forEach { char ->
            val digit = alphabet.indexOf(char)
            require(digit >= 0)
            bits = (bits shl 5) or digit
            count += 5
            if (count >= 8) {
                count -= 8
                bytes += ((bits shr count) and 255).toByte()
            }
        }
        val counter = System.currentTimeMillis() / 1_000 / fixture.period
        val mac = Mac.getInstance("HmacSHA1")
        mac.init(SecretKeySpec(bytes.toByteArray(), "HmacSHA1"))
        val hash = mac.doFinal(ByteBuffer.allocate(8).putLong(counter).array())
        val offset = hash.last().toInt() and 15
        val binary = ((hash[offset].toInt() and 127) shl 24) or
            ((hash[offset + 1].toInt() and 255) shl 16) or
            ((hash[offset + 2].toInt() and 255) shl 8) or
            (hash[offset + 3].toInt() and 255)
        var divisor = 1
        repeat(fixture.digits) { divisor *= 10 }
        return (binary % divisor).toString().padStart(fixture.digits, '0')
    }

    private fun login(fixture: Fixture): AuthStore {
        assertEquals("at.serlest.ukrainiancommunity.staging", compose.activity.packageName)
        val auth = LocalAuthSession.get(compose.activity)
        compose.runOnIdle { auth.signOut() }
        compose.waitUntil(60_000) {
            compose.onAllNodesWithTag("auth-login-submit").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("auth-email").performScrollTo().performTextInput(fixture.email)
        compose.onNodeWithTag("auth-password").performScrollTo().performTextInput(fixture.password)
        compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
        compose.waitUntil(60_000) {
            auth.state.value.stage == AuthStage.MFA_CHALLENGE &&
                compose.onAllNodesWithTag("auth-mfa-code").fetchSemanticsNodes().isNotEmpty()
        }
        compose.waitUntil(60_000) {
            System.currentTimeMillis() / 1_000 / fixture.period > fixture.usedCounter
        }
        compose.onNodeWithTag("auth-mfa-code").performTextInput(code(fixture))
        compose.onNodeWithTag("auth-mfa-submit").performClick()
        try {
            compose.waitUntil(15_000) {
                auth.state.value.let {
                    it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY ||
                        !it.busy && it.error != null
                }
            }
        } catch (_: androidx.compose.ui.test.ComposeTimeoutException) {
            val state = auth.state.value
            throw AssertionError("Owner MFA did not finish: ${state.stage}/${state.gate}/${state.error}")
        }
        val state = auth.state.value
        assertTrue("Owner MFA ended at ${state.stage}/${state.gate}/${state.error}",
            state.stage == AuthStage.AUTHENTICATED && state.gate == AuthGate.READY)
        return auth
    }

    private fun openOwner(fixture: Fixture) {
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val owner = ViewModelProvider(compose.activity)[DsaOwnerDecisionViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/dsa-owner/${fixture.reportId}") }
        compose.waitUntil(60_000) {
            owner.state.value.let { it.review != null || it.error != null } &&
                compose.onAllNodesWithTag("dsa-owner-list").fetchSemanticsNodes().isNotEmpty()
        }
        val state = owner.state.value
        assertTrue("Owner case review failed: ${state.error}", state.review != null)
        assertEquals("profile/dsa-owner/${fixture.reportId}", browse.state.value.route)
    }

    private fun fill(tag: String, value: String) {
        try {
            compose.waitUntil(60_000) {
                compose.onAllNodesWithTag("dsa-owner-list").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag("dsa-owner-list").performScrollToNode(hasTestTag(tag))
            compose.onNodeWithTag(tag).performTextInput(value)
        } catch (error: Throwable) {
            val route = ViewModelProvider(compose.activity)[BrowseViewModel::class.java].state.value.route
            val auth = LocalAuthSession.get(compose.activity).state.value
            val owner = ViewModelProvider(compose.activity)[DsaOwnerDecisionViewModel::class.java].state.value
            throw AssertionError("Owner field $tag unavailable: route=$route, " +
                "auth=${auth.stage}/${auth.gate}/${auth.error}, " +
                "owner=${owner.visible}/${owner.loading}/${owner.error}, " +
                "activity=${compose.activity.lifecycle.currentState}", error)
        }
    }

    private fun submitAndConfirm() {
        compose.onNodeWithTag("dsa-owner-list").performScrollToNode(hasTestTag("dsa-owner-human"))
        compose.onNodeWithTag("dsa-owner-human").performClick()
        compose.onNodeWithTag("dsa-owner-list").performScrollToNode(hasTestTag("dsa-owner-submit"))
        compose.onNodeWithTag("dsa-owner-submit").assertIsEnabled().performClick()
        compose.onNodeWithTag("dsa-owner-confirm").performClick()
        compose.waitUntil(60_000) {
            compose.onAllNodesWithTag("dsa-owner-receipt").fetchSemanticsNodes().isNotEmpty() ||
                compose.onAllNodesWithTag("dsa-owner-error").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("dsa-owner-receipt").assertExists()
    }

    @Test fun ownerDecidesCase() {
        val fixture = fixture()
        val outcome = InstrumentationRegistry.getArguments()
            .getString("dsaOwnerCaseOutcome").orEmpty()
        assertTrue(outcome in setOf("noAction", "restricted", "removed"))
        val auth = login(fixture)
        openOwner(fixture)
        if (outcome != "noAction") {
            compose.onNodeWithTag("dsa-owner-list")
                .performScrollToNode(hasTestTag("dsa-owner-outcome-$outcome"))
            compose.onNodeWithTag("dsa-owner-outcome-$outcome").performClick()
        }
        fill("dsa-owner-facts", "Synthetic staging facts verified by the owner")
        fill("dsa-owner-legal", "Synthetic test basis")
        fill("dsa-owner-duration", "Until review")
        fill("dsa-owner-redress", "Internal appeal available")
        submitAndConfirm()
        compose.runOnIdle { auth.signOut() }
    }

    @Test fun ownerDecidesAppeal() {
        val fixture = fixture()
        val outcome = InstrumentationRegistry.getArguments()
            .getString("dsaOwnerAppealOutcome").orEmpty()
        assertTrue(outcome == "upheld" || outcome == "changed")
        val auth = login(fixture)
        openOwner(fixture)
        compose.onNodeWithTag("dsa-owner-list")
            .performScrollToNode(hasTestTag("dsa-owner-outcome-$outcome"))
        compose.onNodeWithTag("dsa-owner-outcome-$outcome").performClick()
        fill("dsa-owner-reason", "Synthetic appeal decision after separate human review.")
        submitAndConfirm()
        compose.runOnIdle { auth.signOut() }
    }
}
