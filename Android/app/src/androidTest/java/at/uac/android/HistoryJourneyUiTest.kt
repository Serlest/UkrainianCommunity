package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.history.*
import at.uac.android.feature.personal.PersonalTarget
import at.uac.android.feature.personal.PersonalViewModel
import at.uac.android.feature.safety.SafetyFailure
import at.uac.android.feature.safety.SafetyViewModel
import com.google.firebase.firestore.Source
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real Main detail lifecycle and primary marker → history callbacks. No history state or success
 * receipt is injected.
 */
@RunWith(AndroidJUnit4::class)
class HistoryJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AccountDeletionFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val history
        get() = ViewModelProvider(compose.activity)[HistoryViewModel::class.java]

    private val personal
        get() = ViewModelProvider(compose.activity)[PersonalViewModel::class.java]

    private val safety
        get() = ViewModelProvider(compose.activity)[SafetyViewModel::class.java]

    private fun account(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun detail(tag: String) =
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag(tag))

    private fun list(tag: String) =
        compose.onNodeWithTag("history-list").performScrollToNode(hasTestTag(tag))

    private fun awaitRenderedRecent() {
        // The retained ViewModel may be ready before the new RESUMED composition's
        // visibility callback starts another read. Synchronize with the rendered UI,
        // at the point of interaction, not a model snapshot before a server read.
        compose.waitUntil(30_000) {
            compose.onAllNodesWithTag("history-list").fetchSemanticsNodes().size == 1
        }
        list("history-refresh")
        compose.waitUntil(30_000) {
            val state = history.state.value
            auth.state.value.readyForActions &&
                state.visible &&
                state.page?.entries?.size == 1 &&
                !state.loading &&
                state.error == null &&
                compose
                    .onAllNodes(hasTestTag("history-refresh") and isEnabled())
                    .fetchSemanticsNodes()
                    .size == 1
        }
    }

    private var phase = "setup"

    @Test
    fun realDetailBookmarkRecentHistoryExplicitDeleteAndLogoutIsolation() {
        AccountDeletionFixtures.requireLocalAvd()
        assumeTrue(
            "Offline guard is not a real Main history journey",
            AccountDeletionFixtures.online(),
        )
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", "emulator")
            browse.navigate("profile", true)
        }
        val user = runBlocking {
            AuthEmulatorFixtures.seedLegalReference()
            AccountDeletionFixtures.create("deletion-history-journey")
        }
        val fixture = HistoryDeviceFixtures(user.uid)
        val target = fixture.targets.first()
        val markerPath = fixture.marker(target)
        val recentPath = fixture.path(HistorySection.RECENT, target.recentId)
        val bookmarkPath = fixture.bookmark(target)
        var primary: Throwable? = null
        try {
            runBlocking { fixture.seedTargets() }
            LocalFirebase.auth(context).signOut()
            compose.openGuestLogin()
            account("auth-email").performTextReplacement(user.email)
            account("auth-password").performTextReplacement(AccountDeletionFixtures.PASSWORD)
            account("auth-login-submit").performClick()
            compose.waitUntil(30_000) { auth.state.value.readyForActions }
            compose.runOnIdle { browse.navigate(target.path) }
            compose.waitUntil(30_000) {
                browse.state.value.data.detail?.id == target.id &&
                    !browse.state.value.data.loading &&
                    browse.state.value.data.cachedAt == null
            }
            compose.waitUntil(25_000) {
                safety.state.value.visibility.loaded || safety.state.value.error != null
            }
            if (safety.state.value.error == SafetyFailure.OFFLINE) {
                println("HISTORY_INITIAL_SAFETY_OFFLINE ${safety.state.value.readDiagnostic}")
                detail("safety-availability-retry")
                compose.onNodeWithTag("safety-availability-retry").performClick()
                compose.waitUntil(25_000) { !safety.state.value.loading }
            }
            assertTrue(safety.state.value.visibility.loaded)
            assertNull(safety.state.value.error)

            phase = "fresh foreground detail creates recent and immutable view marker"
            compose.waitUntil(30_000) {
                history.state.value.pendingWrites == 0 &&
                    history.state.value.notice == null &&
                    runBlocking { fixture.read(recentPath) != null }
            }
            val firstMarker = runBlocking {
                LocalFirebase.firestore(context)
                    .document(markerPath)
                    .get(Source.SERVER)
                    .await()
                    .getTimestamp("createdAt")
            }
            assertNotNull(firstMarker)
            assertNull(history.state.value.page)
            phase = "actual bookmark confirmation produces activity receipt"
            val personalTarget = PersonalTarget(target.type.kind, target.id)
            compose.waitUntil(30_000) {
                personal.state.value.actions[personalTarget] != null &&
                    personalTarget !in personal.state.value.actionsLoading
            }
            detail("personal-bookmark")
            compose.onNodeWithTag("personal-bookmark").assertIsEnabled().performClick()
            compose.waitUntil(30_000) {
                personal.state.value.actions[personalTarget]?.bookmarked == true &&
                    personalTarget !in personal.state.value.actionsPending &&
                    history.state.value.pendingWrites == 0
            }
            assertNull(personal.state.value.actionErrors[personalTarget])
            assertNull(history.state.value.notice)
            val rows = runBlocking {
                LocalFirebase.firestore(context)
                    .collection("users/${user.uid}/activityLog")
                    .limit(10)
                    .get(Source.SERVER)
                    .await()
            }
            assertEquals(1, rows.size())
            assertEquals("savedNews", rows.documents.single().getString("actionType"))
            assertEquals(target.id, rows.documents.single().getString("targetId"))
            fixture.path(HistorySection.ACTIVITY, rows.documents.single().id)

            phase = "account recent route opens fresh rows; recreation does not write"
            compose.waitUntil(10_000) { compose.onNodeWithTag("tab-profile").isDisplayed() }
            compose.onNodeWithTag("tab-profile").performClick()
            account("account-open-recent").performClick()
            compose.waitUntil(30_000) {
                history.state.value.page?.entries?.size == 1 && !history.state.value.loading
            }
            assertEquals("profile/recent", browse.state.value.route)
            list("history-open-${target.recentId}")
            compose.onNodeWithTag("history-open-${target.recentId}").assertIsEnabled()
            compose.activityRule.scenario.recreate()
            compose.waitUntil(30_000) {
                auth.state.value.readyForActions &&
                    history.state.value.page?.entries?.size == 1 &&
                    !history.state.value.loading
            }
            assertEquals(
                firstMarker,
                runBlocking {
                    LocalFirebase.firestore(context)
                        .document(markerPath)
                        .get(Source.SERVER)
                        .await()
                        .getTimestamp("createdAt")
                },
            )

            phase = "explicit deletion removes history only and keeps bookmark and counter"
            awaitRenderedRecent()
            list("history-delete-visible")
            compose.onNodeWithTag("history-delete-visible").performClick()
            compose.onNodeWithTag("history-confirm-delete").assertIsDisplayed().performClick()
            compose.waitUntil(30_000) {
                !history.state.value.deleting &&
                    history.state.value.page?.entries?.isEmpty() == true
            }
            runBlocking {
                assertNull(fixture.read(recentPath))
                assertTrue(
                    LocalFirebase.firestore(context)
                        .document(bookmarkPath)
                        .get(Source.SERVER)
                        .await()
                        .exists()
                )
                assertEquals(
                    firstMarker,
                    LocalFirebase.firestore(context)
                        .document(markerPath)
                        .get(Source.SERVER)
                        .await()
                        .getTimestamp("createdAt"),
                )
                assertEquals(
                    7L,
                    LocalFirebase.firestore(context)
                        .document(target.path)
                        .get(Source.SERVER)
                        .await()
                        .getLong("viewCount"),
                )
            }
            list("history-back")
            compose.onNodeWithTag("history-back").performClick()
            account("account-open-history").performClick()
            compose.waitUntil(30_000) {
                history.state.value.page?.entries?.singleOrNull()?.record?.action ==
                    HistoryAction.SAVE_NEWS
            }
            assertEquals("profile/history", browse.state.value.route)
            list("history-row-${rows.documents.single().id}")
            compose.onNodeWithText("Nachricht gespeichert").assertIsDisplayed()
            list("history-back")
            compose.onNodeWithTag("history-back").performClick()
            account("auth-signout").performClick()
            compose.waitUntil(30_000) {
                auth.state.value.stage == AuthStage.GUEST && history.state.value.session == null
            }
            assertNull(history.state.value.page)
            assertEquals(0, history.state.value.pendingWrites)
            assertNull(history.state.value.confirmation)
            compose.onNodeWithText("Synthetic history news").assertDoesNotExist()
        } catch (error: Throwable) {
            val failure =
                AssertionError(
                    "History journey phase=$phase, ready=${auth.state.value.readyForActions}, loading=${history.state.value.loading}, " +
                        "error=${history.state.value.error}, notice=${history.state.value.notice}, pending=${history.state.value.pendingWrites}, " +
                        "rows=${history.state.value.page?.entries?.size}, safetyLoaded=${safety.state.value.visibility.loaded}",
                    error,
                )
            primary = failure
            throw failure
        } finally {
            var cleanupFailure = primary
            fun clean(action: () -> Unit) {
                try {
                    action()
                } catch (error: Throwable) {
                    if (cleanupFailure == null) cleanupFailure = error
                    else cleanupFailure?.addSuppressed(error)
                }
            }
            clean {
                runBlocking {
                    val sdk = LocalFirebase.auth(context)
                    if (sdk.currentUser?.uid != user.uid)
                        sdk.signInWithEmailAndPassword(user.email, AccountDeletionFixtures.PASSWORD)
                            .await()
                    fixture.captureActivityReceipts()
                }
            }
            clean { runBlocking { fixture.cleanup(null) } }
            clean { runBlocking { AccountDeletionFixtures.clean(user) } }
            clean { runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() } }
            if (primary == null) cleanupFailure?.let { throw it }
        }
    }
}
