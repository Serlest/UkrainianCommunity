package at.uac.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.*
import at.uac.android.feature.auth.*
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.community.*
import at.uac.android.feature.contentlifecycle.*
import at.uac.android.feature.contentmedia.*
import at.uac.android.feature.organization.*
import com.google.firebase.firestore.Source
import com.google.firebase.storage.StorageException
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ContentLifecycleDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private var phase = "setup"

    @Test
    fun guestNeverReadsPrivateLifecycleOrReachesMutationGate() = runBlocking {
        val gate =
            object : OrganizationMutationGate {
                override suspend fun <T> withSession(
                    session: OrganizationSession,
                    operation: suspend () -> T,
                ): T = error("Guest mutation gate")
            }
        expect(ContentLifecycleFailure.SIGN_IN) {
            ContentLifecycleRepository(localContentLifecycleSource(context), { null }, gate)
                .load(ContentLifecycleTarget("synthetic", ContentKind.NEWS, "synthetic"))
        }
    }

    @Test
    fun actualOwnerDeletionCancellationReferencesRegisteredInboxAndNegatives() = runBlocking {
        assumeTrue(
            InstrumentationRegistry.getArguments().getString("expectEmulator") == "true" &&
                InstrumentationRegistry.getArguments().getString("expectFunctions") == "true"
        )
        val fixture = ContentLifecycleFixtures("author4clife-${UUID.randomUUID()}")
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        val functions = LocalFunctions.instance(context)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val store = AuthStore(FirebaseAuthBackend(auth), FirestoreAuthProfiles(db), scope)
        val gate = AuthOrganizationMutationGate(store)
        val source = localContentLifecycleSource(context)
        val repo =
            ContentLifecycleRepository(source, { store.state.value.organizationScope() }, gate)
        val authoring =
            AuthoringRepository(
                localAuthoringSource(context),
                { store.state.value.organizationScope() },
                gate,
            )
        val community =
            CommunityRepository(
                localCommunitySource(context),
                { store.state.value.communityScope() },
                AuthCommunityMutationGate(store),
            )
        val covers =
            ContentCoverRepository(
                localContentCoverSource(context),
                { store.state.value.organizationScope() },
                gate,
            )
        var failure: Throwable? = null
        var watch: Job? = null
        suspend fun signIn(account: ContentCoverFixtures.Account, ready: Boolean = true) {
            withContext(Dispatchers.Main) { store.signOut() }.join()
            withContext(Dispatchers.Main) { store.signIn(account.email, fixture.password)!! }.join()
            assertEquals("$phase: readiness", ready, store.state.value.readyForActions)
            assertEquals(account.uid, auth.currentUser?.uid)
        }
        suspend fun create(target: ContentLifecycleTarget): AuthoringItem {
            val actor = requireNotNull(store.state.value.organizationScope())
            val org =
                requireNotNull(
                    localAuthoringSource(context).organization(target.organizationId, actor)
                )
            val draft =
                AuthoringContract.newDraft(target.kind, org)
                    .copy(
                        id = target.contentId,
                        title = "Synthetic lifecycle ${target.kind.collection}",
                        summary = "Synthetic local lifecycle summary",
                        body = "Only synthetic local content.",
                    )
                    .let {
                        if (target.kind == ContentKind.EVENTS)
                            it.copy(
                                event = it.event.copy(venue = "Synthetic hall", capacity = "10")
                            )
                        else it
                    }
            return authoring.submit(AuthoringContract.submission(draft, org, actor, null))
        }
        suspend fun call(target: ContentLifecycleTarget) =
            withContext(Dispatchers.IO) {
                val news = target.kind == ContentKind.NEWS
                functions
                    .getHttpsCallable(if (news) "deleteNews" else "cancelEvent")
                    .withTimeout(if (news) 300_000 else 60_000, TimeUnit.MILLISECONDS)
                    .call(mapOf((if (news) "newsId" else "eventId") to target.contentId))
                    .await()
            }
        try {
            AuthEmulatorFixtures.seedLegalReference()
            phase = "fresh verified actors and canonical roles"
            val owner = fixture.media.account("owner")
            val admin = fixture.media.account("admin")
            val moderator = fixture.media.account("moderator")
            val stranger = fixture.media.account("stranger")
            val attendee = fixture.media.account("attendee")
            val unverified = fixture.media.account("unverified", false)
            fixture.media.organization(owner, listOf(admin, unverified), listOf(moderator))
            fixture.media.organization(stranger, foreign = true)
            val news = fixture.register(ContentKind.NEWS)
            val emptyEvent = fixture.register(ContentKind.EVENTS)
            val registeredEvent = fixture.register(ContentKind.EVENTS)
            val guard = fixture.register(ContentKind.NEWS)
            val foreign = fixture.register(ContentKind.NEWS, true)
            signIn(stranger)
            create(foreign)
            signIn(owner)
            create(news)
            create(emptyEvent)
            create(registeredEvent)
            create(guard)

            phase = "server aggregate and transaction missing or foreign target boundaries"
            val missing = fixture.register(ContentKind.NEWS)
            assertNull(repo.load(missing).item)
            assertNull(repo.load(foreign.copy(organizationId = fixture.organizationId)).item)
            expect(ContentLifecycleFailure.DENIED) { repo.load(foreign) }
            expectCallable(LocalCallableFailure.NOT_FOUND) { call(missing) }
            expectCallable(LocalCallableFailure.PERMISSION_DENIED) { call(foreign) }
            phase = "unchanged Rules forbid direct News and Event deletion"
            for (target in listOf(news, emptyEvent)) expect(ContentLifecycleFailure.DENIED) {
                db.document("${target.kind.collection}/${target.contentId}").delete().await()
            }

            phase = "valid active organization editors lack destructive actor permission"
            for (account in listOf(admin, moderator)) {
                signIn(account)
                expect(ContentLifecycleFailure.DENIED) { repo.load(news) }
                expectCallable(LocalCallableFailure.PERMISSION_DENIED) { call(news) }
                expectCallable(LocalCallableFailure.PERMISSION_DENIED) { call(emptyEvent) }
            }
            signIn(stranger)
            expectCallable(LocalCallableFailure.PERMISSION_DENIED) { call(news) }
            signIn(unverified, false)
            expectCallable(LocalCallableFailure.PERMISSION_DENIED) { call(news) }
            signIn(owner)
            assertTrue(fixture.exists(news))
            assertTrue(fixture.exists(emptyEvent))

            phase = "scheduled draft remains read-only without lifecycle mutation"
            val scheduled = fixture.register(ContentKind.NEWS)
            val template = requireNotNull(repo.load(guard).item)
            fixture.data.seed(
                "news/${scheduled.contentId}",
                template.fields +
                    mapOf(
                        "id" to scheduled.contentId,
                        "moderationStatus" to "draft",
                        "scheduledAt" to Instant.now().plusSeconds(600),
                    ),
            )
            val scheduledBase = repo.load(scheduled)
            assertEquals(AuthoringStatus.SCHEDULED, scheduledBase.item?.status)
            expect(ContentLifecycleFailure.READ_ONLY) {
                repo.execute(ContentLifecycleIntent(scheduledBase))
            }
            assertTrue(fixture.exists(scheduled))

            phase = "actual canonical covers before separate lifecycle actions"
            val photo = ContentCoverFixtures.noisyPhoto(4909)
            for (target in listOf(news, registeredEvent)) {
                val base = covers.load(fixture.cover(target))
                covers.execute(ContentCoverIntent.Upload(base, photo))
                assertEquals(200, fixture.media.storageStatus(fixture.cover(target), "GET"))
            }
            phase = "live listener cannot bypass independent fresh text or owner preflight"
            val stale = repo.load(news)
            val captured = requireNotNull(store.state.value.organizationScope())
            watch = scope.launch {
                source.changes(stale, captured).collect {
                    /* Invalidation evidence is exercised by pure/UI tests. */
                }
            }
            fixture.data.patch(
                "news/${news.contentId}",
                mapOf("title" to "Changed before confirmation", "updatedAt" to Instant.now()),
            )
            expect(ContentLifecycleFailure.STALE) { repo.execute(ContentLifecycleIntent(stale)) }
            val roleBase = repo.load(news)
            fixture.data.patch(
                "organizations/${fixture.organizationId}",
                mapOf("ownerId" to stranger.uid),
            )
            expect(ContentLifecycleFailure.DENIED) {
                repo.execute(ContentLifecycleIntent(roleBase))
            }
            fixture.data.patch(
                "organizations/${fixture.organizationId}",
                mapOf("ownerId" to owner.uid),
            )
            assertTrue(fixture.exists(news))
            assertEquals(200, fixture.media.storageStatus(fixture.cover(news), "GET"))

            phase = "synthetic exact reference fixtures and featured banner before News cascade"
            val referenceTypes =
                listOf(
                    ContentLifecycleFixtures.Reference.COMMENT,
                    ContentLifecycleFixtures.Reference.LIKE,
                    ContentLifecycleFixtures.Reference.BOOKMARK,
                    ContentLifecycleFixtures.Reference.VIEW,
                    ContentLifecycleFixtures.Reference.RECENT,
                    ContentLifecycleFixtures.Reference.HISTORY,
                    ContentLifecycleFixtures.Reference.INBOX,
                )
            val references = referenceTypes.map { type ->
                val path = fixture.reference(news, owner.uid, type)
                fixture.seed(
                    path,
                    mapOf(
                        "id" to path.substringAfterLast('/'),
                        "userId" to owner.uid,
                        "newsId" to news.contentId,
                        "itemId" to news.contentId,
                        "itemType" to "news",
                        "targetId" to news.contentId,
                        "targetType" to "news",
                        "actionTargetId" to news.contentId,
                        "actionType" to "openNews",
                        "text" to "Synthetic reference",
                        "createdAt" to Instant.now(),
                    ),
                )
                path
            }
            val banner =
                fixture.reference(news, owner.uid, ContentLifecycleFixtures.Reference.BANNER)
            fixture.seed(
                banner,
                mapOf(
                    "id" to banner.substringAfterLast('/'),
                    "actionType" to "news",
                    "actionTargetID" to news.contentId,
                    "isActive" to true,
                    "updatedAt" to Instant.now(),
                ),
            )
            val deleted = repo.execute(ContentLifecycleIntent(repo.load(news)))
            assertTrue(deleted.receipt is ContentLifecycleReceipt.Deleted)
            assertNull(deleted.snapshot.item)
            assertFalse(fixture.exists(news))
            for (path in references) assertNull(
                "Exact cascade reference retained",
                fixture.fields(path),
            )
            val disabled = requireNotNull(fixture.fields(banner))
            assertFalse(disabled.getJSONObject("isActive").getBoolean("booleanValue"))
            assertEquals("none", disabled.getJSONObject("actionType").getString("stringValue"))
            assertFalse(disabled.has("actionTargetID"))
            assertEquals(404, fixture.media.storageStatus(fixture.cover(news), "GET"))
            try {
                LocalStorage.instance(context)
                    .reference
                    .child(fixture.cover(news).path)
                    .metadata
                    .await()
                fail("Deleted content Storage client access")
            } catch (error: StorageException) {
                assertEquals(StorageException.ERROR_NOT_AUTHORIZED, error.errorCode)
            }
            watch.cancel()
            watch = null
            expect(ContentLifecycleFailure.MISSING) { repo.execute(ContentLifecycleIntent(stale)) }
            assertEquals(
                ContentLifecycleObserved.UNAVAILABLE_CLEANUP_UNCONFIRMED,
                repo.recover(ContentLifecycleIntent(stale)).observed,
            )

            phase = "actual zero-registration Event deletion ignores stale positive displayed count"
            fixture.data.patch("events/${emptyEvent.contentId}", mapOf("registeredCount" to 99L))
            val emptyDeleted = repo.execute(ContentLifecycleIntent(repo.load(emptyEvent)))
            assertTrue(emptyDeleted.receipt is ContentLifecycleReceipt.Deleted)
            assertFalse(fixture.exists(emptyEvent))

            phase = "real registration callables and deterministic prior inbox receipt"
            val registrations =
                listOf(attendee, moderator).map { account ->
                    val path =
                        fixture.reference(
                            registeredEvent,
                            account.uid,
                            ContentLifecycleFixtures.Reference.REGISTRATION,
                        )
                    fixture.reference(
                        registeredEvent,
                        account.uid,
                        ContentLifecycleFixtures.Reference.CANCEL_NOTICE,
                    )
                    signIn(account)
                    assertTrue(
                        community
                            .setRegistration(
                                CommunityTarget(ContentKind.EVENTS, registeredEvent.contentId),
                                true,
                            )
                            .registered
                    )
                    assertNotNull(fixture.fields(path))
                    path
                }
            val oldNotice =
                fixture.reference(
                    registeredEvent,
                    moderator.uid,
                    ContentLifecycleFixtures.Reference.CANCEL_NOTICE,
                )
            fixture.seed(
                oldNotice,
                fixture.existingCancellation(
                    registeredEvent,
                    moderator.uid,
                    Instant.now().minusSeconds(600),
                ),
            )
            val registeredComment =
                fixture.reference(
                    registeredEvent,
                    owner.uid,
                    ContentLifecycleFixtures.Reference.COMMENT,
                )
            fixture.seed(
                registeredComment,
                mapOf(
                    "id" to registeredComment.substringAfterLast('/'),
                    "text" to "Preserved synthetic discussion",
                    "createdAt" to Instant.now(),
                ),
            )
            signIn(owner)
            fixture.data.patch(
                "events/${registeredEvent.contentId}",
                mapOf("registeredCount" to 0L),
            )
            val beforeCancellation = repo.load(registeredEvent)
            val cancelled = repo.execute(ContentLifecycleIntent(beforeCancellation))
            val receipt = cancelled.receipt as ContentLifecycleReceipt.Cancelled
            assertEquals(2L, receipt.recipientCount)
            assertEquals(1L, receipt.notificationCount)
            assertTrue(
                ContentLifecycleContract.cancelled(
                    beforeCancellation,
                    cancelled.snapshot,
                    requireNotNull(store.state.value.organizationScope()),
                    receipt.completedAt,
                )
            )
            assertEquals(0L, cancelled.snapshot.item?.fields?.get("registeredCount"))
            for (path in registrations) assertNotNull(
                "Registered attendee retained",
                fixture.fields(path),
            )
            assertNotNull(fixture.fields(registeredComment))
            assertEquals(200, fixture.media.storageStatus(fixture.cover(registeredEvent), "GET"))
            assertArrayEquals(
                photo.jpeg,
                LocalStorage.instance(context)
                    .reference
                    .child(fixture.cover(registeredEvent).path)
                    .getBytes(3_000_000)
                    .await(),
            )
            assertEquals(
                "Earlier synthetic cancellation",
                requireNotNull(fixture.fields(oldNotice))
                    .getJSONObject("title")
                    .getString("stringValue"),
            )
            val newNotice =
                requireNotNull(
                    fixture.fields(
                        fixture.reference(
                            registeredEvent,
                            attendee.uid,
                            ContentLifecycleFixtures.Reference.CANCEL_NOTICE,
                        )
                    )
                )
            assertEquals("eventCancelled", newNotice.getJSONObject("type").getString("stringValue"))
            assertEquals(
                registeredEvent.contentId,
                newNotice.getJSONObject("actionTargetId").getString("stringValue"),
            )
            assertEquals(
                "eventCancelled:${registeredEvent.contentId}",
                newNotice.getJSONObject("dedupeKey").getString("stringValue"),
            )
            expect(ContentLifecycleFailure.READ_ONLY) {
                repo.execute(ContentLifecycleIntent(cancelled.snapshot))
            }

            phase =
                "registered attendee can read cancelled detail but unregistered public actor cannot"
            signIn(attendee)
            assertEquals(
                "cancelled",
                db.document("events/${registeredEvent.contentId}")
                    .get(Source.SERVER)
                    .await()
                    .getString("cancellationState"),
            )
            signIn(stranger)
            expect(ContentLifecycleFailure.DENIED) {
                db.document("events/${registeredEvent.contentId}").get(Source.SERVER).await()
            }
            signIn(owner)
            phase = "genuine non-TOTP token rejected for activated privileged MFA"
            fixture.data.patch(
                "users/${owner.uid}",
                mapOf("globalRole" to "admin", "requiresMultiFactorAuth" to true),
            )
            withContext(Dispatchers.Main) { store.refresh() }.join()
            assertFalse(store.state.value.readyForActions)
            expectCallable(LocalCallableFailure.FAILED_PRECONDITION) { call(guard) }
            phase = "restricted verified actor cannot delete and guard publication is intact"
            fixture.data.patch(
                "users/${owner.uid}",
                mapOf(
                    "globalRole" to "user",
                    "requiresMultiFactorAuth" to false,
                    "accountStatus" to "suspendedUntil",
                    "blockState" to "suspendedUntil",
                    "updatedAt" to Instant.now(),
                ),
            )
            withContext(Dispatchers.Main) { store.refresh() }.join()
            assertFalse(store.state.value.readyForActions)
            expectCallable(LocalCallableFailure.PERMISSION_DENIED) { call(guard) }
            assertTrue(fixture.exists(guard))
            assertTrue(fixture.exists(foreign))
            assertTrue(fixture.exists(scheduled))
        } catch (error: Throwable) {
            val reported = AssertionError("Content lifecycle actual phase=$phase", error)
            failure = reported
            throw reported
        } finally {
            watch?.cancel()
            scope.cancel()
            auth.signOut()
            fixture.cleanup(failure)
        }
    }

    private suspend fun expect(reason: ContentLifecycleFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $reason at $phase")
        } catch (error: Exception) {
            assertEquals(
                "$phase (${error.javaClass.simpleName})",
                reason,
                contentLifecycleFailure(error),
            )
        }
    }

    private suspend fun expectCallable(code: LocalCallableFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected actual callable $code at $phase")
        } catch (error: LocalCallableException) {
            assertEquals(phase, code, error.code)
        }
    }
}
