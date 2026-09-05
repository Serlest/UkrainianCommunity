package at.uac.android

import android.view.WindowManager
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.dsastatement.DsaStatementViewModel
import at.uac.android.feature.inbox.InboxViewModel
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DsaStatementJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AccountDeletionFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val statement
        get() = ViewModelProvider(compose.activity)[DsaStatementViewModel::class.java]

    private val inbox
        get() = ViewModelProvider(compose.activity)[InboxViewModel::class.java]

    private fun scroll(list: String, tag: String) {
        compose.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
    }

    @Test
    fun actualNotificationOpensOwnStatementBackClearsAndLogoutMasks() {
        AccountDeletionFixtures.requireLocalAvd()
        check(AccountDeletionFixtures.online())
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", "emulator")
            browse.navigate("profile", true)
        }
        val user = runBlocking { AccountDeletionFixtures.create("deletion-dsa-main") }
        val report = "dsa-main-${UUID.randomUUID()}"
        val notice = "dsa-notice-${UUID.randomUUID()}"
        val casePath = "dsaCases/$report"
        val noticePath = "users/${user.uid}/notificationInbox/$notice"
        var primary: Throwable? = null
        try {
            runBlocking {
                val fixtures = LocalEmulatorFixtures(context)
                fixtures.seed(
                    casePath,
                    mapOf(
                        "targetAuthorId" to user.uid,
                        "caseNumber" to "SYNTHETIC MAIN CASE",
                        "status" to "decided",
                        "targetType" to "comment",
                        "targetId" to "synthetic-content",
                        "decision" to
                            mapOf(
                                "outcome" to "noAction",
                                "factsAndCircumstances" to "SYNTHETIC MAIN FACTS",
                                "legalBasis" to "Synthetic basis",
                                "termsBasis" to null,
                                "territorialScope" to "AT",
                                "duration" to "Synthetic duration",
                                "redressInformation" to "Synthetic redress",
                                "automationUsed" to false,
                            ),
                    ),
                )
                fixtures.seed(
                    noticePath,
                    mapOf(
                        "type" to "systemAnnouncement",
                        "sourceType" to "dsaStatement",
                        "sourceId" to report,
                        "actionType" to "dsaStatement",
                        "actionTargetId" to report,
                        "createdAt" to Instant.now(),
                        "isRead" to false,
                        "requiresPopup" to false,
                        "title" to "Synthetic decision notice",
                        "message" to "Synthetic only",
                    ),
                )
                withContext(Dispatchers.Main) {
                        auth.signIn(user.email, AccountDeletionFixtures.PASSWORD)
                    }!!
                    .join()
            }
            compose.waitUntil(30_000) { auth.state.value.readyForActions }
            compose.runOnIdle { browse.navigate("profile/inbox") }
            compose.waitUntil(30_000) {
                inbox.state.value.items.any { it.id == notice } && !inbox.state.value.loading
            }
            scroll("inbox-list", "inbox-details-$notice")
            compose.onNodeWithTag("inbox-details-$notice").performClick()
            // Expanding an unread notice starts READ and disables card actions.
            // A click on the still-disabled Open control is deliberately ignored.
            compose.waitUntil(30_000) {
                val state = inbox.state.value
                !state.mutating &&
                    !state.loading &&
                    state.items.any { it.id == notice && it.isRead }
            }
            assertNull(inbox.state.value.error)
            scroll("inbox-list", "inbox-open-$notice")
            compose.onNodeWithTag("inbox-open-$notice").assertIsEnabled().performClick()
            compose.waitUntil(30_000) {
                statement.state.value.statement?.id == report && !statement.state.value.loading
            }
            assertEquals("profile/dsa-statement/$report", browse.state.value.route)
            scroll("dsa-statement-list", "dsa-facts")
            compose.onNodeWithTag("dsa-facts").assertTextContains("SYNTHETIC MAIN FACTS")
            compose.runOnIdle {
                assertTrue(
                    compose.activity.window.attributes.flags and
                        WindowManager.LayoutParams.FLAG_SECURE != 0
                )
            }
            compose.runOnIdle { browse.back() }
            compose.waitUntil(10_000) {
                browse.state.value.route == "profile/inbox" && !statement.state.value.visible
            }
            assertNull(statement.state.value.statement)
            // Reopening uses a fresh actual source read; no previous statement is restored from
            // navigation.
            compose.runOnIdle { browse.navigate("profile/dsa-statement/$report") }
            compose.waitUntil(30_000) { statement.state.value.statement?.id == report }
            runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
            compose.waitUntil(15_000) { statement.state.value.session == null }
            assertNull(statement.state.value.statement)
            compose.onNodeWithText("SYNTHETIC MAIN FACTS").assertDoesNotExist()
            assertEquals(
                "decided",
                runBlocking {
                    AccountDeletionFixtures.field(
                        AccountDeletionFixtures.document(casePath)!!,
                        "status",
                    )
                },
            )
        } catch (error: Throwable) {
            val failure =
                AssertionError(
                    "DSA journey ready=${auth.state.value.readyForActions}, " +
                        "routeMatches=${browse.state.value.route == "profile/dsa-statement/$report"}, " +
                        "visible=${statement.state.value.visible}, loading=${statement.state.value.loading}, " +
                        "error=${statement.state.value.error}, inboxLoading=${inbox.state.value.loading}, " +
                        "inboxMutating=${inbox.state.value.mutating}, inboxError=${inbox.state.value.error}, " +
                        "noticeRead=${inbox.state.value.items.find { it.id == notice }?.isRead}",
                    error,
                )
            primary = failure
            throw failure
        } finally {
            try {
                runBlocking {
                    val sdk = LocalFirebase.auth(context)
                    if (sdk.currentUser?.uid != user.uid)
                        sdk.signInWithEmailAndPassword(user.email, AccountDeletionFixtures.PASSWORD)
                            .await()
                    AccountDeletionFixtures.clean(user, listOf(casePath, noticePath))
                    for (path in
                        listOf(
                            casePath,
                            noticePath,
                            "users/${user.uid}",
                            "publicProfiles/${user.uid}",
                        )) assertNull(AccountDeletionFixtures.document(path))
                    AccountDeletionFixtures.assertAuthAbsent(user)
                    withContext(Dispatchers.Main) { auth.signOut() }.join()
                }
            } catch (cleanup: Throwable) {
                if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
            }
        }
    }
}
