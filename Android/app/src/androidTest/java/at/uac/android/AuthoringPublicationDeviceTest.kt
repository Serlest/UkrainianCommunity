package at.uac.android

import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.authoring.*
import at.uac.android.feature.authoring.recovery.localAuthoringRecoveryStore
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.*
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

/** Real named Auth, encrypted prepare, actual Firestore Rules. No scheduler worker is invoked. */
class AuthoringPublicationDeviceTest {
    @Test
    fun actualNewsScheduleReceiptPrivacyAndNegativeRules() = runBlocking {
        exercise(ContentKind.NEWS)
    }

    @Test
    fun actualEventScheduleReceiptPrivacyAndNegativeRules() = runBlocking {
        exercise(ContentKind.EVENTS)
    }

    private suspend fun exercise(kind: ContentKind) {
        assumeTrue(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        AuthoringRecoveryFixtures.requireAvd()
        val context = AuthoringRecoveryFixtures.context
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val extra = AuthoringFixtures("author4c-schedule-extra-${UUID.randomUUID()}")
        var phase = "fixture"
        var primary: Throwable? = null
        var fixtureId: String? = null
        try {
            var owned = AuthoringRecoveryFixtures.create(kind)
            fixtureId = owned.suffix
            val auth = LocalFirebase.auth(context)
            val db = LocalFirebase.firestore(context)
            val account = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
            withContext(Dispatchers.Main) { account.restore() }.join()
            assertTrue(account.state.value.readyForActions)
            val actor = requireNotNull(account.state.value.organizationScope())
            val source = localAuthoringSource(context)
            val journal = localAuthoringRecoveryStore(context)
            val org = requireNotNull(source.organization(owned.organizationId, actor))
            var draft =
                AuthoringContract.newDraft(kind, org)
                    .copy(
                        title = "Synthetic scheduled ${kind.collection}",
                        summary = "Only local scheduling proof",
                        body = "No cloud publication or background worker.",
                        publicationMode = AuthoringPublicationMode.SCHEDULED,
                        scheduledAt =
                            Instant.now().plusSeconds(7_200).truncatedTo(ChronoUnit.MICROS),
                    )
            if (kind == ContentKind.NEWS) draft = draft.copy(regionScope = "austria")
            else draft = draft.copy(event = draft.event.copy(venue = "Synthetic scheduled venue"))
            owned = owned.copy(contentId = draft.id)
            AuthoringRecoveryFixtures.write(owned)
            val intent = AuthoringContract.submission(draft, org, actor, null)
            journal.saveDraft(owned.scope, draft, "Europe/Vienna")
            var commits = 0
            val observed =
                object : AuthoringSource by source {
                    override suspend fun commit(
                        submission: AuthoringSubmission,
                        organization: OrganizationRecord,
                        session: OrganizationSession,
                    ) {
                        assertEquals(intent, journal.load(owned.scope)?.pending)
                        commits++
                        source.commit(submission, organization, session)
                    }
                }
            val repository =
                AuthoringRepository(
                    observed,
                    { account.state.value.organizationScope() },
                    AuthOrganizationMutationGate(account),
                    journal,
                )
            phase =
                "encrypted immutable prepare before actual Rules create and exact server receipt"
            val item = repository.submit(intent)
            assertEquals(1, commits)
            assertEquals(AuthoringStatus.SCHEDULED, item.status)
            assertEquals(intent.fields["scheduledAt"], item.fields["scheduledAt"])
            assertTrue(AuthoringContract.matches(intent, item))
            assertFalse(item.editable)
            assertNull(journal.load(owned.scope))
            assertEquals(item.id, repository.submit(intent).id)
            assertEquals("Same intent receipt must not send twice", 1, commits)
            val document = db.document("${kind.collection}/${item.id}").get(Source.SERVER).await()
            val scheduledAt = requireNotNull(document.getTimestamp("scheduledAt"))
            assertEquals(
                intent.fields["scheduledAt"],
                Instant.ofEpochSecond(scheduledAt.seconds, scheduledAt.nanoseconds.toLong()),
            )
            assertEquals("draft", document.getString("moderationStatus"))
            assertEquals(owned.uid, document.getString("authorId"))
            assertEquals(
                listOf(item.id),
                repository.load(org.id, kind, AuthoringStatus.SCHEDULED).page.items.map { it.id },
            )
            assertTrue(repository.load(org.id, kind, AuthoringStatus.APPROVED).page.items.isEmpty())
            expect(AuthoringFailure.DENIED) { repository.open(org.id, kind, item.id) }

            phase =
                "actual Rules reject elapsed or missing schedule, non-draft schedule and foreign author"
            for (invalid in
                listOf(
                    intent.fields + ("scheduledAt" to Instant.now().minusSeconds(60)),
                    intent.fields - "scheduledAt",
                    intent.fields +
                        ("moderationStatus" to
                            if (kind == ContentKind.NEWS) "pendingReview" else "approved"),
                    intent.fields + ("authorId" to "another-synthetic-author"),
                )) {
                val id = UUID.randomUUID().toString()
                extra.ownContent(kind, id)
                expect(AuthoringFailure.DENIED) {
                    db.document("${kind.collection}/$id")
                        .set(
                            (invalid + ("id" to id))
                                .filterValues { it != null }
                                .mapValues { encode(it.value) }
                        )
                        .await()
                }
                assertNull(AccountDeletionFixtures.document("${kind.collection}/$id"))
            }
            assertEquals(1, commits)

            data class Other(val uid: String, val email: String)
            suspend fun other(label: String, verified: Boolean): Other {
                withContext(Dispatchers.Main) { account.signOut() }.join()
                val email = "${extra.organizationId}-$label@example.invalid"
                val user =
                    requireNotNull(
                        auth
                            .createUserWithEmailAndPassword(
                                email,
                                AuthoringRecoveryFixtures.PASSWORD,
                            )
                            .await()
                            .user
                    )
                extra.uids += user.uid
                db.document("users/${user.uid}")
                    .set(
                        registeredProfileFields(
                            user.uid,
                            AuthRegistration(
                                email,
                                "Synthetic schedule $label",
                                "wien",
                                acceptedTerms = true,
                                acceptedPrivacy = true,
                                minimumAgeConfirmed = true,
                            ),
                            FieldValue.serverTimestamp(),
                        )
                    )
                    .await()
                if (verified) {
                    user.sendEmailVerification().await()
                    auth
                        .applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL"))
                        .await()
                    user.reload().await()
                    user.getIdToken(true).await()
                }
                withContext(Dispatchers.Main) { account.restore() }.join()
                assertEquals(verified, account.state.value.readyForActions)
                return Other(user.uid, email)
            }
            phase =
                "another verified organization admin cannot see author's private scheduled draft"
            val verifiedOther = other("verified", true)
            val ownedFixture = AuthoringRecoveryFixtures.fixture(owned)
            ownedFixture.patch(
                "organizations/${org.id}",
                mapOf("adminIds" to listOf(verifiedOther.uid), "updatedAt" to Instant.now()),
            )
            assertTrue(
                repository.load(org.id, kind, AuthoringStatus.SCHEDULED).page.items.isEmpty()
            )
            expect(AuthoringFailure.DENIED) {
                db.document("${kind.collection}/${item.id}").get(Source.SERVER).await()
            }

            phase = "unverified canonical admin cannot schedule via source or direct Rules"
            val unverified = other("unverified", false)
            ownedFixture.patch(
                "organizations/${org.id}",
                mapOf(
                    "adminIds" to listOf(verifiedOther.uid, unverified.uid),
                    "updatedAt" to Instant.now(),
                ),
            )
            expect(AuthoringFailure.NOT_READY) {
                repository.load(org.id, kind, AuthoringStatus.SCHEDULED)
            }
            val deniedId = UUID.randomUUID().toString()
            extra.ownContent(kind, deniedId)
            expect(AuthoringFailure.DENIED) {
                db.document("${kind.collection}/$deniedId")
                    .set(
                        (intent.fields + mapOf("id" to deniedId, "authorId" to unverified.uid))
                            .filterValues { it != null }
                            .mapValues { encode(it.value) }
                    )
                    .await()
            }
            assertNull(AccountDeletionFixtures.document("${kind.collection}/$deniedId"))

            phase =
                "fresh organization role revocation blocks original actor while journal stays clear"
            withContext(Dispatchers.Main) { account.signOut() }.join()
            withContext(Dispatchers.Main) {
                    requireNotNull(account.signIn(owned.email, AuthoringRecoveryFixtures.PASSWORD))
                }
                .join()
            assertTrue(account.state.value.readyForActions)
            ownedFixture.patch(
                "organizations/${org.id}",
                mapOf(
                    "ownerId" to verifiedOther.uid,
                    "adminIds" to emptyList<String>(),
                    "moderatorIds" to emptyList<String>(),
                    "updatedAt" to Instant.now(),
                ),
            )
            expect(AuthoringFailure.DENIED) {
                repository.load(org.id, kind, AuthoringStatus.SCHEDULED)
            }
            assertNull(journal.load(owned.scope))
            assertEquals(1, commits)
            phase = "guest has no mutation authority"
            withContext(Dispatchers.Main) { account.signOut() }.join()
            expect(AuthoringFailure.SIGN_IN) { repository.submit(intent) }
        } catch (error: Throwable) {
            val reported =
                AssertionError(
                    "Scheduled ${kind.collection} device phase=$phase class=${error.javaClass.simpleName}",
                    error,
                )
            primary = reported
            throw reported
        } finally {
            scope.cancel()
            cleanupEveryOwnedFixtureItem(
                listOf<suspend () -> Unit>(
                    { extra.cleanup() },
                    {
                        if (fixtureId != null && AuthoringRecoveryFixtures.exists()) {
                            check(AuthoringRecoveryFixtures.read().suffix == fixtureId)
                            AuthoringRecoveryFixtures.cleanup()
                        }
                    },
                ),
                primary,
            ) {
                it()
            }
        }
    }

    private suspend fun expect(expected: AuthoringFailure, action: suspend () -> Unit) {
        val error =
            runCatching { action() }.exceptionOrNull() ?: throw AssertionError("Expected $expected")
        assertEquals(error.javaClass.simpleName, expected, authoringFailure(error))
    }

    private fun encode(value: Any?): Any? =
        when (value) {
            is Instant ->
                value.truncatedTo(ChronoUnit.MICROS).let { Timestamp(it.epochSecond, it.nano) }
            is Map<*, *> -> value.entries.associate { it.key.toString() to encode(it.value) }
            is List<*> -> value.map(::encode)
            else -> value
        }
}
