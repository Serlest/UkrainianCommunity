package at.uac.android

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.contentlifecycle.*
import at.uac.android.feature.organization.*
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ContentLifecycleTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    private val actor = OrganizationSession("lifecycle-owner", 1, true, "Owner", "user")
    private val now = Instant.parse("2026-09-03T03:00:00Z")

    private fun snapshot(kind: ContentKind = ContentKind.NEWS): ContentLifecycleSnapshot {
        val draft =
            OrganizationDraft(
                "lifecycle-org",
                "Synthetic lifecycle organization",
                "Synthetic organization summary",
                region = "wien",
                city = "Wien",
            )
        val org =
            OrganizationContract.record(
                RawDocument(
                    draft.id,
                    OrganizationContract.create(draft, actor, now) +
                        mapOf("ownerId" to actor.uid, "moderationStatus" to "approved"),
                ),
                actor,
            )
        val content =
            AuthoringContract.newDraft(kind, org, now)
                .copy(
                    id = "lifecycle-content",
                    title = "Private lifecycle title",
                    summary = "Summary",
                    body = "Body",
                )
                .let {
                    if (kind == ContentKind.EVENTS) it.copy(event = it.event.copy(venue = "Hall"))
                    else it
                }
        val fields =
            AuthoringContract.submission(content, org, actor, null, now).fields +
                mapOf("likeCount" to 3L, "commentCount" to 4L)
        val item =
            AuthoringContract.item(
                kind,
                RawDocument(content.id, fields),
                org.id,
                AuthoringStatus.APPROVED,
                actor,
            )
        return ContentLifecycleSnapshot(ContentLifecycleTarget(org.id, kind, item.id), org, item)
    }

    private fun fields(
        value: ContentLifecycleSnapshot,
        updates: Map<String, Any?>,
    ): ContentLifecycleSnapshot {
        val item = requireNotNull(value.item)
        val data = item.fields.toMutableMap()
        updates.forEach { (key, value) ->
            if (value == null) data.remove(key) else data[key] = value
        }
        return value.copy(
            item =
                AuthoringContract.item(
                    item.kind,
                    RawDocument(item.id, data),
                    item.organizationId,
                    AuthoringStatus.entries.first { it.wire == data["moderationStatus"] },
                    actor,
                )
        )
    }

    private fun cancelled(value: ContentLifecycleSnapshot) =
        fields(
            value,
            mapOf(
                "moderationStatus" to "archived",
                "cancellationState" to "cancelled",
                "cancelledBy" to actor.uid,
                "cancelledAt" to now.plusSeconds(5),
                "updatedAt" to now.plusSeconds(5),
                "cancellationReason" to null,
            ),
        )

    private val gate =
        object : OrganizationMutationGate {
            override suspend fun <T> withSession(
                session: OrganizationSession,
                operation: suspend () -> T,
            ): T = withContext(NonCancellable) { operation() }
        }

    private inner class Fake(initial: ContentLifecycleSnapshot = snapshot()) :
        ContentLifecycleSource {
        var current = initial
        var reads = 0
        var sends = 0
        var watches = 0
        var readError: ContentLifecycleFailure? = null
        var sendError: ContentLifecycleFailure? = null
        var pendingRead: CompletableDeferred<Unit>? = null
        var pendingSend: CompletableDeferred<Unit>? = null
        var cancel = false
        var preserve = true
        var commit = true
        var readFailsAfterSend = false
        val changes = MutableSharedFlow<Result<Unit>>(extraBufferCapacity = 8)

        override suspend fun snapshot(
            target: ContentLifecycleTarget,
            session: OrganizationSession,
        ): ContentLifecycleSnapshot {
            reads++
            pendingRead?.await()
            readError?.let { ContentLifecycleContract.fail(it) }
            return current
        }

        override fun changes(snapshot: ContentLifecycleSnapshot, session: OrganizationSession) =
            changes.also {
                watches++
            }

        override suspend fun execute(
            intent: ContentLifecycleIntent,
            session: OrganizationSession,
        ): ContentLifecycleReceipt {
            sends++
            pendingSend?.await()
            if (commit) current = if (cancel) cancelled(current) else current.copy(item = null)
            if (!preserve && current.item != null)
                current = fields(current, mapOf("likeCount" to 99L))
            if (readFailsAfterSend) readError = ContentLifecycleFailure.OFFLINE
            sendError?.let { ContentLifecycleContract.fail(it) }
            return if (cancel)
                ContentLifecycleReceipt.Cancelled(intent.snapshot.target, now.plusSeconds(5), 2, 1)
            else ContentLifecycleReceipt.Deleted(intent.snapshot.target, now.plusSeconds(5))
        }
    }

    private suspend fun fails(reason: ContentLifecycleFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $reason")
        } catch (error: ContentLifecycleException) {
            assertEquals(reason, error.reason)
        }
    }

    private fun eventResponse(target: ContentLifecycleTarget) =
        mapOf(
            "eventId" to target.contentId,
            "status" to "cancelled",
            "recipientCount" to 2L,
            "notificationCount" to 1L,
            "pushRecipientCount" to 0L,
            "cancelledAt" to now.plusSeconds(5).toString(),
        )

    @Test
    fun targetRejectsOtherCollectionsAndNoncanonicalPaths() {
        for (id in listOf("", "../foreign", "a/b", "x".repeat(129), "__id__!")) {
            try {
                ContentLifecycleTarget("org", ContentKind.NEWS, id)
                fail("Invalid ID")
            } catch (_: IllegalArgumentException) {}
        }
        try {
            ContentLifecycleTarget("org", ContentKind.ORGANIZATIONS, "item")
            fail("Invalid kind")
        } catch (_: IllegalArgumentException) {}
    }

    @Test
    fun onlyCanonicalOwnerOrPlatformOwnerHasScopedAuthority() {
        val org = snapshot().organization
        assertTrue(ContentLifecycleContract.permitted(org, actor))
        assertTrue(
            ContentLifecycleContract.permitted(
                org,
                actor.copy(uid = "platform", globalRole = "owner"),
            )
        )
        for (role in listOf("admin", "topAdmin", "user")) assertFalse(
            ContentLifecycleContract.permitted(org, actor.copy(uid = "stranger", globalRole = role))
        )
    }

    @Test
    fun TeamEditorRolesNeverGrantLifecycleAuthority() {
        val org = snapshot().organization
        for (key in listOf("adminIds", "moderatorIds")) {
            val changed =
                org.copy(
                    fields = org.fields + mapOf("ownerId" to "other", key to listOf(actor.uid)),
                    authority = OrganizationAuthority.OWNER,
                )
            assertFalse(ContentLifecycleContract.permitted(changed, actor))
        }
    }

    @Test
    fun systemOrganizationIsExcludedEvenForPlatformOwnerUi() {
        val original = snapshot().organization
        val system =
            original.copy(
                id = "ukrainian-community",
                fields = original.fields + ("id" to "ukrainian-community"),
            )
        assertFalse(ContentLifecycleContract.permitted(system, actor.copy(globalRole = "owner")))
    }

    @Test
    fun staleCachedAuthorityCannotOverrideCanonicalFields() {
        val org = snapshot().organization
        assertFalse(
            ContentLifecycleContract.permitted(
                org.copy(fields = org.fields + ("ownerId" to "new-owner")),
                actor,
            )
        )
        assertFalse(
            ContentLifecycleContract.permitted(
                org.copy(fields = org.fields + ("moderationStatus" to "archived")),
                actor,
            )
        )
        assertFalse(ContentLifecycleContract.permitted(org, actor.copy(ready = false)))
    }

    @Test
    fun missingScheduledAndAlreadyCancelledAreReadOnly() {
        val original = snapshot(ContentKind.EVENTS)
        assertFalse(ContentLifecycleContract.actionable(original.copy(item = null), actor))
        assertFalse(ContentLifecycleContract.actionable(cancelled(original), actor))
        assertFalse(
            ContentLifecycleContract.actionable(
                fields(
                    original,
                    mapOf("moderationStatus" to "draft", "scheduledAt" to now.plusSeconds(600)),
                ),
                actor,
            )
        )
    }

    @Test
    fun archivedUncancelledContentMayStillBeDeletedByOwner() {
        assertTrue(
            ContentLifecycleContract.actionable(
                fields(snapshot(), mapOf("moderationStatus" to "archived")),
                actor,
            )
        )
    }

    @Test
    fun exactNewsReceiptIncludesAlreadyDeletedOnlyForNews() {
        val target = snapshot().target
        for (status in listOf("deleted", "alreadyDeleted")) {
            val receipt =
                ContentLifecycleContract.receipt(
                    mapOf("status" to status, "deletedAt" to now.toString()),
                    target,
                ) as ContentLifecycleReceipt.Deleted
            assertEquals(status == "alreadyDeleted", receipt.alreadyDeleted)
        }
    }

    @Test
    fun newsReceiptRejectsExtraFieldsStatusAndTime() = runTest {
        val valid = mapOf("status" to "deleted", "deletedAt" to now.toString())
        for (bad in
            listOf(
                valid + ("extra" to 1),
                valid + ("status" to "cancelled"),
                valid + ("deletedAt" to "not-time"),
                valid + ("deletedAt" to "1969-12-31T00:00:00Z"),
            )) fails(ContentLifecycleFailure.UNCONFIRMED) {
            ContentLifecycleContract.receipt(bad, snapshot().target)
        }
    }

    @Test
    fun eventReceiptDoesNotEquateRecipientsWithNewNoticesOrDelivery() {
        val target = snapshot(ContentKind.EVENTS).target
        val receipt =
            ContentLifecycleContract.receipt(eventResponse(target), target)
                as ContentLifecycleReceipt.Cancelled
        assertEquals(2L, receipt.recipientCount)
        assertEquals(1L, receipt.notificationCount)
        assertTrue(
            ContentLifecycleContract.receipt(
                eventResponse(target) + mapOf("recipientCount" to 0, "notificationCount" to 0),
                target,
            ) is ContentLifecycleReceipt.Cancelled
        )
    }

    @Test
    fun eventReceiptRejectsForeignIdExtraFieldsAndUnknownStatus() = runTest {
        val target = snapshot(ContentKind.EVENTS).target
        val valid = eventResponse(target)
        for (bad in
            listOf(
                valid + ("eventId" to "foreign"),
                valid + ("extra" to 1),
                valid + ("status" to "alreadyDeleted"),
            )) fails(ContentLifecycleFailure.UNCONFIRMED) {
            ContentLifecycleContract.receipt(bad, target)
        }
    }

    @Test
    fun eventReceiptRejectsFractionNegativeOverflowAndFalsePushClaims() = runTest {
        val target = snapshot(ContentKind.EVENTS).target
        val valid = eventResponse(target)
        for (value in listOf(-1, 1.5, Double.NaN, Double.POSITIVE_INFINITY, Long.MAX_VALUE)) fails(
            ContentLifecycleFailure.UNCONFIRMED
        ) {
            ContentLifecycleContract.receipt(valid + ("recipientCount" to value), target)
        }
        for (bad in
            listOf(valid + ("notificationCount" to 3), valid + ("pushRecipientCount" to 1))) fails(
            ContentLifecycleFailure.UNCONFIRMED
        ) {
            ContentLifecycleContract.receipt(bad, target)
        }
    }

    @Test
    fun deletedEventReceiptRequiresEveryCountZero() = runTest {
        val target = snapshot(ContentKind.EVENTS).target
        val valid =
            eventResponse(target) +
                mapOf("status" to "deleted", "recipientCount" to 0, "notificationCount" to 0)
        assertTrue(
            ContentLifecycleContract.receipt(valid, target) is ContentLifecycleReceipt.Deleted
        )
        fails(ContentLifecycleFailure.UNCONFIRMED) {
            ContentLifecycleContract.receipt(valid + ("recipientCount" to 1), target)
        }
    }

    @Test
    fun cancelledReadBackRequiresActorTimestampAndUnchangedContent() {
        val before = snapshot(ContentKind.EVENTS)
        val after = cancelled(before)
        assertTrue(ContentLifecycleContract.cancelled(before, after, actor, now.plusSeconds(5)))
        for (change in
            listOf(
                mapOf("cancelledBy" to "foreign"),
                mapOf("updatedAt" to now),
                mapOf("cancellationReason" to "unexpected"),
                mapOf("likeCount" to 4L),
            )) assertFalse(
            ContentLifecycleContract.cancelled(
                before,
                fields(after, change),
                actor,
                now.plusSeconds(5),
            )
        )
        assertFalse(ContentLifecycleContract.cancelled(before, after, actor, now.plusSeconds(6)))
    }

    @Test
    fun absentDocumentWithoutReceiptNeverConfirmsCascadeCompletion() {
        val before = snapshot()
        val after = before.copy(item = null)
        assertEquals(
            ContentLifecycleObserved.UNAVAILABLE_CLEANUP_UNCONFIRMED,
            ContentLifecycleContract.observed(before, after, actor),
        )
    }

    @Test
    fun cancelledDocumentWithoutReceiptNeverConfirmsNotificationCompletion() {
        val before = snapshot(ContentKind.EVENTS)
        assertEquals(
            ContentLifecycleObserved.CANCELLED_NOTICES_UNCONFIRMED,
            ContentLifecycleContract.observed(before, cancelled(before), actor),
        )
    }

    @Test
    fun guestAndUnreadyNeverReadOrMutateSource() = runTest {
        val fake = Fake()
        fails(ContentLifecycleFailure.SIGN_IN) {
            ContentLifecycleRepository(fake, { null }, gate).load(fake.current.target)
        }
        fails(ContentLifecycleFailure.NOT_READY) {
            ContentLifecycleRepository(fake, { actor.copy(ready = false) }, gate)
                .execute(ContentLifecycleIntent(fake.current))
        }
        assertEquals(0, fake.reads)
        assertEquals(0, fake.sends)
    }

    @Test
    fun staleTextOrOwnershipBlocksBeforeSingleSend() = runTest {
        val fake = Fake()
        val original = fake.current
        val repository = ContentLifecycleRepository(fake, { actor }, gate)
        fake.current = fields(original, mapOf("title" to "Changed"))
        fails(ContentLifecycleFailure.STALE) {
            repository.execute(ContentLifecycleIntent(original))
        }
        fake.current =
            original.copy(
                organization =
                    original.organization.copy(
                        fields = original.organization.fields + ("ownerId" to "other")
                    )
            )
        fails(ContentLifecycleFailure.DENIED) {
            repository.execute(ContentLifecycleIntent(original))
        }
        assertEquals(0, fake.sends)
    }

    @Test
    fun deleteReceiptAndAbsentReadBackConfirmExactlyOneSend() = runTest {
        val fake = Fake()
        val result =
            ContentLifecycleRepository(fake, { actor }, gate)
                .execute(ContentLifecycleIntent(fake.current))
        assertTrue(result.receipt is ContentLifecycleReceipt.Deleted)
        assertNull(result.snapshot.item)
        assertEquals(1, fake.sends)
    }

    @Test
    fun actualRegistrationBranchComesFromReceiptNotDisplayedCounter() = runTest {
        val fake = Fake(snapshot(ContentKind.EVENTS))
        fake.cancel = true
        fake.current = fields(fake.current, mapOf("registeredCount" to 0L))
        val result =
            ContentLifecycleRepository(fake, { actor }, gate)
                .execute(ContentLifecycleIntent(fake.current))
        assertTrue(result.receipt is ContentLifecycleReceipt.Cancelled)
        assertEquals(0L, result.snapshot.item?.fields?.get("registeredCount"))
    }

    @Test
    fun noRegistrationDeletionCanHaveStalePositiveDisplayedCounter() = runTest {
        val fake = Fake(fields(snapshot(ContentKind.EVENTS), mapOf("registeredCount" to 99L)))
        assertTrue(
            ContentLifecycleRepository(fake, { actor }, gate)
                .execute(ContentLifecycleIntent(fake.current))
                .receipt is ContentLifecycleReceipt.Deleted
        )
    }

    @Test
    fun changedCounterAfterCancellationIsUnconfirmedNotQuietlyAccepted() = runTest {
        val fake = Fake(snapshot(ContentKind.EVENTS))
        fake.cancel = true
        fake.preserve = false
        fails(ContentLifecycleFailure.UNCONFIRMED) {
            ContentLifecycleRepository(fake, { actor }, gate)
                .execute(ContentLifecycleIntent(fake.current))
        }
        assertEquals(1, fake.sends)
    }

    @Test
    fun receiptWithoutMatchingReadBackIsUnconfirmedAndNeverResent() = runTest {
        val fake = Fake()
        fake.commit = false
        fails(ContentLifecycleFailure.UNCONFIRMED) {
            ContentLifecycleRepository(fake, { actor }, gate)
                .execute(ContentLifecycleIntent(fake.current))
        }
        assertEquals(1, fake.sends)
    }

    @Test
    fun readFailureAfterSuccessfulCallIsUnconfirmed() = runTest {
        val fake = Fake()
        fake.readFailsAfterSend = true
        fails(ContentLifecycleFailure.UNCONFIRMED) {
            ContentLifecycleRepository(fake, { actor }, gate)
                .execute(ContentLifecycleIntent(fake.current))
        }
        assertEquals(1, fake.sends)
    }

    @Test
    fun repeatedRecoveryIsReadOnlyEvenWhenPublicationDisappeared() = runTest {
        val fake = Fake()
        val intent = ContentLifecycleIntent(fake.current)
        fake.sendError = ContentLifecycleFailure.UNCONFIRMED
        val repository = ContentLifecycleRepository(fake, { actor }, gate)
        fails(ContentLifecycleFailure.UNCONFIRMED) { repository.execute(intent) }
        repeat(3) {
            assertEquals(
                ContentLifecycleObserved.UNAVAILABLE_CLEANUP_UNCONFIRMED,
                repository.recover(intent).observed,
            )
        }
        assertEquals(1, fake.sends)
    }

    @Test
    fun protocolErrorsRemainPureAndDoNotExposeDetails() {
        assertEquals(
            ContentLifecycleFailure.DENIED,
            contentLifecycleFailure(
                LocalCallableException(LocalCallableFailure.PERMISSION_DENIED, "secret")
            ),
        )
        assertEquals(
            ContentLifecycleFailure.UNCONFIRMED,
            contentLifecycleFailure(LocalCallableException(LocalCallableFailure.UNCONFIRMED)),
        )
        assertEquals(
            ContentLifecycleFailure.STALE,
            contentLifecycleFailure(
                LocalCallableException(LocalCallableFailure.FAILED_PRECONDITION)
            ),
        )
    }

    @Test
    fun doubleConfirmationCannotSendTwiceWhileBusy() = runTest {
        val fake = Fake()
        fake.pendingSend = CompletableDeferred()
        val model = ContentLifecycleViewModel(fake, { actor }, gate)
        model.show(fake.current.target)
        runCurrent()
        model.request()
        model.confirm()
        model.confirm()
        runCurrent()
        assertEquals(1, fake.sends)
        assertTrue(model.state.value.busy)
        fake.pendingSend!!.complete(Unit)
        advanceUntilIdle()
        assertNotNull(model.state.value.confirmed)
        model.hide()
    }

    @Test
    fun uncertaintyOffersOnlyReadOnlyRecoveryAndSurvivesSameUidForeground() = runTest {
        val fake = Fake()
        fake.sendError = ContentLifecycleFailure.UNCONFIRMED
        val session = MutableStateFlow<OrganizationSession?>(actor)
        val model = ContentLifecycleViewModel(fake, { session.value }, gate)
        model.observeSessions(session)
        model.show(fake.current.target)
        runCurrent()
        model.request()
        model.confirm()
        advanceUntilIdle()
        assertNotNull(model.state.value.uncertain)
        assertFalse(model.state.value.actionable)
        session.value = actor.copy(revision = 2)
        advanceUntilIdle()
        assertNotNull(model.state.value.uncertain)
        model.recover()
        advanceUntilIdle()
        assertEquals(
            ContentLifecycleObserved.UNAVAILABLE_CLEANUP_UNCONFIRMED,
            model.state.value.observed,
        )
        assertEquals(1, fake.sends)
        model.hide()
    }

    @Test
    fun switchingAccountDuringSendMasksPriorResultAndPrivateTitle() = runTest {
        val fake = Fake()
        fake.pendingSend = CompletableDeferred()
        val session = MutableStateFlow<OrganizationSession?>(actor)
        val model = ContentLifecycleViewModel(fake, { session.value }, gate)
        model.observeSessions(session)
        model.show(fake.current.target)
        runCurrent()
        model.request()
        model.confirm()
        runCurrent()
        session.value = null
        runCurrent()
        fake.pendingSend!!.complete(Unit)
        advanceUntilIdle()
        assertNull(model.state.value.snapshot)
        assertNull(model.state.value.confirmed)
        assertNull(model.state.value.uncertain)
        assertFalse(model.state.value.busy)
        model.hide()
    }

    @Test
    fun watcherInvalidatesOpenConfirmationBeforeFreshReadCompletes() = runTest {
        val fake = Fake()
        val model = ContentLifecycleViewModel(fake, { actor }, gate)
        model.show(fake.current.target)
        runCurrent()
        model.request()
        assertNotNull(model.state.value.confirmation)
        fake.pendingRead = CompletableDeferred()
        fake.changes.emit(Result.success(Unit))
        runCurrent()
        assertFalse(model.state.value.fresh)
        assertNull(model.state.value.confirmation)
        model.confirm()
        assertEquals(0, fake.sends)
        fake.pendingRead!!.complete(Unit)
        advanceUntilIdle()
        model.hide()
    }

    @Test
    fun failedWatcherIsReattachedOnExplicitRefresh() = runTest {
        val fake = Fake()
        val model = ContentLifecycleViewModel(fake, { actor }, gate)
        model.show(fake.current.target)
        runCurrent()
        assertEquals(1, fake.watches)
        fake.changes.emit(
            Result.failure(ContentLifecycleException(ContentLifecycleFailure.OFFLINE))
        )
        runCurrent()
        assertFalse(model.state.value.fresh)
        model.refresh()
        advanceUntilIdle()
        assertEquals(2, fake.watches)
        assertTrue(model.state.value.fresh)
        model.hide()
    }

    @Test
    fun roleRevocationRemovesPrivateSnapshotAndNeverEnablesDelete() = runTest {
        val fake = Fake()
        val model = ContentLifecycleViewModel(fake, { actor }, gate)
        model.show(fake.current.target)
        runCurrent()
        fake.current =
            fake.current.copy(
                organization =
                    fake.current.organization.copy(
                        fields = fake.current.organization.fields + ("ownerId" to "other")
                    )
            )
        fake.changes.emit(Result.success(Unit))
        advanceUntilIdle()
        assertNull(model.state.value.snapshot)
        assertEquals(ContentLifecycleFailure.DENIED, model.state.value.error)
        assertFalse(model.state.value.actionable)
        model.hide()
    }

    @Test
    fun routeRoundTripDoesNotReenableAnUncertainDestructiveIntent() = runTest {
        val fake = Fake()
        fake.sendError = ContentLifecycleFailure.UNCONFIRMED
        fake.commit = false
        val original = fake.current
        val model = ContentLifecycleViewModel(fake, { actor }, gate)
        model.show(original.target)
        runCurrent()
        model.request()
        model.confirm()
        advanceUntilIdle()
        assertNotNull(model.state.value.uncertain)
        model.show(original.target.copy(contentId = "another"))
        advanceUntilIdle()
        model.show(original.target)
        advanceUntilIdle()
        assertNotNull(model.state.value.uncertain)
        assertFalse(model.state.value.actionable)
        assertEquals(1, fake.sends)
        model.hide()
    }

    @Test
    fun hideCancelsListenerAndReadButDoesNotReplayAnythingOnReturn() = runTest {
        val fake = Fake()
        val model = ContentLifecycleViewModel(fake, { actor }, gate)
        model.show(fake.current.target)
        runCurrent()
        model.request()
        model.hide()
        assertFalse(model.state.value.fresh)
        assertNull(model.state.value.confirmation)
        model.show(fake.current.target)
        advanceUntilIdle()
        assertEquals(2, fake.watches)
        assertEquals(0, fake.sends)
        model.hide()
    }
}
