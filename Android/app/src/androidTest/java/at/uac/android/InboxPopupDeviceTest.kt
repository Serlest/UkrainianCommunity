package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.auth.FirebaseAuthBackend
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.inbox.*
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class InboxPopupDeviceTest {
    @Test
    fun liveHeadOnlyPresentsNewNoticeAndActualRulesConfirmPopupAndRead() = runBlocking {
        if (InstrumentationRegistry.getArguments().getString("expectEmulator") != "true") {
            // Disabled-runtime branch; not a positive Firestore/Rules proof.
            assertNull(InboxPopupState().active)
            return@runBlocking
        }
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val db = LocalFirebase.firestore(context)
        val backend = FirebaseAuthBackend(LocalFirebase.auth(context))
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val auth = AuthStore(backend, FirestoreAuthProfiles(db), scope)
        val fixture = LocalEmulatorFixtures(context)
        val email = "popup-${UUID.randomUUID()}@example.invalid"
        val password = "Synthetic-popup-password-1"
        var uid: String? = null
        val ids = listOf("old", "new", "account-status", "legal")
        try {
            withContext(Dispatchers.Main) { auth.signOut() }.join()
            val identity = backend.create(email, password, "Popup test")
            uid = identity.uid
            withContext(Dispatchers.Main) { auth.restore() }.join()
            assertEquals(AuthStage.VERIFICATION_PENDING, auth.state.value.stage)
            val createdAt = Instant.now()
            val base =
                mapOf(
                    "type" to "systemAnnouncement",
                    "createdAt" to createdAt,
                    "isRead" to false,
                    "severity" to "critical",
                    "requiresPopup" to true,
                    "actionType" to "openEvent",
                    "sourceId" to "synthetic-event-01",
                    "title" to "Synthetic popup receipt test",
                    "message" to "Local test only",
                )
            fixture.seed("users/${identity.uid}/notificationInbox/old", base)
            val model =
                InboxPopupViewModel(
                    FirestoreInboxSource(db),
                    { auth.state.value.inboxPopupAccount() },
                    AuthInboxMutationGate(auth),
                    scope,
                )
            withContext(Dispatchers.Main) {
                model.observeAccounts(auth.state.map { it.inboxPopupAccount() })
            }
            withTimeout(20_000) { while (!model.state.value.confirmed) delay(25) }
            assertNull(model.state.value.active)
            fixture.seed(
                "users/${identity.uid}/notificationInbox/account-status",
                base + ("type" to "accountStatusChanged"),
            )
            fixture.seed(
                "users/${identity.uid}/notificationInbox/legal",
                base + ("type" to "legalDocumentsUpdated"),
            )
            fixture.seed(
                "users/${identity.uid}/notificationInbox/new",
                base + ("createdAt" to createdAt.plusSeconds(1)),
            )
            withTimeout(20_000) { while (model.state.value.active?.id != "new") delay(25) }
            val before = model.state.value
            withContext(Dispatchers.Main) { auth.restore() }.join()
            assertNull(before.forAccount(auth.state.value.inboxPopupAccount()).active)
            withTimeout(20_000) {
                while (!model.state.value.confirmed || model.state.value.active?.id != "new") delay(
                    25
                )
            }
            withContext(Dispatchers.Main) { model.dismiss("new", open = true)!! }.join()
            val action = model.state.value.action!!
            assertEquals(identity.uid, action.session.uid)
            assertEquals(
                InboxDestination(InboxDestinationKind.EVENT, "synthetic-event-01"),
                action.destination,
            )
            assertNull(model.state.value.error)
            val receipt =
                db.document("users/${identity.uid}/notificationInbox/new")
                    .get(Source.SERVER)
                    .await()
            assertFalse(receipt.metadata.isFromCache)
            assertFalse(receipt.metadata.hasPendingWrites())
            assertNotNull(receipt.getTimestamp("popupPresentedAt"))
            assertNotNull(receipt.getTimestamp("readAt"))
            assertEquals(true, receipt.getBoolean("isRead"))
            assertEquals(base["title"], receipt.getString("title"))
            assertEquals(base["message"], receipt.getString("message"))
            assertEquals(base["sourceId"], receipt.getString("sourceId"))
            assertEquals(base["severity"], receipt.getString("severity"))
            assertEquals(
                createdAt.plusSeconds(1).epochSecond,
                receipt.getTimestamp("createdAt")!!.seconds,
            )
            withContext(Dispatchers.Main) { auth.signOut() }.join()
            assertNull(withContext(Dispatchers.Main) { model.takeAction(action.sequence) })
            assertNull(model.state.value.forAccount(auth.state.value.inboxPopupAccount()).active)
        } finally {
            scope.cancel()
            val ownUid = uid
            if (ownUid != null && backend.current == null) backend.signIn(email, password)
            if (ownUid != null && backend.current?.uid == ownUid) backend.deleteCreatedUser(ownUid)
            backend.signOut()
            if (ownUid != null)
                withContext(Dispatchers.IO) {
                    ids.forEach { id ->
                        AuthEmulatorFixtures.adminRequest(
                            8088,
                            AuthEmulatorFixtures.documentPath(
                                "users/$ownUid/notificationInbox/$id"
                            ),
                            "DELETE",
                        )
                    }
                }
        }
    }
}
