package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.subscribers.*
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.tasks.await
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SubscribersDeviceTest {
    @Test
    fun ordinaryUserPagesAllMissingProfilesAndObservesSecondPageMembership() = runBlocking {
        fixture { f, _, session, source ->
            f.seed(55)
            val repository = SubscribersRepository(source, { session }, { true }, { true })
            val missing = repository.load(f.organizationId)
            assertEquals(50, missing.references.size)
            assertEquals(50, missing.unavailable)
            assertEquals(1, missing.members.size)
            assertNull(missing.members.single().profile)
            assertEquals(SubscriberRole.OWNER, missing.members.single().role)
            assertEquals(f.subscription(49).substringAfter('/'), missing.next?.documentId)
            for (index in 1..54) if (index != 49) f.publicProfile(index)
            val page = repository.load(f.organizationId)
            assertTrue(
                page.members.any {
                    it.userId == f.person(1) &&
                        it.profile?.displayName == "Synthetic public member 001"
                }
            )
            assertFalse(page.members.any { it.userId == f.person(49) })
            val all = repository.load(f.organizationId, page)
            assertEquals(55, all.references.size)
            assertNull(all.next)
            assertFalse(all.capped)
            val signals = Channel<Result<Unit>>(Channel.UNLIMITED)
            val watcher = launch {
                source.changes(f.organizationId, session).collect { signals.send(it) }
            }
            try {
                repeat(2) { assertSignal(withTimeout(15_000) { signals.receive() }, "initial-$it") }
                f.removeSubscription(51)
                assertSignal(withTimeout(15_000) { signals.receive() }, "membership-removal")
                val changed = repository.load(f.organizationId, page)
                assertEquals(54, changed.references.size)
                assertFalse(changed.members.any { it.userId == f.person(51) })
                f.subscriptionRecord(51)
            } finally {
                watcher.cancelAndJoin()
                signals.close()
            }
            try {
                LocalFirebase.firestore(AccountDeletionFixtures.context)
                    .document("users/${f.person(0)}")
                    .get(Source.SERVER)
                    .await()
                fail("Private user profile is never community data")
            } catch (error: FirebaseFirestoreException) {
                assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
            }
            f.assertUnchanged(55)
        }
    }

    private fun assertSignal(signal: Result<Unit>, phase: String) {
        signal.exceptionOrNull()?.let { error ->
            val chain =
                generateSequence(error) { it.cause }
                    .take(5)
                    .joinToString(" -> ") { cause ->
                        cause.javaClass.simpleName +
                            when (cause) {
                                is SubscribersException -> ":${cause.failure}"
                                is FirebaseFirestoreException -> ":${cause.code.name}"
                                else -> ""
                            }
                    }
            throw AssertionError("Subscriber watch phase=$phase, failure=$chain")
        }
        assertTrue(signal.isSuccess)
    }

    @Test
    fun cachedSubscriptionsCannotBePublishedWhenNamedFirestoreNetworkIsDisabled() = runBlocking {
        fixture { f, _, session, source ->
            f.seed(2)
            f.publicProfile(1)
            val repository = SubscribersRepository(source, { session }, { true }, { true })
            assertEquals(2, repository.load(f.organizationId).references.size)
            val database = LocalFirebase.firestore(AccountDeletionFixtures.context)
            try {
                database.disableNetwork().await()
                try {
                    repository.load(f.organizationId)
                    fail("Cached community rows cannot replace a SERVER read")
                } catch (error: SubscribersException) {
                    assertEquals(SubscribersFailure.OFFLINE, error.failure)
                }
            } finally {
                database.enableNetwork().await()
            }
            assertEquals(2, repository.load(f.organizationId).references.size)
            f.assertUnchanged(2)
        }
    }

    @Test
    fun realAccountRestrictionAfterJoinRejectsAStillReadyClientSnapshot() = runBlocking {
        fixture { f, user, session, source ->
            f.seed(2)
            f.publicProfile(1)
            var changed = false
            val restricted =
                object : SubscribersSource by source {
                    override suspend fun profiles(
                        ids: List<String>,
                        session: SubscriberSession,
                    ): List<RawDocument> {
                        val rows = source.profiles(ids, session)
                        if (!changed) {
                            changed = true
                            AccountDeletionFixtures.patch(
                                "users/${user.uid}",
                                mapOf("accountStatus" to "deactivated"),
                                merge = true,
                            )
                        }
                        return rows
                    }
                }
            try {
                SubscribersRepository(restricted, { session }, { true }, { true })
                    .load(f.organizationId)
                fail("Public joins cannot reauthorize restricted subscriber-list access")
            } catch (error: SubscribersException) {
                assertEquals(SubscribersFailure.DENIED, error.failure)
                assertTrue(changed)
            } finally {
                AccountDeletionFixtures.patch(
                    "users/${user.uid}",
                    mapOf("accountStatus" to "active"),
                    merge = true,
                )
            }
            assertEquals(
                2,
                SubscribersRepository(source, { session }, { true }, { true })
                    .load(f.organizationId)
                    .references
                    .size,
            )
            f.assertUnchanged(2)
        }
    }

    private suspend fun fixture(
        action:
            suspend (
                Fixture,
                AccountDeletionFixtures.User,
                SubscriberSession,
                SubscribersSource,
            ) -> Unit
    ) {
        AccountDeletionFixtures.requireLocalAvd()
        if (!AccountDeletionFixtures.online()) {
            val source = localSubscribersSource(AccountDeletionFixtures.context) { null }
            try {
                SubscribersRepository(source, { null }, { true }, { true }).load("synthetic")
                fail("Guest read")
            } catch (error: SubscribersException) {
                assertEquals(SubscribersFailure.SIGN_IN, error.failure)
            }
            return
        }
        AuthEmulatorFixtures.seedLegalReference()
        val user = AccountDeletionFixtures.create("deletion-subscribers")
        val session = SubscriberSession(user.uid, 1, true)
        val fixture = Fixture()
        val source = localSubscribersSource(AccountDeletionFixtures.context) { session }
        var primary: Throwable? = null
        try {
            action(fixture, user, session, source)
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            var cleanup = primary
            try {
                fixture.cleanup()
            } catch (error: Throwable) {
                if (cleanup == null) cleanup = error else cleanup.addSuppressed(error)
            }
            try {
                AccountDeletionFixtures.clean(user)
            } catch (error: Throwable) {
                if (cleanup == null) cleanup = error else cleanup.addSuppressed(error)
            }
            if (primary == null && cleanup != null) throw cleanup
        }
    }

    /** Own unique demo paths only, no collection-wide cleanup and no external profile creation. */
    internal class Fixture {
        private val prefix = "subscribers-${UUID.randomUUID()}"
        val organizationId = "$prefix-org"
        private val owned = linkedSetOf<String>()
        private val time = Instant.parse("2026-09-03T10:00:00Z")

        fun person(index: Int): String {
            require(index in 0..59)
            return "$prefix-person-${index.toString().padStart(3, '0')}"
        }

        fun subscription(index: Int) =
            "likes/organization_follow_${organizationId}_${person(index)}"

        suspend fun seed(count: Int) {
            require(count in 1..60)
            seedPath(
                "organizations/$organizationId",
                mapOf(
                    "id" to organizationId,
                    "moderationStatus" to "approved",
                    "name" to "Synthetic subscriber community",
                    "ownerId" to person(0),
                    "createdAt" to time,
                    "updatedAt" to time,
                    "subscriberCount" to count,
                    "description" to "Synthetic community members",
                    "city" to "Wien",
                ),
            )
            seedPath(
                "users/${person(0)}",
                mapOf(
                    "id" to person(0),
                    "email" to "private-person@example.invalid",
                    "bio" to "Never expose this synthetic private biography",
                ),
            )
            repeat(count) { subscriptionRecord(it) }
        }

        suspend fun subscriptionRecord(index: Int) =
            seedPath(
                subscription(index),
                mapOf(
                    "id" to subscription(index).substringAfter('/'),
                    "subscribedOrganizationId" to organizationId,
                    "userId" to person(index),
                    "createdAt" to time.minusSeconds(index.toLong()),
                ),
            )

        suspend fun publicProfile(index: Int) =
            seedPath(
                "publicProfiles/${person(index)}",
                mapOf(
                    "id" to person(index),
                    "displayName" to "Synthetic public member ${index.toString().padStart(3, '0')}",
                    "city" to "Wien",
                    "federalState" to "wien",
                    "updatedAt" to time,
                ),
            )

        suspend fun privatePerson(index: Int) =
            seedPath(
                "users/${person(index)}",
                mapOf(
                    "id" to person(index),
                    "displayName" to "Synthetic private member",
                    "accountStatus" to "active",
                    "blockState" to "active",
                ),
            )

        suspend fun removeSubscription(index: Int) {
            require(subscription(index) in owned)
            AccountDeletionFixtures.remove(subscription(index))
        }

        suspend fun assertUnchanged(count: Int) {
            val db = LocalFirebase.firestore(AccountDeletionFixtures.context)
            for (index in 0 until count) assertTrue(
                "Subscriber reads cannot remove canonical membership",
                db.document(subscription(index)).get(Source.SERVER).await().exists(),
            )
            assertEquals(
                count.toLong(),
                db.document("organizations/$organizationId")
                    .get(Source.SERVER)
                    .await()
                    .getLong("subscriberCount"),
            )
        }

        private suspend fun seedPath(path: String, fields: Map<String, Any>) =
            withContext(Dispatchers.IO) {
                AccountDeletionFixtures.requireLocalAvd()
                require(
                    path == "organizations/$organizationId" ||
                        (0..59).any {
                            path in
                                setOf(
                                    subscription(it),
                                    "publicProfiles/${person(it)}",
                                    "users/${person(it)}",
                                )
                        }
                )
                owned += path
                val connection =
                    URL(
                            "http://${LocalEnvironment.HOST}:8088${AuthEmulatorFixtures.documentPath(path)}"
                        )
                        .openConnection() as HttpURLConnection
                try {
                    connection.instanceFollowRedirects = false
                    connection.connectTimeout = 5_000
                    connection.readTimeout = 5_000
                    connection.requestMethod = "PATCH"
                    connection.doOutput = true
                    connection.setRequestProperty("Authorization", "Bearer owner")
                    connection.setRequestProperty("Content-Type", "application/json")
                    val values = fields.mapValues { (_, value) ->
                        when (value) {
                            is String -> JSONObject().put("stringValue", value)
                            is Int -> JSONObject().put("integerValue", value.toString())
                            is Instant -> JSONObject().put("timestampValue", value.toString())
                            else -> error("Unsupported scoped subscribers fixture value")
                        }
                    }
                    connection.outputStream.use {
                        it.write(
                            JSONObject().put("fields", JSONObject(values)).toString().toByteArray()
                        )
                    }
                    check(connection.responseCode in 200..299) {
                        "Scoped subscribers fixture setup failed"
                    }
                    connection.inputStream.use { it.readBytes() }
                } finally {
                    connection.disconnect()
                }
            }

        suspend fun cleanup() {
            var failure: Throwable? = null
            for (path in owned.toList().asReversed()) try {
                AccountDeletionFixtures.remove(path)
            } catch (error: Throwable) {
                if (failure == null) failure = error else failure.addSuppressed(error)
            }
            failure?.let { throw it }
        }
    }
}
