package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.dsastatement.*
import com.google.firebase.FirebaseApp
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.util.UUID
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Exact synthetic local fixtures only; no real DSA action or privileged success. */
@RunWith(AndroidJUnit4::class)
class DsaStatementDeviceTest {
    @Test
    fun actualFirestoreErrorCodesKeepTheirReadMeaning() {
        AccountDeletionFixtures.requireLocalAvd()
        for ((code, expected) in
            listOf(
                FirebaseFirestoreException.Code.PERMISSION_DENIED to DsaStatementFailure.ACCESS,
                FirebaseFirestoreException.Code.UNAUTHENTICATED to DsaStatementFailure.ACCESS,
                FirebaseFirestoreException.Code.UNAVAILABLE to DsaStatementFailure.OFFLINE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED to DsaStatementFailure.OFFLINE,
                FirebaseFirestoreException.Code.INTERNAL to DsaStatementFailure.UNKNOWN,
            )) assertEquals(
            expected,
            dsaStatementReadFailure(FirebaseFirestoreException("synthetic", code)),
        )
    }

    private val context
        get() = AccountDeletionFixtures.context

    private suspend fun failed(expected: DsaStatementFailure, action: suspend () -> Any?) {
        val error = runCatching { action() }.exceptionOrNull()
        assertEquals(expected, (error as? DsaStatementException)?.failure)
    }

    @Test
    fun unreadyReadRejectsBeforeRequestWithoutDefaultApp() = runBlocking {
        AccountDeletionFixtures.requireLocalAvd()
        val source = localDsaStatementSource(context)
        failed(DsaStatementFailure.ACCESS) {
            source.read(
                DsaStatementSession("unready", 1, dsaStatementBackendBinding, false),
                "synthetic",
            )
        }
        assertFalse(FirebaseApp.getApps(context).any { it.name == FirebaseApp.DEFAULT_APP_NAME })
    }

    @Test
    fun actualAuthorCanReadOnlySanitizedOwnStatementAndCleanupIsVerified() = runBlocking {
        AccountDeletionFixtures.requireLocalAvd()
        check(AccountDeletionFixtures.online())
        val user = AccountDeletionFixtures.create("deletion-dsa-statement")
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val source = localDsaStatementSource(context)
        val own = "dsa-${UUID.randomUUID()}"
        val other = "dsa-${UUID.randomUUID()}"
        val paths = listOf("dsaCases/$own", "dsaCases/$other")
        var primary: Throwable? = null
        try {
            val decision =
                mapOf(
                    "outcome" to "removed",
                    "factsAndCircumstances" to "Synthetic facts",
                    "legalBasis" to "Synthetic basis",
                    "termsBasis" to "Synthetic terms",
                    "territorialScope" to "AT",
                    "duration" to "Synthetic duration",
                    "redressInformation" to "Synthetic redress",
                    "automationUsed" to false,
                )
            val fields =
                mapOf<String, Any>(
                    "targetAuthorId" to user.uid,
                    "caseNumber" to "SYNTHETIC-ONLY",
                    "status" to "decided",
                    "targetType" to "comment",
                    "targetId" to "synthetic-content",
                    "decision" to decision,
                    "reporterEmail" to "private-reporter@example.invalid",
                    "evidence" to "PRIVATE SYNTHETIC EVIDENCE",
                    "accessTokenHash" to "SYNTHETIC-NOT-A-TOKEN",
                )
            AccountDeletionFixtures.patch(paths[0], fields)
            AccountDeletionFixtures.patch(
                paths[1],
                fields + ("targetAuthorId" to "different-synthetic-author"),
            )
            val session = DsaStatementSession(user.uid, 1, dsaStatementBackendBinding, true)
            val raw = source.read(session, own)
            val statement = DsaStatementContract.response(own, raw)
            assertEquals(own, statement.id)
            assertEquals(DsaStatementOutcome.REMOVED, statement.decision!!.outcome)
            assertFalse(
                (raw as Map<*, *>).keys.any {
                    it in setOf("reporterEmail", "evidence", "accessTokenHash")
                }
            )
            failed(DsaStatementFailure.MISSING) { source.read(session, other) }
            failed(DsaStatementFailure.MISSING) {
                source.read(session, "missing-${UUID.randomUUID()}")
            }
            val direct = runCatching {
                db.document(paths[0]).get(Source.SERVER).await()
            }
                .exceptionOrNull()
            assertEquals(
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                (direct as? FirebaseFirestoreException)?.code,
            )
            assertEquals(
                "decided",
                AccountDeletionFixtures.field(
                    AccountDeletionFixtures.document(paths[0])!!,
                    "status",
                ),
            )
            // Synthetic fixture profile only: a forged ready projection never supplies actual TOTP.
            AccountDeletionFixtures.patch(
                "users/${user.uid}",
                mapOf("globalRole" to "owner", "requiresMultiFactorAuth" to true),
                merge = true,
            )
            failed(DsaStatementFailure.ACCESS) { source.read(session, own) }
            assertNotEquals(
                "totp",
                (auth.currentUser!!.getIdToken(false).await().claims["firebase"] as? Map<*, *>)
                    ?.get("sign_in_second_factor"),
            )
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            try {
                AccountDeletionFixtures.clean(user, paths)
                for (path in
                    paths + listOf("users/${user.uid}", "publicProfiles/${user.uid}")) assertNull(
                    AccountDeletionFixtures.document(path)
                )
                AccountDeletionFixtures.assertAuthAbsent(user)
            } catch (cleanup: Throwable) {
                if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
            }
        }
    }
}
