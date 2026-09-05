package at.uac.android

import android.view.KeyEvent
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.AuthRemediationPriority
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.accountstatus.AccountStatusViewModel
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.personal.PersonalProfileEditorViewModel
import at.uac.android.feature.personal.personalScope
import com.google.firebase.Timestamp
import com.google.firebase.firestore.Source
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Real ordinary-user Auth and Main; never a synthetic privileged/TOTP success. */
@RunWith(AndroidJUnit4::class)
class AccountStatusJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AccountDeletionFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val status
        get() = ViewModelProvider(compose.activity)[AccountStatusViewModel::class.java]

    private val editor
        get() = ViewModelProvider(compose.activity)[PersonalProfileEditorViewModel::class.java]

    private val remediation
        get() = ViewModelProvider(compose.activity)[AuthRemediationPriority::class.java]

    private fun field(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun waitForHomeTab() {
        try {
            compose.waitUntil(10_000) { compose.onNodeWithTag("tab-home").isDisplayed() }
        } catch (failure: Throwable) {
            fun geometry(unmerged: Boolean) = runCatching {
                compose
                    .onAllNodesWithTag("tab-home", useUnmergedTree = unmerged)
                    .fetchSemanticsNodes()
                    .map { "placed=${it.layoutInfo.isPlaced},bounds=${it.boundsInRoot}" }
            }
                .getOrElse { listOf("unavailable:${it.javaClass.simpleName}") }
            val session = auth.state.value
            throw AssertionError(
                "Home tab after login: stage=${session.stage},ready=${session.readyForActions},busy=${session.busy}," +
                    "accountRoute=${browse.state.value.isAccountRoute},ime=${imeVisible()}," +
                    "remediation=${remediation.active.value},notice=${status.state.value.notice != null}," +
                    "merged=${geometry(false)},unmerged=${geometry(true)}",
                failure,
            )
        }
    }

    private fun imeVisible(): Boolean {
        var visible = false
        compose.runOnUiThread {
            visible =
                ViewCompat.getRootWindowInsets(compose.activity.window.decorView)
                    ?.isVisible(WindowInsetsCompat.Type.ime()) == true
        }
        return visible
    }

    private fun own(user: AccountStatusFixtures.User): Map<String, Any> = runBlocking {
        requireNotNull(
            LocalFirebase.firestore(context)
                .document("users/${user.uid}")
                .get(Source.SERVER)
                .await()
                .data
        )
    }

    private fun changed(before: Map<String, Any>, after: Map<String, Any>) =
        (before.keys + after.keys).filter { before[it] != after[it] }.toSet()

    private fun withAccount(block: (AccountStatusFixtures, AccountStatusFixtures.User) -> Unit) {
        AccountDeletionFixtures.requireLocalAvd()
        assumeTrue(
            "Own-status Main proof requires the named local runtime",
            AccountDeletionFixtures.online(),
        )
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        val fixtures = AccountStatusFixtures("status-main")
        var primary: Throwable? = null
        try {
            val user = runBlocking { fixtures.create() }
            runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
            compose.runOnIdle {
                browse.preference("language", "de")
                browse.preference("mode", "emulator")
                browse.navigate("profile", true)
            }
            compose.waitUntil(15_000) { auth.state.value.stage == AuthStage.GUEST }
            compose.openGuestLogin()
            field("auth-email").performTextReplacement(user.email)
            field("auth-password").performTextReplacement(fixtures.password)
            field("auth-login-submit").assertIsEnabled().performClick()
            compose.waitUntil(30_000) { auth.state.value.readyForActions }
            assertEquals("user", auth.state.value.profile?.globalRole)
            assertEquals(user.uid, auth.state.value.identity?.uid)
            block(fixtures, user)
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            var cleanupFailure: Throwable? = null
            try {
                runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
            } catch (error: Throwable) {
                if (primary == null) cleanupFailure = error else primary.addSuppressed(error)
            }
            runBlocking { fixtures.cleanup(primary ?: cleanupFailure) }
            if (primary == null && cleanupFailure != null) throw cleanupFailure
        }
    }

    private fun warn(
        fixtures: AccountStatusFixtures,
        user: AccountStatusFixtures.User,
        message: String,
    ) {
        val previousAck =
            (own(user)["statusAcknowledgedAt"] as? Timestamp)?.let {
                Instant.ofEpochSecond(it.seconds, it.nanoseconds.toLong())
            }
        // Keep fixture timestamps safely in the past while making a second notice newer than
        // the actual preceding acknowledgement. Changing message alone cannot bypass that fence.
        compose.waitUntil(8_000) {
            previousAck == null || Instant.now().minusSeconds(2).isAfter(previousAck)
        }
        runBlocking {
            fixtures.status(
                user,
                "warned",
                updatedAt = Instant.now().minusSeconds(2),
                reason = "Synthetic own-status Main reason",
                message = message,
            )
        }
        compose.waitUntil(20_000) { auth.state.value.profile?.statusMessage == message }
    }

    private fun notice(message: String) {
        compose.waitUntil(20_000) {
            status.state.value.notice?.message == message &&
                compose.onNodeWithTag("account-status-notice").isDisplayed()
        }
        field("account-status-message").assertTextEquals(message)
        field("account-status-reason").assertTextEquals("Synthetic own-status Main reason")
    }

    private fun acknowledge(user: AccountStatusFixtures.User): Timestamp {
        val before = own(user)
        field("account-status-acknowledge").assertIsEnabled().performClick()
        compose.waitUntil(20_000) {
            status.state.value.notice == null &&
                !status.state.value.busy &&
                auth.state.value.profile?.statusAcknowledgedAt != null
        }
        compose.onNodeWithTag("account-status-notice").assertDoesNotExist()
        val after = own(user)
        assertEquals(setOf("statusAcknowledgedAt"), changed(before, after))
        val acknowledged = after["statusAcknowledgedAt"] as Timestamp
        assertTrue(acknowledged >= after["statusUpdatedAt"] as Timestamp)
        assertEquals("warned", after["accountStatus"])
        assertEquals("active", after["blockState"])
        return acknowledged
    }

    @Test
    fun warningOutsideProfileChangesOnlyAcknowledgementAndDoesNotReplayAfterRefresh() =
        withAccount { fixtures, user ->
            waitForHomeTab()
            compose.onNodeWithTag("tab-home").performClick()
            compose.waitUntil(20_000) { !browse.state.value.isAccountRoute }
            val route = browse.state.value.route
            warn(fixtures, user, "Synthetic warning outside Profile")
            notice("Synthetic warning outside Profile")
            assertEquals(route, browse.state.value.route)
            val acknowledged = acknowledge(user)
            runBlocking { withContext(Dispatchers.Main) { auth.refresh() }.join() }
            compose.waitUntil(30_000) {
                auth.state.value.readyForActions && status.state.value.notice == null
            }
            compose.onNodeWithTag("account-status-notice").assertDoesNotExist()
            assertEquals(acknowledged, own(user)["statusAcknowledgedAt"])
            assertEquals(route, browse.state.value.route)
        }

    @Test
    fun legalReaderKeepsPriorityAndWarningDoesNotLoseOrTypeIntoDirtyProfile() =
        withAccount { fixtures, user ->
            field("auth-legal-terms").assertIsEnabled().performClick()
            compose.onNodeWithTag("legal-reader").assertIsDisplayed()
            compose.waitUntil(10_000) { remediation.active.value }
            warn(fixtures, user, "Synthetic warning deferred by legal reader")
            compose.waitUntil(20_000) {
                status.state.value.notice?.message == "Synthetic warning deferred by legal reader"
            }
            compose.onNodeWithTag("legal-reader").assertIsDisplayed()
            compose.onNodeWithTag("account-status-notice").assertDoesNotExist()
            assertNull(own(user)["statusAcknowledgedAt"])
            compose.onNodeWithTag("legal-close").assertIsDisplayed().performClick()
            notice("Synthetic warning deferred by legal reader")
            acknowledge(user)

            field("account-open-edit").assertIsEnabled().performClick()
            compose.waitUntil(30_000) {
                editor.state.value.confirmedSession == auth.state.value.personalScope() &&
                    editor.state.value.baseline != null
            }
            val draft = "Synthetic unsaved status-interruption draft"
            field("profile-display-name").performTextReplacement(draft)
            compose.waitUntil(10_000) { imeVisible() }
            assertEquals(draft, editor.state.value.draft.displayName)
            val storedName = own(user)["displayName"]
            assertNotEquals(draft, storedName)
            warn(fixtures, user, "Synthetic warning over focused profile")
            notice("Synthetic warning over focused profile")
            compose.waitUntil(10_000) { !imeVisible() }
            InstrumentationRegistry.getInstrumentation().sendKeyDownUpSync(KeyEvent.KEYCODE_X)
            compose.waitForIdle()
            assertEquals(draft, editor.state.value.draft.displayName)
            assertEquals(storedName, own(user)["displayName"])
            acknowledge(user)
            assertEquals("profile/edit", browse.state.value.route)
            field("profile-display-name").assertTextContains(draft)
            assertEquals(storedName, own(user)["displayName"])
        }
}
