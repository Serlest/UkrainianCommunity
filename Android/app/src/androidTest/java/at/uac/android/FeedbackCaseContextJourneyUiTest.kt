package at.uac.android

import android.view.WindowManager
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.feedback.*
import com.google.firebase.firestore.FirebaseFirestoreException
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

@RunWith(AndroidJUnit4::class)
class FeedbackCaseContextJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AccountDeletionFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val feedback
        get() = ViewModelProvider(compose.activity)[FeedbackViewModel::class.java]

    private fun scroll(list: String, tag: String) {
        compose.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
    }

    @Test
    fun actualOwnFeedbackPreservesStoredTimestampAndCannotReadAnotherReporter() {
        AccountDeletionFixtures.requireLocalAvd()
        check(AccountDeletionFixtures.online())
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", "emulator")
            browse.navigate("profile", true)
        }
        val user = runBlocking { AccountDeletionFixtures.create("deletion-dsa-context") }
        val report = "context-${UUID.randomUUID()}"
        val foreign = "context-foreign-${UUID.randomUUID()}"
        val appealMessage = "synthetic-appeal-${UUID.randomUUID()}"
        val appealText = "DSA appeal: SYNTHETIC SERVER-GENERATED REPORTER MESSAGE"
        val paths =
            listOf(
                "feedback/$report",
                "feedback/$foreign",
                "feedback/$report/messages/$appealMessage",
            )
        val acknowledged = Instant.ofEpochSecond(1_788_451_200, 123_456_789)
        var primary: Throwable? = null
        try {
            runBlocking {
                val actor = FeedbackSession(user.uid, 0, true, false, "Synthetic reporter")
                val fields =
                    FeedbackContract.creation(
                        report,
                        actor,
                        FeedbackDraft(FeedbackType.REPORT, "Synthetic initial report"),
                        Instant.now(),
                    ) +
                        mapOf(
                            "dsaCase" to
                                mapOf(
                                    "caseNumber" to "SYNTHETIC REPORTER CASE",
                                    "status" to "submitted",
                                    "category" to "other",
                                    "exactLocation" to "https://invalid.example/local-synthetic",
                                    "illegalExplanation" to
                                        "SYNTHETIC REPORTER PRIVATE EXPLANATION",
                                    "legalBasis" to null,
                                    "evidence" to "SYNTHETIC REPORTER EVIDENCE",
                                    "goodFaithConfirmed" to true,
                                    "acknowledgementAt" to acknowledged,
                                    "preferredLanguage" to "de",
                                )
                        )
                val fixtures = LocalEmulatorFixtures(context)
                fixtures.seed(paths[0], fields)
                fixtures.seed(
                    paths[1],
                    fields + mapOf("id" to foreign, "userId" to "synthetic-other-reporter"),
                )
                // Exact server message shape, not an appeal dispatch or a forged client write.
                fixtures.seed(
                    paths[2],
                    mapOf(
                        "id" to appealMessage,
                        "feedbackId" to report,
                        "senderId" to user.uid,
                        "senderDisplayName" to "Reporter",
                        "senderRole" to "user",
                        "text" to appealText,
                        "createdAt" to Instant.now(),
                        "isSystem" to true,
                    ),
                )
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
            assertFalse(feedback.state.value.page!!.items.any { it.id == foreign })
            scroll("feedback-list", "feedback-item-$report")
            compose.onNodeWithTag("feedback-item-$report").performClick()
            compose.waitUntil(30_000) {
                feedback.state.value.conversation?.item?.id == report &&
                    !feedback.state.value.loading
            }
            assertNull(feedback.state.value.error)
            assertEquals("profile/feedback/$report", browse.state.value.route)
            // Independently read the stored SDK timestamp, not the pre-write fixture value:
            // this local Firestore round-trip stores microseconds, while our Instant decoder
            // must retain every nanosecond actually returned by the SDK.
            val storedTimestamp = runBlocking {
                LocalFirebase.firestore(context)
                    .document(paths[0])
                    .get(Source.SERVER)
                    .await()
                    .getTimestamp("dsaCase.acknowledgementAt")!!
            }
            assertEquals(acknowledged.epochSecond, storedTimestamp.seconds)
            assertEquals(123_456_000, storedTimestamp.nanoseconds)
            assertEquals(
                Instant.ofEpochSecond(
                    storedTimestamp.seconds,
                    storedTimestamp.nanoseconds.toLong(),
                ),
                feedback.state.value.conversation!!.item.caseContext!!.acknowledgementAt,
            )
            scroll("feedback-conversation", "feedback-case-explanation")
            compose
                .onNodeWithTag("feedback-case-explanation")
                .assertTextEquals("SYNTHETIC REPORTER PRIVATE EXPLANATION")
            scroll("feedback-conversation", "feedback-case-evidence")
            val loadedMessage =
                feedback.state.value.conversation!!.messages.single { it.id == appealMessage }
            assertTrue(loadedMessage.system)
            assertFalse(loadedMessage.owner)
            assertEquals(0, feedback.state.value.conversation!!.invalid)
            compose.onNodeWithTag("feedback-conversation").performScrollToNode(hasText(appealText))
            compose.onNodeWithText(appealText).assertIsDisplayed()
            compose.runOnIdle {
                assertTrue(
                    compose.activity.window.attributes.flags and
                        WindowManager.LayoutParams.FLAG_SECURE != 0
                )
            }
            compose.onNodeWithTag("feedback-close").assertDoesNotExist()
            runBlocking {
                assertNull(localFeedbackSource(context).item(foreign, user.uid))
                try {
                    LocalFirebase.firestore(context).document(paths[1]).get(Source.SERVER).await()
                    fail("Another reporter's private parent must be denied")
                } catch (error: FirebaseFirestoreException) {
                    assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
                }
            }
            compose.onNodeWithTag("back").assertIsDisplayed().performClick()
            compose.waitUntil(15_000) {
                browse.state.value.route == "profile/feedback" &&
                    feedback.state.value.selectedId == null
            }
            assertNull(feedback.state.value.conversation)
            compose.onNodeWithTag("feedback-case-explanation").assertDoesNotExist()
            runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
            compose.waitUntil(15_000) { feedback.state.value.session == null }
            assertNull(feedback.state.value.page)
            runBlocking {
                assertEquals(
                    "open",
                    AccountDeletionFixtures.field(
                        AccountDeletionFixtures.document(paths[0])!!,
                        "status",
                    ),
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
                    AccountDeletionFixtures.clean(user, paths.reversed())
                    for (path in
                        paths +
                            listOf("users/${user.uid}", "publicProfiles/${user.uid}")) assertNull(
                        AccountDeletionFixtures.document(path)
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
