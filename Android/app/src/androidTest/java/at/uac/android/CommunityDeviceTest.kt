package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalFunctions
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.auth.FirebaseAuthBackend
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.auth.bundledReferenceLegal
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.community.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CommunityDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val functionsOnline
        get() = InstrumentationRegistry.getArguments().getString("expectFunctions") == "true"

    @Test
    fun namedLocalFunctionsAndOfflineFailureRemainClosed() = runBlocking {
        val functions = LocalFunctions.instance(context)
        assertSame(functions, LocalFunctions.instance(context))
        assertEquals("demo-uac-android", LocalFirebase.auth(context).app.options.projectId)
        val repository = CommunityRepository(localCommunitySource(context), { null })
        expect(CommunityFailure.SIGN_IN) {
            repository.setRegistration(
                CommunityTarget(ContentKind.EVENTS, "synthetic-event-01"),
                true,
            )
        }
        if (
            !functionsOnline &&
                InstrumentationRegistry.getArguments().getString("expectEmulator") != "true"
        ) {
            LocalFirebase.auth(context).signOut()
            try {
                functions
                    .getHttpsCallable("registerForEvent")
                    .withTimeout(3, TimeUnit.SECONDS)
                    .call(mapOf("eventId" to "synthetic-event-01"))
                    .await()
                fail("Stopped emulator cannot confirm a mutation")
            } catch (error: Exception) {
                assertEquals(CommunityFailure.OFFLINE, communityFailure(error))
            }
        }
    }

    @Test
    fun actualCallableRegistrationCommentsAndScopedModerationReadBack() = runBlocking {
        if (!functionsOnline) return@runBlocking
        check(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        val db = LocalFirebase.firestore(context)
        val auth = LocalFirebase.auth(context)
        val functions = LocalFunctions.instance(context)
        val source = localCommunitySource(context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val store = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
        val repository =
            CommunityRepository(
                source,
                { store.state.value.communityScope() },
                AuthCommunityMutationGate(store),
            )
        val prefix = "android-3c-${UUID.randomUUID()}"
        val email = "$prefix@example.invalid"
        val event = CommunityTarget(ContentKind.EVENTS, "$prefix-event")
        val news = CommunityTarget(ContentKind.NEWS, "$prefix-news")
        val organization = CommunityTarget(ContentKind.ORGANIZATIONS, "$prefix-org")
        val createdDocuments = mutableSetOf<String>()
        val createdComments = mutableSetOf<String>()
        var uid: String? = null
        auth.signOut()
        try {
            seedLegal()
            val user =
                auth
                    .createUserWithEmailAndPassword(email, "Synthetic-local-3C-only!")
                    .await()
                    .user!!
            uid = user.uid
            db.document("users/$uid")
                .set(
                    registeredProfileFields(
                        uid,
                        AuthRegistration(
                            email,
                            "3C Synthetic Author",
                            "wien",
                            acceptedTerms = true,
                            acceptedPrivacy = true,
                            minimumAgeConfirmed = true,
                        ),
                        FieldValue.serverTimestamp(),
                    )
                )
                .await()
            val future = Instant.now().plusSeconds(7200)
            val eventFields =
                mapOf(
                    "id" to event.id,
                    "title" to "Synthetic event",
                    "summary" to "Synthetic summary",
                    "details" to "Synthetic details",
                    "createdAt" to Instant.now(),
                    "updatedAt" to Instant.now(),
                    "startDate" to future,
                    "endDate" to future.plusSeconds(3600),
                    "moderationStatus" to "approved",
                    "cancellationState" to "active",
                    "requiresRegistration" to true,
                    "registeredCount" to 0L,
                    "capacity" to 2L,
                    "sourceType" to "app",
                    "commentCount" to 0L,
                )
            adminDocument(event.path, eventFields)
            createdDocuments += event.path
            adminDocument(
                news.path,
                mapOf(
                    "id" to news.id,
                    "title" to "Synthetic news",
                    "body" to "Synthetic body",
                    "moderationStatus" to "approved",
                    "sourceType" to "organization",
                    "organizationId" to organization.id,
                    "commentCount" to 0L,
                ),
            )
            createdDocuments += news.path
            adminDocument(
                organization.path,
                mapOf(
                    "id" to organization.id,
                    "name" to "Synthetic organization",
                    "moderationStatus" to "approved",
                    "ownerId" to "synthetic-unrelated-owner",
                    "adminIds" to emptyList<String>(),
                    "moderatorIds" to emptyList<String>(),
                    "commentCount" to 0L,
                ),
            )
            createdDocuments += organization.path

            // Bypass no app gates: test the real unverified Auth token against the callable itself.
            expect(CommunityFailure.DENIED) {
                functions
                    .getHttpsCallable("registerForEvent")
                    .call(mapOf("eventId" to event.id))
                    .await()
            }
            expect(CommunityFailure.DENIED) {
                functions
                    .getHttpsCallable("saveComment")
                    .call(
                        mapOf("parentType" to "news", "parentId" to news.id, "text" to "Unverified")
                    )
                    .await()
            }
            user.sendEmailVerification().await()
            auth.applyActionCode(verificationCode(email)).await()
            withContext(Dispatchers.Main) { store.restore() }.join()
            assertTrue(
                "Actual AuthStore must pass all gates: ${store.state.value.error}",
                store.state.value.readyForActions,
            )

            assertFalse(repository.participation(event).registered)
            assertTrue(repository.setRegistration(event, true).registered)
            assertEquals(1L, repository.setRegistration(event, true).count)
            val registrationId = CommunityContract.registrationId(event.id, uid)
            val registration =
                db.document("registrations/$registrationId").get(Source.SERVER).await()
            assertEquals(uid, registration.getString("userId"))
            assertEquals(true, registration.getBoolean("counterManagedAtomically"))
            assertNotNull(registration.getTimestamp("registeredAt"))
            assertDenied { db.document("registrations/$registrationId").delete().await() }
            assertDenied {
                db.document("registrations/event_${event.id}_foreign").get(Source.SERVER).await()
            }
            assertDenied { db.document(event.path).update("registeredCount", 900L).await() }
            assertFalse(repository.setRegistration(event, false).registered)
            assertEquals(0L, repository.setRegistration(event, false).count)
            assertFalse(
                db.document("registrations/$registrationId").get(Source.SERVER).await().exists()
            )

            val failures =
                listOf(
                    mapOf("registeredCount" to 2L) to CommunityFailure.FULL,
                    mapOf("startDate" to Instant.now().minusSeconds(1)) to CommunityFailure.PAST,
                    mapOf("cancellationState" to "cancelled") to CommunityFailure.CANCELLED,
                    mapOf("requiresRegistration" to false) to CommunityFailure.NOT_REQUIRED,
                )
            for ((override, failure) in failures) {
                adminDocument(event.path, eventFields + override)
                expect(failure) { repository.setRegistration(event, true) }
                assertFalse(
                    db.document("registrations/$registrationId").get(Source.SERVER).await().exists()
                )
            }
            adminDocument(event.path, eventFields)

            for (target in listOf(news, event, organization)) {
                val saved = repository.addComment(target, "  Дякую за інформацію!  ")
                createdComments += "${target.path}/comments/${saved.id}"
                assertEquals("Дякую за інформацію!", saved.text)
                assertEquals(uid, saved.authorId)
                assertEquals("3C Synthetic Author", saved.authorName)
                val stored =
                    db.document("${target.path}/comments/${saved.id}").get(Source.SERVER).await()
                assertEquals(saved.text, stored.getString("body"))
                assertEquals("approved", stored.getString("moderationStatus"))
                val page =
                    withTimeout(15_000) {
                        source
                            .comments(target)
                            .first {
                                it.getOrNull()?.let { page ->
                                    !page.cached && page.comments.any { row -> row.id == saved.id }
                                } == true
                            }
                            .getOrThrow()
                    }
                assertTrue(page.comments.any { it.id == saved.id })
                assertDenied {
                    db.document("${target.path}/comments/${saved.id}")
                        .update("text", "Direct update")
                        .await()
                }
                assertDenied { db.document("${target.path}/comments/${saved.id}").delete().await() }
                expect(CommunityFailure.DENIED) { repository.deleteComment(target, saved.id) }
            }
            assertDenied {
                db.document("${news.path}/comments/direct-create")
                    .set(mapOf("text" to "Direct create", "authorId" to uid))
                    .await()
            }
            expect(CommunityFailure.REJECTED_TEXT) {
                repository.addComment(news, "I will kill you")
            }
            expect(CommunityFailure.TEXT_TOO_LONG) { repository.addComment(news, "x".repeat(1001)) }
            expect(CommunityFailure.INVALID) {
                functions
                    .getHttpsCallable("saveComment")
                    .call(mapOf("parentType" to "unknown", "parentId" to news.id, "text" to "Test"))
                    .await()
            }

            val hiddenId = "$prefix-hidden"
            adminDocument(
                "${news.path}/comments/$hiddenId",
                mapOf(
                    "id" to hiddenId,
                    "parentType" to "news",
                    "parentId" to news.id,
                    "authorId" to uid,
                    "authorName" to "Hidden",
                    "text" to "Not publicly shown",
                    "createdAt" to Instant.now(),
                    "moderationStatus" to "pendingReview",
                    "isDeleted" to false,
                ),
            )
            createdComments += "${news.path}/comments/$hiddenId"
            val filtered =
                withTimeout(15_000) {
                    source
                        .comments(news)
                        .first {
                            it.getOrNull()?.let { page -> !page.cached && page.withheld == 1 } ==
                                true
                        }
                        .getOrThrow()
                }
            assertFalse(filtered.comments.any { it.id == hiddenId })

            // Exact existing Rules grant: organization moderator, not an invented author-delete
            // endpoint.
            adminDocument(
                organization.path,
                mapOf(
                    "id" to organization.id,
                    "name" to "Synthetic organization",
                    "moderationStatus" to "approved",
                    "ownerId" to "synthetic-unrelated-owner",
                    "adminIds" to emptyList<String>(),
                    "moderatorIds" to listOf(uid),
                    "commentCount" to 0L,
                ),
            )
            assertTrue(repository.moderation(news))
            val ownNews = filtered.comments.single()
            repository.deleteComment(news, ownNews.id)
            assertFalse(
                db.document("${news.path}/comments/${ownNews.id}")
                    .get(Source.SERVER)
                    .await()
                    .exists()
            )
            assertEquals(
                0L,
                db.document(news.path).get(Source.SERVER).await().getLong("commentCount"),
            )

            // Backend account status remains authoritative even if a client is optimistic.
            adminPatch("users/$uid", mapOf("accountStatus" to "suspended"))
            expect(CommunityFailure.DENIED) {
                functions
                    .getHttpsCallable("registerForEvent")
                    .call(mapOf("eventId" to event.id))
                    .await()
            }
            expect(CommunityFailure.DENIED) {
                functions
                    .getHttpsCallable("saveComment")
                    .call(
                        mapOf("parentType" to "news", "parentId" to news.id, "text" to "Suspended")
                    )
                    .await()
            }
            adminPatch("users/$uid", mapOf("accountStatus" to "active"))
        } finally {
            scope.cancel()
            for (path in createdComments) adminDelete(path)
            for (path in createdDocuments) adminDelete(path)
            uid?.let {
                if (auth.currentUser?.uid == it) auth.currentUser!!.delete().await()
                adminDelete("users/$it")
                adminDelete("publicProfiles/$it")
            }
            auth.signOut()
        }
    }

    private suspend fun expect(expected: CommunityFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: Exception) {
            val classes =
                generateSequence(error as Throwable?) { it.cause }
                    .take(5)
                    .joinToString(" -> ") { it.javaClass.name }
            val code = (error as? at.uac.android.core.LocalCallableException)?.code?.name
            assertEquals(
                "Exception types: $classes; callable code: $code; detail: ${error.message?.take(160)}",
                expected,
                communityFailure(error),
            )
        }
    }

    private suspend fun assertDenied(action: suspend () -> Unit) {
        try {
            action()
            fail("Expected Rules denial")
        } catch (error: FirebaseFirestoreException) {
            assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
        }
    }

    private suspend fun verificationCode(email: String): String =
        withContext(Dispatchers.IO) {
            val json = request(9098, "/emulator/v1/projects/demo-uac-android/oobCodes")
            val codes = json.getJSONArray("oobCodes")
            (0 until codes.length())
                .map { codes.getJSONObject(it) }
                .last {
                    it.optString("email") == email && it.optString("requestType") == "VERIFY_EMAIL"
                }
                .getString("oobCode")
        }

    private suspend fun seedLegal() {
        for (document in
            bundledReferenceLegal(context).filter { it.type in setOf("terms", "privacy") }) {
            val path = "legalDocuments/${document.type}"
            adminDocument(path, mapOf("activeVersion" to document.version, "status" to "published"))
            adminDocument(
                "$path/versions/${document.version}",
                mapOf(
                    "version" to document.version,
                    "status" to "published",
                    "requiresAcceptance" to document.requiresAcceptance,
                    "locales" to
                        document.texts.mapValues { (locale, text) ->
                            mapOf(
                                "title" to document.title(locale),
                                "contentText" to text,
                                "contentMarkdown" to text,
                            )
                        },
                ),
            )
        }
    }

    private suspend fun adminDocument(path: String, fields: Map<String, Any?>) =
        withContext(Dispatchers.IO) {
            request(
                8088,
                "/v1/projects/demo-uac-android/databases/(default)/documents/$path",
                "PATCH",
                fields,
            )
        }

    private suspend fun adminPatch(path: String, fields: Map<String, Any?>) =
        withContext(Dispatchers.IO) {
            val mask = fields.keys.joinToString("&") { "updateMask.fieldPaths=$it" }
            request(
                8088,
                "/v1/projects/demo-uac-android/databases/(default)/documents/$path?$mask",
                "PATCH",
                fields,
            )
        }

    private suspend fun adminDelete(path: String) =
        withContext(Dispatchers.IO) {
            request(
                8088,
                "/v1/projects/demo-uac-android/databases/(default)/documents/$path",
                "DELETE",
            )
        }

    /** Test setup only. Fixed demo host and project, no redirect, no production credentials. */
    private fun request(
        port: Int,
        path: String,
        method: String = "GET",
        fields: Map<String, Any?>? = null,
    ): JSONObject {
        LocalEnvironment.requireSafe()
        check(port in setOf(8088, 9098) && path.contains("/projects/demo-uac-android/"))
        val connection = URL("http://10.0.2.2:$port$path").openConnection() as HttpURLConnection
        connection.instanceFollowRedirects = false
        connection.requestMethod = method
        connection.connectTimeout = 5_000
        connection.readTimeout = 5_000
        connection.setRequestProperty("Authorization", "Bearer owner")
        return try {
            if (fields != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                val json =
                    JSONObject().put("fields", JSONObject(fields.mapValues { value(it.value) }))
                connection.outputStream.use { it.write(json.toString().toByteArray()) }
            }
            check(
                connection.responseCode in 200..299 ||
                    (method == "DELETE" && connection.responseCode == 404)
            ) {
                "Local 3C fixture request failed: ${connection.responseCode}"
            }
            if (connection.responseCode == 404) JSONObject()
            else
                connection.inputStream
                    .bufferedReader()
                    .use { it.readText() }
                    .let { if (it.isBlank()) JSONObject() else JSONObject(it) }
        } finally {
            connection.disconnect()
        }
    }

    private fun value(item: Any?): JSONObject =
        when (item) {
            null -> JSONObject().put("nullValue", JSONObject.NULL)
            is String -> JSONObject().put("stringValue", item)
            is Boolean -> JSONObject().put("booleanValue", item)
            is Instant -> JSONObject().put("timestampValue", item.toString())
            is Number -> JSONObject().put("integerValue", item.toLong().toString())
            is List<*> ->
                JSONObject()
                    .put("arrayValue", JSONObject().put("values", JSONArray(item.map(::value))))
            is Map<*, *> ->
                JSONObject()
                    .put(
                        "mapValue",
                        JSONObject()
                            .put(
                                "fields",
                                JSONObject(
                                    item.entries.associate { it.key.toString() to value(it.value) }
                                ),
                            ),
                    )
            else -> error("Unsupported synthetic fixture value")
        }
}
