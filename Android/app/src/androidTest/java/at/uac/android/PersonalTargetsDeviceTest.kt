package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.personal.*
import at.uac.android.feature.registrations.FirestoreRegistrationsSource
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Orphan marker regression. Exact unique local paths only, no Rules modifications and no collection
 * cleanup.
 */
@RunWith(AndroidJUnit4::class)
class PersonalTargetsDeviceTest {
    @Test
    fun savedSubscriptionsAndRegistrationTargetsKeepAvailableNeighboursOrGuard() = runBlocking {
        AccountDeletionFixtures.requireLocalAvd()
        val context = AccountDeletionFixtures.context
        if (!AccountDeletionFixtures.online()) {
            try {
                PersonalRepository(localPersonalSource(context), { null }).saved(ContentKind.NEWS)
                fail("Guest guard")
            } catch (error: PersonalException) {
                assertEquals(PersonalFailure.SIGN_IN, error.reason)
            }
            return@runBlocking
        }
        AuthEmulatorFixtures.seedLegalReference()
        val user = AccountDeletionFixtures.create("deletion-personal-targets")
        val prefix = "personal-target-${UUID.randomUUID()}"
        val db = LocalFirebase.firestore(context)
        val session = PersonalSession(user.uid, true, true, 1)
        val source = localPersonalSource(context)
        var visible = true
        val repository = PersonalRepository(source, { session }, { visible })
        val cleanup = linkedSetOf<String>()
        val markers = linkedSetOf<String>()
        val time = Instant.parse("2026-09-03T10:00:00Z")
        var primary: Throwable? = null
        fun target(kind: ContentKind, state: String) =
            PersonalTarget(kind, "$prefix-${kind.collection}-$state")
        suspend fun seed(path: String, fields: Map<String, Any>) {
            check(
                path.split('/').last().contains(prefix) ||
                    path.startsWith("likes/organization_follow_$prefix")
            )
            cleanup += path
            // The auth fixture deliberately accepts only strings/booleans/maps. These content and
            // marker fixtures need actual Firestore timestamps, never ISO strings in timestamp
            // fields.
            withContext(Dispatchers.IO) {
                AccountDeletionFixtures.requireLocalAvd()
                check(path in cleanup)
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
                            is Instant -> JSONObject().put("timestampValue", value.toString())
                            else -> error("Unsupported personal target fixture value")
                        }
                    }
                    val payload = JSONObject().put("fields", JSONObject(values)).toString()
                    connection.outputStream.use { it.write(payload.toByteArray()) }
                    check(connection.responseCode in 200..299) {
                        "Scoped personal fixture setup failed"
                    }
                    connection.inputStream.use { it.readBytes() }
                } finally {
                    connection.disconnect()
                }
            }
        }
        try {
            for (kind in ContentKind.entries) {
                for (state in listOf("approved", "draft", "missing")) {
                    val target = target(kind, state)
                    if (state != "missing")
                        seed(
                            target.key,
                            mapOf(
                                "id" to target.id,
                                "moderationStatus" to state,
                                "sourceType" to "organization",
                                "title" to "Synthetic target $state",
                                "name" to "Synthetic organization $state",
                                "summary" to "Summary",
                                "details" to "Details",
                                "body" to "Body",
                                "description" to "Description",
                                "city" to "Wien",
                                "createdAt" to time,
                                "updatedAt" to time,
                                "startDate" to time,
                                "endDate" to time.plusSeconds(3600),
                                "ownerId" to user.uid,
                            ),
                        )
                    val bookmark = PersonalMarker(target, user.uid, PersonalAction.BOOKMARK)
                    seed(bookmark.path, bookmark.identityFields() + ("createdAt" to time))
                    markers += bookmark.path
                    if (kind == ContentKind.ORGANIZATIONS) {
                        val follow = PersonalMarker(target, user.uid, PersonalAction.SUBSCRIBE)
                        seed(follow.path, follow.identityFields() + ("createdAt" to time))
                        markers += follow.path
                    }
                }
            }
            // Record the exact legacy query result without making persistence of an emulator bug a
            // future test requirement.
            try {
                val legacy =
                    db.collection("news")
                        .whereIn(
                            FieldPath.documentId(),
                            listOf(target(ContentKind.NEWS, "missing").id),
                        )
                        .whereEqualTo("moderationStatus", "approved")
                        .whereEqualTo("sourceType", "organization")
                        .get(Source.SERVER)
                        .await()
                assertTrue(legacy.isEmpty)
                println("PERSONAL_LEGACY_MISSING_TARGET_QUERY EMPTY")
            } catch (error: FirebaseFirestoreException) {
                assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
                println("PERSONAL_LEGACY_MISSING_TARGET_QUERY PERMISSION_DENIED")
            }
            for (kind in ContentKind.entries) {
                val page = repository.saved(kind)
                assertEquals(listOf(target(kind, "approved").id), page.items.map { it.id })
                assertEquals(2, page.unavailable)
                assertFalse(page.hasMore)
                val raw =
                    source.approvedContent(
                        kind,
                        listOf("approved", "draft", "missing").map { target(kind, it).id },
                    )
                assertEquals(listOf(target(kind, "approved").id), raw.map { it.id })
            }
            val subscriptions = repository.subscriptions()
            assertEquals(
                listOf(target(ContentKind.ORGANIZATIONS, "approved").id),
                subscriptions.items.map { it.id },
            )
            assertEquals(2, subscriptions.unavailable)
            val events =
                FirestoreRegistrationsSource(db)
                    .events(
                        listOf("approved", "draft", "missing").map {
                            target(ContentKind.EVENTS, it).id
                        }
                    )
            assertEquals(listOf(target(ContentKind.EVENTS, "approved").id), events.map { it.id })
            visible = false
            val hidden = repository.saved(ContentKind.NEWS)
            assertTrue(hidden.items.isEmpty())
            assertEquals(3, hidden.unavailable)
            var checks = 0
            try {
                source.approvedContentCurrent(
                    ContentKind.NEWS,
                    listOf(target(ContentKind.NEWS, "approved").id),
                ) {
                    ++checks == 1
                }
                fail("A revision change after await must discard the target")
            } catch (_: CancellationException) {}
            db.disableNetwork().await()
            try {
                source.approvedContent(
                    ContentKind.NEWS,
                    listOf(target(ContentKind.NEWS, "approved").id),
                )
                fail("Offline must not become empty success")
            } catch (error: PersonalException) {
                assertEquals(PersonalFailure.OFFLINE, error.reason)
            } finally {
                db.enableNetwork().await()
            }
            for (path in markers) assertTrue(
                "Source resolution cannot delete a saved or subscription marker",
                db.document(path).get(Source.SERVER).await().exists(),
            )
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            var cleanupFailure = primary
            suspend fun clean(action: suspend () -> Unit) {
                try {
                    action()
                } catch (error: Throwable) {
                    if (cleanupFailure == null) cleanupFailure = error
                    else cleanupFailure?.addSuppressed(error)
                }
            }
            clean { db.enableNetwork().await() }
            for (path in cleanup.toList().asReversed()) clean {
                AccountDeletionFixtures.remove(path)
            }
            clean { AccountDeletionFixtures.clean(user) }
            if (primary == null) cleanupFailure?.let { throw it }
        }
    }
}
