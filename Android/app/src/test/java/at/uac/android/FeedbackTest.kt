package at.uac.android

import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthIdentity
import at.uac.android.feature.auth.AuthProfile
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.feedback.*
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.*
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class FeedbackTest {
    private val time = Instant.parse("2026-09-03T01:00:00.123456Z")
    private val alice = FeedbackSession("alice", 1, true, false, "Synthetic Alice")
    private val bob = FeedbackSession("bob", 2, true, false, "Synthetic Bob")
    private val admin = FeedbackSession("admin", 3, true, true, "Synthetic Admin")
    private val draft = FeedbackDraft(FeedbackType.QUESTION, "A synthetic question")

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    private fun row(
        id: String = "thread",
        actor: FeedbackSession = alice,
        extra: Map<String, Any?> = emptyMap(),
    ) = RawDocument(id, FeedbackContract.creation(id, actor, draft, time) + extra)

    private fun message(
        id: String = "message",
        parent: String = "thread",
        actor: FeedbackSession = alice,
        text: String = "Reply",
        owner: Boolean = false,
        close: Boolean = false,
        at: Instant = time,
    ) =
        RawDocument(
            id,
            mapOf(
                "id" to id,
                "feedbackId" to parent,
                "senderId" to actor.uid,
                "senderDisplayName" to actor.displayName,
                "senderRole" to if (owner) "owner" else "user",
                "text" to text,
                "createdAt" to at,
                "isSystem" to close,
            ),
        )

    private inner class Fake : FeedbackSource {
        val rows = mutableMapOf<String, RawDocument>()
        val messages = mutableMapOf<String, MutableMap<String, RawDocument>>()
        var writes = 0
        var fail: FeedbackFailure? = null
        var writeDelay = 0L
        var readDelay = 0L
        var foreignRead = false
        var uncertainAfterCommit = false
        var missingReadback = false
        var staleCursor = false

        override suspend fun page(
            uid: String?,
            after: FeedbackCursor?,
            size: Int,
        ): FeedbackRawPage {
            delay(readDelay)
            fail?.let { throw FeedbackException(it) }
            val sorted =
                rows.values
                    .filter { foreignRead || uid == null || it.fields["userId"] == uid }
                    .sortedWith(
                        compareByDescending<RawDocument> { it.fields["createdAt"] as Instant }
                            .thenByDescending { it.id }
                    )
            val selected =
                sorted
                    .drop(if (after == null) 0 else sorted.indexOfFirst { it.id == after.id } + 1)
                    .take(size + 1)
            val next =
                if (staleCursor) after
                else
                    selected.take(size).lastOrNull()?.let {
                        FeedbackCursor(it.fields["createdAt"] as Instant, it.id)
                    }
            return FeedbackRawPage(selected.take(size), next, selected.size > size || staleCursor)
        }

        override suspend fun item(id: String, uid: String?): RawDocument? {
            delay(readDelay)
            fail?.let { throw FeedbackException(it) }
            return rows[id]?.takeIf { foreignRead || uid == null || it.fields["userId"] == uid }
        }

        override suspend fun messages(id: String) =
            messages[id]?.values?.sortedByDescending { it.fields["createdAt"] as Instant }.orEmpty()

        override suspend fun message(id: String, messageId: String) =
            if (missingReadback) null else messages[id]?.get(messageId)

        override suspend fun create(
            id: String,
            session: FeedbackSession,
            draft: FeedbackDraft,
            current: () -> Boolean,
        ) {
            delay(writeDelay)
            if (!current()) throw CancellationException()
            check(!rows.containsKey(id))
            rows[id] = RawDocument(id, FeedbackContract.creation(id, session, draft, time))
            writes++
            if (uncertainAfterCommit) throw FeedbackException(FeedbackFailure.UNCONFIRMED)
        }

        override suspend fun reply(
            id: String,
            messageId: String,
            session: FeedbackSession,
            text: String,
            owner: Boolean,
            close: Boolean,
            current: () -> Boolean,
        ) {
            delay(writeDelay)
            if (!current()) throw CancellationException()
            val parent =
                rows[id]?.let(FeedbackContract::item)
                    ?: throw FeedbackException(FeedbackFailure.MISSING)
            if (!owner && parent.uid != session.uid || owner && !session.canManage)
                throw FeedbackException(FeedbackFailure.DENIED)
            val children = messages.getOrPut(id) { mutableMapOf() }
            val existing = children[messageId]?.let { FeedbackContract.message(it, id) }
            if (existing != null) {
                if (
                    existing.text != text ||
                        existing.owner != owner ||
                        existing.senderId != session.uid ||
                        existing.system != close
                )
                    throw FeedbackException(FeedbackFailure.CONFLICT)
                return
            }
            if (parent.status.closed) throw FeedbackException(FeedbackFailure.CLOSED)
            if (close && (parent.hasDsaCase || !owner))
                throw FeedbackException(FeedbackFailure.DENIED)
            children[messageId] = message(messageId, id, session, text, owner, close)
            rows[id] =
                rows.getValue(id).let {
                    it.copy(
                        fields =
                            it.fields +
                                mapOf(
                                    "lastMessageText" to text,
                                    "status" to
                                        if (close) "closed" else if (owner) "answered" else "open",
                                    "unreadForUser" to owner,
                                    "unreadForOwner" to !owner,
                                )
                    )
                }
            writes++
            if (uncertainAfterCommit) throw FeedbackException(FeedbackFailure.UNCONFIRMED)
        }

        override fun changes(uid: String?, id: String?) = emptyFlow<Unit>()
    }

    private suspend fun failure(expected: FeedbackFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: FeedbackException) {
            assertEquals(expected, error.failure)
        }
    }

    @Test
    fun serverGeneratedReporterAppealIsReadWithoutPromotingItToSupport() = runTest {
        val source =
            Fake().apply {
                rows["thread"] = row(extra = mapOf("dsaCase" to mapOf("caseNumber" to "SYNTHETIC")))
                messages["thread"] =
                    mutableMapOf(
                        "appeal" to
                            message("appeal", text = "DSA appeal: synthetic reason", close = true)
                    )
            }
        val conversation =
            FeedbackRepository(source, { alice }).conversation("thread", FeedbackAudience.OWN)
        assertEquals(0, conversation.invalid)
        val appeal = conversation.messages.single { it.id == "appeal" }
        assertTrue(appeal.system)
        assertFalse(appeal.owner)
        assertEquals(alice.uid, appeal.senderId)
        assertEquals("DSA appeal: synthetic reason", appeal.text)
        assertEquals(time, appeal.createdAt)
        assertEquals(0, source.writes)
    }

    @Test
    fun ordinaryReplyCannotReuseServerSystemMessageAsItsReceipt() = runTest {
        val source =
            Fake().apply {
                rows["thread"] = row()
                messages["thread"] =
                    mutableMapOf("appeal" to message("appeal", text = "Same text", close = true))
            }
        failure(FeedbackFailure.CONFLICT) {
            FeedbackRepository(source, { alice })
                .reply("thread", "appeal", "Same text", FeedbackAudience.OWN)
        }
        assertEquals(0, source.writes)
        assertEquals(1, source.messages.getValue("thread").size)
    }

    @Test
    fun serverSystemMarkerNeverMakesUnknownRolesValid() = runTest {
        val raw = message(close = true)
        for (role in listOf("admin", "system", "reporter", "", "Owner")) {
            failure(FeedbackFailure.INVALID) {
                FeedbackContract.message(
                    raw.copy(fields = raw.fields + ("senderRole" to role)),
                    "thread",
                )
            }
        }
    }

    @Test
    fun systemMarkerIsStrictBooleanAndCannotChangeParentIdentity() = runTest {
        val raw = message(close = true)
        for (flag in listOf("true", 1, mapOf("value" to true))) {
            failure(FeedbackFailure.INVALID) {
                FeedbackContract.message(
                    raw.copy(fields = raw.fields + ("isSystem" to flag)),
                    "thread",
                )
            }
        }
        failure(FeedbackFailure.INVALID) { FeedbackContract.message(raw, "different-parent") }
        failure(FeedbackFailure.INVALID) {
            FeedbackContract.message(
                raw.copy(fields = raw.fields + ("id" to "different-message")),
                "thread",
            )
        }
    }

    @Test
    fun ordinaryLegacyMessageAndSupportSystemMessageRetainTheirRoles() {
        val raw = message()
        val legacy = FeedbackContract.message(raw.copy(fields = raw.fields - "isSystem"), "thread")
        assertFalse(legacy.system)
        assertFalse(legacy.owner)
        val support =
            FeedbackContract.message(message(actor = admin, owner = true, close = true), "thread")
        assertTrue(support.owner)
        assertTrue(support.system)
    }

    @Test
    fun creationMatchesExistingRulesFieldsAndUtf16Bounds() {
        val fields = FeedbackContract.creation("request", alice, draft, time)
        assertEquals(14, fields.size)
        assertEquals(fields["message"], fields["lastMessageText"])
        assertEquals("user", fields["lastMessageByRole"])
        assertEquals(true, fields["unreadForOwner"])
        assertEquals(false, fields["unreadForUser"])
        assertTrue(FeedbackDraft(message = "x".repeat(2000)).valid())
        assertFalse(FeedbackDraft(message = "x".repeat(2001)).valid())
        assertFalse(FeedbackDraft(message = " \n ").valid())
        assertFalse(feedbackId("a/b"))
        assertFalse(feedbackId(".."))
        assertFalse(feedbackId("a\n"))
    }

    @Test
    fun decodingUsesPathIdentityAndDoesNotTurnUnknownStatusIntoOpen() = runTest {
        failure(FeedbackFailure.INVALID) {
            FeedbackContract.item(row(extra = mapOf("id" to "other")))
        }
        failure(FeedbackFailure.INVALID) {
            FeedbackContract.item(row(extra = mapOf("createdAt" to "today")))
        }
        failure(FeedbackFailure.INVALID) {
            FeedbackContract.item(row(extra = mapOf("unreadForUser" to 1)))
        }
        assertEquals(
            FeedbackStatus.UNKNOWN,
            FeedbackContract.item(row(extra = mapOf("status" to "futureStatus"))).status,
        )
        assertTrue(
            FeedbackContract.item(row(extra = mapOf("status" to "futureStatus"))).status.closed
        )
        assertEquals(time, FeedbackContract.item(row()).createdAt)
    }

    @Test
    fun legacyInitialIsMergedOnlyWhenNoStoredEquivalentWithinTwoSeconds() {
        val parent = FeedbackContract.item(row())
        assertEquals(1, FeedbackContract.merge(parent, emptyList()).size)
        val initial =
            FeedbackContract.message(
                message(text = parent.message, at = time.plusMillis(1999)),
                parent.id,
            )
        assertEquals(listOf(initial), FeedbackContract.merge(parent, listOf(initial)))
        assertEquals(
            2,
            FeedbackContract.merge(parent, listOf(initial.copy(createdAt = time.plusSeconds(2))))
                .size,
        )
    }

    @Test
    fun legacyOwnerReplyIsNotDuplicatedOnceModernOwnerMessagesExist() {
        val parent =
            FeedbackContract.item(
                row(
                    extra =
                        mapOf(
                            "ownerReply" to "Old reply",
                            "repliedAt" to time,
                            "repliedByUserId" to "owner",
                        )
                )
            )
        assertEquals(2, FeedbackContract.merge(parent, emptyList()).size)
        val stored = FeedbackContract.message(message(actor = admin, owner = true), parent.id)
        assertEquals(2, FeedbackContract.merge(parent, listOf(stored, stored)).size)
    }

    @Test
    fun foreignMessagePathAndForgedSystemRoleAreRejected() = runTest {
        failure(FeedbackFailure.INVALID) {
            FeedbackContract.message(message(parent = "foreign"), "thread")
        }
        failure(FeedbackFailure.INVALID) {
            val raw = message(close = true)
            FeedbackContract.message(
                raw.copy(fields = raw.fields + ("senderRole" to "system")),
                "thread",
            )
        }
    }

    @Test
    fun ownReadsRemainAvailableOutsideReadyButWritesAndManagementDoNot() = runTest {
        val source = Fake().apply { rows["thread"] = row() }
        val repo = FeedbackRepository(source, { alice.copy(ready = false) })
        assertEquals(1, repo.page(FeedbackAudience.OWN).items.size)
        failure(FeedbackFailure.NOT_READY) { repo.create("new", draft) }
        failure(FeedbackFailure.DENIED) { repo.page(FeedbackAudience.MANAGEMENT) }
        failure(FeedbackFailure.SIGN_IN) {
            FeedbackRepository(source, { null }).page(FeedbackAudience.OWN)
        }
    }

    @Test
    fun foreignRowsAreRejectedEvenIfSourceIsIncorrect() = runTest {
        val source =
            Fake().apply {
                rows["thread"] = row(actor = bob)
                foreignRead = true
            }
        val repo = FeedbackRepository(source, { alice })
        failure(FeedbackFailure.DENIED) { repo.page(FeedbackAudience.OWN) }
        failure(FeedbackFailure.DENIED) { repo.conversation("thread", FeedbackAudience.OWN) }
    }

    @Test
    fun stableCreationIdMakesUncertainRetryIdempotent() = runTest {
        val source = Fake().apply { uncertainAfterCommit = true }
        val repo = FeedbackRepository(source, { alice })
        failure(FeedbackFailure.UNCONFIRMED) { repo.create("new", draft) }
        assertEquals("new", repo.create("new", draft).id)
        assertEquals(1, source.writes)
        failure(FeedbackFailure.CONFLICT) { repo.create("new", draft.copy(message = "different")) }
    }

    @Test
    fun replyUsesSameImmutableMessageIdAndChecksDirectReadback() = runTest {
        val source =
            Fake().apply {
                rows["thread"] = row()
                uncertainAfterCommit = true
            }
        val repo = FeedbackRepository(source, { alice })
        failure(FeedbackFailure.UNCONFIRMED) {
            repo.reply("thread", "reply", "Hello", FeedbackAudience.OWN)
        }
        assertEquals(2, repo.reply("thread", "reply", "Hello", FeedbackAudience.OWN).messages.size)
        assertEquals(1, source.writes)
        source.missingReadback = true
        failure(FeedbackFailure.UNCONFIRMED) {
            repo.reply("thread", "reply", "Hello", FeedbackAudience.OWN)
        }
    }

    @Test
    fun ownerReplyAndClosePreserveRoleWhileDsaCloseStaysSeparate() = runTest {
        val source = Fake().apply { rows["thread"] = row() }
        val manager = FeedbackRepository(source, { admin })
        val answered = manager.reply("thread", "answer", "A reply", FeedbackAudience.MANAGEMENT)
        assertEquals(FeedbackStatus.ANSWERED, answered.item.status)
        assertTrue(answered.messages.single { it.id == "answer" }.owner)
        assertTrue(answered.item.unreadForUser)
        assertEquals(
            FeedbackStatus.CLOSED,
            manager
                .reply("thread", "close", "Closed", FeedbackAudience.MANAGEMENT, true)
                .item
                .status,
        )
        failure(FeedbackFailure.CLOSED) {
            FeedbackRepository(source, { alice })
                .reply("thread", "later", "Later", FeedbackAudience.OWN)
        }
        source.rows["dsa"] = row("dsa", extra = mapOf("dsaCase" to mapOf("caseNumber" to "test")))
        failure(FeedbackFailure.DENIED) {
            manager.reply("dsa", "close", "Closed", FeedbackAudience.MANAGEMENT, true)
        }
        failure(FeedbackFailure.DENIED) {
            FeedbackRepository(source, { alice })
                .reply("dsa", "close", "Closed", FeedbackAudience.OWN, true)
        }
    }

    @Test
    fun stablePaginationDoesNotLoseInvalidRowsOrReuseCursorForever() = runTest {
        val source =
            Fake().apply {
                repeat(52) {
                    val id = "row-$it"
                    rows[id] = row(id)
                }
            }
        val repo = FeedbackRepository(source, { alice })
        val first = repo.page(FeedbackAudience.OWN)
        val next = repo.page(FeedbackAudience.OWN, first.next)
        assertEquals(52, (first.items + next.items).map { it.id }.toSet().size)
        assertFalse(next.hasMore)
        source.staleCursor = true
        failure(FeedbackFailure.INVALID) { repo.page(FeedbackAudience.OWN, first.next) }
    }

    @Test
    fun readTimeoutIsClassifiedButSubmittedMutationIsAwaited() = runTest {
        val source = Fake().apply { readDelay = 16_000 }
        failure(FeedbackFailure.OFFLINE) {
            FeedbackRepository(source, { alice }).page(FeedbackAudience.OWN)
        }
        source.readDelay = 0
        source.writeDelay = 20_000
        assertEquals("new", FeedbackRepository(source, { alice }).create("new", draft).id)
    }

    @Test
    fun accountSwitchRejectsLateReadAndImmediatelyMasksTheUi() = runTest {
        var actor = alice
        val source =
            Fake().apply {
                rows["thread"] = row()
                readDelay = 100
            }
        val deferred = async { FeedbackRepository(source, { actor }).page(FeedbackAudience.OWN) }
        runCurrent()
        actor = bob
        try {
            deferred.await()
            fail("Old account response")
        } catch (_: CancellationException) {}
        val old = FeedbackState(session = alice, draft = draft)
        assertEquals(FeedbackState(session = bob), old.forSession(bob))
        assertEquals(FeedbackState(), old.forSession(null))
    }

    @Test
    fun viewModelPreventsDoubleTapAndPreservesUncertainPayload() = runTest {
        val source =
            Fake().apply {
                writeDelay = 100
                uncertainAfterCommit = true
            }
        val model =
            FeedbackViewModel(source, { alice }, DirectFeedbackMutationGate, backgroundScope)
        model.bind(alice)
        model.draft(draft)
        val first = model.submit()!!
        assertNull(model.submit())
        first.join()
        assertEquals(FeedbackFailure.UNCONFIRMED, model.state.value.actionError)
        assertTrue(model.state.value.createRetryPending)
        model.draft(draft.copy(message = "Changed"))
        assertEquals(draft, model.state.value.draft)
        model.submit()!!.join()
        assertEquals(1, source.writes)
        assertNotNull(model.state.value.confirmedId)
        assertFalse(model.state.value.createRetryPending)
    }

    @Test
    fun offlinePreservesOnlySameAccountWhileDeniedClearsPrivateData() = runTest {
        val source = Fake().apply { rows["thread"] = row() }
        val model =
            FeedbackViewModel(source, { alice }, DirectFeedbackMutationGate, backgroundScope)
        model.bind(alice)
        model.show(FeedbackAudience.OWN, null)
        model.refresh()!!.join()
        assertEquals(1, model.state.value.page!!.items.size)
        source.fail = FeedbackFailure.OFFLINE
        model.refresh()!!.join()
        assertEquals(1, model.state.value.page!!.items.size)
        source.fail = FeedbackFailure.DENIED
        model.refresh()!!.join()
        assertNull(model.state.value.page)
    }

    @Test
    fun invalidRouteShowsAnErrorInsteadOfAnInfiniteLoadingDestination() = runTest {
        val model =
            FeedbackViewModel(Fake(), { alice }, DirectFeedbackMutationGate, backgroundScope)
        model.bind(alice)
        model.show(FeedbackAudience.OWN, "bad/path")
        assertEquals("bad/path", model.state.value.selectedId)
        assertEquals(FeedbackFailure.INVALID, model.state.value.error)
        assertFalse(model.state.value.loading)
    }

    @Test
    fun inboxSelectionDoesNotFetchMutateOrChangeTheServerPage() = runTest {
        val source = Fake().apply { rows["thread"] = row() }
        val model =
            FeedbackViewModel(source, { admin }, DirectFeedbackMutationGate, backgroundScope)
        model.bind(admin)
        model.show(FeedbackAudience.MANAGEMENT, null)
        model.refresh()!!.join()
        val page = model.state.value.page
        source.fail = FeedbackFailure.OFFLINE
        model.inboxSearch("private query")
        model.inboxFilter(FeedbackInboxFilter.ALL)
        model.inboxSort(FeedbackInboxSort.OLDEST)
        runCurrent()
        assertSame(page, model.state.value.page)
        assertNull(model.state.value.error)
        assertEquals(0, source.writes)
        assertEquals(
            FeedbackInboxOptions(
                "private query",
                FeedbackInboxFilter.ALL,
                FeedbackInboxSort.OLDEST,
            ),
            model.state.value.inbox,
        )
    }

    @Test
    fun inboxSearchRejectsLongOrMalformedPasteWithoutChangingAcceptedText() = runTest {
        val model =
            FeedbackViewModel(Fake(), { admin }, DirectFeedbackMutationGate, backgroundScope)
        model.bind(admin)
        model.show(FeedbackAudience.MANAGEMENT, null)
        model.inboxSearch("accepted")
        for (value in listOf("x".repeat(201), "\uD800")) {
            model.inboxSearch(value)
            assertEquals("accepted", model.state.value.inbox.query)
            assertTrue(model.state.value.inboxQueryRejected)
        }
        model.inboxSearch("")
        assertFalse(model.state.value.inboxQueryRejected)
        assertEquals("", model.state.value.inbox.query)
    }

    @Test
    fun inboxSearchIsClearedOnHideNavigationAndAccountRevisionLoss() = runTest {
        var actor = admin
        val model =
            FeedbackViewModel(Fake(), { actor }, DirectFeedbackMutationGate, backgroundScope)
        model.bind(actor)
        model.show(FeedbackAudience.MANAGEMENT, null)
        model.inboxSearch("PRIVATE")
        model.hide(FeedbackAudience.MANAGEMENT, null)
        assertEquals(FeedbackInboxOptions(), model.state.value.inbox)
        model.inboxSearch("hidden callback")
        assertEquals("", model.state.value.inbox.query)
        model.show(FeedbackAudience.MANAGEMENT, null)
        model.inboxSearch("PRIVATE")
        model.show(FeedbackAudience.MANAGEMENT, "thread")
        assertEquals("", model.state.value.inbox.query)
        model.inboxSearch("detail callback")
        assertEquals("", model.state.value.inbox.query)
        model.show(FeedbackAudience.MANAGEMENT, null)
        model.inboxSearch("PRIVATE")
        actor = actor.copy(revision = actor.revision + 1)
        assertEquals("", model.state.value.forSession(actor).inbox.query)
        model.bind(actor)
        assertEquals("", model.state.value.inbox.query)
    }

    @Test
    fun ownAudienceAndRevokedAuthorityCannotEditInboxOptions() = runTest {
        var actor = admin
        val model =
            FeedbackViewModel(Fake(), { actor }, DirectFeedbackMutationGate, backgroundScope)
        model.bind(actor)
        model.show(FeedbackAudience.OWN, null)
        model.inboxSearch("own")
        model.inboxFilter(FeedbackInboxFilter.ALL)
        assertEquals(FeedbackInboxOptions(), model.state.value.inbox)
        model.show(FeedbackAudience.MANAGEMENT, null)
        actor = actor.copy(canManage = false)
        model.inboxSearch("revoked")
        model.inboxSort(FeedbackInboxSort.OLDEST)
        assertEquals(FeedbackInboxOptions(), model.state.value.inbox)
    }

    @Test
    fun refreshAndLoadMoreKeepOptionsAndOriginalNanosecondCursor() = runTest {
        val source = Fake().apply { repeat(52) { rows["row-$it"] = row("row-$it") } }
        val model =
            FeedbackViewModel(source, { admin }, DirectFeedbackMutationGate, backgroundScope)
        model.bind(admin)
        model.show(FeedbackAudience.MANAGEMENT, null)
        model.refresh()!!.join()
        assertEquals(50, model.state.value.page!!.items.size)
        model.inboxSearch("Alice")
        model.inboxSort(FeedbackInboxSort.OLDEST)
        val options = model.state.value.inbox
        val cursor = model.state.value.page!!.next!!
        assertEquals(time.nano, cursor.createdAt.nano)
        model.refresh(true)!!.join()
        assertEquals(52, model.state.value.page!!.items.size)
        assertEquals(options, model.state.value.inbox)
        model.refresh()!!.join()
        assertEquals(50, model.state.value.page!!.items.size)
        assertEquals(options, model.state.value.inbox)
    }

    @Test
    fun offlineKeepsSelectionButDeniedClearsPrivateQuery() = runTest {
        val source = Fake().apply { rows["thread"] = row() }
        val model =
            FeedbackViewModel(source, { admin }, DirectFeedbackMutationGate, backgroundScope)
        model.bind(admin)
        model.show(FeedbackAudience.MANAGEMENT, null)
        model.refresh()!!.join()
        model.inboxSearch("PRIVATE")
        source.fail = FeedbackFailure.OFFLINE
        model.refresh()!!.join()
        assertEquals("PRIVATE", model.state.value.inbox.query)
        source.fail = FeedbackFailure.DENIED
        model.refresh()!!.join()
        assertEquals("", model.state.value.inbox.query)
        assertNull(model.state.value.page)
    }

    @Test
    fun authScopeNeverTreatsSessionUnavailableAsAReadableIdentity() {
        val identity = AuthIdentity(alice.uid, "demo@example.invalid", true)
        val auth =
            AuthSession(
                AuthStage.AUTHENTICATED,
                identity,
                AuthProfile(alice.uid, identity.email, alice.displayName),
                revision = 1,
            )
        assertTrue(auth.feedbackScope()!!.ready)
        assertFalse(auth.copy(gate = AuthGate.RESTRICTED).feedbackScope()!!.ready)
        assertNull(auth.copy(stage = AuthStage.SESSION_UNAVAILABLE).feedbackScope())
        assertNull(auth.copy(identity = identity.copy(anonymous = true)).feedbackScope())
    }
}
