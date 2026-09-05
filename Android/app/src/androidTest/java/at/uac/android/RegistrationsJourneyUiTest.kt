package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.*
import at.uac.android.feature.community.*
import at.uac.android.feature.personal.*
import at.uac.android.feature.registrations.*
import at.uac.android.feature.safety.SafetyViewModel
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Actual signup → callable registration → own list → detail/cancel → server receipt. */
@RunWith(AndroidJUnit4::class)
class RegistrationsJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val auth
        get() = LocalFirebase.auth(context)

    private val db
        get() = LocalFirebase.firestore(context)

    private val store
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val registrations
        get() = ViewModelProvider(compose.activity)[RegistrationsViewModel::class.java]

    private val safety
        get() = ViewModelProvider(compose.activity)[SafetyViewModel::class.java]

    private val community
        get() = ViewModelProvider(compose.activity)[CommunityViewModel::class.java]

    private val fixtures
        get() = LocalEmulatorFixtures(context)

    private fun list(tag: String) {
        compose.onNodeWithTag("registrations-list").performScrollToNode(hasTestTag(tag))
    }

    @Test
    fun ownRegistrationJourneyAndRulesIsolationOrGuestGate() {
        runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", "emulator")
            browse.navigate("profile", true)
        }
        compose.waitUntil(15_000) { store.state.value.stage == AuthStage.GUEST }
        if (InstrumentationRegistry.getArguments().getString("expectFunctions") != "true") {
            compose.onNodeWithTag("account-open-registrations").assertDoesNotExist()
            assertNull(registrations.state.value.session)
            return
        }
        check(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        val prefix = "registration-journey-${UUID.randomUUID()}"
        val email = "$prefix@example.invalid"
        val password = "Synthetic-registration-journey-only!"
        val eventId = "$prefix-event"
        val organizationId = "$prefix-organization"
        var uid: String? = null
        val paths = mutableSetOf<String>()
        var primaryFailure: Throwable? = null
        var bodyCompleted = false
        try {
            runBlocking {
                fixtures.seedLegal()
                withContext(Dispatchers.Main) {
                        store.register(
                            AuthRegistration(
                                email,
                                "Registration Journey",
                                "wien",
                                acceptedTerms = true,
                                acceptedPrivacy = true,
                                minimumAgeConfirmed = true,
                            ),
                            password,
                            password,
                            "de",
                        )!!
                    }
                    .join()
                uid = store.state.value.identity!!.uid
                paths += "users/$uid"
                paths += "publicProfiles/$uid"
                withContext(Dispatchers.Main) {
                        store.applyVerificationCode(fixtures.verificationCode(email))!!
                    }
                    .join()
                assertTrue(store.state.value.readyForActions)
                val now = Instant.now()
                paths += "organizations/$organizationId"
                fixtures.seed(
                    "organizations/$organizationId",
                    mapOf(
                        "id" to organizationId,
                        "name" to "Synthetic Registration Organization",
                        "city" to "Wien",
                        "description" to "Synthetic only",
                        "moderationStatus" to "approved",
                        "ownerId" to uid,
                        "createdAt" to now,
                        "updatedAt" to now,
                    ),
                )
                paths += "events/$eventId"
                fixtures.seed(
                    "events/$eventId",
                    mapOf(
                        "id" to eventId,
                        "title" to "Synthetic registered event",
                        "summary" to "Synthetic summary",
                        "details" to "Synthetic details",
                        "city" to "Wien",
                        "federalState" to "wien",
                        "createdAt" to now,
                        "updatedAt" to now,
                        "startDate" to now.plusSeconds(7200),
                        "endDate" to now.plusSeconds(10_800),
                        "moderationStatus" to "approved",
                        "sourceType" to "organization",
                        "organizationId" to organizationId,
                        "cancellationState" to "active",
                        "requiresRegistration" to true,
                        "registeredCount" to 0L,
                        "capacity" to 10L,
                    ),
                )
                paths += "registrations/${CommunityContract.registrationId(eventId, uid)}"
                val repository =
                    CommunityRepository(
                        localCommunitySource(context),
                        { store.state.value.communityScope() },
                        AuthCommunityMutationGate(store),
                    )
                assertTrue(
                    repository
                        .setRegistration(CommunityTarget(ContentKind.EVENTS, eventId), true)
                        .registered
                )
                // Query is own-user scoped; direct clients cannot forge/remove membership.
                val own =
                    RegistrationsRepository(localRegistrationsSource(context)) {
                            store.state.value.personalScope()
                        }
                        .load()
                assertEquals(listOf(eventId), own.items.map { it.id })
                denied {
                    localRegistrationsSource(context).page("synthetic-foreign-$prefix", null, 50)
                }
                denied { db.document(paths.last()).delete().await() }
            }
            compose.waitUntil(25_000) {
                safety.state.value.visibility.loaded || safety.state.value.error != null
            }
            if (!safety.state.value.visibility.loaded) {
                compose.runOnIdle { safety.refresh() }
                compose.waitUntil(25_000) { safety.state.value.visibility.loaded }
            }
            compose.onNodeWithTag("account-open-registrations").performScrollTo().performClick()
            compose.waitUntil(20_000) {
                registrations.state.value.loaded && !registrations.state.value.loading
            }
            list("registration-$eventId")
            compose.onNodeWithTag("registration-$eventId").performClick()
            compose.waitUntil(20_000) {
                browse.state.value.data.detail?.id == eventId && !browse.state.value.data.loading
            }
            compose.waitUntil(20_000) { community.state.value.participation?.registered == true }
            compose
                .onNodeWithTag("browse-list")
                .performScrollToNode(hasTestTag("registration-toggle"))
            compose.onNodeWithTag("registration-toggle").performScrollTo().performClick()
            compose.onNodeWithTag("registration-confirm-cancel").performClick()
            compose.waitUntil(20_000) {
                community.state.value.participation?.registered == false &&
                    !community.state.value.registrationBusy
            }
            runBlocking {
                assertFalse(
                    db.document("registrations/${CommunityContract.registrationId(eventId, uid!!)}")
                        .get(Source.SERVER)
                        .await()
                        .exists()
                )
                assertEquals(
                    0L,
                    db.document("events/$eventId")
                        .get(Source.SERVER)
                        .await()
                        .getLong("registeredCount"),
                )
            }
            compose.onNodeWithTag("back").performClick()
            compose.waitUntil(20_000) {
                registrations.state.value.loaded &&
                    !registrations.state.value.loading &&
                    registrations.state.value.items.isEmpty()
            }
            list("registrations-empty")
            compose.onNodeWithTag("registrations-empty").assertExists()
            runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
            compose.waitUntil(10_000) { registrations.state.value.session == null }
            assertTrue(registrations.state.value.items.isEmpty())
            bodyCompleted = true
            println("RegistrationsJourney body_complete=true")
        } catch (error: Throwable) {
            primaryFailure = error
            println("RegistrationsJourney body_complete=false")
            throw error
        } finally {
            val failures = mutableListOf<Throwable>()
            var confirmedAbsenceWarnings = 0
            fun cleanup(step: String, action: () -> Unit) {
                try {
                    action()
                } catch (error: Throwable) {
                    failures += AssertionError("Registration cleanup step=$step", error)
                }
            }
            // Joining sign-out settles the shared Auth gate before reading owned side effects.
            cleanup("initial-sign-out") {
                runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
            }
            cleanup("settle-private-observers") { compose.waitForIdle() }
            val capturedUid = uid
            val descendants = linkedSetOf<String>()
            if (capturedUid != null) {
                val known = setOf("activityLog", "eventViews", "recentViews")
                cleanup("known-user-collections") {
                    val response =
                        cleanupRequest(
                            AuthEmulatorFixtures.documentPath("users/$capturedUid") +
                                ":listCollectionIds",
                            "POST",
                            JSONObject().put("pageSize", 8),
                        )
                    check(response.status == 200) { "Collection discovery HTTP=" + response.status }
                    val body = JSONObject(response.body)
                    check(body.optString("nextPageToken").isBlank()) {
                        "Collection discovery exceeded bound"
                    }
                    val names = body.optJSONArray("collectionIds") ?: JSONArray()
                    check(names.length() <= known.size) { "Unexpected user collection count" }
                    repeat(names.length()) { index ->
                        check(names.getString(index) in known) {
                            "Unexpected user collection category"
                        }
                    }
                }
                known.forEach { collection ->
                    cleanup("discover-$collection") {
                        val response =
                            cleanupRequest(
                                AuthEmulatorFixtures.documentPath(
                                    "users/$capturedUid/$collection"
                                ) + "?pageSize=16"
                            )
                        check(response.status == 200) { "Child discovery HTTP=" + response.status }
                        val body = JSONObject(response.body)
                        check(body.optString("nextPageToken").isBlank()) {
                            "Child discovery exceeded bound"
                        }
                        val documents = body.optJSONArray("documents") ?: JSONArray()
                        check(documents.length() < 16) { "Child discovery reached bound" }
                        repeat(documents.length()) { index ->
                            cleanup("validate-$collection-$index") {
                                val document = documents.getJSONObject(index)
                                val path = cleanupDocumentPath(document)
                                val parent = "users/$capturedUid/$collection/"
                                check(path.startsWith(parent)) { "Foreign child parent" }
                                val id = path.removePrefix(parent)
                                check('/' !in id && id.isNotBlank()) { "Unexpected nested child" }
                                val fields = document.getJSONObject("fields")
                                when (collection) {
                                    "activityLog" -> {
                                        check(
                                            runCatching { UUID.fromString(id).toString() == id }
                                                .getOrDefault(false)
                                        )
                                        check(wireString(fields, "id") == id)
                                        check(wireString(fields, "targetId") == eventId)
                                        check(wireString(fields, "targetType") == "event")
                                        check(
                                            wireString(fields, "actionType") in
                                                setOf(
                                                    "registeredForEvent",
                                                    "canceledEventRegistration",
                                                )
                                        )
                                    }
                                    "eventViews" -> {
                                        check(id == eventId)
                                        check(wireString(fields, "eventId") == eventId)
                                        check(wireString(fields, "userId") == capturedUid)
                                    }
                                    "recentViews" -> {
                                        check(id == "event_$eventId")
                                        check(wireString(fields, "itemId") == eventId)
                                        check(wireString(fields, "itemType") == "event")
                                    }
                                    else -> error("Unknown child category")
                                }
                                descendants += path
                            }
                        }
                    }
                }
                cleanup("discover-counter-receipt") {
                    fun equals(field: String, value: String) =
                        JSONObject()
                            .put(
                                "fieldFilter",
                                JSONObject()
                                    .put("field", JSONObject().put("fieldPath", field))
                                    .put("op", "EQUAL")
                                    .put("value", JSONObject().put("stringValue", value)),
                            )
                    val query =
                        JSONObject()
                            .put(
                                "structuredQuery",
                                JSONObject()
                                    .put(
                                        "from",
                                        JSONArray()
                                            .put(
                                                JSONObject()
                                                    .put(
                                                        "collectionId",
                                                        "eventRegistrationCounterOperations",
                                                    )
                                            ),
                                    )
                                    .put(
                                        "where",
                                        JSONObject()
                                            .put(
                                                "compositeFilter",
                                                JSONObject()
                                                    .put("op", "AND")
                                                    .put(
                                                        "filters",
                                                        JSONArray()
                                                            .put(equals("userId", capturedUid))
                                                            .put(equals("eventId", eventId)),
                                                    ),
                                            ),
                                    )
                                    .put("limit", 16),
                            )
                    val response =
                        cleanupRequest(cleanupDocumentsBase() + ":runQuery", "POST", query)
                    check(response.status == 200) { "Counter discovery HTTP=" + response.status }
                    val rows = JSONArray(response.body)
                    check(rows.length() < 16) { "Counter discovery reached bound" }
                    repeat(rows.length()) { index ->
                        val document = rows.getJSONObject(index).optJSONObject("document")
                        if (document != null)
                            cleanup("validate-counter-$index") {
                                val path = cleanupDocumentPath(document)
                                check(path.startsWith("eventRegistrationCounterOperations/"))
                                val id = path.removePrefix("eventRegistrationCounterOperations/")
                                check(
                                    runCatching { UUID.fromString(id).toString() == id }
                                        .getOrDefault(false)
                                )
                                val fields = document.getJSONObject("fields")
                                check(wireString(fields, "id") == id)
                                check(wireString(fields, "userId") == capturedUid)
                                check(wireString(fields, "eventId") == eventId)
                                check(wireString(fields, "operation") == "unregister")
                                check(
                                    wireString(fields, "registrationId") ==
                                        CommunityContract.registrationId(eventId, capturedUid)
                                )
                                descendants += path
                            }
                    }
                }
            }
            // No recursive deletion and no functional operation retry.
            (descendants.toList() + paths.toList().asReversed()).distinct().forEachIndexed {
                index,
                path ->
                cleanup("document-$index") {
                    if (
                        deleteExactFixture(path, index) ==
                            RegistrationCleanupOutcome.CONFIRMED_ABSENT_WITH_WARNING
                    )
                        confirmedAbsenceWarnings++
                }
            }
            // A Firestore cleanup failure cannot skip cleanup of this exact synthetic Auth
            // identity.
            if (capturedUid != null)
                cleanup("exact-auth-identity") {
                    runBlocking {
                        check(email == "$prefix@example.invalid")
                        val user = auth.signInWithEmailAndPassword(email, password).await().user
                        check(user != null && user.uid == capturedUid && user.email == email) {
                            "Synthetic Auth identity mismatch"
                        }
                        check(auth.currentUser?.uid == capturedUid) {
                            "Synthetic Auth identity changed"
                        }
                        user.delete().await()
                    }
                }
            cleanup("final-sign-out") {
                runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
            }
            println(
                "RegistrationsJourney cleanup_complete=" +
                    failures.isEmpty() +
                    " body_complete=" +
                    bodyCompleted +
                    " cleanup_failures=" +
                    failures.size +
                    " cleanup_warnings=" +
                    confirmedAbsenceWarnings
            )
            if (failures.isNotEmpty()) {
                val primary = primaryFailure ?: AssertionError("Registration cleanup incomplete")
                failures.forEach(primary::addSuppressed)
                if (primaryFailure == null) throw primary
            }
        }
    }

    private data class CleanupResponse(val status: Int, val body: String)

    private fun cleanupDocumentsBase() =
        "/v1/projects/" + LocalEnvironment.PROJECT_ID + "/databases/(default)/documents"

    private fun cleanupDocumentPath(document: JSONObject): String {
        val base = "projects/" + LocalEnvironment.PROJECT_ID + "/databases/(default)/documents/"
        val name = document.getString("name")
        check(name.startsWith(base)) { "Foreign cleanup database" }
        return name.removePrefix(base)
    }

    private fun wireString(fields: JSONObject, name: String): String =
        fields.getJSONObject(name).getString("stringValue")

    /** Local-only bounded test transport; never logs payload, credentials, email or path values. */
    private fun cleanupRequest(
        path: String,
        method: String = "GET",
        body: JSONObject? = null,
    ): CleanupResponse {
        check(LocalEnvironment.PROJECT_ID == "demo-uac-android")
        check(LocalEnvironment.HOST == "10.0.2.2" && LocalEnvironment.FIRESTORE_PORT == 8088)
        check(path.startsWith(cleanupDocumentsBase()))
        check(method in setOf("GET", "DELETE", "POST"))
        check(!path.contains("..") && !path.contains('#'))
        check((method == "POST") == (body != null))
        if (method == "POST")
            check(path.endsWith(":runQuery") || path.endsWith(":listCollectionIds"))
        val connection =
            URL("http://" + LocalEnvironment.HOST + ":8088" + path).openConnection()
                as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 5_000
            connection.readTimeout = 5_000
            connection.setRequestProperty("Authorization", "Bearer owner")
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.outputStream.use {
                    it.write(body.toString().toByteArray(Charsets.UTF_8))
                }
            }
            val status = connection.responseCode
            if (status !in 200..299) {
                connection.errorStream?.close()
                return CleanupResponse(status, "")
            }
            val bytes = ByteArrayOutputStream()
            connection.inputStream.use { input ->
                val chunk = ByteArray(4_096)
                while (true) {
                    val count = input.read(chunk)
                    if (count == -1) break
                    check(bytes.size() + count <= 65_536) { "Cleanup response exceeded bound" }
                    bytes.write(chunk, 0, count)
                }
            }
            return CleanupResponse(status, bytes.toString(Charsets.UTF_8.name()))
        } finally {
            connection.disconnect()
        }
    }

    private fun deleteExactFixture(path: String, index: Int): RegistrationCleanupOutcome {
        val requestPath = AuthEmulatorFixtures.documentPath(path)
        var deleteStatus: Int? = null
        var readStatus: Int? = null
        var deleteFailure: Throwable? = null
        var readFailure: Throwable? = null
        try {
            val response = cleanupRequest(requestPath, "DELETE")
            deleteStatus = response.status
            println("RegistrationsJourney cleanup_document=$index delete_http=" + response.status)
        } catch (error: Throwable) {
            deleteFailure = error
        }
        try {
            val readBack = cleanupRequest(requestPath)
            readStatus = readBack.status
            println(
                "RegistrationsJourney cleanup_document=$index absent=" +
                    (readBack.status == 404) +
                    " read_http=" +
                    readBack.status
            )
        } catch (error: Throwable) {
            readFailure = error
        }
        val outcome =
            RegistrationCleanupPolicy.evaluate(
                deleteStatus,
                readStatus,
                deleteTransportError = deleteFailure != null,
                readTransportError = readFailure != null,
            )
        println("RegistrationsJourney cleanup_document=$index outcome=$outcome")
        if (outcome == RegistrationCleanupOutcome.FAILED) {
            val failure =
                deleteFailure
                    ?: readFailure
                    ?: IllegalStateException(
                        "Exact cleanup invariant failed registered_index=$index " +
                            "delete_http=$deleteStatus read_http=$readStatus"
                    )
            if (deleteFailure != null && readFailure != null && readFailure !== failure)
                failure.addSuppressed(readFailure)
            throw failure
        }
        return outcome
    }

    private suspend fun denied(action: suspend () -> Unit) {
        try {
            action()
            fail("Foreign query/client membership write must be denied")
        } catch (error: PersonalException) {
            assertEquals(PersonalFailure.DENIED, error.reason)
        } catch (error: FirebaseFirestoreException) {
            assertEquals(FirebaseFirestoreException.Code.PERMISSION_DENIED, error.code)
        }
    }
}

internal enum class RegistrationCleanupOutcome {
    CONFIRMED_ABSENT,
    CONFIRMED_ABSENT_WITH_WARNING,
    FAILED,
}

/** Only this local fixture harness: absence is its invariant, not DELETE transport correctness. */
internal object RegistrationCleanupPolicy {
    fun evaluate(
        deleteStatus: Int?,
        readStatus: Int?,
        deleteTransportError: Boolean = false,
        readTransportError: Boolean = false,
    ): RegistrationCleanupOutcome {
        if (deleteTransportError || readTransportError || readStatus != 404)
            return RegistrationCleanupOutcome.FAILED
        return when {
            (deleteStatus != null && deleteStatus in 200..299) || deleteStatus == 404 ->
                RegistrationCleanupOutcome.CONFIRMED_ABSENT
            // Emulator listener notification can fail after a committed exact-target DELETE.
            // This does not assert causality or hide the warning, and never causes a replay.
            deleteStatus == 500 -> RegistrationCleanupOutcome.CONFIRMED_ABSENT_WITH_WARNING
            else -> RegistrationCleanupOutcome.FAILED
        }
    }
}
