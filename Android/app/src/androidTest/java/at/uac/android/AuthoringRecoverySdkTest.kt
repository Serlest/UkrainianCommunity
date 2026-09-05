package at.uac.android

import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.authoring.*
import at.uac.android.feature.authoring.recovery.localAuthoringRecoveryStore
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.*
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class AuthoringRecoverySdkTest {
    @Test
    fun actualSdkCommitLostReceiptThenNewRepositoryReadOnlyRecovery() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        AuthoringRecoveryFixtures.requireAvd()
        val context = AuthoringRecoveryFixtures.context
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        var phase = "create fixture"
        var primary: Throwable? = null
        try {
            var owned = AuthoringRecoveryFixtures.create()
            val auth = LocalFirebase.auth(context)
            val db = LocalFirebase.firestore(context)
            val account = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
            withContext(Dispatchers.Main) { account.restore() }.join()
            assertTrue(account.state.value.readyForActions)
            val actor = requireNotNull(account.state.value.organizationScope())
            assertEquals(owned.uid, actor.uid)
            val source = localAuthoringSource(context)
            val journal = localAuthoringRecoveryStore(context)
            val org = requireNotNull(source.organization(owned.organizationId, actor))
            val draft =
                AuthoringContract.newDraft(ContentKind.NEWS, org)
                    .copy(
                        title = "SDK recovery exact title",
                        summary = "Only synthetic summary",
                        body = "Only synthetic encrypted recovery body",
                    )
            owned = owned.copy(contentId = draft.id)
            AuthoringRecoveryFixtures.write(owned)
            val intent = AuthoringContract.submission(draft, org, actor, null)
            journal.saveDraft(owned.scope, draft, "Europe/Vienna")
            var commits = 0
            val lost =
                object : AuthoringSource by source {
                    override suspend fun commit(
                        submission: AuthoringSubmission,
                        organization: OrganizationRecord,
                        session: OrganizationSession,
                    ) {
                        assertEquals(intent, journal.load(owned.scope)?.pending)
                        commits++
                        source.commit(submission, organization, session)
                        throw AuthoringException(AuthoringFailure.UNCONFIRMED)
                    }
                }
            phase =
                "real Auth gate durable-before-SDK, then synthetic lost receipt after actual commit"
            try {
                AuthoringRepository(
                        lost,
                        { account.state.value.organizationScope() },
                        AuthOrganizationMutationGate(account),
                        journal,
                    )
                    .submit(intent)
                fail("Synthetic lost receipt")
            } catch (error: AuthoringException) {
                assertEquals(AuthoringFailure.UNCONFIRMED, error.failure)
            }
            assertEquals(1, commits)
            assertEquals(intent, journal.load(owned.scope)?.pending)
            val original = requireNotNull(source.find(org.id, ContentKind.NEWS, draft.id, actor))
            assertTrue(AuthoringContract.matches(intent, original))
            phase = "new repository can reconcile only through reads"
            val readOnly =
                object : AuthoringSource by source {
                    override suspend fun commit(
                        submission: AuthoringSubmission,
                        organization: OrganizationRecord,
                        session: OrganizationSession,
                    ): Unit = error("Read-only recovery attempted mutation")
                }
            val second =
                AuthoringRepository(
                    readOnly,
                    { account.state.value.organizationScope() },
                    AuthOrganizationMutationGate(account),
                    journal,
                )
            assertEquals(
                original,
                second.recover(requireNotNull(journal.load(owned.scope)?.pending)),
            )
            assertNull(journal.load(owned.scope))
            assertEquals(1, commits)
            val readBack = source.find(org.id, ContentKind.NEWS, draft.id, actor)
            assertEquals(original, readBack)
            assertEquals(
                listOf(draft.id),
                second.load(org.id, ContentKind.NEWS, AuthoringStatus.APPROVED).page.items.map {
                    it.id
                },
            )
            println(
                "AUTHORING_RECOVERY_SDK_CONFIRMED durableBeforeSdk=true actualCommits=1 recoveryWrites=0 exactReadback=true pending=0"
            )
            phase = "scoped cleanup"
            AuthoringRecoveryFixtures.cleanup()
        } catch (error: Throwable) {
            val reported =
                AssertionError(
                    "Authoring recovery SDK phase=$phase; exact fixture marker retained unless cleanup confirmed",
                    error,
                )
            primary = reported
            throw reported
        } finally {
            scope.cancel()
            // No compensating mutation or account deletion if a pending intent still needs
            // reconciliation.
            if (AuthoringRecoveryFixtures.exists())
                try {
                    val owned = AuthoringRecoveryFixtures.read()
                    if (localAuthoringRecoveryStore(context).load(owned.scope)?.pending == null)
                        AuthoringRecoveryFixtures.cleanup()
                } catch (cleanup: Throwable) {
                    if (primary != null) primary.addSuppressed(cleanup) else throw cleanup
                }
        }
    }
}
