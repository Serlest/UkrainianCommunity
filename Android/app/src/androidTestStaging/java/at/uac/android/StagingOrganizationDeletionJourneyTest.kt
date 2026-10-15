package at.uac.android

import android.content.Context
import android.view.inputmethod.InputMethodManager
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.organization.OrganizationManagementViewModel
import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** A disposable approved organization and two disposable staging identities. */
@RunWith(AndroidJUnit4::class)
class StagingOrganizationDeletionJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val args get() = InstrumentationRegistry.getArguments()
    private val suffix get() = args.getString("deletionSuffix").orEmpty()
    private val id get() = "step5-owner-delete-$suffix"

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
        assertTrue(suffix.matches(Regex("[a-f0-9]{16}")))
        val email = args.getString("${role}Email").orEmpty()
        val password = args.getString("${role}Password").orEmpty()
        assertEquals("org-delete-step5-$role-$suffix@example.invalid", email)
        assertTrue(password.length >= 20)
        val auth = LocalAuthSession.get(compose.activity)
        compose.runOnIdle { auth.signOut() }
        compose.waitUntil(60_000) { compose.onAllNodesWithTag("auth-login-submit").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("auth-email").performScrollTo().performTextInput(email)
        compose.onNodeWithTag("auth-password").performScrollTo().performTextInput(password)
        compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
        if (role == "owner") {
            compose.waitUntil(60_000) { auth.state.value.stage == AuthStage.MFA_CHALLENGE }
            val secret = args.getString("ownerSecret").orEmpty()
            val period = args.getString("ownerPeriod").orEmpty().toInt()
            val digits = args.getString("ownerDigits").orEmpty().toInt()
            val used = args.getString("ownerUsedCounter").orEmpty().toLong()
            assertTrue(secret.matches(Regex("[A-Z2-7]+=*")) && period in 15..120 && digits in 6..8)
            compose.waitUntil(60_000) { System.currentTimeMillis() / 1_000 / period > used }
            compose.onNodeWithTag("auth-mfa-code").performTextInput(totp(secret, period, digits))
            compose.onNodeWithTag("auth-mfa-submit").performClick()
        }
        compose.waitUntil(60_000) { auth.state.value.let {
            it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY || !it.busy && it.error != null
        } }
        assertEquals(AuthGate.READY, auth.state.value.gate)
        compose.runOnIdle {
            compose.activity.currentFocus?.clearFocus()
            (compose.activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                .hideSoftInputFromWindow(compose.activity.window.decorView.windowToken, 0)
        }
    }

    @Test fun organizationOwnerCannotDeleteApprovedOrganization() {
        login("member")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val management = ViewModelProvider(compose.activity)[OrganizationManagementViewModel::class.java]
        compose.runOnIdle {
            browse.navigate("profile/organizations")
            browse.navigate("profile/organizations/manage/$id")
        }
        compose.waitUntil(60_000) { management.state.value.actionable }
        assertFalse(compose.onAllNodesWithTag("organization-management-delete").fetchSemanticsNodes().isNotEmpty())
        compose.runOnIdle { management.requestDelete() }
        assertFalse(management.state.value.deleteConfirmation)
    }

    @Test fun platformOwnerDeletesApprovedOrganizationWithConfirmation() {
        login("owner")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val management = ViewModelProvider(compose.activity)[OrganizationManagementViewModel::class.java]
        compose.runOnIdle {
            browse.navigate("profile/organizations")
            browse.navigate("profile/organizations/manage/$id")
        }
        compose.waitUntil(90_000) { management.state.value.actionable || management.state.value.error != null }
        assertNull(management.state.value.error)
        compose.onNodeWithTag("organization-management").performScrollToNode(hasTestTag("organization-management-delete"))
        compose.onNodeWithTag("organization-management-delete").performClick()
        compose.onNodeWithTag("organization-management-confirm-delete").performClick()
        compose.waitUntil(180_000) { management.state.value.deleted || management.state.value.error != null }
        assertNull(management.state.value.error)
        assertTrue(management.state.value.deleted)
        compose.waitUntil(30_000) { browse.state.value.route == "profile/organizations" }
    }
}
