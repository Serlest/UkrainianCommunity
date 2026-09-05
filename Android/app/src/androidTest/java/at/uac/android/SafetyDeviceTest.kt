package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalFunctions
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.auth.FirebaseAuthBackend
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.safety.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.util.UUID
import java.util.concurrent.TimeUnit
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

/**
 * Real named Android Auth → fixed local callable protocol → unchanged safety handlers/Rules →
 * server read-back.
 */
@RunWith(AndroidJUnit4::class)
class SafetyDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val functionsOnline
        get() = InstrumentationRegistry.getArguments().getString("expectFunctions") == "true"

    @Test
    fun localSafetyAuthorityAndStoppedRuntimeStayClosed() = runBlocking {
        assertEquals("demo-uac-android", LocalFirebase.auth(context).app.options.projectId)
        expect(SafetyFailure.SIGN_IN) {
            SafetyRepository(localSafetySource(context), { null }).blocks()
        }
        if (
            !functionsOnline &&
                InstrumentationRegistry.getArguments().getString("expectEmulator") != "true"
        ) {
            LocalFirebase.auth(context).signOut()
            expect(SafetyFailure.OFFLINE) {
                LocalFunctions.instance(context)
                    .getHttpsCallable("getBlockedOrganizations")
                    .withTimeout(3, TimeUnit.SECONDS)
                    .call(emptyMap<String, Any>())
                    .await()
            }
        }
    }

    @Test
    fun verifiedUserBlockReportAndOrganizationUnblockReadBack() = runBlocking {
        if (!functionsOnline) return@runBlocking
        check(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val functions = LocalFunctions.instance(context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val store = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
        val repository =
            SafetyRepository(
                localSafetySource(context),
                { store.state.value.safetyScope() },
                AuthSafetyMutationGate(store),
            )
        val prefix = "safety-${UUID.randomUUID()}"
        val email = "$prefix@example.invalid"
        val author = "$prefix-author"
        val org = "$prefix-org"
        val news = "$prefix-news"
        val event = "$prefix-event"
        val comment = "$prefix-comment"
        val created = mutableSetOf<String>()
        var uid: String? = null
        auth.signOut()
        suspend fun seed(path: String, fields: Map<String, Any>) {
            withContext(Dispatchers.IO) {
                AuthEmulatorFixtures.adminRequest(
                    8088,
                    AuthEmulatorFixtures.documentPath(path),
                    "PATCH",
                    fields,
                )
            }
            created += path
        }
        suspend fun delete(path: String) =
            withContext(Dispatchers.IO) {
                AuthEmulatorFixtures.adminRequest(
                    8088,
                    AuthEmulatorFixtures.documentPath(path),
                    "DELETE",
                )
                Unit
            }
        try {
            AuthEmulatorFixtures.seedLegalReference()
            val user =
                auth
                    .createUserWithEmailAndPassword(email, "Synthetic-local-safety-only!")
                    .await()
                    .user!!
            uid = user.uid
            db.document("users/$uid")
                .set(
                    registeredProfileFields(
                        uid,
                        AuthRegistration(
                            email,
                            "Synthetic Safety Actor",
                            "wien",
                            acceptedTerms = true,
                            acceptedPrivacy = true,
                            minimumAgeConfirmed = true,
                        ),
                        FieldValue.serverTimestamp(),
                    )
                )
                .await()
            seed(
                "users/$author",
                mapOf(
                    "id" to author,
                    "displayName" to "Synthetic Safety Author",
                    "globalRole" to "user",
                    "accountStatus" to "active",
                    "blockState" to "active",
                ),
            )
            seed(
                "organizations/$org",
                mapOf(
                    "id" to org,
                    "name" to "Synthetic Safety Organization",
                    "ownerId" to author,
                    "moderationStatus" to "approved",
                ),
            )
            seed(
                "news/$news",
                mapOf(
                    "id" to news,
                    "title" to "Synthetic Safety News",
                    "body" to "Synthetic body",
                    "authorId" to author,
                    "sourceType" to "organization",
                    "organizationId" to org,
                    "moderationStatus" to "approved",
                ),
            )
            seed(
                "events/$event",
                mapOf(
                    "id" to event,
                    "title" to "Synthetic Safety Event",
                    "details" to "Synthetic details",
                    "authorId" to author,
                    "sourceType" to "organization",
                    "organizationId" to org,
                    "moderationStatus" to "approved",
                ),
            )
            seed(
                "news/$news/comments/$comment",
                mapOf(
                    "id" to comment,
                    "parentType" to "news",
                    "parentId" to news,
                    "authorId" to author,
                    "text" to "Synthetic comment",
                    "moderationStatus" to "approved",
                    "isDeleted" to false,
                ),
            )

            // Direct test requests intentionally omit the client ready gate: the actual unverified
            // token must fail on the server.
            expect(SafetyFailure.DENIED) {
                functions
                    .getHttpsCallable("setUserBlocked")
                    .call(mapOf("targetUserId" to author, "isBlocked" to true))
                    .await()
            }
            expect(SafetyFailure.DENIED) {
                functions
                    .getHttpsCallable("setOrganizationBlocked")
                    .call(mapOf("organizationId" to org, "isBlocked" to true))
                    .await()
            }
            user.sendEmailVerification().await()
            auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
            user.reload().await()
            user.getIdToken(true).await()
            withContext(Dispatchers.Main) { store.restore() }.join()
            assertTrue(
                "Real authoritative account must be ready",
                store.state.value.readyForActions,
            )
            assertTrue(repository.blocks().users.isEmpty())

            val blockedUser = repository.setUser(author, true)!!
            created += "users/$uid/blockedUsers/$author"
            assertEquals(blockedUser.blockedAt, repository.setUser(author, true)!!.blockedAt)
            val storedUser =
                db.document("users/$uid/blockedUsers/$author").get(Source.SERVER).await()
            assertEquals(author, storedUser.getString("targetUserId"))
            assertNotNull(storedUser.getTimestamp("updatedAt"))
            assertEquals(listOf(author), repository.blocks().users.map { it.id })
            assertDenied { db.document("users/$uid/blockedUsers/$author").delete().await() }
            assertDenied {
                db.document("users/$author/blockedUsers/$uid").get(Source.SERVER).await()
            }
            expect(SafetyFailure.OWN_TARGET) { repository.setUser(uid, true) }

            val blockedOrg = repository.setOrganization(org, true)!!
            created += "users/$uid/blockedOrganizations/$org"
            assertEquals(blockedOrg.blockedAt, repository.setOrganization(org, true)!!.blockedAt)
            assertEquals(listOf(org), repository.blocks().organizations.map { it.id })
            assertDenied {
                db.document("users/$uid/blockedOrganizations/$org").get(Source.SERVER).await()
            }
            assertDenied {
                db.document("users/$uid/blockedOrganizations/$org")
                    .set(mapOf("organizationId" to org))
                    .await()
            }
            val state = repository.blocks()
            val policy =
                SafetyVisibility(
                    state.users.map { it.id }.toSet(),
                    state.organizations.map { it.id }.toSet(),
                )
            assertFalse(policy.allowsAuthor(author))
            assertTrue(policy.allowsAuthor(null))
            assertFalse(
                policy.allows(
                    Content(
                        ContentKind.NEWS,
                        news,
                        mapOf("authorId" to author, "organizationId" to org),
                    )
                )
            )
            assertFalse(
                policy.allows(Content(ContentKind.EVENTS, event, mapOf("organizationId" to org)))
            )
            assertFalse(
                policy.allows(Content(ContentKind.ORGANIZATIONS, org, mapOf("ownerId" to author)))
            )

            val reportDraft =
                SafetyReportDraft(
                    SafetyReason.SPAM,
                    "Synthetic local explanation: this is only an automated test.",
                    "Synthetic basis",
                    "Synthetic evidence",
                    true,
                )
            for (target in
                listOf(
                    SafetyReportTarget(SafetyTargetType.NEWS, news, "News", author),
                    SafetyReportTarget(SafetyTargetType.EVENT, event, "Event", author),
                    SafetyReportTarget(SafetyTargetType.ORGANIZATION, org, "Organization", author),
                    SafetyReportTarget(
                        SafetyTargetType.COMMENT,
                        comment,
                        "Comment",
                        author,
                        SafetyTargetType.NEWS,
                        news,
                    ),
                )) {
                val receipt = repository.submit(target, reportDraft)
                created += "feedback/${receipt.id}"
                created += "dsaCases/${receipt.id}"
                val report = db.document("feedback/${receipt.id}").get(Source.SERVER).await()
                assertEquals(uid, report.getString("userId"))
                assertEquals("report", report.getString("type"))
                assertEquals(target.id, report.getString("reportContext.targetId"))
                assertEquals(receipt.caseNumber, report.getString("dsaCase.caseNumber"))
                assertEquals(
                    reportDraft.explanation,
                    report.getString("dsaCase.illegalExplanation"),
                )
                assertFalse(receipt.duplicate)
                assertDenied { db.document("dsaCases/${receipt.id}").get(Source.SERVER).await() }
            }
            expect(SafetyFailure.INVALID) {
                functions
                    .getHttpsCallable("submitContentReport")
                    .call(
                        mapOf("targetType" to "comment", "targetId" to comment) +
                            reportDraft.fields()
                    )
                    .await()
            }
            expect(SafetyFailure.OWN_TARGET) {
                repository.submit(
                    SafetyReportTarget(SafetyTargetType.NEWS, news, "Own", uid),
                    reportDraft,
                )
            }

            assertNull(repository.setUser(author, false))
            assertNull(repository.setUser(author, false))
            repository.setUser(author, true)
            delete("users/$author")
            expect(SafetyFailure.MISSING) { repository.setUser(author, false) }
            assertEquals(
                author,
                repository.blocks().users.single().id,
            ) // Truthful existing backend limitation.
            seed(
                "users/$author",
                mapOf(
                    "id" to author,
                    "displayName" to "Synthetic Safety Author",
                    "accountStatus" to "active",
                    "blockState" to "active",
                ),
            )
            assertNull(repository.setUser(author, false))
            delete("organizations/$org")
            assertNull(
                repository.setOrganization(org, false)
            ) // Existing callable explicitly supports deleted organizations.
            assertNull(repository.setOrganization(org, false))
            assertTrue(repository.blocks().organizations.isEmpty())
        } finally {
            scope.cancel()
            for (path in created.toList().asReversed()) delete(path)
            uid?.let {
                if (auth.currentUser?.uid == it) auth.currentUser!!.delete().await()
                delete("users/$it")
                delete("publicProfiles/$it")
            }
            auth.signOut()
        }
    }

    private suspend fun expect(expected: SafetyFailure, operation: suspend () -> Unit) {
        try {
            operation()
            fail("Expected $expected")
        } catch (error: Exception) {
            assertEquals(
                "Failure class: ${error.javaClass.simpleName}",
                expected,
                safetyFailure(error),
            )
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
