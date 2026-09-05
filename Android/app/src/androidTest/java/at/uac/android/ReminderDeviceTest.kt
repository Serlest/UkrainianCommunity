package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalFunctions
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.FirebaseAuthBackend
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.community.CommunityContract
import at.uac.android.feature.inbox.FirestoreInboxSource
import at.uac.android.feature.inbox.InboxPreferences
import at.uac.android.feature.reminders.*
import java.io.File
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real named-local server reads. No NotificationManager fake is presented as native alarm/delivery
 * proof.
 */
@RunWith(AndroidJUnit4::class)
class ReminderDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun freshProfilePreferencesRegistrationAndBlockProofRejectAllStaleTargets() = runBlocking {
        assumeTrue(
            "Requires the explicitly enabled local Auth/Firestore/Functions runtime",
            AccountDeletionFixtures.online(),
        )
        AccountDeletionFixtures.requireLocalAvd()
        val fixtures = LocalEmulatorFixtures(context)
        fixtures.seedLegal()
        val auth = LocalFirebase.auth(context)
        val backend = FirebaseAuthBackend(auth)
        val db = LocalFirebase.firestore(context)
        val prefix = "reminder-${UUID.randomUUID()}"
        val email = "$prefix@example.invalid"
        val eventId = "$prefix-event"
        val organizationId = "$prefix-org"
        val authorId = "$prefix-author"
        val base = Instant.now().truncatedTo(ChronoUnit.MINUTES)
        var clock = base
        val source = LocalReminderSource(db, auth, LocalFunctions.instance(context)) { clock }
        val paths = mutableListOf<String>()
        var uid: String? = null
        var failure: Throwable? = null
        suspend fun remove(path: String) =
            withContext(Dispatchers.IO) {
                check(path in paths)
                AuthEmulatorFixtures.adminRequest(
                    8088,
                    AuthEmulatorFixtures.documentPath(path),
                    "DELETE",
                )
            }
        try {
            backend.signOut()
            val identity =
                backend.create(email, "Synthetic-reminder-Only-Password1!", "Synthetic reminder")
            uid = identity.uid
            paths +=
                listOf(
                    "users/${identity.uid}",
                    "publicProfiles/${identity.uid}",
                    "users/${identity.uid}/notificationPreferences/settings",
                    "events/$eventId",
                    "organizations/$organizationId",
                    "users/${identity.uid}/blockedUsers/$authorId",
                    "users/${identity.uid}/blockedOrganizations/$organizationId",
                )
            FirestoreAuthProfiles(db)
                .create(
                    identity.uid,
                    AuthRegistration(email, "Synthetic reminder", "wien", "", true, true, true),
                )
            val session = ReminderSession(identity.uid, 1, true)
            assertTrue(
                runCatching { source.snapshot(session) { true } }.isFailure
            ) // Optimistic client state cannot verify real email.
            backend.sendVerification("de")
            backend.verifyEmailCode(fixtures.verificationCode(email))
            backend.reload()
            backend.refreshToken()
            val inbox = FirestoreInboxSource(db)
            inbox.savePreferences(identity.uid, InboxPreferences(true, true, 60)) {
                auth.currentUser?.uid == identity.uid
            }
            val registration =
                "registrations/${CommunityContract.registrationId(eventId, identity.uid)}"
                    .also { paths += it }
            val registrationFields =
                mapOf(
                    "id" to registration.substringAfterLast('/'),
                    "userId" to identity.uid,
                    "eventId" to eventId,
                    "registeredAt" to base,
                )
            val eventFields =
                mapOf(
                    "id" to eventId,
                    "sourceType" to "organization",
                    "organizationId" to organizationId,
                    "authorId" to authorId,
                    "moderationStatus" to "approved",
                    "title" to "Synthetic private reminder title",
                    "summary" to "Synthetic summary",
                    "details" to "Synthetic details",
                    "createdAt" to base,
                    "updatedAt" to base,
                    "startDate" to base.plusSeconds(7_200),
                    "endDate" to base.plusSeconds(10_800),
                )
            fixtures.seed(
                "organizations/$organizationId",
                mapOf(
                    "id" to organizationId,
                    "name" to "Synthetic organization",
                    "description" to "Synthetic",
                    "city" to "Wien",
                    "moderationStatus" to "approved",
                    "createdAt" to base,
                    "updatedAt" to base,
                ),
            )
            fixtures.seed("events/$eventId", eventFields)
            fixtures.seed(registration, registrationFields)
            val snapshot = withTimeout(7_000) { source.snapshot(session) { true } }
            assertTrue(snapshot.complete)
            assertEquals(listOf(eventId), snapshot.candidates.map { it.eventId })
            val candidate = snapshot.candidates.single()
            val ticket =
                ReminderTicket(
                    UUID.randomUUID().toString(),
                    reminderOwner(identity.uid),
                    UUID.randomUUID().toString(),
                    eventId,
                    candidate.occurrence,
                    candidate.fireAt,
                )
            clock = ticket.fireAt
            assertEquals(
                eventId,
                withTimeout(7_000) { source.verify(ticket) { true } }.content!!.id,
            )

            remove(registration)
            assertTrue(
                runCatching { withTimeout(7_000) { source.verify(ticket) { true } } }.isFailure
            )
            fixtures.seed(registration, registrationFields)
            inbox.savePreferences(identity.uid, InboxPreferences(false, true, 60)) { true }
            assertTrue(
                runCatching { withTimeout(7_000) { source.verify(ticket) { true } } }.isFailure
            )
            inbox.savePreferences(identity.uid, InboxPreferences(true, true, 60)) { true }

            fixtures.seed(
                "users/${identity.uid}/blockedUsers/$authorId",
                mapOf(
                    "id" to authorId,
                    "targetUserId" to authorId,
                    "displayName" to "Synthetic blocked author",
                    "blockedAt" to base,
                    "updatedAt" to base,
                ),
            )
            assertTrue(
                runCatching { withTimeout(7_000) { source.verify(ticket) { true } } }.isFailure
            )
            remove("users/${identity.uid}/blockedUsers/$authorId")
            fixtures.seed(
                "users/${identity.uid}/blockedOrganizations/$organizationId",
                mapOf(
                    "organizationId" to organizationId,
                    "name" to "Synthetic blocked organization",
                    "blockedAt" to base,
                ),
            )
            assertTrue(
                runCatching { withTimeout(7_000) { source.verify(ticket) { true } } }.isFailure
            )
            remove("users/${identity.uid}/blockedOrganizations/$organizationId")
            fixtures.seed("events/$eventId", eventFields + ("cancellationState" to "cancelled"))
            assertTrue(
                runCatching { withTimeout(7_000) { source.verify(ticket) { true } } }.isFailure
            )
            fixtures.seed("events/$eventId", eventFields)
            assertEquals(
                eventId,
                withTimeout(7_000) { source.verify(ticket) { true } }.content!!.id,
            )
            assertTrue(runCatching { source.verify(ticket) { false } }.isFailure)

            withContext(Dispatchers.IO) {
                AuthEmulatorFixtures.adminRequest(
                    8088,
                    AuthEmulatorFixtures.documentPath("users/${identity.uid}") +
                        "?updateMask.fieldPaths=accountStatus",
                    "PATCH",
                    mapOf("accountStatus" to "bannedPermanent"),
                )
            }
            assertTrue(
                runCatching { withTimeout(7_000) { source.verify(ticket) { true } } }.isFailure
            )
        } catch (error: Throwable) {
            failure = error
            throw error
        } finally {
            suspend fun cleanup(action: suspend () -> Unit) {
                try {
                    action()
                } catch (error: Throwable) {
                    val previous = failure
                    if (previous == null) failure = error else previous.addSuppressed(error)
                }
            }
            cleanup {
                val old = uid
                if (old != null && auth.currentUser?.uid == old) backend.deleteCreatedUser(old)
            }
            cleanup { backend.signOut() }
            paths.asReversed().forEach { path -> cleanup { remove(path) } }
            // Original failure remains primary; a cleanup-only failure must still fail the test.
            failure?.let { throw it }
        }
    }

    @Test
    fun actualAtomicFileReadBackRetainsClaimAcrossReopenAndRejectsCorruption() = runBlocking {
        AccountDeletionFixtures.requireLocalAvd()
        val directory = File(context.noBackupFilesDir, "reminder-ledger-test-${UUID.randomUUID()}")
        val owner = ReminderSession("synthetic-ledger", 1, true)
        val now = Instant.now()
        val snapshot =
            ReminderSnapshot(
                owner,
                InboxPreferences(true, true, 60),
                listOf(
                    ReminderCandidate(
                        "synthetic-event",
                        ReminderOccurrence(
                            "synthetic-occurrence",
                            now.plusSeconds(7_200),
                            now.plusSeconds(10_800),
                        ),
                        now.plusSeconds(3_600),
                    )
                ),
                true,
                now,
            )
        try {
            val first = fileReminderLedger(directory)
            val ticket = first.replace(snapshot) { true }.tickets.single()
            first.finish(ticket, true, ticket.fireAt) { true }
            val reopened = fileReminderLedger(directory)
            assertEquals(ReminderTicketState.CLAIMED, reopened.read().tickets.single().state)
            assertNull(reopened.finish(ticket, true, ticket.fireAt) { true })
            withContext(Dispatchers.IO) {
                File(directory, "plan.bin").writeBytes(byteArrayOf(0, 1, 2))
            }
            assertTrue(runCatching { fileReminderLedger(directory).read() }.isFailure)
        } finally {
            withContext(Dispatchers.IO) {
                check(directory.name.startsWith("reminder-ledger-test-"))
                check(directory.deleteRecursively())
            }
        }
    }
}
