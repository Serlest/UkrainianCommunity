package at.uac.android

import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalFirebase
import at.uac.android.core.backend.AppBackend
import at.uac.android.feature.auth.FirestoreAuthProfiles
import at.uac.android.feature.moderation.*
import com.google.firebase.firestore.Source
import java.time.Instant
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Test

/** Disposable demo backend only; transport proof does not bypass or prove positive TOTP. */
class Build80TransportDeviceTest {
    @Test
    fun revisionReceiptReplayAndConflictTravelThroughAndroidGateway() = runBlocking {
        AccountDeletionFixtures.requireLocalAvd()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val contentId = "android80-transport-${java.util.UUID.randomUUID()}"
        AuthEmulatorFixtures.adminRequest(
            8088,
            AuthEmulatorFixtures.documentPath("news/$contentId"),
            "PATCH",
            mapOf(
                "id" to contentId,
                "title" to "Synthetic SDK moderation",
                "sourceType" to "organization",
                "organizationId" to "android80-synthetic-org",
                "moderationStatus" to "pendingReview",
                "updatedAt" to Instant.ofEpochMilli(1700000000123),
            ),
        )
        auth
            .signInWithEmailAndPassword(
                "android80-owner@example.invalid",
                "Synthetic-Android80-Only!",
            )
            .await()
        try {
            val fields = db.document("news/$contentId").get(Source.SERVER).await().data!!
            val target = ModerationTarget(ModerationKind.NEWS, contentId)
            val version = ModerationReviewVersion.from(target, fields)
            val pending =
                ModerationPending(
                    ModerationDecisionContract.accountHash(auth.currentUser!!.uid),
                    version,
                    java.util.UUID.randomUUID().toString(),
                    "owner",
                    ModerationDecision.APPROVE,
                    Instant.now(),
                    ModerationDecisionPhase.DISPATCHED,
                )
            val source = localModerationDecisionSource(context)
            try {
                source.authorize(ModerationSession(auth.currentUser!!.uid, 1, "owner", true))
                fail("No TOTP must remain blocked by app authorization")
            } catch (error: ModerationException) {
                assertEquals(ModerationFailure.NOT_READY, error.failure)
            }
            val gateway = AppBackend.callables(context)
            val payload = ModerationBuild80Contract.payload(pending)
            val first =
                gateway.getHttpsCallable("reviewContentModeration").call(payload).await().data
            ModerationBuild80Contract.requireReceipt(pending, first)
            assertEquals(false, (first as Map<*, *>)["replayed"])
            val replay =
                gateway.getHttpsCallable("reviewContentModeration").call(payload).await().data
            ModerationBuild80Contract.requireReceipt(pending, replay)
            assertEquals(true, (replay as Map<*, *>)["replayed"])
            val stored = db.document("news/$contentId").get(Source.SERVER).await()
            assertEquals("approved", stored.getString("moderationStatus"))
            assertEquals(pending.operationId, stored.getString("moderationOperationId"))
            assertTrue(
                ModerationBuild80Contract.confirmsCurrentOperation(
                    pending,
                    auth.currentUser!!.uid,
                    stored.data.orEmpty(),
                )
            )
            try {
                gateway
                    .getHttpsCallable("reviewContentModeration")
                    .call(payload + ("operationId" to java.util.UUID.randomUUID().toString()))
                    .await()
                fail("A new operation using an old revision must fail")
            } catch (error: LocalCallableException) {
                assertEquals(LocalCallableFailure.ABORTED, error.code)
            }

            try {
                gateway
                    .getHttpsCallable("reviewContentModeration")
                    .call(payload + ("decision" to "rejected"))
                    .await()
                fail("Same operation with different payload must fail")
            } catch (error: LocalCallableException) {
                assertEquals(LocalCallableFailure.ALREADY_EXISTS, error.code)
            }
        } finally {
            auth.signOut()
            AuthEmulatorFixtures.adminRequest(
                8088,
                AuthEmulatorFixtures.documentPath("news/$contentId"),
                "DELETE",
            )
        }
    }

    @Test
    fun legalReaderValidatesActualServerDocumentsAndRejectsTampering() = runBlocking {
        AccountDeletionFixtures.requireLocalAvd()
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        AuthEmulatorFixtures.seedLegalReference()
        val profiles = FirestoreAuthProfiles(LocalFirebase.firestore(context))
        val valid = profiles.legalDocuments()
        assertEquals(setOf("terms", "privacy"), valid.map { it.type }.toSet())
        val document =
            at.uac.android.feature.auth.bundledReferenceLegal(context).first { it.type == "terms" }
        val fields = build80LegalFixture(document) + ("contentHash" to "invalid")
        try {
            AuthEmulatorFixtures.adminRequest(
                8088,
                AuthEmulatorFixtures.documentPath(
                    "legalDocuments/terms/versions/${document.version}"
                ),
                "PATCH",
                fields,
            )
            try {
                profiles.legalDocuments()
                fail("Corrupted server document must be rejected")
            } catch (error: at.uac.android.feature.auth.AuthException) {
                assertEquals(at.uac.android.feature.auth.AuthProblem.INVALID_PROFILE, error.problem)
            }
        } finally {
            AuthEmulatorFixtures.seedLegalReference()
        }
    }
}
