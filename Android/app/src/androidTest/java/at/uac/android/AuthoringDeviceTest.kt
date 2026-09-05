package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.authoring.*
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
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AuthoringDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private var phase = "setup"
    private val password = "Synthetic-authoring-only!"

    @Test
    fun guestAuthoringNeverReachesMutationGate() = runBlocking {
        val gate =
            object : OrganizationMutationGate {
                override suspend fun <T> withSession(
                    session: OrganizationSession,
                    operation: suspend () -> T,
                ): T = error("Guest reached mutation gate")
            }
        expect(AuthoringFailure.SIGN_IN) {
            AuthoringRepository(localAuthoringSource(context), { null }, gate)
                .load("synthetic-org", ContentKind.NEWS, AuthoringStatus.APPROVED)
        }
    }

    @Test
    fun actualTextPublishingReviewEditingRolesAndScheduledPrivacy() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        val fixture = AuthoringFixtures("author4c-${UUID.randomUUID()}")
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val source = localAuthoringSource(context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val store = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
        val repo =
            AuthoringRepository(
                source,
                { store.state.value.organizationScope() },
                AuthOrganizationMutationGate(store),
            )
        var failure: Throwable? = null
        data class Account(val uid: String, val email: String)
        suspend fun account(label: String, verified: Boolean = true): Account {
            auth.signOut()
            val email = "${fixture.organizationId}-$label@example.invalid"
            val user = auth.createUserWithEmailAndPassword(email, password).await().user!!
            fixture.uids += user.uid
            db.document("users/${user.uid}")
                .set(
                    registeredProfileFields(
                        user.uid,
                        AuthRegistration(
                            email,
                            "Synthetic $label",
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
                auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
                user.reload().await()
                user.getIdToken(true).await()
                assertTrue(user.isEmailVerified)
            }
            fixture.seed(
                "publicProfiles/${user.uid}",
                mapOf(
                    "id" to user.uid,
                    "displayName" to "Synthetic $label",
                    "city" to "Wien",
                    "updatedAt" to Instant.now(),
                ),
            )
            return Account(user.uid, email)
        }
        suspend fun signIn(account: Account, ready: Boolean = true) {
            withContext(Dispatchers.Main) { store.signOut() }.join()
            withContext(Dispatchers.Main) { store.signIn(account.email, password)!! }.join()
            assertEquals("$phase: readiness", ready, store.state.value.readyForActions)
            assertEquals(account.uid, auth.currentUser?.uid)
        }
        fun prepared(
            kind: ContentKind,
            org: OrganizationRecord,
            title: String = "Synthetic authoring ${kind.collection}",
        ): AuthoringDraft {
            val draft =
                AuthoringContract.newDraft(kind, org)
                    .copy(
                        title = title,
                        summary = "A complete synthetic summary",
                        body = "Only local synthetic full text.",
                        germanTitle = "Lokaler synthetischer Titel",
                        germanSummary = "Lokale Zusammenfassung",
                        germanBody = "Nur lokaler synthetischer Text",
                    )
            fixture.ownContent(kind, draft.id)
            return if (kind == ContentKind.EVENTS)
                draft.copy(
                    event =
                        draft.event.copy(
                            venue = "Synthetic hall",
                            address = "Synthetic street",
                            priceKind = "range",
                            amount = "2.50",
                            maximumAmount = "5.00",
                            capacity = "10",
                        )
                )
            else draft
        }
        suspend fun publish(draft: AuthoringDraft): AuthoringItem {
            val actor = store.state.value.organizationScope()!!
            val org = source.organization(fixture.organizationId, actor)!!
            return repo.submit(AuthoringContract.submission(draft, org, actor, null))
        }
        try {
            AuthEmulatorFixtures.seedLegalReference()
            phase = "create actual synthetic identities"
            val owner = account("owner")
            val admin = account("admin")
            val moderator = account("moderator")
            val stranger = account("stranger")
            val unverified = account("unverified", false)
            signIn(owner)
            val actor = store.state.value.organizationScope()!!
            val basics =
                OrganizationDraft(
                    fixture.organizationId,
                    "Synthetic Authoring SDK",
                    "A verified local synthetic community",
                    region = "wien",
                    city = "Wien",
                )
            val orgFields =
                OrganizationContract.create(basics, actor, Instant.now()) +
                    mapOf(
                        "moderationStatus" to "approved",
                        "ownerId" to owner.uid,
                        "adminIds" to listOf(admin.uid),
                        "moderatorIds" to listOf(moderator.uid),
                    )
            fixture.seed("organizations/${fixture.organizationId}", orgFields)
            fixture.seed(
                "organizations/${fixture.foreignOrganizationId}",
                orgFields +
                    mapOf(
                        "id" to fixture.foreignOrganizationId,
                        "ownerId" to stranger.uid,
                        "adminIds" to emptyList<String>(),
                        "moderatorIds" to emptyList<String>(),
                    ),
            )
            phase = "fresh scoped missing content and approved list"
            val hub = repo.load(fixture.organizationId, ContentKind.NEWS, AuthoringStatus.APPROVED)
            assertTrue(hub.page.items.isEmpty())
            assertNull(
                source.find(
                    fixture.organizationId,
                    ContentKind.NEWS,
                    UUID.randomUUID().toString(),
                    actor,
                )
            )
            phase = "owner creates approved localized news with zero counters"
            val newsDraft = prepared(ContentKind.NEWS, hub.organization)
            val intent = AuthoringContract.submission(newsDraft, hub.organization, actor, null)
            val news = repo.submit(intent)
            assertEquals(AuthoringStatus.APPROVED, news.status)
            assertEquals(owner.uid, news.fields["authorId"])
            assertEquals(0L, news.fields["likeCount"])
            assertEquals(0L, news.fields["commentCount"])
            assertTrue(AuthoringContract.matches(intent, news))
            assertEquals(news, repo.submit(intent))
            assertEquals(
                1,
                repo
                    .load(fixture.organizationId, ContentKind.NEWS, AuthoringStatus.APPROVED)
                    .page
                    .items
                    .size,
            )
            phase = "Austria news submits and client cannot force approval"
            val review =
                publish(prepared(ContentKind.NEWS, hub.organization).copy(regionScope = "austria"))
            assertEquals(AuthoringStatus.REVIEW, review.status)
            expect(AuthoringFailure.DENIED) {
                db.document("news/${review.id}")
                    .update(
                        "moderationStatus",
                        "approved",
                        "updatedAt",
                        FieldValue.serverTimestamp(),
                    )
                    .await()
            }
            assertEquals(
                listOf(review.id),
                repo
                    .load(fixture.organizationId, ContentKind.NEWS, AuthoringStatus.REVIEW)
                    .page
                    .items
                    .map { it.id },
            )
            phase = "actual event create participation pricing occurrence readback"
            val event = publish(prepared(ContentKind.EVENTS, hub.organization))
            assertEquals(AuthoringStatus.APPROVED, event.status)
            assertEquals(true, event.fields["requiresRegistration"])
            assertEquals(0L, event.fields["registeredCount"])
            assertEquals(10L, event.fields["capacity"])
            assertEquals(2.5, event.fields["price"])
            assertTrue((event.fields["occurrences"] as List<*>).isNotEmpty())
            phase = "update preserves existing author counters creation media and publication"
            fixture.patch(
                "news/${news.id}",
                mapOf(
                    "likeCount" to 7L,
                    "viewCount" to 9L,
                    "commentCount" to 2L,
                    "imageURL" to "https://example.invalid/preserved-cover",
                    "mediaMetadata" to mapOf("credit" to "Preserved credit"),
                ),
            )
            val base = repo.open(fixture.organizationId, ContentKind.NEWS, news.id).second
            val changed =
                repo.submit(
                    AuthoringContract.submission(
                        AuthoringContract.draft(base).copy(title = "Updated synthetic article"),
                        hub.organization,
                        actor,
                        base,
                    )
                )
            for (key in AuthoringContract.immutableFields) assertEquals(
                "Preserved $key",
                base.fields[key],
                changed.fields[key],
            )
            assertEquals("Updated synthetic article", changed.fields["title"])
            phase = "counter author organization and direct delete injections denied"
            for ((key, value) in
                mapOf(
                    "likeCount" to 99L,
                    "authorId" to stranger.uid,
                    "organizationId" to fixture.foreignOrganizationId,
                    "createdAt" to Timestamp.now(),
                )) expect(AuthoringFailure.DENIED) {
                db.document("news/${news.id}").update(key, value).await()
            }
            expect(AuthoringFailure.DENIED) { db.document("news/${news.id}").delete().await() }
            phase = "same id foreign organization target remains unavailable"
            val foreignId = UUID.randomUUID().toString()
            fixture.ownContent(ContentKind.NEWS, foreignId)
            fixture.seed(
                "news/$foreignId",
                intent.fields +
                    mapOf(
                        "id" to foreignId,
                        "organizationId" to fixture.foreignOrganizationId,
                        "authorId" to stranger.uid,
                    ),
            )
            assertNull(source.find(fixture.organizationId, ContentKind.NEWS, foreignId, actor))
            expect(AuthoringFailure.DENIED) {
                repo.load(fixture.foreignOrganizationId, ContentKind.NEWS, AuthoringStatus.APPROVED)
            }
            phase = "real scheduled document own-only list and no C1 mutation"
            val scheduledDraft = prepared(ContentKind.NEWS, hub.organization)
            val scheduled =
                AuthoringContract.submission(scheduledDraft, hub.organization, actor, null).fields +
                    mapOf(
                        "moderationStatus" to "draft",
                        "scheduledAt" to Instant.now().plusSeconds(3_600),
                    )
            db.document("news/${scheduledDraft.id}")
                .set(scheduled.filterValues { it != null }.mapValues { encode(it.value) })
                .await()
            val scheduledItem =
                repo
                    .load(fixture.organizationId, ContentKind.NEWS, AuthoringStatus.SCHEDULED)
                    .page
                    .items
                    .single()
            assertEquals(scheduledDraft.id, scheduledItem.id)
            assertFalse(scheduledItem.editable)
            expect(AuthoringFailure.DENIED) {
                repo.open(fixture.organizationId, ContentKind.NEWS, scheduledDraft.id)
            }
            phase =
                "canonical organization admin may create but cannot read another author's scheduled draft"
            signIn(admin)
            assertTrue(
                repo
                    .load(fixture.organizationId, ContentKind.NEWS, AuthoringStatus.SCHEDULED)
                    .page
                    .items
                    .isEmpty()
            )
            expect(AuthoringFailure.DENIED) {
                db.document("news/${scheduledDraft.id}").get(Source.SERVER).await()
            }
            val adminNews =
                publish(
                    prepared(
                        ContentKind.NEWS,
                        source.organization(
                            fixture.organizationId,
                            store.state.value.organizationScope()!!,
                        )!!,
                    )
                )
            assertEquals(admin.uid, adminNews.fields["authorId"])
            phase = "canonical moderator creates and edits content without organization-info rights"
            signIn(moderator)
            val modOrg =
                source.organization(
                    fixture.organizationId,
                    store.state.value.organizationScope()!!,
                )!!
            assertEquals(OrganizationAuthority.MODERATOR, modOrg.authority)
            val modEvent = publish(prepared(ContentKind.EVENTS, modOrg))
            assertEquals(moderator.uid, modEvent.fields["authorId"])
            val otherBase = repo.open(fixture.organizationId, ContentKind.NEWS, news.id).second
            val moderatorUpdate =
                repo.submit(
                    AuthoringContract.submission(
                        AuthoringContract.draft(otherBase).copy(title = "Moderator content edit"),
                        modOrg,
                        store.state.value.organizationScope()!!,
                        otherBase,
                    )
                )
            assertEquals(owner.uid, moderatorUpdate.fields["authorId"])
            expect(AuthoringFailure.DENIED) {
                db.document("organizations/${fixture.organizationId}")
                    .update("name", "Forbidden moderator info")
                    .await()
            }
            phase = "fresh role revocation prevents old draft write"
            fixture.patch(
                "organizations/${fixture.organizationId}",
                mapOf("moderatorIds" to emptyList<String>(), "updatedAt" to Instant.now()),
            )
            expect(AuthoringFailure.DENIED) {
                repo.submit(
                    AuthoringContract.submission(
                        AuthoringContract.draft(moderatorUpdate)
                            .copy(title = "Stale moderator write"),
                        modOrg,
                        store.state.value.organizationScope()!!,
                        moderatorUpdate,
                    )
                )
            }
            phase = "unverified actor rejected by source and actual Rules token"
            fixture.patch(
                "organizations/${fixture.organizationId}",
                mapOf(
                    "adminIds" to listOf(admin.uid, unverified.uid),
                    "updatedAt" to Instant.now(),
                ),
            )
            signIn(unverified, false)
            assertFalse(auth.currentUser!!.isEmailVerified)
            expect(AuthoringFailure.NOT_READY) {
                repo.load(fixture.organizationId, ContentKind.NEWS, AuthoringStatus.APPROVED)
            }
            val forged = prepared(ContentKind.NEWS, hub.organization)
            val data =
                AuthoringContract.submission(forged, hub.organization, actor, null).fields +
                    ("authorId" to unverified.uid)
            expect(AuthoringFailure.DENIED) {
                db.document("news/${forged.id}")
                    .set(data.filterValues { it != null }.mapValues { encode(it.value) })
                    .await()
            }
            phase = "restricted verified account cannot author despite canonical role"
            signIn(owner)
            fixture.patch(
                "users/${owner.uid}",
                mapOf("accountStatus" to "suspendedUntil", "blockState" to "suspendedUntil"),
            )
            withContext(Dispatchers.Main) { store.refresh() }.join()
            assertFalse(store.state.value.readyForActions)
            expect(AuthoringFailure.NOT_READY) {
                repo.load(fixture.organizationId, ContentKind.NEWS, AuthoringStatus.APPROVED)
            }
            expect(AuthoringFailure.DENIED) {
                db.document("news/${news.id}").update("title", "Restricted write").await()
            }
        } catch (error: Throwable) {
            val reported = AssertionError("Authoring device phase=$phase", error)
            failure = reported
            throw reported
        } finally {
            scope.cancel()
            auth.signOut()
            fixture.cleanup(failure)
        }
    }

    private suspend fun expect(expected: AuthoringFailure, action: suspend () -> Unit) {
        val error =
            runCatching { action() }.exceptionOrNull()
                ?: throw AssertionError("$phase: expected $expected")
        assertEquals("$phase: ${error.javaClass.simpleName}", expected, authoringFailure(error))
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
