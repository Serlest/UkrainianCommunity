package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.attendees.*
import at.uac.android.feature.auth.*
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AttendeesDeviceTest {
    private val context
        get() = AccountDeletionFixtures.context

    private suspend fun denied(action: suspend () -> Any?) {
        try {
            action()
            fail("The unchanged Rules must deny this direct request")
        } catch (error: FirebaseFirestoreException) {
            assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
        }
    }

    private suspend fun failure(expected: AttendeesFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: AttendeesException) {
            assertEquals(expected, error.failure)
        }
    }

    @Test
    fun realRulesManagedPaginationPublicJoinAndRoleLossOrLocalGuard() = runBlocking {
        AccountDeletionFixtures.requireLocalAvd()
        if (!AccountDeletionFixtures.online()) {
            failure(AttendeesFailure.SIGN_IN) {
                AttendeesRepository(localAttendeesSource(context)) { null }.load("synthetic-event")
            }
            return@runBlocking
        }
        AuthEmulatorFixtures.seedLegalReference()
        val user = AccountDeletionFixtures.create("deletion-attendees")
        val fixture = AttendeesDeviceFixtures("attendees-${UUID.randomUUID()}", user.uid)
        val db = LocalFirebase.firestore(context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        var primaryFailure: Throwable? = null
        try {
            fixture.seedEventAndOrganization(31)
            for (index in 0..30) fixture.seedPerson(
                index,
                dated = index != 30,
                publicProfile = index != 30,
            )
            val store =
                AuthStore(
                    FirebaseAuthBackend(LocalFirebase.auth(context)),
                    FirestoreAuthProfiles(db),
                    scope,
                )
            withContext(Dispatchers.Main) { store.restore() }.join()
            val session = store.state.value.attendeesScope()!!
            assertTrue(session.ready)
            val source = localAttendeesSource(context)
            val repository = AttendeesRepository(source) { store.state.value.attendeesScope() }
            val first = repository.load(fixture.eventId)
            assertEquals(25, first.people.size)
            assertNotNull(first.next)
            assertEquals(0, first.invalid)
            val complete = repository.load(fixture.eventId, first)
            assertEquals(31, complete.people.size)
            assertNull(complete.next)
            assertEquals(0, complete.invalid)
            val legacy = complete.people.single { it.userId == fixture.personId(30) }
            assertNull(legacy.registeredAt)
            assertNull(legacy.displayName)
            assertNull(legacy.avatarUrl)
            assertEquals(
                "Synthetic public attendee 00",
                complete.people.single { it.userId == fixture.personId(0) }.displayName,
            )
            assertEquals(
                fixture.time,
                complete.people.single { it.userId == fixture.personId(0) }.registeredAt,
            )
            // Event managers receive no additional access to private user documents and cannot
            // mutate registration records.
            denied { db.document("users/${fixture.personId(0)}").get(Source.SERVER).await() }
            denied { db.document(fixture.registrationPath(0)).delete().await() }
            assertEquals(
                31L,
                db.document("events/${fixture.eventId}")
                    .get(Source.SERVER)
                    .await()
                    .getLong("registeredCount"),
            )
            assertEquals(
                fixture.personId(0),
                fixture
                    .read(fixture.registrationPath(0))
                    .getJSONObject("fields")
                    .getJSONObject("userId")
                    .getString("stringValue"),
            )

            fixture.patch(
                "organizations/${fixture.organizationId}",
                mapOf("ownerId" to "synthetic-foreign-owner"),
            )
            failure(AttendeesFailure.DENIED) { repository.load(fixture.eventId) }
            // Skip only the optional iOS UI preflight: server Rules independently deny the same
            // stale manager query.
            failure(AttendeesFailure.DENIED) {
                source.registrations(fixture.eventId, null, session)
            }
            fixture.patch(
                "organizations/${fixture.organizationId}",
                mapOf("adminIds" to listOf(user.uid)),
            )
            assertEquals(25, repository.load(fixture.eventId).people.size)
            fixture.patch(
                "organizations/${fixture.organizationId}",
                mapOf("adminIds" to emptyList<String>(), "moderatorIds" to listOf(user.uid)),
            )
            assertEquals(25, repository.load(fixture.eventId).people.size)
        } catch (error: Throwable) {
            primaryFailure = error
            throw error
        } finally {
            scope.cancel()
            cleanup(fixture, user, primaryFailure)
        }
    }

    @Test
    fun offlineRestrictedMfaAndForeignIdentityCannotReadPrivateAttendeesOrLocalGuard() =
        runBlocking {
            AccountDeletionFixtures.requireLocalAvd()
            if (!AccountDeletionFixtures.online()) {
                failure(AttendeesFailure.NOT_READY) {
                    AttendeesRepository(localAttendeesSource(context)) {
                            AttendeesSession("synthetic", 1, false, "user")
                        }
                        .load("synthetic-event")
                }
                return@runBlocking
            }
            AuthEmulatorFixtures.seedLegalReference()
            val user = AccountDeletionFixtures.create("deletion-attendee-gates")
            val fixture = AttendeesDeviceFixtures("attendees-${UUID.randomUUID()}", user.uid)
            val auth = LocalFirebase.auth(context)
            val db = LocalFirebase.firestore(context)
            val source = localAttendeesSource(context)
            val session = AttendeesSession(user.uid, 1, true, "user")
            var primaryFailure: Throwable? = null
            try {
                fixture.seedEventAndOrganization(1)
                fixture.seedPerson(0)
                assertEquals(1, source.registrations(fixture.eventId, null, session).rows.size)
                db.disableNetwork().await()
                try {
                    failure(AttendeesFailure.OFFLINE) {
                        source.registrations(fixture.eventId, null, session)
                    }
                } finally {
                    db.enableNetwork().await()
                }
                fixture.patch(
                    "users/${user.uid}",
                    mapOf("accountStatus" to "deactivated", "blockState" to "deactivated"),
                )
                // A client ready flag cannot bypass an actual server-side restriction.
                failure(AttendeesFailure.DENIED) {
                    source.registrations(fixture.eventId, null, session)
                }
                fixture.patch(
                    "users/${user.uid}",
                    mapOf(
                        "accountStatus" to "active",
                        "blockState" to "active",
                        "globalRole" to "admin",
                        "requiresMultiFactorAuth" to true,
                    ),
                )
                auth.currentUser!!.getIdToken(true).await()
                failure(AttendeesFailure.DENIED) {
                    source.registrations(fixture.eventId, null, session)
                }
                fixture.patch(
                    "users/${user.uid}",
                    mapOf("globalRole" to "user", "requiresMultiFactorAuth" to false),
                )
                assertEquals(1, source.registrations(fixture.eventId, null, session).rows.size)
                auth.signOut()
                try {
                    source.registrations(fixture.eventId, null, session)
                    fail("Old identity accepted")
                } catch (_: CancellationException) {}
            } catch (error: Throwable) {
                primaryFailure = error
                throw error
            } finally {
                cleanup(fixture, user, primaryFailure)
            }
        }

    private suspend fun cleanup(
        fixture: AttendeesDeviceFixtures,
        user: AccountDeletionFixtures.User,
        primary: Throwable?,
    ) {
        var failure = primary
        suspend fun attempt(action: suspend () -> Unit) {
            try {
                action()
            } catch (error: Throwable) {
                if (failure == null) failure = error else failure!!.addSuppressed(error)
            }
        }
        attempt { LocalFirebase.firestore(context).enableNetwork().await() }
        attempt { fixture.cleanup() }
        attempt {
            // Only this exact new synthetic account is reacquired for explicit fixture cleanup.
            val auth = LocalFirebase.auth(context)
            if (auth.currentUser?.uid != user.uid)
                auth
                    .signInWithEmailAndPassword(user.email, AccountDeletionFixtures.PASSWORD)
                    .await()
            AccountDeletionFixtures.clean(user)
        }
        if (primary == null) failure?.let { throw it }
    }
}
