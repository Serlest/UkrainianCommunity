package at.uac.android

import android.graphics.Bitmap
import android.util.Log
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.feedback.*
import at.uac.android.feature.inbox.InboxViewModel
import com.google.firebase.firestore.Source
import java.io.File
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

/** The actual application: compose a request, reply, open from inbox, and switch accounts. */
@RunWith(AndroidJUnit4::class)
class FeedbackJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val feedback
        get() = ViewModelProvider(compose.activity)[FeedbackViewModel::class.java]

    private val inbox
        get() = ViewModelProvider(compose.activity)[InboxViewModel::class.java]

    private val auth
        get() = LocalAuthSession.get(context)

    private val fixtures
        get() = LocalEmulatorFixtures(context)

    private fun scroll(list: String, tag: String) {
        compose.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performScrollTo()
    }

    private fun waitForRead(id: String? = null) =
        compose.waitUntil(20_000) {
            feedback.state.value.selectedId == id &&
                !feedback.state.value.loading &&
                (feedback.state.value.page != null ||
                    feedback.state.value.conversation != null ||
                    feedback.state.value.error != null)
        }

    @Test
    fun ownRequestReplyInboxDestinationAndAccountIsolationOrGuestGate() {
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "uk")
            browse.navigate("profile", true)
        }
        compose.waitUntil(15_000) { auth.state.value.stage == AuthStage.GUEST }
        if (InstrumentationRegistry.getArguments().getString("expectEmulator") != "true") {
            compose.onNodeWithTag("account-open-feedback").assertDoesNotExist()
            assertNull(feedback.state.value.session)
            return
        }
        try {
            val uid = prepare("first")
            compose.onNodeWithTag("account-open-feedback").performScrollTo().performClick()
            waitForRead()
            assertNull(feedback.state.value.error)
            val first = "Синтетичне звернення: хочу запропонувати корисну функцію."
            scroll("feedback-list", "feedback-draft")
            compose.onNodeWithTag("feedback-draft").performTextReplacement(first)
            scroll("feedback-list", "feedback-submit")
            compose.onNodeWithTag("feedback-submit").performClick()
            compose.waitUntil(20_000) {
                !feedback.state.value.pending &&
                    (feedback.state.value.confirmedId != null ||
                        feedback.state.value.actionError != null)
            }
            assertNull(feedback.state.value.actionError)
            val id = feedback.state.value.confirmedId!!
            runBlocking {
                val saved =
                    LocalFirebase.firestore(context)
                        .document("feedback/$id")
                        .get(Source.SERVER)
                        .await()
                assertEquals(uid, saved.getString("userId"))
                assertEquals(first, saved.getString("message"))
            }
            scroll("feedback-list", "feedback-open-confirmed")
            compose.onNodeWithTag("feedback-open-confirmed").performClick()
            waitForRead(id)
            assertNull(feedback.state.value.error)
            assertEquals("profile/feedback/$id", browse.state.value.route)
            val reply = "Додаткове уточнення. Без реальних персональних даних."
            scroll("feedback-conversation", "feedback-reply")
            compose.onNodeWithTag("feedback-reply").performTextReplacement(reply)
            scroll("feedback-conversation", "feedback-send")
            compose.onNodeWithTag("feedback-send").performClick()
            compose.waitUntil(20_000) {
                !feedback.state.value.pending &&
                    (feedback.state.value.conversation?.messages?.any { it.text == reply } ==
                        true || feedback.state.value.actionError != null)
            }
            assertNull(feedback.state.value.actionError)
            runBlocking {
                val db = LocalFirebase.firestore(context)
                assertEquals(
                    1,
                    db.collection("feedback/$id/messages").get(Source.SERVER).await().size(),
                )
                assertEquals(
                    reply,
                    db.document("feedback/$id")
                        .get(Source.SERVER)
                        .await()
                        .getString("lastMessageText"),
                )
                fixtures.seed(
                    "users/$uid/notificationInbox/feedback-journey",
                    mapOf(
                        "type" to "feedbackReply",
                        "actionType" to "openFeedback",
                        "sourceType" to "feedback",
                        "sourceId" to id,
                        "actionTargetId" to id,
                        "createdAt" to Instant.now(),
                        "title" to "Синтетичне повідомлення підтримки",
                        "message" to "Перехід до власного звернення",
                        "isRead" to false,
                        "archivedAt" to null,
                        "deletedAt" to null,
                    ),
                )
            }
            screenshot("feedback-journey-conversation.png")
            compose.onNodeWithTag("back").performClick()
            compose.onNodeWithTag("back").performClick()
            compose.onNodeWithTag("account-open-inbox").performScrollTo().performClick()
            compose.waitUntil(20_000) {
                inbox.state.value.items.any { it.id == "feedback-journey" }
            }
            scroll("inbox-list", "inbox-details-feedback-journey")
            compose.onNodeWithTag("inbox-details-feedback-journey").performClick()
            // Expanding an unread item starts an asynchronous READ and temporarily disables Open.
            // Wait for its own receipt/read-back before the one real navigation click.
            compose.waitUntil(20_000) {
                !inbox.state.value.mutating &&
                    (inbox.state.value.error != null ||
                        inbox.state.value.items.any { it.id == "feedback-journey" && it.isRead })
            }
            assertNull("The detail READ must settle successfully", inbox.state.value.error)
            scroll("inbox-list", "inbox-open-feedback-journey")
            fun navigationState(): String {
                val current = feedback.state.value
                val notice = inbox.state.value.items.find { it.id == "feedback-journey" }
                return "expectedRoute=${browse.state.value.route == "profile/feedback/$id"}," +
                    "inboxRoute=${browse.state.value.route == "profile/inbox"}," +
                    "selectedMatches=${current.selectedId == id},conversationMatches=${current.conversation?.item?.id == id}," +
                    "loading=${current.loading},error=${current.error},actionError=${current.actionError}," +
                    "inboxMutating=${inbox.state.value.mutating},inboxLoading=${inbox.state.value.loading}," +
                    "inboxError=${inbox.state.value.error},noticePresent=${notice != null},noticeUnread=${notice?.unread}," +
                    "authReady=${auth.state.value.readyForActions},sessionMatches=${current.session == auth.state.value.feedbackScope()}"
            }
            val clickEnabled =
                compose
                    .onNodeWithTag("inbox-open-feedback-journey")
                    .fetchSemanticsNode()
                    .config
                    .getOrNull(SemanticsProperties.Disabled) == null
            Log.i(
                "UACJourneyTrace",
                "feedback before-single-open enabled=$clickEnabled ${navigationState()}",
            )
            compose.onNodeWithTag("inbox-open-feedback-journey").assertIsEnabled().performClick()
            var lastNavigationState = ""
            try {
                compose.waitUntil(20_000) {
                    val trace = navigationState()
                    if (trace != lastNavigationState) {
                        Log.i("UACJourneyTrace", "feedback after-single-open $trace")
                        lastNavigationState = trace
                    }
                    browse.state.value.route == "profile/feedback/$id" &&
                        feedback.state.value.conversation?.item?.id == id
                }
            } catch (failure: Throwable) {
                Log.i("UACJourneyTrace", "feedback navigation-timeout ${navigationState()}")
                runCatching { screenshot("feedback-journey-navigation-timeout.png") }
                throw failure
            }
            compose.onNodeWithTag("back").performClick()
            compose.onNodeWithTag("back").performClick()
            compose.onNodeWithTag("auth-signout").performScrollTo().performClick()
            compose.waitUntil(15_000) {
                auth.state.value.stage == AuthStage.GUEST && feedback.state.value.session == null
            }
            assertNull(feedback.state.value.conversation)
            assertNull(feedback.state.value.page)
            val other = prepare("second")
            assertNotEquals(uid, other)
            compose.onNodeWithTag("account-open-feedback").performScrollTo().performClick()
            waitForRead()
            assertNull(feedback.state.value.error)
            assertTrue(feedback.state.value.page!!.items.isEmpty())
            // A stale notification/deep link does not grant access to another user's private
            // thread.
            compose.runOnIdle { browse.navigate("profile/feedback/$id") }
            waitForRead(id)
            assertNull(feedback.state.value.conversation)
            assertTrue(
                feedback.state.value.error in setOf(FeedbackFailure.MISSING, FeedbackFailure.DENIED)
            )
            compose.onNodeWithText(first).assertDoesNotExist()
        } finally {
            runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        }
    }

    private fun prepare(suffix: String): String = runBlocking {
        fixtures.seedLegal()
        val email = "feedback-journey-$suffix-${UUID.randomUUID()}@example.invalid"
        val password = "Synthetic-feedback-journey-only!"
        withContext(Dispatchers.Main) {
                auth.register(
                    AuthRegistration(
                        email,
                        "Feedback Journey $suffix",
                        "wien",
                        acceptedTerms = true,
                        acceptedPrivacy = true,
                        minimumAgeConfirmed = true,
                    ),
                    password,
                    password,
                    "uk",
                )!!
            }
            .join()
        assertEquals(AuthStage.VERIFICATION_PENDING, auth.state.value.stage)
        val code = fixtures.verificationCode(email)
        withContext(Dispatchers.Main) { auth.applyVerificationCode(code)!! }.join()
        assertTrue(auth.state.value.readyForActions)
        auth.state.value.identity!!.uid
    }

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val bitmap =
            InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
                ?: error("Screenshot unavailable")
        File(context.externalCacheDir, name).outputStream().use {
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
        }
    }
}
