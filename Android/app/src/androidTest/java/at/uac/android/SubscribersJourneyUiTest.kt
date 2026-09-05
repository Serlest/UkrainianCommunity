package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.safety.SafetyFailure
import at.uac.android.feature.safety.SafetyViewModel
import at.uac.android.feature.subscribers.*
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
 * Real Main route, ordinary real Auth, real scoped subscriptions and callable-backed live block
 * policy.
 */
@RunWith(AndroidJUnit4::class)
class SubscribersJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AccountDeletionFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val subscribers
        get() = ViewModelProvider(compose.activity)[SubscribersViewModel::class.java]

    private val safety
        get() = ViewModelProvider(compose.activity)[SafetyViewModel::class.java]

    private fun account(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun detail(tag: String) =
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag(tag))

    private fun list(tag: String) {
        // A fresh state sample can precede a real listener invalidation by one frame. Wait for
        // the requested rendered row, retaining the exact row/count assertions and bounded timeout.
        compose.waitUntil(30_000) {
            if (subscribers.state.value.loading || subscribers.state.value.page == null) false
            else
                runCatching {
                        compose
                            .onNodeWithTag("subscribers-list")
                            .performScrollToNode(hasTestTag(tag))
                        compose.onNodeWithTag(tag).isDisplayed()
                    }
                    .getOrDefault(false)
        }
        compose.onNodeWithTag(tag).assertIsDisplayed()
    }

    private var phase = "setup"

    @Test
    fun ordinaryAccountOpensPagesSearchesMasksLiveBlockAndClearsOnExit() {
        AccountDeletionFixtures.requireLocalAvd()
        assumeTrue(
            "Offline account guard is not a real Main community journey",
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
            AccountDeletionFixtures.create("deletion-subscribers-journey")
        }
        val fixture = SubscribersDeviceTest.Fixture()
        val blockedId = fixture.person(1)
        val blockPath = "users/${user.uid}/blockedUsers/$blockedId"
        // Opening a real organization detail may create one bounded recent-view record through U11.
        val recentPath = "users/${user.uid}/recentViews/organization_${fixture.organizationId}"
        var primary: Throwable? = null
        try {
            runBlocking {
                fixture.seed(55)
                for (index in 1..54) fixture.publicProfile(index)
                fixture.privatePerson(1)
            }
            LocalFirebase.auth(context).signOut()
            // Supports the explicitly observed old account host and the new guest welcome button.
            if (compose.onAllNodesWithTag("guest-sign-in").fetchSemanticsNodes().isNotEmpty())
                compose.onNodeWithTag("guest-sign-in").performClick()
            account("auth-email").performTextReplacement(user.email)
            account("auth-password").performTextReplacement(AccountDeletionFixtures.PASSWORD)
            account("auth-login-submit").assertIsEnabled().performClick()
            compose.waitUntil(30_000) { auth.state.value.readyForActions }
            assertEquals("user", auth.state.value.profile?.globalRole)
            compose.runOnIdle { browse.navigate("organizations/${fixture.organizationId}") }
            compose.waitUntil(30_000) {
                browse.state.value.data.detail?.id == fixture.organizationId &&
                    !browse.state.value.data.loading &&
                    browse.state.value.data.cachedAt == null
            }
            compose.waitUntil(25_000) {
                safety.state.value.visibility.loaded || safety.state.value.error != null
            }
            if (safety.state.value.error == SafetyFailure.OFFLINE) {
                println("SUBSCRIBERS_INITIAL_SAFETY_OFFLINE ${safety.state.value.readDiagnostic}")
                detail("safety-availability-retry")
                compose.onNodeWithTag("safety-availability-retry").performClick()
                compose.waitUntil(25_000) { !safety.state.value.loading }
            }
            assertTrue(safety.state.value.visibility.loaded)
            assertNull(safety.state.value.error)
            phase = "ordinary public detail entry without opening protected source"
            assertNull(subscribers.state.value.page)
            assertFalse(subscribers.state.value.visible)
            assertNull(subscribers.state.value.organizationId)
            assertNotEquals(user.uid, browse.state.value.data.detail?.fields?.get("ownerId"))
            detail("subscribers-open")
            compose.onNodeWithTag("subscribers-open").assertIsEnabled().performClick()
            phase = "first protected page and rendered initial-listener settlement"
            compose.waitUntil(30_000) {
                subscribers.state.value.page?.references?.size == 50 &&
                    !subscribers.state.value.loading
            }
            assertEquals("profile/subscribers/${fixture.organizationId}", browse.state.value.route)
            list("subscribers-partial")
            compose.onNodeWithTag("subscribers-partial").assertIsDisplayed()
            list("subscribers-more")
            compose.onNodeWithTag("subscribers-more").performClick()
            compose.waitUntil(30_000) {
                subscribers.state.value.page?.references?.size == 55 &&
                    !subscribers.state.value.loading
            }
            assertNull(subscribers.state.value.page!!.next)
            phase = "loaded-only search and live callable-backed safety filtering"
            list("subscribers-search")
            compose.onNodeWithTag("subscribers-search").performTextReplacement("member 001")
            list("subscriber-$blockedId")
            compose.onNodeWithText("Synthetic public member 001").assertIsDisplayed()
            compose.onNodeWithText(blockedId).assertDoesNotExist()
            // C09 intentionally has no mutation controls. Exercise the existing root Safety
            // VM/callable
            // while its read-only list is visible; no successful block state is injected into the
            // UI.
            compose.runOnIdle { safety.setUser(blockedId, true) }
            compose.waitUntil(30_000) {
                "user:$blockedId" !in safety.state.value.pendingBlocks &&
                    blockedId in safety.state.value.visibility.blockedUserIds
            }
            assertNull(safety.state.value.blockErrors["user:$blockedId"])
            compose.onNodeWithTag("subscriber-$blockedId").assertDoesNotExist()
            compose.onNodeWithText("Synthetic public member 001").assertDoesNotExist()
            assertTrue(
                runBlocking {
                    LocalFirebase.firestore(context)
                        .document(blockPath)
                        .get(Source.SERVER)
                        .await()
                        .exists()
                }
            )
            compose.runOnIdle { safety.setUser(blockedId, false) }
            compose.waitUntil(30_000) {
                "user:$blockedId" !in safety.state.value.pendingBlocks &&
                    blockedId !in safety.state.value.visibility.blockedUserIds &&
                    !subscribers.state.value.loading &&
                    subscribers.state.value.page?.members?.any { it.userId == blockedId } == true
            }
            assertNull(safety.state.value.blockErrors["user:$blockedId"])
            list("subscriber-$blockedId")
            compose.onNodeWithText("Synthetic public member 001").assertIsDisplayed()
            assertFalse(
                runBlocking {
                    LocalFirebase.firestore(context)
                        .document(blockPath)
                        .get(Source.SERVER)
                        .await()
                        .exists()
                }
            )
            phase = "back return revalidates and logout clears protected state"
            list("subscribers-back")
            compose.onNodeWithTag("subscribers-back").performClick()
            compose.waitUntil(30_000) {
                browse.state.value.route == "organizations/${fixture.organizationId}" &&
                    !browse.state.value.data.loading
            }
            assertNull(subscribers.state.value.page)
            assertFalse(subscribers.state.value.visible)
            detail("subscribers-open")
            compose.onNodeWithTag("subscribers-open").performClick()
            compose.waitUntil(30_000) {
                subscribers.state.value.page?.references?.size == 50 &&
                    !subscribers.state.value.loading
            }
            assertEquals("", subscribers.state.value.search)
            list("subscribers-back")
            compose.onNodeWithTag("subscribers-back").performClick()
            compose.waitUntil(30_000) { !browse.state.value.data.loading }
            compose.waitUntil(10_000) { compose.onNodeWithTag("tab-profile").isDisplayed() }
            compose.onNodeWithTag("tab-profile").performClick()
            account("auth-signout").performClick()
            compose.waitUntil(30_000) {
                auth.state.value.stage == AuthStage.GUEST && subscribers.state.value.session == null
            }
            assertNull(subscribers.state.value.page)
            assertEquals("", subscribers.state.value.search)
            compose.onNodeWithText("Synthetic public member 001").assertDoesNotExist()
            runBlocking {
                val sdk = LocalFirebase.auth(context)
                sdk.signInWithEmailAndPassword(user.email, AccountDeletionFixtures.PASSWORD).await()
                fixture.assertUnchanged(55)
            }
        } catch (error: Throwable) {
            val failure =
                AssertionError(
                    "Subscribers journey phase=$phase, ready=${auth.state.value.readyForActions}, " +
                        "loading=${subscribers.state.value.loading}, error=${subscribers.state.value.error}, " +
                        "loaded=${subscribers.state.value.page?.references?.size}, safetyLoaded=${safety.state.value.visibility.loaded}, safetyError=${safety.state.value.error}",
                    error,
                )
            primary = failure
            throw failure
        } finally {
            var cleanup = primary
            fun clean(action: () -> Unit) {
                try {
                    action()
                } catch (error: Throwable) {
                    if (cleanup == null) cleanup = error else cleanup?.addSuppressed(error)
                }
            }
            clean { runBlocking { fixture.cleanup() } }
            clean {
                runBlocking {
                    val sdk = LocalFirebase.auth(context)
                    if (sdk.currentUser?.uid != user.uid)
                        sdk.signInWithEmailAndPassword(user.email, AccountDeletionFixtures.PASSWORD)
                            .await()
                    AccountDeletionFixtures.clean(user, listOf(blockPath, recentPath))
                }
            }
            clean { runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() } }
            if (primary == null) cleanup?.let { throw it }
        }
    }
}
