package at.uac.android

import android.app.Notification
import android.app.NotificationManager
import android.os.Process
import android.util.AtomicFile
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.FirebaseAuthBackend
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.community.CommunityContract
import at.uac.android.feature.inbox.FirestoreInboxSource
import at.uac.android.feature.inbox.InboxPreferences
import at.uac.android.feature.reminders.*
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Phased real-AlarmManager proof. There is intentionally no ActivityRule and no manually delivered
 * broadcast. Prepare leaves exactly one synthetic fixture and signed-in SDK identity for the
 * root-controlled cold phase. Root must prove process absence without force-stop, observe actual
 * alarm dispatch, and invoke inspect/cleanup.
 */
@RunWith(AndroidJUnit4::class)
class ReminderColdDeviceTest {
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val context
        get() = instrumentation.targetContext

    private val arguments
        get() = InstrumentationRegistry.getArguments()

    private val manager
        get() = context.getSystemService(NotificationManager::class.java)

    private val ledger
        get() = fileReminderLedger(File(context.noBackupFilesDir, "event-reminders-v1"))

    private val markerFile
        get() = AtomicFile(File(context.noBackupFilesDir, "u15-cold-reminder-test.bin"))

    private val password = "Synthetic-cold-reminder-Only1!"

    private enum class Mode {
        POSITIVE,
        SUPPRESSION,
    }

    private data class Marker(
        val suffix: String,
        val uid: String,
        val mode: Mode,
        val preparingPid: Int,
        val fireAt: Instant,
        val epoch: String = "",
        val token: String = "",
    ) {
        val eventId
            get() = "reminder-cold-$suffix"

        val organizationId
            get() = "reminder-cold-org-$suffix"

        val email
            get() = "reminder-cold-$suffix@example.invalid"

        val start
            get() = fireAt.plusSeconds(3_600)

        val end
            get() = start.plusSeconds(3_600)

        val registrationId
            get() = CommunityContract.registrationId(eventId, uid)

        fun paths() =
            listOf(
                "users/$uid",
                "publicProfiles/$uid",
                "users/$uid/notificationPreferences/settings",
                "organizations/$organizationId",
                "events/$eventId",
                "registrations/$registrationId",
            )

        fun valid(): Boolean =
            runCatching { UUID.fromString(suffix).toString() == suffix }.getOrDefault(false) &&
                uid.matches(Regex("[A-Za-z0-9_-]{1,128}")) &&
                preparingPid > 0 &&
                fireAt.nano == 0 &&
                (epoch.isEmpty() && token.isEmpty() ||
                    reminderOpaque(epoch) && reminderOpaque(token))
    }

    @Test
    fun a_prepareColdPositive() = runBlocking {
        requirePhase("prepare-positive")
        prepare(Mode.POSITIVE)
    }

    @Test
    fun b_prepareColdDozeSuppression() = runBlocking {
        requirePhase("prepare-suppression")
        assertEquals(
            "Doze phases require a second explicit opt-in",
            "true",
            arguments.getString("expectReminderDoze"),
        )
        prepare(Mode.SUPPRESSION)
    }

    @Test
    fun c_inspectColdPositive() = runBlocking {
        requirePhase("inspect-positive")
        inspect(Mode.POSITIVE)
    }

    @Test
    fun d_inspectColdDozeSuppression() = runBlocking {
        requirePhase("inspect-suppression")
        assertEquals(
            "Doze observation belongs to root and must precede inspection",
            "true",
            arguments.getString("expectReminderDoze"),
        )
        inspect(Mode.SUPPRESSION)
    }

    @Test
    fun e_restoreRegistrationAndConfirmNoReplay() = runBlocking {
        requirePhase("restore-no-replay")
        val marker = readMarker()
        check(marker.mode == Mode.SUPPRESSION && marker.epoch.isNotEmpty())
        val previous = ledger.read()
        val consumed = matchingTicket(previous, marker)
        assertEquals(ReminderTicketState.SUPPRESSED, consumed.state)
        assertEquals(1, previous.receipts.count { it.key == consumed.key })
        assertTrue(
            "The same occurrence must still have a genuinely future shorter-lead trigger",
            Instant.now() < marker.start.minusSeconds(15 * 60L),
        )
        check(LocalFirebase.auth(context).currentUser?.uid == marker.uid)
        LocalEmulatorFixtures(context)
            .seed("registrations/${marker.registrationId}", registration(marker))
        FirestoreInboxSource(LocalFirebase.firestore(context)).savePreferences(
            marker.uid,
            InboxPreferences(true, true, 15),
        ) {
            LocalFirebase.auth(context).currentUser?.uid == marker.uid
        }
        // This explicit recovery/reconcile phase may construct AuthStore; the cold inspector below
        // never does.
        val auth = LocalAuthSession.get(context)
        withContext(Dispatchers.Main) { auth.restore() }.join()
        check(auth.state.value.readyForActions && auth.state.value.identity?.uid == marker.uid)
        val runtime = LocalReminders.get(context)
        runtime.attachAuth { auth.state.value }
        withContext(Dispatchers.Main) {
            runtime.controller.bindAuth(auth.state.value)
            runtime.controller.reconcile()
        }
        val state =
            withTimeout(25_000) {
                runtime.controller.state.first {
                    it.stage in setOf(ReminderStage.SCHEDULED, ReminderStage.FAILED)
                }
            }
        assertEquals(ReminderStage.SCHEDULED, state.stage)
        assertEquals(0, state.scheduled)
        val fresh = ledger.read()
        assertEquals(1, fresh.receipts.count { it.key == consumed.key })
        assertTrue(
            fresh.tickets.none { it.key == consumed.key && it.state == ReminderTicketState.PENDING }
        )
        assertTrue(ownNotifications().isEmpty())
        System.out.println(
            "ReminderColdTrace phase=no_replay futureCandidateEligible=true matchingReceipts=1 scheduledCount=0 postedCount=0"
        )
    }

    @Test
    fun f_cleanupPreparedPhase() = runBlocking {
        requirePhase("cleanup")
        cleanup(readMarker())
        assertFalse(markerFile.baseFile.exists())
        assertTrue(ownNotifications().isEmpty())
        System.out.println(
            "ReminderColdTrace phase=cleanup markerAbsent=true postedCount=0 exactFixturesRemoved=true"
        )
    }

    private fun requirePhase(phase: String) {
        assumeTrue(
            "Cold reminder phases require explicit method-specific opt-in; a skip proves nothing",
            arguments.getString("expectLocalReminders") == "true" &&
                arguments.getString("expectReminderCold") == "true" &&
                arguments.getString("reminderColdPhase") == phase,
        )
        AccountDeletionFixtures.requireLocalAvd()
        assertTrue(
            "Only the explicitly enabled demo Auth/Firestore/Functions runtime is allowed",
            AccountDeletionFixtures.online(),
        )
    }

    private suspend fun prepare(mode: Mode) {
        check(!markerFile.baseFile.exists() && !File(markerFile.baseFile.path + ".bak").exists()) {
            "A prior cold-reminder fixture requires exact cleanup before another preparation"
        }
        val sink = AndroidReminderNotifications(context)
        assertEquals(
            "Root must first obtain this AVD package's permission through its explicit UI",
            ReminderPermission.ALLOWED,
            sink.permission(),
        )
        assertTrue("Do not replace another fixture's notification", ownNotifications().isEmpty())
        check(
            ledger.read().tickets.none {
                it.state == ReminderTicketState.PENDING || it.state == ReminderTicketState.CLAIMED
            }
        )
        val auth = LocalAuthSession.get(context)
        withContext(Dispatchers.Main) { auth.signOut() }.join()
        val fixtures = LocalEmulatorFixtures(context)
        fixtures.seedLegal()
        val suffix = UUID.randomUUID().toString()
        val email = "reminder-cold-$suffix@example.invalid"
        val backend = FirebaseAuthBackend(LocalFirebase.auth(context))
        var marker: Marker? = null
        try {
            val created = backend.create(email, password, "Synthetic cold reminder")
            val owned =
                Marker(
                        suffix,
                        created.uid,
                        mode,
                        Process.myPid(),
                        Instant.now().truncatedTo(ChronoUnit.MINUTES).plusSeconds(240),
                    )
                    .also { marker = it }
            writeMarker(owned)
            FirestoreAuthProfiles(LocalFirebase.firestore(context))
                .create(
                    created.uid,
                    AuthRegistration(
                        email,
                        "Synthetic cold reminder",
                        "wien",
                        "",
                        true,
                        true,
                        true,
                    ),
                )
            backend.sendVerification("de")
            backend.verifyEmailCode(fixtures.verificationCode(email))
            backend.reload()
            backend.refreshToken()
            backend.signOut()
            withContext(Dispatchers.Main) { checkNotNull(auth.signIn(email, password)) }.join()
            check(auth.state.value.readyForActions && auth.state.value.identity?.uid == owned.uid)
            val now = Instant.now()
            fixtures.seed(
                "organizations/${owned.organizationId}",
                mapOf(
                    "id" to owned.organizationId,
                    "name" to "Synthetic cold organization",
                    "description" to "Synthetic",
                    "city" to "Wien",
                    "moderationStatus" to "approved",
                    "createdAt" to now,
                    "updatedAt" to now,
                ),
            )
            fixtures.seed(
                "events/${owned.eventId}",
                mapOf(
                    "id" to owned.eventId,
                    "sourceType" to "organization",
                    "organizationId" to owned.organizationId,
                    "moderationStatus" to "approved",
                    "title" to "Synthetic private cold event",
                    "summary" to "Synthetic",
                    "details" to "Synthetic private venue",
                    "createdAt" to now,
                    "updatedAt" to now,
                    "startDate" to owned.start,
                    "endDate" to owned.end,
                ),
            )
            fixtures.seed("registrations/${owned.registrationId}", registration(owned))
            FirestoreInboxSource(LocalFirebase.firestore(context)).savePreferences(
                owned.uid,
                InboxPreferences(true, true, 60),
            ) {
                LocalFirebase.auth(context).currentUser?.uid == owned.uid
            }
            val runtime = LocalReminders.get(context)
            runtime.ensureChannel()
            runtime.attachAuth { auth.state.value }
            withContext(Dispatchers.Main) {
                runtime.controller.bindAuth(auth.state.value)
                runtime.controller.reconcile()
            }
            val state =
                withTimeout(25_000) {
                    runtime.controller.state.first {
                        it.stage in setOf(ReminderStage.SCHEDULED, ReminderStage.FAILED)
                    }
                }
            assertEquals(ReminderStage.SCHEDULED, state.stage)
            assertEquals(1, state.scheduled)
            val ticket = ledger.read().tickets.single { it.state == ReminderTicketState.PENDING }
            check(
                ticket.owner == reminderOwner(owned.uid) &&
                    ticket.eventId == owned.eventId &&
                    ticket.fireAt == owned.fireAt
            )
            assertTrue(
                "Preparation must leave at least a minute for a real cold-process transition",
                Instant.now() < owned.fireAt.minusSeconds(60),
            )
            val prepared =
                owned.copy(epoch = ticket.epoch, token = ticket.token).also { marker = it }
            writeMarker(prepared)
            if (mode == Mode.SUPPRESSION) {
                // Server-side change after scheduling, without a client callback which would simply
                // cancel the alarm.
                AccountDeletionFixtures.remove("registrations/${prepared.registrationId}")
                assertNull(
                    AccountDeletionFixtures.document("registrations/${prepared.registrationId}")
                )
            }
            assertTrue(ownNotifications().isEmpty())
            System.out.println(
                "ReminderColdTrace phase=prepared mode=${mode.name} scheduledCount=1 postedCount=0 markerConfirmed=true " +
                    "registrationPresent=${mode == Mode.POSITIVE} awaitingRootProcessDeath=true"
            )
            // Deliberately no success cleanup: root owns the separate process-death / Doze / alarm
            // / inspect phases.
        } catch (failure: Throwable) {
            val owned = marker
            if (owned != null)
                try {
                    cleanup(owned)
                } catch (cleanupFailure: Throwable) {
                    failure.addSuppressed(cleanupFailure)
                }
            throw failure
        }
    }

    /**
     * No MainActivity, AuthStore, source, controller, receiver or synthetic broadcast is
     * constructed here.
     */
    private suspend fun inspect(expected: Mode) {
        assertEquals(
            "Root must independently observe process absence and preserved system alarm first",
            "true",
            arguments.getString("expectColdProcessObserved"),
        )
        val marker = readMarker()
        check(marker.mode == expected && marker.epoch.isNotEmpty())
        assertTrue(
            "An in-process pause is not cold restart",
            marker.preparingPid != Process.myPid(),
        )
        val plan = ledger.read()
        val ticket = matchingTicket(plan, marker)
        assertTrue(
            "Do not inspect before the requested alarm minute",
            Instant.now() >= marker.fireAt,
        )
        assertEquals(1, plan.receipts.count { it.key == ticket.key })
        val expectedState =
            if (expected == Mode.POSITIVE) ReminderTicketState.CLAIMED
            else ReminderTicketState.SUPPRESSED
        assertEquals(
            "A pending/delayed alarm is inconclusive, not suppression",
            expectedState,
            ticket.state,
        )
        val notifications = ownNotifications()
        if (expected == Mode.POSITIVE) {
            val notification = notifications.single()
            check(notification.tag == "uac-reminder:${marker.token}")
            assertTrue(notification.postTime >= marker.fireAt.toEpochMilli())
            assertEquals(ReminderIntents.CHANNEL, notification.notification.channelId)
            assertEquals(Notification.CATEGORY_REMINDER, notification.notification.category)
            assertEquals(Notification.VISIBILITY_PRIVATE, notification.notification.visibility)
            assertNotNull(notification.notification.publicVersion)
            val title =
                notification.notification.extras
                    .getCharSequence(Notification.EXTRA_TITLE)
                    ?.toString()
            val body =
                notification.notification.extras
                    .getCharSequence(Notification.EXTRA_TEXT)
                    ?.toString()
                    .orEmpty()
            assertTrue(
                title in setOf("UAC · Veranstaltungserinnerung", "UAC · Нагадування про подію")
            )
            assertFalse(body.contains("Synthetic private"))
            assertFalse(body.contains(marker.email))
        } else assertTrue(notifications.isEmpty())
        System.out.println(
            "ReminderColdTrace phase=inspected mode=${expected.name} newProcess=true terminalState=${ticket.state.name} " +
                "matchingReceipts=1 postedCount=${notifications.size}"
        )
    }

    private fun matchingTicket(plan: ReminderPlan, marker: Marker): ReminderTicket {
        check(plan.owner == reminderOwner(marker.uid) && plan.epoch == marker.epoch)
        return plan.tickets
            .single { it.token == marker.token }
            .also {
                check(
                    it.eventId == marker.eventId &&
                        it.epoch == marker.epoch &&
                        it.fireAt == marker.fireAt &&
                        !it.localTest
                )
            }
    }

    private fun registration(marker: Marker): Map<String, Any> =
        mapOf(
            "id" to marker.registrationId,
            "eventId" to marker.eventId,
            "userId" to marker.uid,
            "registeredAt" to marker.fireAt.minusSeconds(240),
        )

    private fun ownNotifications() =
        manager.activeNotifications.filter {
            it.id == 1_517 && it.tag?.startsWith("uac-reminder:") == true
        }

    private suspend fun cleanup(marker: Marker) {
        check(marker.valid())
        val sdkAuth = LocalFirebase.auth(context)
        check(sdkAuth.currentUser == null || sdkAuth.currentUser?.uid == marker.uid) {
            "Do not alter a different live account"
        }
        val currentPlan = ledger.read()
        check(currentPlan.owner == null || currentPlan.owner == reminderOwner(marker.uid)) {
            "Do not cancel a different owner's plan"
        }
        var failure: Throwable? = null
        suspend fun attempt(action: suspend () -> Unit) {
            try {
                action()
            } catch (error: Throwable) {
                val previous = failure
                if (previous == null) failure = error else previous.addSuppressed(error)
            }
        }
        attempt {
            withContext(Dispatchers.Main) {
                AndroidReminderScheduler(context).cancelOwned()
                AndroidReminderNotifications(context).cancelOwned()
                LocalReminders.get(context).controller.bind(null)
            }
            ledger.retire(null) { true }
        }
        attempt { withContext(Dispatchers.Main) { LocalAuthSession.get(context).signOut() }.join() }
        attempt {
            val users = authAdmin(marker, "lookup").optJSONArray("users") ?: JSONArray()
            check(users.length() <= 1)
            if (users.length() == 1) {
                val user = users.getJSONObject(0)
                check(
                    user.getString("localId") == marker.uid &&
                        user.getString("email") == marker.email
                )
                authAdmin(marker, "delete")
            }
            assertEquals(0, authAdmin(marker, "lookup").optJSONArray("users")?.length() ?: 0)
        }
        for (path in marker.paths().asReversed()) attempt {
            AccountDeletionFixtures.remove(path)
            assertNull(AccountDeletionFixtures.document(path))
        }
        if (failure == null) {
            markerFile.delete()
            check(
                !markerFile.baseFile.exists() && !File(markerFile.baseFile.path + ".bak").exists()
            )
        }
        failure?.let { throw it }
    }

    /**
     * Test-only exact UID lookup/delete. Never an export/list endpoint, SDK-config credential or
     * cloud fallback.
     */
    private suspend fun authAdmin(marker: Marker, operation: String): JSONObject =
        withContext(Dispatchers.IO) {
            AccountDeletionFixtures.requireLocalAvd()
            LocalEnvironment.requireSafe()
            check(marker.valid() && operation in setOf("lookup", "delete"))
            val connection =
                URL(
                        "http://10.0.2.2:9098/identitytoolkit.googleapis.com/v1/projects/demo-uac-android/accounts:$operation"
                    )
                    .openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 5_000
                connection.readTimeout = 5_000
                connection.instanceFollowRedirects = false
                connection.requestMethod = "POST"
                connection.setRequestProperty("Authorization", "Bearer owner")
                connection.setRequestProperty("Content-Type", "application/json")
                connection.doOutput = true
                val body =
                    JSONObject()
                        .put(
                            "localId",
                            if (operation == "lookup") JSONArray().put(marker.uid) else marker.uid,
                        )
                connection.outputStream.use {
                    it.write(body.toString().toByteArray(Charsets.UTF_8))
                }
                check(connection.responseCode in 200..299) {
                    "Exact cold fixture Auth request failed"
                }
                val bytes =
                    connection.inputStream.use { input ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(1_024)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            check(output.size() + count <= 16_384)
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    }
                if (bytes.isEmpty()) JSONObject() else JSONObject(bytes.toString(Charsets.UTF_8))
            } finally {
                connection.disconnect()
            }
        }

    private suspend fun writeMarker(marker: Marker) =
        withContext(Dispatchers.IO) {
            check(marker.valid())
            val bytes =
                ByteArrayOutputStream()
                    .also { output ->
                        DataOutputStream(output).use {
                            it.writeInt(0x55414316)
                            it.writeInt(1)
                            it.writeUTF(marker.suffix)
                            it.writeUTF(marker.uid)
                            it.writeByte(marker.mode.ordinal)
                            it.writeInt(marker.preparingPid)
                            it.writeLong(marker.fireAt.epochSecond)
                            it.writeUTF(marker.epoch)
                            it.writeUTF(marker.token)
                        }
                    }
                    .toByteArray()
            check(bytes.size <= 4_096)
            val stream = markerFile.startWrite()
            try {
                stream.write(bytes)
                markerFile.finishWrite(stream)
            } catch (error: Throwable) {
                markerFile.failWrite(stream)
                throw error
            }
            check(readMarker() == marker)
        }

    private suspend fun readMarker(): Marker =
        withContext(Dispatchers.IO) {
            val bytes =
                markerFile.openRead().use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(512)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        check(output.size() + count <= 4_096)
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
            DataInputStream(ByteArrayInputStream(bytes)).use { input ->
                check(input.readInt() == 0x55414316 && input.readInt() == 1)
                val suffix = input.readUTF()
                val uid = input.readUTF()
                val mode = checkNotNull(Mode.entries.getOrNull(input.readUnsignedByte()))
                Marker(
                        suffix,
                        uid,
                        mode,
                        input.readInt(),
                        Instant.ofEpochSecond(input.readLong()),
                        input.readUTF(),
                        input.readUTF(),
                    )
                    .also { check(input.read() == -1 && it.valid()) }
            }
        }
}
