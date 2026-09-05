package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.dsaappeal.*
import at.uac.android.feature.feedback.*
import com.google.firebase.FirebaseApp
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Synthetic own feedback projections only. Does not decide, appeal, call Functions or use cloud.
 */
@RunWith(AndroidJUnit4::class)
class DsaAppealReadDeviceTest {
    private val context
        get() = AccountDeletionFixtures.context

    private suspend fun failed(expected: DsaAppealReviewFailure, action: suspend () -> Any?) {
        val failure = runCatching { action() }.exceptionOrNull()
        assertEquals(expected, (failure as? DsaAppealReviewException)?.failure)
        assertNull(failure?.cause)
    }

    @Test
    fun actualFirestoreCodesRemainDistinctWithoutPrivateCause() {
        AccountDeletionFixtures.requireLocalAvd()
        for ((code, expected) in
            listOf(
                FirebaseFirestoreException.Code.PERMISSION_DENIED to DsaAppealReviewFailure.ACCESS,
                FirebaseFirestoreException.Code.UNAUTHENTICATED to DsaAppealReviewFailure.ACCESS,
                FirebaseFirestoreException.Code.UNAVAILABLE to DsaAppealReviewFailure.OFFLINE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED to DsaAppealReviewFailure.OFFLINE,
                FirebaseFirestoreException.Code.DATA_LOSS to DsaAppealReviewFailure.INVALID,
                FirebaseFirestoreException.Code.INTERNAL to DsaAppealReviewFailure.UNKNOWN,
            )) assertEquals(
            expected,
            dsaAppealReadFailure(FirebaseFirestoreException("Synthetic", code)),
        )
    }

    @Test
    fun unreadyAndWrongBackendFailBeforeReadingWithoutDefaultApp() = runBlocking {
        AccountDeletionFixtures.requireLocalAvd()
        val source = localDsaAppealReadSource(context)
        for (session in
            listOf(
                DsaAppealSession("reporter", 1, dsaAppealBackendBinding, false),
                DsaAppealSession("reporter", 1, "not-the-local-backend", true),
            )) failed(DsaAppealReviewFailure.ACCESS) { source.read(session, "synthetic") }
        assertFalse(FirebaseApp.getApps(context).any { it.name == FirebaseApp.DEFAULT_APP_NAME })
    }

    @Test
    fun actualOwnServerReviewUsesAuthGateDetectsChangedDecisionAndCleansExactFixtures() =
        runBlocking {
            AccountDeletionFixtures.requireLocalAvd()
            check(AccountDeletionFixtures.online())
            val user = AccountDeletionFixtures.create("deletion-appeal-read")
            val auth = LocalFirebase.auth(context)
            val db = LocalFirebase.firestore(context)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val store = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
            val source = localDsaAppealReadSource(context)
            val decided =
                Instant.now().minusSeconds(60).let {
                    Instant.ofEpochSecond(it.epochSecond, 123_456_789)
                }
            val own = "appeal-${UUID.randomUUID()}"
            val other = "appeal-${UUID.randomUUID()}"
            val paths = listOf("feedback/$own", "feedback/$other")
            var primary: Throwable? = null
            try {
                val decision =
                    mapOf<String, Any?>(
                        "outcome" to "noAction",
                        "factsAndCircumstances" to "PRIVATE SYNTHETIC FACTS",
                        "legalBasis" to "Synthetic basis",
                        "termsBasis" to null,
                        "territorialScope" to "AT",
                        "duration" to "Synthetic duration",
                        "redressInformation" to "Synthetic redress",
                        "automationUsed" to false,
                        "humanReviewConfirmed" to true,
                        "actionVerifiedAt" to decided,
                        "decidedAt" to decided,
                        "decidedByUserId" to "synthetic-owner",
                        "appealDeadline" to decided.plusSeconds(3600),
                    )
                val case =
                    mapOf(
                        "caseNumber" to "SYNTHETIC-ONLY",
                        "status" to "decided",
                        "category" to "other",
                        "exactLocation" to "Synthetic location",
                        "illegalExplanation" to "Synthetic explanation",
                        "legalBasis" to null,
                        "evidence" to "Synthetic evidence",
                        "goodFaithConfirmed" to true,
                        "acknowledgementAt" to decided.minusSeconds(60),
                        "preferredLanguage" to "de",
                        "decision" to decision,
                    )
                fun fields(id: String, uid: String) =
                    FeedbackContract.creation(
                        id,
                        FeedbackSession(uid, 0, true, false, "Synthetic"),
                        FeedbackDraft(FeedbackType.REPORT, "Synthetic report"),
                        decided.minusSeconds(60),
                    ) +
                        mapOf(
                            "status" to "closed",
                            "updatedAt" to decided,
                            "dsaCase" to case,
                            "privateUnneededParent" to "NOT RETAINED",
                        )
                val fixtures = LocalEmulatorFixtures(context)
                fixtures.seed(paths[0], fields(own, user.uid))
                fixtures.seed(paths[1], fields(other, "different-synthetic-reporter"))
                withContext(Dispatchers.Main) { store.restore() }.join()
                val actor = store.state.value.dsaAppealScope()!!
                assertTrue(actor.ready)
                val repository =
                    DsaAppealReadRepository(
                        source,
                        { store.state.value.dsaAppealScope() },
                        AuthDsaAppealReadGate(store),
                    )
                val first = repository.read(actor, own)
                assertEquals("PRIVATE SYNTHETIC FACTS", first.snapshot.decision.facts)
                val saved =
                    db.document(paths[0])
                        .get(Source.SERVER)
                        .await()
                        .getTimestamp("dsaCase.decision.decidedAt")!!
                assertEquals(123_456_000, saved.nanoseconds)
                assertEquals(
                    Instant.ofEpochSecond(saved.seconds, saved.nanoseconds.toLong()),
                    first.snapshot.decision.decidedAt,
                )
                assertEquals(
                    first.snapshot.fingerprint,
                    repository.read(actor, own, first.snapshot.fingerprint).snapshot.fingerprint,
                )
                assertFalse(source.read(actor, own)!!.fields.containsKey("privateUnneededParent"))
                failed(DsaAppealReviewFailure.MISSING) { repository.read(actor, other) }
                failed(DsaAppealReviewFailure.MISSING) {
                    repository.read(actor, "missing-${UUID.randomUUID()}")
                }
                val denied = runCatching {
                    db.document(paths[1]).get(Source.SERVER).await()
                }
                    .exceptionOrNull()
                assertEquals(
                    FirebaseFirestoreException.Code.PERMISSION_DENIED,
                    (denied as? FirebaseFirestoreException)?.code,
                )
                fixtures.seed(
                    paths[0],
                    fields(own, user.uid) +
                        ("dsaCase" to
                            (case +
                                ("decision" to
                                    (decision +
                                        ("factsAndCircumstances" to "Changed synthetic facts"))))),
                )
                failed(DsaAppealReviewFailure.STALE) {
                    repository.read(actor, own, first.snapshot.fingerprint)
                }
                assertEquals(
                    "Changed synthetic facts",
                    repository.read(actor, own).snapshot.decision.facts,
                )
                assertEquals(
                    "closed",
                    AccountDeletionFixtures.field(
                        AccountDeletionFixtures.document(paths[0])!!,
                        "status",
                    ),
                )
                assertTrue(db.collection("${paths[0]}/messages").get(Source.SERVER).await().isEmpty)
                // A forged locally-ready privileged projection still cannot replace the actual TOTP
                // claim.
                AccountDeletionFixtures.patch(
                    "users/${user.uid}",
                    mapOf("globalRole" to "owner", "requiresMultiFactorAuth" to true),
                    merge = true,
                )
                failed(DsaAppealReviewFailure.ACCESS) { source.read(actor, own) }
            } catch (error: Throwable) {
                primary = error
                throw error
            } finally {
                scope.cancel()
                try {
                    AccountDeletionFixtures.clean(user, paths)
                    for (path in
                        paths +
                            listOf("users/${user.uid}", "publicProfiles/${user.uid}")) assertNull(
                        AccountDeletionFixtures.document(path)
                    )
                    AccountDeletionFixtures.assertAuthAbsent(user)
                } catch (cleanup: Throwable) {
                    if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
                }
            }
        }
}
