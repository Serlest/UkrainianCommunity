package at.uac.android

import android.graphics.Bitmap
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.*
import at.uac.android.feature.auth.*
import at.uac.android.feature.organization.*
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class OrganizationDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val online
        get() = InstrumentationRegistry.getArguments().getString("expectFunctions") == "true"

    private var phase = "setup"

    @Test
    fun namedStorageAndOfflineGuestRemainFailClosed() = runBlocking {
        assertSame(LocalStorage.instance(context), LocalStorage.instance(context))
        assertEquals("uac-local", LocalStorage.instance(context).app.name)
        assertEquals(
            "demo-uac-android.appspot.com",
            LocalStorage.instance(context).reference.bucket,
        )
        val gate =
            object : OrganizationMutationGate {
                override suspend fun <T> withSession(
                    session: OrganizationSession,
                    operation: suspend () -> T,
                ): T = error("Guest must never reach gate")
            }
        expect(OrganizationFailure.SIGN_IN) {
            OrganizationRepository(localOrganizationSource(context), { null }, gate).hub()
        }
    }

    @Test
    fun actualRulesProofCreateResubmitDiscardLogoAndAuthority() = runBlocking {
        if (!online) return@runBlocking
        check(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val source = localOrganizationSource(context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val store = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
        val repository =
            OrganizationRepository(
                source,
                { store.state.value.organizationScope() },
                AuthOrganizationMutationGate(store),
            )
        val prefix = "org4a-${UUID.randomUUID()}"
        val email = "$prefix@example.invalid"
        val ids = mutableSetOf<String>()
        var uid: String? = null
        auth.signOut()
        try {
            for (document in bundledReferenceLegal(context)) {
                fixture(
                    "legalDocuments/${document.type}",
                    mapOf(
                        "activeVersion" to document.version,
                        "status" to "published",
                        "requiresAcceptance" to document.requiresAcceptance,
                    ),
                )
                fixture(
                    "legalDocuments/${document.type}/versions/${document.version}",
                    mapOf(
                        "version" to document.version,
                        "status" to "published",
                        "requiresAcceptance" to document.requiresAcceptance,
                        "locales" to
                            document.texts.mapValues { (locale, text) ->
                                mapOf("title" to document.title(locale), "contentText" to text)
                            },
                    ),
                )
            }
            val user =
                auth.createUserWithEmailAndPassword(email, "Synthetic-org4a-only!").await().user!!
            uid = user.uid
            db.document("users/$uid")
                .set(
                    registeredProfileFields(
                        uid,
                        AuthRegistration(
                            email,
                            "Synthetic Applicant",
                            "wien",
                            acceptedTerms = true,
                            acceptedPrivacy = true,
                            minimumAgeConfirmed = true,
                        ),
                        FieldValue.serverTimestamp(),
                    )
                )
                .await()
            val rules = source.rules()
            var draft =
                OrganizationDraft(
                    "$prefix-main",
                    "Synthetic Local Organization",
                    "A local request with verified contracts",
                    region = "wien",
                    city = "Wien",
                    acceptedRulesVersion = rules.version,
                )
            ids += draft.id
            phase = "unverified callable denied"
            expect(OrganizationFailure.DENIED) {
                LocalFunctions.instance(context)
                    .getHttpsCallable("acceptOrganizationRules")
                    .call(OrganizationContract.acceptancePayload(draft, rules, "de", "test"))
                    .await()
            }
            user.sendEmailVerification().await()
            auth.applyActionCode(verificationCode(email)).await()
            store.restore().join()
            assertTrue(store.state.value.readyForActions)
            val session = store.state.value.organizationScope()!!
            phase = "missing target list query"
            assertNull(repository.request(draft.id))
            phase = "direct create without proof denied"
            expect(OrganizationFailure.DENIED) {
                db.document("organizations/${draft.id}")
                    .set(OrganizationContract.create(draft, session, FieldValue.serverTimestamp()))
                    .await()
            }
            phase = "proof acceptance and create"
            val initial = repository.submit(draft, rules, null, null, "de").record
            assertEquals("pendingReview", initial.status)
            assertEquals(uid, initial.submitter)
            assertEquals(initial.id, repository.request(initial.id)?.id)
            assertEquals(OrganizationAuthority.NONE, initial.authority)
            assertEquals(
                initial.createdAt,
                repository.submit(draft, rules, null, null, "de").record.createdAt,
            )
            phase = "identity role proof and direct-delete negatives"
            expect(OrganizationFailure.STALE) {
                repository.submit(draft.copy(name = "Different"), rules, null, null, "de")
            }
            expect(OrganizationFailure.DENIED) {
                db.document("organizationCreationProofs/${draft.id}").get(Source.SERVER).await()
            }
            expect(OrganizationFailure.DENIED) {
                db.document("organizations/${draft.id}").update("ownerId", uid).await()
            }
            expect(OrganizationFailure.DENIED) {
                db.document("organizations/${draft.id}")
                    .update("moderationStatus", "approved")
                    .await()
            }
            expect(OrganizationFailure.DENIED) {
                db.document("organizations/${draft.id}").delete().await()
            }
            val limitIds = listOf("$prefix-limit1", "$prefix-limit2")
            for (id in limitIds) {
                ids += id
                fixture("organizations/$id", initial.fields + mapOf("id" to id))
            }
            phase = "three open request limit"
            expect(OrganizationFailure.LIMIT) {
                LocalFunctions.instance(context)
                    .getHttpsCallable("acceptOrganizationRules")
                    .call(
                        OrganizationContract.acceptancePayload(
                            draft.copy(id = "$prefix-overlimit"),
                            rules,
                            "de",
                            "test",
                        )
                    )
                    .await()
            }
            for (id in limitIds) adminDelete("organizations/$id")
            val foreignId = "$prefix-foreign"
            ids += foreignId
            fixture(
                "organizations/$foreignId",
                initial.fields +
                    mapOf("id" to foreignId, "submittedByUserId" to "foreign-synthetic-uid"),
            )
            phase = "foreign target query and actions"
            assertNull(repository.request(foreignId))
            expect(OrganizationFailure.DENIED) {
                db.document("organizations/$foreignId").get(Source.SERVER).await()
            }
            expect(OrganizationFailure.DENIED) {
                LocalFunctions.instance(context)
                    .getHttpsCallable("deleteOrganization")
                    .call(mapOf("organizationId" to foreignId))
                    .await()
            }
            fixture(
                "organizations/${draft.id}",
                initial.fields +
                    mapOf(
                        "moderationStatus" to "needsRevision",
                        "reviewMessage" to "Please clarify",
                        "reviewedAt" to Instant.now(),
                        "updatedAt" to Instant.now(),
                    ),
            )
            phase = "review race and resubmit"
            expect(OrganizationFailure.STALE) {
                repository.submit(draft, rules, initial, null, "de")
            }
            val revision = repository.hub().requests.single { it.id == draft.id }
            assertEquals("Please clarify", revision.reviewMessage)
            draft = draft.copy(summary = "Updated local request with useful details")
            val resubmitted = repository.submit(draft, rules, revision, null, "de").record
            assertEquals("pendingReview", resubmitted.status)
            assertNull(resubmitted.reviewMessage)
            assertNull(resubmitted.rejectionReason)
            val bitmap =
                Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888).apply {
                    eraseColor(android.graphics.Color.BLUE)
                }
            val jpeg =
                try {
                    ByteArrayOutputStream().use {
                        bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it)
                        it.toByteArray()
                    }
                } finally {
                    bitmap.recycle()
                }
            val withLogo = repository.submit(draft, rules, resubmitted, jpeg, "de")
            phase = "logo read-back"
            assertFalse(withLogo.logoIncomplete)
            val logoUrl = withLogo.record.fields["logoURL"] as String
            assertTrue(LocalStorage.urlMatches(logoUrl, "organizations/${draft.id}/logo.jpg"))
            assertArrayEquals(
                jpeg,
                LocalStorage.instance(context)
                    .reference
                    .child("organizations/${draft.id}/logo.jpg")
                    .getBytes(3_000_000)
                    .await(),
            )
            expectStorageDenied {
                LocalStorage.instance(context)
                    .reference
                    .child("organizations/$foreignId/logo.jpg")
                    .putBytes(
                        jpeg,
                        com.google.firebase.storage.StorageMetadata.Builder()
                            .setContentType("image/jpeg")
                            .build(),
                    )
                    .await()
            }
            fixture(
                "organizations/${draft.id}",
                withLogo.record.fields +
                    mapOf(
                        "moderationStatus" to "rejected",
                        "rejectionReason" to "Synthetic reason",
                        "updatedAt" to Instant.now().minusSeconds(24 * 86400),
                    ),
            )
            val rejected = repository.hub().requests.single { it.id == draft.id }
            assertEquals(RequestRetention.WARNING, rejected.retention(Instant.now()))
            assertEquals("Synthetic reason", rejected.rejectionReason)
            val approvedId = "$prefix-approved"
            ids += approvedId
            fixture(
                "organizations/$approvedId",
                initial.fields +
                    mapOf(
                        "id" to approvedId,
                        "moderationStatus" to "approved",
                        "submittedByUserId" to "other",
                        "adminIds" to listOf(uid),
                    ),
            )
            assertEquals(
                OrganizationAuthority.ADMIN,
                repository.hub().managed.single { it.id == approvedId }.authority,
            )
            assertNull(repository.request(approvedId))
            val ownApprovedId = "$prefix-own-approved"
            ids += ownApprovedId
            fixture(
                "organizations/$ownApprovedId",
                initial.fields + mapOf("id" to ownApprovedId, "moderationStatus" to "approved"),
            )
            val ownApproved = repository.request(ownApprovedId)!!
            assertEquals("approved", ownApproved.status)
            assertFalse(ownApproved.editable(session))
            assertEquals(OrganizationAuthority.NONE, ownApproved.authority)
            phase = "approved delete denied and own discard"
            expect(OrganizationFailure.DENIED) {
                LocalFunctions.instance(context)
                    .getHttpsCallable("deleteOrganization")
                    .call(mapOf("organizationId" to approvedId))
                    .await()
            }
            repository.discard(rejected)
            assertNull(repository.request(rejected.id))
            assertTrue(repository.hub().requests.none { it.id == rejected.id })
            repository.discard(
                rejected
            ) // Exact retry: alreadyDeleted, never another organization's ID.
            phase = "discard revokes client Storage read and removes exact object"
            expectStorageDenied {
                LocalStorage.instance(context)
                    .reference
                    .child("organizations/${draft.id}/logo.jpg")
                    .metadata
                    .await()
            }
            assertEquals(404, adminStorageStatus(draft.id, "GET"))
            fixture(
                "users/$uid",
                db.document("users/$uid").get(Source.SERVER).await().data!! +
                    mapOf("accountStatus" to "suspendedUntil", "blockState" to "suspendedUntil"),
            )
            phase = "suspended caller denied"
            expect(OrganizationFailure.DENIED) {
                LocalFunctions.instance(context)
                    .getHttpsCallable("acceptOrganizationRules")
                    .call(OrganizationContract.acceptancePayload(draft, rules, "de", "test"))
                    .await()
            }
        } finally {
            scope.cancel()
            for (id in ids) {
                adminStorageDelete(id)
                adminDelete("organizations/$id")
                adminDelete("organizationCreationProofs/$id")
            }
            uid?.let {
                adminDelete("users/$it")
                adminDelete("publicProfiles/$it")
            }
            runCatching { auth.currentUser?.delete()?.await() }
            auth.signOut()
        }
    }

    private suspend fun expect(expected: OrganizationFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("$phase: expected $expected")
        } catch (error: Exception) {
            val actual = organizationFailure(error)
            if (actual != expected)
                throw AssertionError("$phase: expected $expected but was $actual", error)
        }
    }

    private suspend fun expectStorageDenied(action: suspend () -> Unit) {
        try {
            action()
            fail("Storage should deny foreign scope")
        } catch (error: com.google.firebase.storage.StorageException) {
            assertEquals(
                com.google.firebase.storage.StorageException.ERROR_NOT_AUTHORIZED,
                error.errorCode,
            )
        }
    }

    private suspend fun fixture(path: String, fields: Map<String, Any?>) =
        withContext(Dispatchers.IO) {
            request(
                8088,
                "/v1/projects/demo-uac-android/databases/(default)/documents/$path",
                "PATCH",
                JSONObject().put("fields", JSONObject(fields.mapValues { value(it.value) })),
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

    private suspend fun adminStorageDelete(id: String) {
        check(adminStorageStatus(id, "DELETE") in setOf(200, 204, 404)) {
            "Synthetic logo cleanup failed"
        }
    }

    private suspend fun adminStorageStatus(id: String, method: String): Int =
        withContext(Dispatchers.IO) {
            LocalEnvironment.requireSafe()
            require(id.startsWith("org4a-") && OrganizationContract.id(id))
            require(method in setOf("GET", "DELETE"))
            val connection =
                URL(
                        "http://10.0.2.2:9198/v0/b/demo-uac-android.appspot.com/o/organizations%2F$id%2Flogo.jpg"
                    )
                    .openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                connection.instanceFollowRedirects = false
                connection.requestMethod = method
                connection.setRequestProperty("Authorization", "Bearer owner")
                connection.responseCode
            } finally {
                connection.disconnect()
            }
        }

    private suspend fun verificationCode(email: String): String =
        withContext(Dispatchers.IO) {
            val list =
                request(9098, "/emulator/v1/projects/demo-uac-android/oobCodes", "GET")
                    .getJSONArray("oobCodes")
            (0 until list.length())
                .map { list.getJSONObject(it) }
                .last {
                    it.optString("email") == email && it.optString("requestType") == "VERIFY_EMAIL"
                }
                .getString("oobCode")
        }

    private fun request(
        port: Int,
        path: String,
        method: String,
        data: JSONObject? = null,
    ): JSONObject {
        LocalEnvironment.requireSafe()
        require(port in setOf(8088, 9098) && path.contains("/demo-uac-android/"))
        val connection = URL("http://10.0.2.2:$port$path").openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.instanceFollowRedirects = false
            connection.requestMethod = method
            connection.setRequestProperty("Authorization", "Bearer owner")
            if (data != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use { it.write(data.toString().toByteArray()) }
            }
            if (method == "DELETE" && connection.responseCode == 404) return JSONObject()
            check(connection.responseCode in 200..299) {
                "Synthetic fixture HTTP ${connection.responseCode}"
            }
            val body = connection.inputStream.bufferedReader().use { it.readText() }
            return if (body.isBlank()) JSONObject() else JSONObject(body)
        } finally {
            connection.disconnect()
        }
    }

    private fun value(item: Any?): JSONObject =
        when (item) {
            null -> JSONObject().put("nullValue", JSONObject.NULL)
            is String -> JSONObject().put("stringValue", item)
            is Boolean -> JSONObject().put("booleanValue", item)
            is Int,
            is Long -> JSONObject().put("integerValue", item.toString())
            is Instant -> JSONObject().put("timestampValue", item.toString())
            is Timestamp ->
                JSONObject()
                    .put(
                        "timestampValue",
                        Instant.ofEpochSecond(item.seconds, item.nanoseconds.toLong()).toString(),
                    )
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
            is List<*> ->
                JSONObject()
                    .put("arrayValue", JSONObject().put("values", JSONArray(item.map(::value))))
            else -> error("Unsupported fixture field")
        }
}
