package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.auth.FirebaseAuthBackend
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.feedback.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real named Android Auth → Firestore transactions/Rules → server read-back, using synthetic users
 * only.
 */
@RunWith(AndroidJUnit4::class)
class FeedbackDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val online
        get() = InstrumentationRegistry.getArguments().getString("expectEmulator") == "true"

    @Test
    fun guestAndLocalProjectBoundary() = runBlocking {
        assertEquals("demo-uac-android", LocalFirebase.auth(context).app.options.projectId)
        expect(FeedbackFailure.SIGN_IN) {
            FeedbackRepository(localFeedbackSource(context), { null }).page(FeedbackAudience.OWN)
        }
    }

    @Test
    fun ownConversationIsAtomicIdempotentAndRulesProtected() = runBlocking {
        if (!online) return@runBlocking
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val store = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
        val repository =
            FeedbackRepository(
                localFeedbackSource(context),
                { store.state.value.feedbackScope() },
                AuthFeedbackMutationGate(store),
            )
        val prefix = "feedback-${UUID.randomUUID()}"
        val email = "$prefix@example.invalid"
        val thread = "$prefix-thread"
        val reply = "$prefix-reply"
        var uid: String? = null
        var phase = "register"
        auth.signOut()
        try {
            AuthEmulatorFixtures.seedLegalReference()
            val user =
                auth
                    .createUserWithEmailAndPassword(email, "Synthetic-feedback-only!")
                    .await()
                    .user!!
            uid = user.uid
            db.document("users/$uid")
                .set(
                    registeredProfileFields(
                        uid,
                        AuthRegistration(
                            email,
                            "Synthetic Feedback Actor",
                            "wien",
                            acceptedTerms = true,
                            acceptedPrivacy = true,
                            minimumAgeConfirmed = true,
                        ),
                        FieldValue.serverTimestamp(),
                    )
                )
                .await()
            withContext(Dispatchers.Main) { store.restore() }.join()
            assertFalse(store.state.value.readyForActions)
            phase = "unverified-owned-page"
            assertTrue(repository.page(FeedbackAudience.OWN).items.isEmpty())
            assertNull(localFeedbackSource(context).item(thread, uid))
            val draft =
                FeedbackDraft(
                    FeedbackType.SUGGESTION,
                    "Synthetic local feedback. No real person or external recipient.",
                )
            expect(FeedbackFailure.NOT_READY) { repository.create(thread, draft) }
            denied {
                db.document("feedback/$thread")
                    .set(
                        FeedbackContract.creation(
                            thread,
                            FeedbackSession(uid, 0, true, false, "Synthetic"),
                            draft,
                            FieldValue.serverTimestamp(),
                        )
                    )
                    .await()
            }

            user.sendEmailVerification().await()
            auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
            user.reload().await()
            user.getIdToken(true).await()
            withContext(Dispatchers.Main) { store.restore() }.join()
            assertTrue(store.state.value.readyForActions)
            phase = "create-and-read-back"
            val created = repository.create(thread, draft)
            assertEquals(thread, created.id)
            assertEquals(uid, created.uid)
            val initial = db.document("feedback/$thread").get(Source.SERVER).await()
            assertEquals("open", initial.getString("status"))
            assertEquals(true, initial.getBoolean("unreadForOwner"))
            assertEquals(false, initial.getBoolean("unreadForUser"))
            assertNotNull(initial.getTimestamp("createdAt"))
            assertEquals(created.createdAt, repository.create(thread, draft).createdAt)
            assertEquals(1, repository.page(FeedbackAudience.OWN).items.size)
            assertTrue(
                db.collection("feedback/$thread/messages").get(Source.SERVER).await().isEmpty
            )

            val text = "A second synthetic message."
            phase = "atomic-reply"
            val conversation = repository.reply(thread, reply, text, FeedbackAudience.OWN)
            assertEquals(2, conversation.messages.size)
            repository.reply(thread, reply, text, FeedbackAudience.OWN)
            val message = db.document("feedback/$thread/messages/$reply").get(Source.SERVER).await()
            val summary = db.document("feedback/$thread").get(Source.SERVER).await()
            assertEquals(message.getTimestamp("createdAt"), summary.getTimestamp("lastMessageAt"))
            assertEquals(message.getTimestamp("createdAt"), summary.getTimestamp("updatedAt"))
            assertEquals(text, summary.getString("lastMessageText"))
            assertEquals(
                1,
                db.collection("feedback/$thread/messages").get(Source.SERVER).await().size(),
            )
            denied { db.document("feedback/$thread").update("message", "Forged original").await() }
            denied { db.document("feedback/$thread").delete().await() }
            denied {
                db.document("feedback/$thread/messages/$reply")
                    .update("text", "Forged reply")
                    .await()
            }
            denied { db.document("feedback/$thread/messages/$reply").delete().await() }
            // A standalone child cannot be created without the matching parent summary in the same
            // transaction.
            denied {
                db.document("feedback/$thread/messages/forged")
                    .set(
                        mapOf(
                            "id" to "forged",
                            "feedbackId" to thread,
                            "senderId" to uid,
                            "senderDisplayName" to "Synthetic",
                            "senderRole" to "user",
                            "text" to "Forged",
                            "createdAt" to FieldValue.serverTimestamp(),
                            "isSystem" to false,
                        )
                    )
                    .await()
            }
            expect(FeedbackFailure.DENIED) { repository.page(FeedbackAudience.MANAGEMENT) }
            expect(FeedbackFailure.DENIED) {
                repository.reply(thread, "close", "Closed", FeedbackAudience.OWN, close = true)
            }

            withContext(Dispatchers.IO) {
                AuthEmulatorFixtures.adminRequest(
                    8088,
                    AuthEmulatorFixtures.documentPath("feedback/$thread") +
                        "?updateMask.fieldPaths=status",
                    "PATCH",
                    mapOf("status" to "closed"),
                )
            }
            phase = "closed-thread"
            expect(FeedbackFailure.CLOSED) {
                repository.reply(thread, "after-close", "Too late", FeedbackAudience.OWN)
            }
            assertEquals(
                FeedbackStatus.CLOSED,
                repository.conversation(thread, FeedbackAudience.OWN).item.status,
            )

            withContext(Dispatchers.Main) { store.signOut() }.join()
            expect(FeedbackFailure.SIGN_IN) {
                repository.conversation(thread, FeedbackAudience.OWN)
            }
            denied { db.document("feedback/$thread").get(Source.SERVER).await() }
        } catch (error: Exception) {
            throw AssertionError("Feedback device phase: $phase", error)
        } finally {
            withContext(Dispatchers.Main) { store.signOut() }.join()
            scope.cancel()
            withContext(Dispatchers.IO) {
                for (path in
                    listOfNotNull(
                        "feedback/$thread/messages/$reply",
                        "feedback/$thread",
                        uid?.let { "users/$it" },
                        uid?.let { "publicProfiles/$it" },
                    )) {
                    runCatching {
                        AuthEmulatorFixtures.adminRequest(
                            8088,
                            AuthEmulatorFixtures.documentPath(path),
                            "DELETE",
                        )
                    }
                }
            }
        }
    }

    private suspend fun expect(expected: FeedbackFailure, block: suspend () -> Unit) {
        try {
            block()
            fail("Expected $expected")
        } catch (error: FeedbackException) {
            assertEquals(expected, error.failure)
        }
    }

    private suspend fun denied(block: suspend () -> Unit) {
        try {
            block()
            fail("Rules must deny this operation")
        } catch (error: FirebaseFirestoreException) {
            assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
        }
    }
}
