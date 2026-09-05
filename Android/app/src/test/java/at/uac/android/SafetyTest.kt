package at.uac.android

import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthIdentity
import at.uac.android.feature.auth.AuthProfile
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.safety.*
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SafetyTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    private val now = Instant.parse("2026-09-03T02:00:00.123Z")
    private val alice = SafetySession("synthetic-alice", 1, true)
    private val bob = SafetySession("synthetic-bob", 2, true)
    private val target =
        SafetyReportTarget(
            SafetyTargetType.NEWS,
            "synthetic-news-01",
            "Example",
            "synthetic-author",
        )
    private val draft =
        SafetyReportDraft(
            SafetyReason.SPAM,
            "Synthetic report explanation for a local test.",
            goodFaith = true,
        )

    @Test
    fun blockReadDiagnosticContainsOnlyStructureAndClearsWithAccount() = runTest {
        val source =
            object : SafetySource by FakeSource() {
                override suspend fun userBlocks(uid: String): List<RawDocument> =
                    throw SafetyException(
                        SafetyFailure.OFFLINE,
                        java.io.EOFException("private-identifier-and-token-must-not-be-retained"),
                        SafetyOperation.USER_BLOCKS,
                    )
            }
        val model = SafetyViewModel(source)
        model.bind(alice)
        advanceUntilIdle()
        assertFalse(model.state.value.visibility.loaded)
        assertEquals(SafetyFailure.OFFLINE, model.state.value.error)
        assertEquals(
            SafetyReadDiagnostic(
                SafetyOperation.USER_BLOCKS,
                listOf("SafetyException", "EOFException"),
            ),
            model.state.value.readDiagnostic,
        )
        assertFalse(model.state.value.readDiagnostic.toString().contains("private-identifier"))
        model.bind(null)
        assertNull(model.state.value.readDiagnostic)
    }

    private fun user(id: String) =
        RawDocument(
            id,
            mapOf(
                "id" to id,
                "targetUserId" to id,
                "displayName" to "Demo $id",
                "avatarURL" to null,
                "blockedAt" to now,
                "updatedAt" to now,
            ),
        )

    private fun organization(id: String): Fields =
        mapOf("organizationId" to id, "name" to "Demo $id", "blockedAt" to now.toString())

    private fun content(
        kind: ContentKind = ContentKind.NEWS,
        id: String = "post",
        author: String? = "author",
        organization: String = "org",
    ) =
        Content(
            kind,
            id,
            mapOf("authorId" to author, "ownerId" to author, "organizationId" to organization),
        )

    private inner class FakeSource : SafetySource {
        val users = mutableMapOf<String, MutableMap<String, RawDocument>>()
        val organizations = mutableMapOf<String, MutableMap<String, Fields>>()
        val reports = mutableMapOf<String, RawDocument>()
        val calls = mutableListOf<Triple<String, Fields, String>>()
        var delayMillis = 0L
        var gate: CompletableDeferred<Unit>? = null
        var beforeFailure: SafetyFailure? = null
        var failAfterCommit = false
        var failReadBack = false
        var corruptResponse = false
        var foreignReport = false
        var reportWrites = 0

        override suspend fun userBlocks(uid: String): List<RawDocument> =
            users[uid]?.values.orEmpty().toList()

        override suspend fun userBlock(uid: String, id: String): RawDocument? {
            if (failReadBack) throw SafetyException(SafetyFailure.OFFLINE)
            return users[uid]?.get(id)
        }

        override suspend fun report(uid: String, id: String): RawDocument? {
            if (failReadBack) throw SafetyException(SafetyFailure.OFFLINE)
            val row = reports[id]
            return if (foreignReport && row != null)
                row.copy(fields = row.fields + ("userId" to bob.uid))
            else row
        }

        override suspend fun call(name: String, fields: Fields, uid: String): Any? {
            calls += Triple(name, fields, uid)
            delay(delayMillis)
            gate?.await()
            beforeFailure?.let { throw SafetyException(it) }
            val result: Any =
                when (name) {
                    "getBlockedOrganizations" ->
                        mapOf("blocks" to organizations[uid]?.values.orEmpty().toList())
                    "setUserBlocked" -> {
                        val id = fields["targetUserId"] as String
                        val blocked = fields["isBlocked"] as Boolean
                        val list = users.getOrPut(uid) { mutableMapOf() }
                        if (blocked) list[id] = user(id) else list.remove(id)
                        mapOf(
                            "targetUserId" to id,
                            "isBlocked" to blocked,
                            "displayName" to "Demo $id",
                            "updatedAt" to now.toString(),
                        )
                    }
                    "setOrganizationBlocked" -> {
                        val id = fields["organizationId"] as String
                        val blocked = fields["isBlocked"] as Boolean
                        val list = organizations.getOrPut(uid) { mutableMapOf() }
                        if (blocked) list[id] = organization(id) else list.remove(id)
                        mapOf("organizationId" to id, "isBlocked" to blocked, "block" to list[id])
                    }
                    "submitContentReport" -> {
                        val id = "report-${++reportWrites}"
                        val case = "DSA-DEMO-$reportWrites"
                        reports[id] =
                            RawDocument(
                                id,
                                mapOf(
                                    "id" to id,
                                    "userId" to uid,
                                    "type" to "report",
                                    "createdAt" to now,
                                    "reportContext" to
                                        fields.filterKeys {
                                            it in
                                                setOf(
                                                    "targetType",
                                                    "targetId",
                                                    "parentType",
                                                    "parentId",
                                                    "reason",
                                                )
                                        },
                                    "dsaCase" to
                                        mapOf(
                                            "caseNumber" to case,
                                            "illegalExplanation" to fields["illegalExplanation"],
                                            "legalBasis" to fields["legalBasis"],
                                            "evidence" to fields["evidence"],
                                            "goodFaithConfirmed" to true,
                                            "acknowledgementAt" to now,
                                        ),
                                ),
                            )
                        mapOf(
                            "reportId" to id,
                            "caseNumber" to case,
                            "accessToken" to "synthetic-secret-token",
                            "status" to "open",
                            "submittedAt" to now.toString(),
                            "acknowledgementAt" to now.toString(),
                            "wasDuplicate" to false,
                        )
                    }
                    else -> error("Unexpected callable")
                }
            if (name != "getBlockedOrganizations" && failAfterCommit)
                throw SafetyException(SafetyFailure.OFFLINE)
            return if (corruptResponse) mapOf("unexpected" to true) else result
        }
    }

    private suspend fun expect(failure: SafetyFailure, operation: suspend () -> Unit) {
        try {
            operation()
            fail("Expected $failure")
        } catch (error: SafetyException) {
            assertEquals(failure, error.failure)
        }
    }

    @Test
    fun reportPayloadContainsOnlyActualCallableFields() {
        assertTrue(target.valid())
        val fields = target.identityFields() + draft.fields()
        assertEquals(
            setOf("targetType", "targetId", "reason", "illegalExplanation", "goodFaithConfirmed"),
            fields.keys,
        )
        assertEquals("news", fields["targetType"])
        assertFalse(fields.containsKey("authorId"))
        assertFalse(fields.containsKey("reportId"))
    }

    @Test
    fun reportCommentRequiresExactContainingParent() {
        assertFalse(target.copy(type = SafetyTargetType.COMMENT).valid())
        val comment =
            target.copy(
                type = SafetyTargetType.COMMENT,
                parentType = SafetyTargetType.EVENT,
                parentId = "event-1",
            )
        assertTrue(comment.valid())
        assertEquals("event", comment.identityFields()["parentType"])
        assertFalse(comment.copy(parentType = SafetyTargetType.COMMENT).valid())
        assertFalse(target.copy(parentType = SafetyTargetType.NEWS, parentId = "news-1").valid())
    }

    @Test
    fun idsRejectPathTraversalWhitespaceAndControlCharacters() {
        for (id in listOf("", " ", "a/b", ".", "..", " a", "a\n", "x".repeat(257))) assertFalse(
            id,
            safetyId(id),
        )
        assertTrue(safetyId("synthetic-target"))
    }

    @Test
    fun commentIdentityDoesNotAliasWhenDocumentIdsContainSeparators() {
        val one =
            target.copy(
                type = SafetyTargetType.COMMENT,
                parentType = SafetyTargetType.NEWS,
                parentId = "a:b",
                id = "c",
            )
        val two = one.copy(parentId = "a", id = "b:c")
        assertTrue(one.valid())
        assertTrue(two.valid())
        assertNotEquals(one.key, two.key)
    }

    @Test
    fun draftNormalizesButEnforcesReferenceBoundsAndDeclaration() {
        assertTrue(draft.valid())
        assertFalse(draft.copy(explanation = "x".repeat(19)).valid())
        assertTrue(draft.copy(explanation = "x".repeat(5_000)).valid())
        assertFalse(draft.copy(explanation = "x".repeat(5_001)).valid())
        assertFalse(draft.copy(legalBasis = "x".repeat(1_001)).valid())
        assertFalse(draft.copy(evidence = "x".repeat(5_001)).valid())
        assertFalse(draft.copy(reason = null).valid())
        assertFalse(draft.copy(goodFaith = false).valid())
        assertEquals(
            draft.explanation,
            draft.copy(explanation = "  ${draft.explanation}  ").normalized().explanation,
        )
        assertFalse(draft.copy(legalBasis = "  ").fields().containsKey("legalBasis"))
    }

    @Test
    fun blockRecordsMustMatchDocumentIdentity() = runTest {
        assertEquals("target", SafetyContract.user(user("target")).id)
        expect(SafetyFailure.INVALID) {
            SafetyContract.user(
                user("target").copy(fields = user("target").fields + ("targetUserId" to "other"))
            )
        }
        expect(SafetyFailure.INVALID) {
            SafetyContract.user(user("target").copy(fields = user("target").fields - "blockedAt"))
        }
    }

    @Test
    fun organizationReceiptValidatesStateAndDuplicates() = runTest {
        SafetyContract.organizationReceipt(
            mapOf("organizationId" to "org", "isBlocked" to false, "block" to null),
            "org",
            false,
        )
        expect(SafetyFailure.INVALID) {
            SafetyContract.organizationReceipt(
                mapOf(
                    "organizationId" to "other",
                    "isBlocked" to true,
                    "block" to organization("org"),
                ),
                "org",
                true,
            )
        }
        expect(SafetyFailure.INVALID) {
            SafetyContract.organizations(
                mapOf("blocks" to listOf(organization("org"), organization("org")))
            )
        }
        expect(SafetyFailure.INVALID) {
            SafetyContract.organizations(mapOf("blocks" to List(501) { organization("org-$it") }))
        }
    }

    @Test
    fun userAndOrganizationVisibilityAreIndependent() {
        val policy = SafetyVisibility(setOf("blocked-author"), setOf("blocked-org"))
        assertFalse(policy.allows(content(author = "blocked-author")))
        assertFalse(policy.allows(content(organization = "blocked-org")))
        assertFalse(policy.allows(content(ContentKind.ORGANIZATIONS, id = "blocked-org")))
        assertTrue(
            policy.allows(
                content(ContentKind.ORGANIZATIONS, id = "other-org", organization = "blocked-org")
            )
        )
        assertTrue(policy.allowsAuthor(null))
        assertFalse(policy.allowsAuthor("blocked-author"))
    }

    @Test
    fun organizationOwnerFallbackNeverGuessesMissingAuthor() {
        val org =
            Content(ContentKind.ORGANIZATIONS, "org", mapOf("submittedByUserId" to "submitter"))
        assertEquals("submitter", safetyAuthor(org))
        assertNull(
            safetyAuthor(
                Content(ContentKind.NEWS, "news", mapOf("organizationId" to "owner-not-author"))
            )
        )
    }

    @Test
    fun projectionAndReasonsNeverExposeUnknownOrBlockedCards() {
        val rows = listOf(content(id = "visible"), content(id = "hidden", organization = "blocked"))
        val policy = SafetyVisibility(blockedOrganizationIds = setOf("blocked"))
        assertEquals(listOf("visible"), policy.project(rows).items.map { it.id })
        assertEquals(1, policy.project(rows).withheld)
        assertEquals(SafetyVisibilityReason.ORGANIZATION_BLOCKED, policy.reason(rows.last()))
        assertEquals(
            SafetyVisibilityReason.AUTHOR_BLOCKED,
            SafetyVisibility(setOf("author")).reason(rows.first()),
        )
        assertTrue(policy.copy(loaded = false).project(rows).items.isEmpty())
        assertTrue(policy.copy(loaded = false).project(rows).checking)
        assertEquals(
            SafetyVisibilityReason.CHECKING,
            policy.copy(loaded = false).reason(rows.first()),
        )
    }

    @Test
    fun unconfirmedAuthenticatedBlockStateIsNotAnEmptyPolicy() {
        assertTrue(SafetyState().visibility.allows(content()))
        assertFalse(SafetyState(session = alice).visibility.allows(content()))
        assertFalse(SafetyState(session = alice).visibility.allowsAuthor(null))
        assertTrue(
            SafetyState(session = alice, blocks = SafetyBlocks(emptyList(), emptyList()))
                .visibility
                .allows(content())
        )
    }

    @Test
    fun synchronousMaskDropsPreviousAccountsListsAndReportReceipts() {
        val private =
            SafetyState(
                session = alice,
                blocks = SafetyBlocks(listOf(SafetyContract.user(user("target"))), emptyList()),
            )
        assertSame(private, private.forSession(alice))
        assertNull(private.forSession(bob).blocks)
        assertFalse(private.forSession(bob).visibility.loaded)
        assertTrue(private.forSession(null).visibility.loaded)
    }

    @Test
    fun verificationRestrictedLegalAndMfaHaveExplicitAccountStateNotGuestOrInfiniteLoading() =
        runTest {
            val ready =
                AuthSession(
                    stage = AuthStage.AUTHENTICATED,
                    identity = AuthIdentity(alice.uid, "demo@example.invalid", true),
                    profile = AuthProfile(alice.uid, "demo@example.invalid", "Demo"),
                    revision = 1,
                )
            val cases =
                listOf(
                    ready.copy(
                        stage = AuthStage.VERIFICATION_PENDING,
                        identity = ready.identity!!.copy(emailVerified = false),
                    ) to SafetyAccess.VERIFY_EMAIL,
                    ready.copy(gate = AuthGate.RESTRICTED) to SafetyAccess.RESTRICTED,
                    ready.copy(gate = AuthGate.LEGAL_REQUIRED) to SafetyAccess.LEGAL,
                    ready.copy(gate = AuthGate.LEGAL_UNAVAILABLE) to SafetyAccess.LEGAL,
                    ready.copy(gate = AuthGate.MFA_REQUIRED) to SafetyAccess.MFA,
                    ready.copy(stage = AuthStage.SESSION_UNAVAILABLE) to SafetyAccess.UNAVAILABLE,
                )
            for ((auth, access) in cases) {
                val source = FakeSource()
                val model = SafetyViewModel(source)
                val scope = auth.safetyScope()!!
                assertFalse(scope.ready)
                assertEquals(access, scope.access)
                model.bind(scope)
                advanceUntilIdle()
                assertFalse(model.state.value.loading)
                assertEquals(SafetyFailure.NOT_READY, model.state.value.error)
                assertFalse(model.state.value.visibility.loaded)
                assertEquals(
                    SafetyVisibilityReason.ACCOUNT_REQUIRED,
                    model.state.value.visibility.reason(content()),
                )
                assertFalse(model.state.value.visibility.project(listOf(content())).checking)
                assertTrue(source.calls.isEmpty())
            }
            assertTrue(ready.safetyScope()!!.ready)
            assertNull(ready.copy(stage = AuthStage.GUEST).safetyScope())
            assertNull(ready.copy(identity = ready.identity.copy(anonymous = true)).safetyScope())
        }

    @Test
    fun guestAndRestrictedCannotReadOrMutate() = runTest {
        val source = FakeSource()
        expect(SafetyFailure.SIGN_IN) { SafetyRepository(source, { null }).blocks() }
        expect(SafetyFailure.NOT_READY) {
            SafetyRepository(source, { alice.copy(ready = false) }).setUser("target", true)
        }
        assertTrue(source.calls.isEmpty())
    }

    @Test
    fun ownUserAndContentAreRejectedBeforeCallable() = runTest {
        val source = FakeSource()
        val repository = SafetyRepository(source, { alice })
        expect(SafetyFailure.OWN_TARGET) { repository.setUser(alice.uid, true) }
        expect(SafetyFailure.OWN_TARGET) {
            repository.submit(target.copy(authorId = alice.uid), draft)
        }
        assertTrue(source.calls.isEmpty())
    }

    @Test
    fun userDesiredStateReadBackAndRepeatedDeleteAreIdempotent() = runTest {
        val source = FakeSource()
        val repository = SafetyRepository(source, { alice })
        assertEquals("target", repository.setUser("target", true)?.id)
        repository.setUser("target", true)
        assertEquals(1, repository.blocks().users.size)
        assertNull(repository.setUser("target", false))
        assertNull(repository.setUser("target", false))
        assertTrue(repository.blocks().users.isEmpty())
        assertEquals(setOf("targetUserId", "isBlocked"), source.calls.first().second.keys)
    }

    @Test
    fun organizationMutationUsesCallableReadBackNotForbiddenFirestoreCollection() = runTest {
        val source = FakeSource()
        val repository = SafetyRepository(source, { alice })
        assertEquals("org", repository.setOrganization("org", true)?.id)
        assertEquals(
            listOf("setOrganizationBlocked", "getBlockedOrganizations"),
            source.calls.map { it.first },
        )
        assertNull(repository.setOrganization("org", false))
        assertTrue(repository.blocks().organizations.isEmpty())
    }

    @Test
    fun blocksAreIsolatedBetweenAccounts() = runTest {
        val source = FakeSource()
        var scope = alice
        val repository = SafetyRepository(source, { scope })
        repository.setUser("target", true)
        repository.setOrganization("org", true)
        scope = bob
        assertTrue(repository.blocks().users.isEmpty())
        assertTrue(repository.blocks().organizations.isEmpty())
        scope = alice
        assertEquals(1, repository.blocks().users.size)
        assertEquals(1, repository.blocks().organizations.size)
    }

    @Test
    fun reportReceiptRequiresMatchingPrivateReadBack() = runTest {
        val source = FakeSource()
        val repository = SafetyRepository(source, { alice })
        val receipt = repository.submit(target, draft)
        assertEquals("DSA-DEMO-1", receipt.caseNumber)
        assertEquals(1, source.reportWrites)
        assertFalse(receipt.toString().contains(receipt.accessToken))
    }

    @Test
    fun reportNormalizesOptionalFieldsAndRetainsParentContext() = runTest {
        val source = FakeSource()
        val repository = SafetyRepository(source, { alice })
        val comment =
            target.copy(
                type = SafetyTargetType.COMMENT,
                parentType = SafetyTargetType.NEWS,
                parentId = "parent",
            )
        repository.submit(
            comment,
            draft.copy(legalBasis = "  demo basis ", evidence = " demo evidence "),
        )
        val request = source.calls.single().second
        assertEquals("parent", request["parentId"])
        assertEquals("demo basis", request["legalBasis"])
        assertEquals("demo evidence", request["evidence"])
    }

    @Test
    fun missingOrForeignReportReadBackCannotBeReportedAsSuccess() = runTest {
        val source = FakeSource()
        source.foreignReport = true
        expect(SafetyFailure.UNCONFIRMED) {
            SafetyRepository(source, { alice }).submit(target, draft)
        }
        assertEquals(1, source.reportWrites)
    }

    @Test
    fun malformedResponseAfterPossibleCommitIsUnconfirmed() = runTest {
        val source = FakeSource()
        source.corruptResponse = true
        expect(SafetyFailure.UNCONFIRMED) {
            SafetyRepository(source, { alice }).submit(target, draft)
        }
        assertEquals(1, source.reportWrites)
    }

    @Test
    fun networkLossAfterReportCommitDoesNotRetry() = runTest {
        val source = FakeSource()
        source.failAfterCommit = true
        expect(SafetyFailure.UNCONFIRMED) {
            SafetyRepository(source, { alice }).submit(target, draft)
        }
        assertEquals(1, source.calls.size)
        assertEquals(1, source.reportWrites)
    }

    @Test
    fun knownRejectionIsNotMisrepresentedAsUncertainCommit() = runTest {
        val source = FakeSource()
        source.beforeFailure = SafetyFailure.DENIED
        expect(SafetyFailure.DENIED) { SafetyRepository(source, { alice }).submit(target, draft) }
        assertEquals(0, source.reportWrites)
    }

    @Test
    fun mutationWaitsActualCompletionBeyondReadTimeout() = runTest {
        val source = FakeSource()
        source.delayMillis = 20_000
        val result = async { SafetyRepository(source, { alice }).setUser("target", true) }
        advanceTimeBy(15_500)
        assertFalse(result.isCompleted)
        advanceUntilIdle()
        assertEquals("target", result.await()?.id)
    }

    @Test
    fun mutationIdentityGateReceivesCapturedScope() = runTest {
        val seen = mutableListOf<SafetySession>()
        val gate =
            object : SafetyMutationGate {
                override suspend fun <T> withSession(
                    session: SafetySession,
                    operation: suspend () -> T,
                ): T {
                    seen += session
                    return operation()
                }
            }
        val repository = SafetyRepository(FakeSource(), { alice }, gate)
        repository.blocks()
        repository.setUser("target", true)
        repository.submit(target, draft)
        assertEquals(listOf(alice, alice, alice), seen)
    }

    @Test
    fun delayedResponseCannotCrossAccountRevision() = runTest {
        val source = FakeSource()
        source.gate = CompletableDeferred()
        var scope = alice
        val repository = SafetyRepository(source, { scope })
        val result = async { repository.setUser("target", true) }
        runCurrent()
        scope = alice.copy(revision = 2)
        source.gate!!.complete(Unit)
        advanceUntilIdle()
        try {
            result.await()
            fail("Stale result")
        } catch (_: CancellationException) {}
    }

    @Test
    fun viewModelLoadsBothListsAndClearsSynchronously() = runTest {
        val model = SafetyViewModel(FakeSource())
        model.bind(alice)
        assertFalse(model.state.value.visibility.loaded)
        advanceUntilIdle()
        assertTrue(model.state.value.visibility.loaded)
        model.bind(bob)
        assertNull(model.state.value.blocks)
        advanceUntilIdle()
        model.bind(null)
        assertTrue(model.state.value.visibility.loaded)
    }

    @Test
    fun duplicateReportTapsAndReopenAfterSuccessSubmitOnlyOnce() = runTest {
        val source = FakeSource()
        val model = SafetyViewModel(source)
        model.bind(alice)
        advanceUntilIdle()
        model.submit(target, draft)
        model.submit(target, draft)
        advanceUntilIdle()
        model.submit(target, draft)
        advanceUntilIdle()
        assertEquals(1, source.reportWrites)
        assertNotNull(model.state.value.reports[target.key]?.receipt)
    }

    @Test
    fun uncertainReportCannotBeResentByReopeningSheet() = runTest {
        val source = FakeSource()
        val model = SafetyViewModel(source)
        model.bind(alice)
        advanceUntilIdle()
        source.failAfterCommit = true
        model.submit(target, draft)
        advanceUntilIdle()
        assertEquals(SafetyFailure.UNCONFIRMED, model.state.value.reports[target.key]?.error)
        source.failAfterCommit = false
        model.submit(target, draft)
        advanceUntilIdle()
        assertEquals(1, source.reportWrites)
    }

    @Test
    fun uncertainBlockMutationWithholdsContentUntilFreshListRead() = runTest {
        val source = FakeSource()
        val model = SafetyViewModel(source)
        model.bind(alice)
        advanceUntilIdle()
        source.failAfterCommit = true
        model.setUser("target", true)
        advanceUntilIdle()
        assertFalse(model.state.value.visibility.loaded)
        source.failAfterCommit = false
        model.refresh()
        advanceUntilIdle()
        assertTrue(model.state.value.visibility.loaded)
        assertFalse(model.state.value.visibility.allowsAuthor("target"))
    }

    @Test
    fun deletedUserUnblockErrorRetainsActualBlockAndExplanation() = runTest {
        val source = FakeSource()
        source.users[alice.uid] = mutableMapOf("target" to user("target"))
        val model = SafetyViewModel(source)
        model.bind(alice)
        advanceUntilIdle()
        source.beforeFailure = SafetyFailure.MISSING
        model.setUser("target", false)
        advanceUntilIdle()
        assertFalse(model.state.value.visibility.allowsAuthor("target"))
        assertEquals(SafetyFailure.MISSING, model.state.value.blockErrors["user:target"])
    }

    @Test
    fun staleCallbackIsRejectedBeforeObserverCatchesUp() = runTest {
        val source = FakeSource()
        var scope: SafetySession? = alice
        val model = SafetyViewModel(source, { scope })
        model.bind(alice)
        advanceUntilIdle()
        scope = bob
        model.submit(target, draft)
        advanceUntilIdle()
        assertEquals(bob, model.state.value.session)
        assertEquals(0, source.reportWrites)
    }
}
