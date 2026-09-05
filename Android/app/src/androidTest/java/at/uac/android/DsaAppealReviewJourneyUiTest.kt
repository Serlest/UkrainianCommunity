package at.uac.android

import android.view.WindowManager
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.dsaappeal.DsaAppealReviewFailure
import at.uac.android.feature.dsaappeal.DsaAppealReviewViewModel
import at.uac.android.feature.feedback.*
import com.google.firebase.firestore.Source
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

/** Own feedback → fresh read-only decision → back/reopen → logout. No actual DSA actions. */
@RunWith(AndroidJUnit4::class)
class DsaAppealReviewJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AccountDeletionFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val feedback
        get() = ViewModelProvider(compose.activity)[FeedbackViewModel::class.java]

    private val review
        get() = ViewModelProvider(compose.activity)[DsaAppealReviewViewModel::class.java]

    private fun scroll(list: String, tag: String) {
        compose.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
    }

    @Test
    fun actualReporterOpensFreshDecisionAndLeavingClearsItWithoutSending() {
        AccountDeletionFixtures.requireLocalAvd()
        check(AccountDeletionFixtures.online())
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", "emulator")
            browse.navigate("profile", true)
        }
        val user = runBlocking { AccountDeletionFixtures.create("deletion-review-main") }
        val report = "review-${UUID.randomUUID()}"
        val path = "feedback/$report"
        val time = Instant.now().minusSeconds(60)
        val decision =
            mapOf<String, Any?>(
                "outcome" to "noAction",
                "factsAndCircumstances" to "PRIVATE SYNTHETIC ORIGINAL FACTS",
                "legalBasis" to "Synthetic basis",
                "termsBasis" to null,
                "territorialScope" to "AT",
                "duration" to "Synthetic duration",
                "redressInformation" to "Synthetic redress",
                "automationUsed" to false,
                "humanReviewConfirmed" to true,
                "actionVerifiedAt" to time,
                "decidedAt" to time,
                "decidedByUserId" to "synthetic-owner",
                "appealDeadline" to time.plusSeconds(3600),
            )
        val case =
            mapOf(
                "caseNumber" to "SYNTHETIC-ONLY",
                "status" to "decided",
                "category" to "other",
                "exactLocation" to "Synthetic location",
                "illegalExplanation" to "Synthetic explanation",
                "legalBasis" to null,
                "evidence" to null,
                "goodFaithConfirmed" to true,
                "acknowledgementAt" to time.minusSeconds(60),
                "preferredLanguage" to "de",
                "decision" to decision,
            )
        val fields =
            FeedbackContract.creation(
                report,
                FeedbackSession(user.uid, 0, true, false, "Synthetic"),
                FeedbackDraft(FeedbackType.REPORT, "Synthetic own report"),
                time.minusSeconds(60),
            ) + mapOf("status" to "closed", "updatedAt" to time, "dsaCase" to case)
        var primary: Throwable? = null
        try {
            runBlocking {
                LocalEmulatorFixtures(context).seed(path, fields)
                withContext(Dispatchers.Main) {
                        auth.signIn(user.email, AccountDeletionFixtures.PASSWORD)
                    }!!
                    .join()
            }
            compose.waitUntil(30_000) { auth.state.value.readyForActions }
            compose.runOnIdle { browse.navigate("profile/feedback") }
            compose.waitUntil(30_000) {
                feedback.state.value.page?.items?.any { it.id == report } == true &&
                    !feedback.state.value.loading
            }
            scroll("feedback-list", "feedback-item-$report")
            compose.onNodeWithTag("feedback-item-$report").performClick()
            compose.waitUntil(30_000) {
                feedback.state.value.conversation?.item?.id == report &&
                    !feedback.state.value.loading
            }
            scroll("feedback-conversation", "feedback-read-decision")
            compose.onNodeWithTag("feedback-read-decision").performClick()
            compose.waitUntil(30_000) {
                review.state.value.review?.snapshot?.reportId == report &&
                    !review.state.value.loading
            }
            assertEquals("profile/dsa-review/$report", browse.state.value.route)
            assertNull(review.state.value.error)
            scroll("dsa-review-list", "dsa-review-readonly")
            scroll("dsa-review-list", "dsa-review-facts")
            compose
                .onNodeWithTag("dsa-review-facts")
                .assertTextEquals("PRIVATE SYNTHETIC ORIGINAL FACTS")
            compose.runOnIdle {
                assertTrue(
                    compose.activity.window.attributes.flags and
                        WindowManager.LayoutParams.FLAG_SECURE != 0
                )
            }
            val database = LocalFirebase.firestore(context)
            try {
                // Only this named local SDK client, not AVD radios/server/global database state.
                // The decision and own profile have already been read into the SDK cache.
                runBlocking { database.disableNetwork().await() }
                scroll("dsa-review-list", "dsa-review-refresh")
                compose.onNodeWithTag("dsa-review-refresh").performClick()
                compose.waitUntil(15_000) {
                    review.state.value.error == DsaAppealReviewFailure.OFFLINE &&
                        !review.state.value.loading
                }
                assertNull(review.state.value.review)
                compose.onNodeWithText("PRIVATE SYNTHETIC ORIGINAL FACTS").assertDoesNotExist()
                compose.onNodeWithText("PRIVATE SYNTHETIC UPDATED FACTS").assertDoesNotExist()
                compose.onNodeWithText("PRIVATE SYNTHETIC AFTER BACKGROUND").assertDoesNotExist()
                compose.onNodeWithText("PRIVATE SYNTHETIC AFTER RECREATION").assertDoesNotExist()
                scroll("dsa-review-list", "dsa-review-error")
            } finally {
                runBlocking { database.enableNetwork().await() }
            }
            scroll("dsa-review-list", "dsa-review-refresh")
            compose.onNodeWithTag("dsa-review-refresh").performClick()
            compose.waitUntil(30_000) {
                review.state.value.review != null && !review.state.value.loading
            }
            assertNull(review.state.value.error)
            val fingerprint = review.state.value.review!!.snapshot.fingerprint
            compose.onNodeWithTag("back").assertIsDisplayed().performClick()
            compose.waitUntil(15_000) {
                browse.state.value.route == "profile/feedback/$report" &&
                    !review.state.value.visible
            }
            assertNull(review.state.value.review)
            assertNull(review.state.value.reportId)
            runBlocking {
                LocalEmulatorFixtures(context)
                    .seed(
                        path,
                        fields +
                            ("dsaCase" to
                                (case +
                                    ("decision" to
                                        (decision +
                                            ("factsAndCircumstances" to
                                                "PRIVATE SYNTHETIC UPDATED FACTS"))))),
                    )
            }
            compose.waitUntil(30_000) {
                feedback.state.value.conversation?.item?.id == report &&
                    !feedback.state.value.loading
            }
            scroll("feedback-conversation", "feedback-read-decision")
            compose.onNodeWithTag("feedback-read-decision").performClick()
            compose.waitUntil(30_000) {
                review.state.value.review?.snapshot?.decision?.facts ==
                    "PRIVATE SYNTHETIC UPDATED FACTS"
            }
            assertNotEquals(fingerprint, review.state.value.review!!.snapshot.fingerprint)
            scroll("dsa-review-list", "dsa-review-facts")
            compose
                .onNodeWithTag("dsa-review-facts")
                .assertTextEquals("PRIVATE SYNTHETIC UPDATED FACTS")
            val retainedModel = review
            compose.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
            assertFalse(retainedModel.state.value.visible)
            assertNull(retainedModel.state.value.review)
            assertNull(retainedModel.state.value.reportId)
            runBlocking {
                LocalEmulatorFixtures(context)
                    .seed(
                        path,
                        fields +
                            ("dsaCase" to
                                (case +
                                    ("decision" to
                                        (decision +
                                            ("factsAndCircumstances" to
                                                "PRIVATE SYNTHETIC AFTER BACKGROUND"))))),
                    )
            }
            compose.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
            compose.waitUntil(30_000) {
                review.state.value.review?.snapshot?.decision?.facts ==
                    "PRIVATE SYNTHETIC AFTER BACKGROUND"
            }
            scroll("dsa-review-list", "dsa-review-facts")
            compose
                .onNodeWithTag("dsa-review-facts")
                .assertTextEquals("PRIVATE SYNTHETIC AFTER BACKGROUND")
            runBlocking {
                LocalEmulatorFixtures(context)
                    .seed(
                        path,
                        fields +
                            ("dsaCase" to
                                (case +
                                    ("decision" to
                                        (decision +
                                            ("factsAndCircumstances" to
                                                "PRIVATE SYNTHETIC AFTER RECREATION"))))),
                    )
            }
            compose.activityRule.scenario.recreate()
            compose.waitUntil(30_000) {
                review.state.value.review?.snapshot?.decision?.facts ==
                    "PRIVATE SYNTHETIC AFTER RECREATION"
            }
            scroll("dsa-review-list", "dsa-review-facts")
            compose
                .onNodeWithTag("dsa-review-facts")
                .assertTextEquals("PRIVATE SYNTHETIC AFTER RECREATION")
            compose.runOnIdle {
                assertTrue(
                    compose.activity.window.attributes.flags and
                        WindowManager.LayoutParams.FLAG_SECURE != 0
                )
            }
            runBlocking {
                val saved =
                    LocalFirebase.firestore(context).document(path).get(Source.SERVER).await()
                assertEquals("closed", saved.getString("status"))
                assertNull(saved.get("dsaCase.appeal"))
                assertTrue(
                    LocalFirebase.firestore(context)
                        .collection("$path/messages")
                        .get(Source.SERVER)
                        .await()
                        .isEmpty
                )
                withContext(Dispatchers.Main) { auth.signOut() }.join()
            }
            compose.waitUntil(15_000) {
                review.state.value.session == null && browse.state.value.route == "profile"
            }
            assertNull(review.state.value.review)
            compose.onNodeWithText("PRIVATE SYNTHETIC UPDATED FACTS").assertDoesNotExist()
            compose.onNodeWithText("PRIVATE SYNTHETIC AFTER BACKGROUND").assertDoesNotExist()
            compose.onNodeWithText("PRIVATE SYNTHETIC AFTER RECREATION").assertDoesNotExist()
            compose.runOnIdle {
                assertEquals(
                    0,
                    compose.activity.window.attributes.flags and
                        WindowManager.LayoutParams.FLAG_SECURE,
                )
            }
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            try {
                runBlocking {
                    val sdk = LocalFirebase.auth(context)
                    if (sdk.currentUser?.uid != user.uid)
                        sdk.signInWithEmailAndPassword(user.email, AccountDeletionFixtures.PASSWORD)
                            .await()
                    AccountDeletionFixtures.clean(user, listOf(path))
                    for (owned in
                        listOf(path, "users/${user.uid}", "publicProfiles/${user.uid}")) assertNull(
                        AccountDeletionFixtures.document(owned)
                    )
                    AccountDeletionFixtures.assertAuthAbsent(user)
                    withContext(Dispatchers.Main) { auth.signOut() }.join()
                }
            } catch (cleanup: Throwable) {
                if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
            }
        }
    }
}
