package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.inbox.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.time.Instant
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

@RunWith(AndroidJUnit4::class)
class InboxDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val online
        get() = InstrumentationRegistry.getArguments().getString("expectEmulator") == "true"

    private val fixtures
        get() = LocalEmulatorFixtures(context)

    @Test
    fun actualInboxRulesReadbackAndAccountGatesOrOfflineGuest() = runBlocking {
        val db = LocalFirebase.firestore(context)
        val auth = LocalFirebase.auth(context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val store = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
        val repository =
            InboxRepository(
                FirestoreInboxSource(db),
                { store.state.value.inboxScope() },
                AuthInboxMutationGate(store),
            )
        try {
            withContext(Dispatchers.Main) { store.signOut() }.join()
            if (!online) {
                try {
                    repository.page()
                    fail("Guest read")
                } catch (error: InboxException) {
                    assertEquals(InboxFailure.SIGN_IN, error.reason)
                }
                return@runBlocking
            }
            fixtures.seedLegal()
            val email = "inbox3d-${UUID.randomUUID()}@example.invalid"
            val password = "Synthetic-inbox-3D-only!"
            val user = auth.createUserWithEmailAndPassword(email, password).await().user!!
            val uid = user.uid
            val registration =
                AuthRegistration(
                    email,
                    "Inbox Demo",
                    "wien",
                    acceptedTerms = true,
                    acceptedPrivacy = true,
                    minimumAgeConfirmed = true,
                )
            db.document("users/$uid")
                .set(registeredProfileFields(uid, registration, FieldValue.serverTimestamp()))
                .await()
            val timestamp = Instant.now()
            val base =
                mapOf(
                    "type" to "eventUpdated",
                    "sourceType" to "event",
                    "sourceId" to "synthetic-event-01",
                    "createdAt" to timestamp,
                    "isRead" to false,
                    "archivedAt" to null,
                    "deletedAt" to null,
                    "title" to "Synthetic inbox fixture",
                    "message" to "Test only",
                )
            fixtures.seed("users/$uid/notificationInbox/one", base)
            fixtures.seed(
                "users/$uid/notificationInbox/archived",
                base + ("archivedAt" to timestamp),
            )
            fixtures.seed("users/$uid/notificationInbox/deleted", base + ("deletedAt" to timestamp))
            fixtures.seed("users/synthetic-inbox-foreign/notificationInbox/foreign", base)
            withContext(Dispatchers.Main) { store.restore() }.join()
            assertEquals(AuthStage.VERIFICATION_PENDING, store.state.value.stage)
            assertEquals(1L, repository.unreadCount())
            assertEquals(setOf("one", "archived"), repository.page().items.map { it.id }.toSet())
            val one = repository.page().items.first { it.id == "one" }
            // Status/legal messages must remain manageable even before email verification.
            repository.mutate(one, InboxMutation.READ)
            val reference = db.document("users/$uid/notificationInbox/one")
            var confirmed = reference.get(Source.SERVER).await()
            assertEquals(true, confirmed.getBoolean("isRead"))
            assertNotNull(confirmed.getTimestamp("readAt"))
            assertEquals(0L, repository.unreadCount())
            repository.mutate(one, InboxMutation.UNREAD)
            confirmed = reference.get(Source.SERVER).await()
            assertEquals(false, confirmed.getBoolean("isRead"))
            assertFalse(confirmed.contains("readAt"))
            repository.mutate(one, InboxMutation.POPUP_PRESENTED)
            assertNotNull(reference.get(Source.SERVER).await().getTimestamp("popupPresentedAt"))
            try {
                repository.savePreferences(InboxPreferences(true))
                fail("Unverified settings")
            } catch (error: InboxException) {
                assertEquals(InboxFailure.NOT_READY, error.reason)
            }
            assertDenied {
                db.document("users/$uid/notificationPreferences/settings")
                    .set(
                        mapOf(
                            "notificationsEnabled" to true,
                            "eventRemindersEnabled" to true,
                            "reminderLeadMinutes" to 60,
                            "updatedAt" to FieldValue.serverTimestamp(),
                        )
                    )
                    .await()
            }
            assertDenied {
                db.document("users/synthetic-inbox-foreign/notificationInbox/foreign")
                    .get(Source.SERVER)
                    .await()
            }
            assertDenied { reference.update("title", "Forged content").await() }
            assertDenied {
                db.document("users/$uid/notificationInbox/forged")
                    .set(mapOf("isRead" to false))
                    .await()
            }
            assertDenied { reference.delete().await() }

            user.sendEmailVerification().await()
            val code = fixtures.verificationCode(email)
            withContext(Dispatchers.Main) { store.applyVerificationCode(code)!! }.join()
            assertTrue(store.state.value.readyForActions)
            assertEquals(InboxPreferences(), repository.preferences())
            assertEquals(
                InboxPreferences(true, false, 15),
                repository.savePreferences(InboxPreferences(true, false, 15)),
            )
            val preferences =
                db.document("users/$uid/notificationPreferences/settings")
                    .get(Source.SERVER)
                    .await()
            assertNotNull(preferences.getTimestamp("updatedAt"))
            assertEquals(
                setOf(
                    "notificationsEnabled",
                    "eventRemindersEnabled",
                    "reminderLeadMinutes",
                    "updatedAt",
                ),
                preferences.data!!.keys,
            )
            assertDenied { preferences.reference.update("reminderLeadMinutes", 10_081).await() }
            assertDenied { preferences.reference.update("extra", true).await() }
            repository.mutate(one, InboxMutation.ARCHIVE)
            assertTrue(repository.page().items.any { it.id == "one" })
            assertEquals(0L, repository.unreadCount())
            assertNotNull(reference.get(Source.SERVER).await().getTimestamp("archivedAt"))
            assertEquals(InboxBulkResult(2, true), repository.mutateAll(InboxMutation.DELETE))
            assertTrue(repository.page().items.isEmpty())
            confirmed = reference.get(Source.SERVER).await()
            assertNotNull(confirmed.getTimestamp("deletedAt"))
            assertEquals("Synthetic inbox fixture", confirmed.getString("title"))
            withContext(Dispatchers.Main) { store.signOut() }.join()
            try {
                repository.mutate(one, InboxMutation.READ)
                fail("Logged-out write")
            } catch (error: InboxException) {
                assertEquals(InboxFailure.SIGN_IN, error.reason)
            }
        } finally {
            withContext(Dispatchers.Main) { store.signOut() }.join()
            scope.cancel()
        }
    }

    private suspend fun assertDenied(operation: suspend () -> Unit) {
        try {
            operation()
            fail("Expected Rules denial")
        } catch (error: FirebaseFirestoreException) {
            assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
        }
    }
}
