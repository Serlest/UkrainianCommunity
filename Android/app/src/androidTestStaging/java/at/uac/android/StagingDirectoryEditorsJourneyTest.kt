package at.uac.android

import androidx.activity.compose.setContent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.semantics.SemanticsActions
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.design.UacTheme
import at.uac.android.feature.directory.DirectoryEditorsScreen
import at.uac.android.feature.directory.FirebaseDirectoryEditorsSource
import at.uac.android.feature.moderation.moderationScope
import java.nio.ByteBuffer
import kotlinx.coroutines.runBlocking
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class StagingDirectoryEditorsJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val args get() = InstrumentationRegistry.getArguments()
    private val uid get() = args.getString("directoryEditorUid").orEmpty()
    private val category get() = args.getString("directoryCategoryId").orEmpty()
    private fun visible(tag: String): Boolean = runCatching {
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
        assertTrue(uid.isNotBlank() && category.startsWith("custom-"))
        val email = args.getString("directory${role}Email").orEmpty()
        val password = args.getString("directory${role}Password").orEmpty()
        assertTrue(email.matches(Regex("directory-step2-[a-f0-9]{16}-(owner|editor|reader)@example\\.invalid")))
        assertTrue(password.length >= 20)
        val auth = LocalAuthSession.get(compose.activity)
        compose.runOnIdle { auth.signOut() }
        compose.waitUntil(60_000) { compose.onAllNodesWithTag("auth-login-submit").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("auth-email").performScrollTo().performTextInput(email)
        compose.onNodeWithTag("auth-password").performScrollTo().performTextInput(password)
        compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
        if (role == "Owner") {
            compose.waitUntil(60_000) { auth.state.value.stage == AuthStage.MFA_CHALLENGE &&
                compose.onAllNodesWithTag("auth-mfa-code").fetchSemanticsNodes().isNotEmpty() }
            val secret = args.getString("directoryOwnerSecret").orEmpty()
            val period = args.getString("directoryOwnerPeriod").orEmpty().toInt()
            val digits = args.getString("directoryOwnerDigits").orEmpty().toInt()
            val used = args.getString("directoryOwnerUsedCounter").orEmpty().toLong()
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

    @Test fun ownerGrantsEditor() {
        login("Owner")
        val auth = LocalAuthSession.get(compose.activity)
        val session = auth.state.value.moderationScope()!!
        val source = FirebaseDirectoryEditorsSource(compose.activity, auth)
        compose.runOnIdle { compose.activity.setContent {
            UacTheme("light") { DirectoryEditorsScreen(session, "de", source, {}) }
        } }
        compose.waitUntil(60_000) { visible("directory-editors-search") }
        compose.onNodeWithTag("directory-editors-search").performTextInput("directory-step2-")
        compose.waitUntil(60_000) { visible("directory-grant-$uid") }
        compose.waitUntil(60_000) { visible("directory-editors-screen") && !visible("directory-editors-loading") }
        compose.onNodeWithTag("directory-editors-screen").performScrollToNode(hasTestTag("directory-grant-$uid"))
        compose.onNodeWithTag("directory-grant-$uid").assertIsEnabled()
        compose.onNodeWithTag("directory-grant-$uid").performClick()
        compose.waitUntil(60_000) { visible("directory-revoke-$uid") || visible("directory-editors-error") }
        compose.onNodeWithTag("directory-revoke-$uid").assertExists()
    }

    @Test fun editorPublishesCategory() {
        login("Editor")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { browse.navigate("directory/manage/$category") }
        compose.waitUntil(60_000) { visible("directory-editor-category-title-de") }
        compose.onNodeWithTag("directory-editor").performScrollToNode(hasTestTag("directory-editor-category-title-de"))
        compose.onNodeWithTag("directory-editor-category-title-de").performTextReplacement("Staging redigiert")
        compose.onNodeWithTag("directory-editor").performScrollToNode(hasTestTag("directory-publish"))
        compose.onNodeWithTag("directory-publish").assertIsEnabled()
        compose.onNodeWithTag("directory-publish").performSemanticsAction(SemanticsActions.OnClick)
        try {
            compose.waitUntil(30_000) {
                browse.state.value.route == "directory/manage" ||
                visible("directory-editor-error")
            }
        } catch (failure: Throwable) {
            val accessLost = runCatching {
                compose.onAllNodesWithText("Zugriff auf die Redaktion nicht verfügbar.")
                    .fetchSemanticsNodes().isNotEmpty()
            }.getOrDefault(false)
            val editorVisible = runCatching {
                compose.onAllNodesWithTag("directory-editor").fetchSemanticsNodes().isNotEmpty()
            }.getOrDefault(false)
            throw AssertionError("Editor publish timed out; route=${browse.state.value.route}; " +
                "editorVisible=$editorVisible; accessLost=$accessLost", failure)
        }
        if (browse.state.value.route != "directory/manage")
            throw AssertionError("Editor publication failed: route=${browse.state.value.route}; " +
                compose.onNodeWithTag("directory-editor-error").printToString())
    }

    @Test fun ownerRevokesEditor() {
        login("Owner")
        val auth = LocalAuthSession.get(compose.activity)
        val session = auth.state.value.moderationScope()!!
        val source = FirebaseDirectoryEditorsSource(compose.activity, auth)
        val serverGrants = runBlocking { source.grants(session) }
        assertTrue("Owner did not read the active grant from the server", serverGrants.any { it.uid == uid })
        compose.runOnIdle { compose.activity.setContent {
            UacTheme("light") { DirectoryEditorsScreen(session, "de", source, {}) }
        } }
        compose.waitUntil(60_000) { visible("directory-editors-screen") && !visible("directory-editors-loading") }
        try {
            compose.onNodeWithTag("directory-editors-screen")
                .performScrollToNode(hasTestTag("directory-revoke-$uid"))
        } catch (failure: Throwable) {
            val uiError = runCatching { compose.onNodeWithTag("directory-editors-error").printToString() }
                .getOrDefault("no error banner")
            throw AssertionError("Owner grant row missing after server read; $uiError", failure)
        }
        compose.onNodeWithTag("directory-revoke-$uid").assertIsEnabled()
        compose.onNodeWithTag("directory-revoke-$uid").performClick()
        compose.onNodeWithTag("directory-editors-confirm-revoke").performClick()
        compose.waitUntil(60_000) { !visible("directory-revoke-$uid") }
    }

    @Test fun readerCannotOpenGrantScreen() {
        login("Reader")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/directory-editors") }
        compose.waitUntil(30_000) { visible("management-access-denied") }
        compose.onNodeWithTag("directory-editors-screen").assertDoesNotExist()
    }
}
