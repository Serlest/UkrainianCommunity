package at.uac.android

import at.uac.android.feature.authoring.*
import at.uac.android.feature.authoring.recovery.*
import at.uac.android.feature.browse.*
import at.uac.android.feature.organization.*
import java.time.Instant
import java.time.ZoneId
import javax.crypto.KeyGenerator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AuthoringRecoveryTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    private val now = Instant.parse("2026-09-03T02:00:00.123456789Z")
    private val actor = OrganizationSession("recovery-author", 1, true, "Author", "user")
    private val basics =
        OrganizationDraft(
            "recovery-org",
            "Synthetic recovery",
            "A complete synthetic organization",
            region = "wien",
            city = "Wien",
        )
    private val org
        get() =
            OrganizationContract.record(
                RawDocument(
                    basics.id,
                    OrganizationContract.create(basics, actor, now) +
                        mapOf("moderationStatus" to "approved", "ownerId" to actor.uid),
                ),
                actor,
            )

    private val scope
        get() = AuthoringRecoveryScope(actor.uid, org.id, ContentKind.NEWS)

    private fun draft(kind: ContentKind = ContentKind.NEWS) =
        AuthoringContract.newDraft(kind, org, now)
            .copy(
                title = "Private title 🇺🇦",
                summary = "Summary",
                body = "Private body\nUnicode € 🔒",
            )

    private fun intent(draft: AuthoringDraft = draft()) =
        AuthoringContract.submission(draft, org, actor, null, now, ZoneId.of("Europe/Vienna"))

    private fun item(intent: AuthoringSubmission): AuthoringItem =
        AuthoringContract.item(
            intent.kind,
            RawDocument(
                intent.id,
                intent.fields.filterValues { it != null } + ("updatedAt" to now),
            ),
            intent.organizationId,
            AuthoringStatus.APPROVED,
            actor,
        )

    private suspend fun fails(reason: AuthoringRecoveryFailure, block: suspend () -> Unit) {
        try {
            block()
            fail("Expected $reason")
        } catch (error: AuthoringRecoveryException) {
            assertEquals(reason, error.reason)
        }
    }

    private fun cipher(): AuthoringRecoveryCipher {
        val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
        return AuthoringRecoveryCipher { key }
    }

    private val gate =
        object : OrganizationMutationGate {
            override suspend fun <T> withSession(
                session: OrganizationSession,
                operation: suspend () -> T,
            ): T = operation()
        }

    private inner class Source : AuthoringSource {
        var writes = 0
        var actual: AuthoringItem? = null
        var failAfterSend = false
        var failBeforeCommit = false
        var checkBeforeWrite: suspend (AuthoringSubmission) -> Unit = {}
        var organization = org
        val signals = MutableSharedFlow<Result<Unit>>(extraBufferCapacity = 10)

        override suspend fun organization(id: String, session: OrganizationSession) = organization

        override suspend fun page(
            organizationId: String,
            kind: ContentKind,
            status: AuthoringStatus,
            after: AuthoringCursor?,
            session: OrganizationSession,
        ) =
            AuthoringPage(
                listOfNotNull(actual).filter { it.kind == kind && it.status == status },
                null,
            )

        override suspend fun find(
            organizationId: String,
            kind: ContentKind,
            id: String,
            session: OrganizationSession,
        ) = actual?.takeIf { it.id == id && it.kind == kind }

        override fun changes(
            organizationId: String,
            kind: ContentKind,
            status: AuthoringStatus,
            session: OrganizationSession,
            target: AuthoringItem?,
        ) = signals

        override suspend fun commit(
            submission: AuthoringSubmission,
            organization: OrganizationRecord,
            session: OrganizationSession,
        ) {
            checkBeforeWrite(submission)
            writes++
            if (!failBeforeCommit) actual = item(submission)
            if (failAfterSend || failBeforeCommit)
                throw AuthoringException(AuthoringFailure.UNCONFIRMED)
        }
    }

    @Test
    fun draftCodecRoundTripsEveryFieldAndOriginalTimeZone() {
        val d =
            draft(ContentKind.EVENTS)
                .copy(
                    germanTitle = "Deutsch",
                    germanBody = "Körper",
                    additionalCategories = setOf("culture", "education"),
                    event =
                        draft(ContentKind.EVENTS)
                            .event
                            .copy(
                                contactEmail = "private@example.invalid",
                                amount = "12.50",
                                maximumAmount = "99",
                                contactPhone = "+4312345",
                            ),
                )
        val s = scope.copy(kind = ContentKind.EVENTS)
        val value = RecoveryDraft(d, "America/Los_Angeles")
        assertEquals(
            value,
            AuthoringRecoveryCodec.readDraft(s, AuthoringRecoveryCodec.draft(s, value)),
        )
    }

    @Test
    fun pendingCodecPreservesExactInstantLongDoubleNullAndNestedMaps() {
        val value =
            intent().let {
                it.copy(
                    fields =
                        it.fields +
                            ("price" to
                                mapOf("amount" to 12.5, "count" to Long.MAX_VALUE, "empty" to null))
                )
            }
        assertEquals(
            value,
            AuthoringRecoveryCodec.readPending(scope, AuthoringRecoveryCodec.pending(scope, value)),
        )
        val typed = listOf(Long.MIN_VALUE, Long.MAX_VALUE, Int.MIN_VALUE, 1.25, now, null, "🇺🇦")
        assertEquals(typed, AuthoringRecoveryCodec.decode(AuthoringRecoveryCodec.encode(typed)))
    }

    @Test
    fun actualNewsAndEventSubmissionsKeepCanonicalInitialInteractionStates() = runTest {
        val store = MemoryAuthoringRecoveryStore()
        for (kind in AuthoringContract.kinds) {
            val d =
                draft(kind).let {
                    if (kind == ContentKind.EVENTS)
                        it.copy(event = it.event.copy(venue = "Synthetic hall"))
                    else it
                }
            val value = intent(d)
            val target = scope.copy(kind = kind)
            assertEquals("notLiked", value.fields["likeState"])
            assertEquals(
                if (kind == ContentKind.EVENTS) "notRegistered" else null,
                value.fields["registrationState"],
            )
            assertEquals(value, store.prepareCreation(target, value))
            assertEquals(value, store.load(target)?.pending)
        }
    }

    @Test
    fun invalidInitialStatesAndNonzeroCountersRemainRejected() = runTest {
        val value = intent()
        for ((key, state) in
            mapOf(
                "likeState" to "liked",
                "registrationState" to "notRegistered",
                "likeCount" to 1L,
                "registeredCount" to 1L,
                "role" to "owner",
            )) fails(AuthoringRecoveryFailure.INVALID) {
            AuthoringRecoveryCodec.pending(
                scope,
                value.copy(fields = value.fields + (key to state)),
            )
        }
    }

    @Test
    fun typedCodecUsesCanonicalMapOrder() {
        assertArrayEquals(
            AuthoringRecoveryCodec.encode(mapOf("b" to 2L, "a" to 1L)),
            AuthoringRecoveryCodec.encode(mapOf("a" to 1L, "b" to 2L)),
        )
    }

    @Test
    fun invalidMagicVersionTrailingBytesAndOversizeFailClosed() = runTest {
        val bytes = AuthoringRecoveryCodec.encode("valid")
        for (bad in
            listOf(
                bytes + 0,
                bytes.copyOf().also { it[0] = 0 },
                bytes.copyOf().also { it[4] = 99 },
                bytes.copyOf(6),
                ByteArray(AuthoringRecoveryCodec.MAX_BYTES + 1),
            )) fails(AuthoringRecoveryFailure.INVALID) { AuthoringRecoveryCodec.decode(bad) }
    }

    @Test
    fun oversizedStringsDepthUnsupportedTypesAndNonFiniteNumbersAreRejected() = runTest {
        var deep: Any? = "leaf"
        repeat(14) { deep = listOf(deep) }
        for (bad in
            listOf(
                "🙂".repeat(70_000),
                deep,
                Double.NaN,
                Double.POSITIVE_INFINITY,
                byteArrayOf(1),
                List(129) { 0 },
                mapOf("ü".repeat(65) to 1),
            )) fails(AuthoringRecoveryFailure.INVALID) { AuthoringRecoveryCodec.encode(bad) }
    }

    @Test
    fun codecRejectsForeignUidOrganizationKindAndNonUuidIdentity() = runTest {
        val bytes = AuthoringRecoveryCodec.pending(scope, intent())
        for (foreign in
            listOf(
                scope.copy(uid = "foreign"),
                scope.copy(organizationId = "other-org"),
                scope.copy(kind = ContentKind.EVENTS),
            )) fails(AuthoringRecoveryFailure.INVALID) {
            AuthoringRecoveryCodec.readPending(foreign, bytes)
        }
        fails(AuthoringRecoveryFailure.INVALID) {
            AuthoringRecoveryCodec.pending(scope, intent().copy(id = "not-a-uuid"))
        }
    }

    @Test
    fun editBaselinesAndAuthorityCredentialsCannotEnterJournal() = runTest {
        val value = intent()
        fails(AuthoringRecoveryFailure.INVALID) {
            AuthoringRecoveryCodec.pending(scope, value.copy(base = item(value)))
        }
        for (field in listOf("idToken", "role", "password", "scheduledAt", "imageBase64")) fails(
            AuthoringRecoveryFailure.INVALID
        ) {
            AuthoringRecoveryCodec.pending(
                scope,
                value.copy(fields = value.fields + (field to "secret")),
            )
        }
    }

    @Test
    fun scopeHashSeparatesFieldBoundariesAndAccounts() {
        assertNotEquals(hash("ab", "c"), hash("a", "bc"))
        assertNotEquals(scope.accountHash, scope.copy(uid = "other").accountHash)
        assertNotEquals(scope.scopeHash, scope.copy(kind = ContentKind.EVENTS).scopeHash)
        assertEquals(64, scope.scopeHash.length)
    }

    @Test
    fun freshEncryptionNonceMakesIdenticalPlaintextsDifferent() {
        val crypto = cipher()
        val value = intent()
        val plain = AuthoringRecoveryCodec.pending(scope, value)
        val a = crypto.encrypt(scope, RecoveryPurpose.PENDING, value.id, plain, true)
        val b = crypto.encrypt(scope, RecoveryPurpose.PENDING, value.id, plain, true)
        assertFalse(a.contentEquals(b))
        assertArrayEquals(plain, crypto.decrypt(scope, RecoveryPurpose.PENDING, a).second)
        assertFalse(a.toString(Charsets.ISO_8859_1).contains("Private body"))
    }

    @Test
    fun ciphertextIsBoundToUidOrganizationKindPurposeAndId() = runTest {
        val crypto = cipher()
        val value = intent()
        val bytes =
            crypto.encrypt(
                scope,
                RecoveryPurpose.PENDING,
                value.id,
                AuthoringRecoveryCodec.pending(scope, value),
                true,
            )
        for (other in
            listOf(
                scope.copy(uid = "other"),
                scope.copy(organizationId = "another-org"),
                scope.copy(kind = ContentKind.EVENTS),
            )) fails(AuthoringRecoveryFailure.LOCKED) {
            crypto.decrypt(other, RecoveryPurpose.PENDING, bytes)
        }
        fails(AuthoringRecoveryFailure.LOCKED) {
            crypto.decrypt(scope, RecoveryPurpose.DRAFT, bytes)
        }
        val changedId =
            bytes.copyOf().also {
                it[5] = if (it[5] == 'a'.code.toByte()) 'b'.code.toByte() else 'a'.code.toByte()
            }
        fails(AuthoringRecoveryFailure.LOCKED) {
            crypto.decrypt(scope, RecoveryPurpose.PENDING, changedId)
        }
    }

    @Test
    fun tamperingWrongKeyAndTruncationDoNotProducePlaintext() = runTest {
        val crypto = cipher()
        val value = intent()
        val bytes =
            crypto.encrypt(
                scope,
                RecoveryPurpose.PENDING,
                value.id,
                AuthoringRecoveryCodec.pending(scope, value),
                true,
            )
        fails(AuthoringRecoveryFailure.LOCKED) {
            crypto.decrypt(
                scope,
                RecoveryPurpose.PENDING,
                bytes.copyOf().also { it[it.lastIndex] = (it.last().toInt() xor 1).toByte() },
            )
        }
        fails(AuthoringRecoveryFailure.LOCKED) {
            cipher().decrypt(scope, RecoveryPurpose.PENDING, bytes)
        }
        fails(AuthoringRecoveryFailure.INVALID) {
            crypto.decrypt(scope, RecoveryPurpose.PENDING, bytes.copyOf(bytes.size - 1))
        }
    }

    @Test
    fun missingDecryptionKeyNeverRequestsRegeneration() = runTest {
        val value = intent()
        val bytes =
            cipher()
                .encrypt(
                    scope,
                    RecoveryPurpose.PENDING,
                    value.id,
                    AuthoringRecoveryCodec.pending(scope, value),
                    true,
                )
        var called = false
        val missing = AuthoringRecoveryCipher { mayCreate ->
            called = true
            assertFalse(mayCreate)
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.LOCKED)
        }
        fails(AuthoringRecoveryFailure.LOCKED) {
            missing.decrypt(scope, RecoveryPurpose.PENDING, bytes)
        }
        assertTrue(called)
    }

    @Test
    fun unsentDeletionAndLogoutNeverDeletePendingCreation() = runTest {
        val store = MemoryAuthoringRecoveryStore()
        val d = draft()
        val value = intent(d)
        store.saveDraft(scope, d, "Europe/Vienna")
        store.prepareCreation(scope, value)
        store.discardUnsent(scope, d.id)
        store.clearUnsentForAccount(actor.uid)
        assertNull(store.load(scope)?.draft)
        assertEquals(value, store.load(scope)?.pending)
        assertNull(store.load(scope.copy(uid = "other")))
    }

    @Test
    fun anotherUuidAndChangedSameUuidCannotReplacePending() = runTest {
        val store = MemoryAuthoringRecoveryStore()
        val value = intent()
        store.prepareCreation(scope, value)
        fails(AuthoringRecoveryFailure.PENDING_CONFLICT) { store.prepareCreation(scope, intent()) }
        fails(AuthoringRecoveryFailure.PENDING_CONFLICT) {
            store.prepareCreation(scope, value.copy(fields = value.fields + ("title" to "changed")))
        }
        fails(AuthoringRecoveryFailure.PENDING_CONFLICT) {
            store.saveDraft(scope, draft(), "Europe/Vienna")
        }
        assertEquals(value, store.prepareCreation(scope, value))
        assertEquals(value, store.load(scope)?.pending)
    }

    @Test
    fun onlyExactReadbackMayClearPendingAndCorrespondingUnsentCopy() = runTest {
        val store = MemoryAuthoringRecoveryStore()
        val d = draft()
        val value = intent(d)
        store.saveDraft(scope, d, "Europe/Vienna")
        store.prepareCreation(scope, value)
        fails(AuthoringRecoveryFailure.PENDING_CONFLICT) {
            store.confirmCreation(
                scope,
                value,
                item(value).copy(fields = item(value).fields + ("title" to "foreign")),
            )
        }
        assertEquals(value, store.load(scope)?.pending)
        store.confirmCreation(scope, value, item(value))
        assertNull(store.load(scope))
    }

    @Test
    fun storesReturnDefensiveTypedCopiesRatherThanMutableInputMaps() = runTest {
        val fields = intent().fields.toMutableMap()
        val value = intent().copy(id = fields["id"] as String, fields = fields)
        val store = MemoryAuthoringRecoveryStore()
        val saved = store.prepareCreation(scope, value)
        fields["title"] = "mutated after save"
        assertNotEquals(fields["title"], saved.fields["title"])
        assertEquals(saved, store.load(scope)?.pending)
    }

    @Test
    fun scopeLimitNeverEvictsPreviousPendingRequests() = runTest {
        val store = MemoryAuthoringRecoveryStore()
        repeat(32) { n ->
            val s = scope.copy(organizationId = "org-$n")
            val value =
                intent().let {
                    it.copy(
                        organizationId = s.organizationId,
                        fields = it.fields + ("organizationId" to s.organizationId),
                    )
                }
            store.prepareCreation(s, value)
        }
        fails(AuthoringRecoveryFailure.LIMIT) { store.saveDraft(scope, draft(), "Europe/Vienna") }
        assertNotNull(store.load(scope.copy(organizationId = "org-0"))?.pending)
    }

    @Test
    fun repositoryHasExactJournalBeforeFirstSdkCommitAndClearsOnlyAfterReceipt() = runTest {
        val store = MemoryAuthoringRecoveryStore()
        val source = Source()
        val value = intent()
        source.checkBeforeWrite = { sent -> assertEquals(sent, store.load(scope)?.pending) }
        assertEquals(value.id, AuthoringRepository(source, { actor }, gate, store).submit(value).id)
        assertEquals(1, source.writes)
        assertNull(store.load(scope))
    }

    @Test
    fun persistenceFailureBeforeCommitMakesNoSdkWrite() = runTest {
        val store =
            object : AuthoringRecoveryStore by MemoryAuthoringRecoveryStore() {
                override suspend fun prepareCreation(
                    scope: AuthoringRecoveryScope,
                    intent: AuthoringSubmission,
                ): AuthoringSubmission =
                    throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO)
            }
        val source = Source()
        fails(AuthoringRecoveryFailure.IO) {
            AuthoringRepository(source, { actor }, gate, store).submit(intent())
        }
        assertEquals(0, source.writes)
    }

    @Test
    fun accountChangeImmediatelyAfterDurablePrepareLeavesJournalButNeverCallsSdk() = runTest {
        var current: OrganizationSession? = actor
        val memory = MemoryAuthoringRecoveryStore()
        val store =
            object : AuthoringRecoveryStore by memory {
                override suspend fun prepareCreation(
                    scope: AuthoringRecoveryScope,
                    intent: AuthoringSubmission,
                ): AuthoringSubmission {
                    val durable = memory.prepareCreation(scope, intent)
                    current = actor.copy(uid = "another-account", revision = 2)
                    return durable
                }
            }
        val source = Source()
        val original = intent()
        try {
            AuthoringRepository(source, { current }, gate, store).submit(original)
            fail("Changed identity must cancel before SDK")
        } catch (_: kotlinx.coroutines.CancellationException) {}
        assertEquals(0, source.writes)
        assertNull(source.actual)
        assertEquals(original, memory.load(scope)?.pending)
        assertNull(memory.load(scope.copy(uid = "another-account")))
    }

    @Test
    fun localClearFailureAfterServerReadbackStaysUnconfirmedUntilExplicitReadOnlyRecovery() =
        runTest {
            val memory = MemoryAuthoringRecoveryStore()
            var failClear = true
            val store =
                object : AuthoringRecoveryStore by memory {
                    override suspend fun confirmCreation(
                        scope: AuthoringRecoveryScope,
                        expectedIntent: AuthoringSubmission,
                        actual: AuthoringItem,
                    ) {
                        if (failClear) throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO)
                        memory.confirmCreation(scope, expectedIntent, actual)
                    }
                }
            val source = Source()
            val original = intent()
            val repository = AuthoringRepository(source, { actor }, gate, store)
            try {
                repository.submit(original)
                fail("Unconfirmed local clear")
            } catch (error: AuthoringException) {
                assertEquals(AuthoringFailure.UNCONFIRMED, error.failure)
            }
            assertEquals(1, source.writes)
            assertEquals(original, memory.load(scope)?.pending)
            assertTrue(AuthoringContract.matches(original, requireNotNull(source.actual)))
            failClear = false
            assertEquals(source.actual, repository.recover(original))
            assertEquals(1, source.writes)
            assertNull(memory.load(scope))
        }

    @Test
    fun lostResponseReadRecoveryClearsJournalWithoutSecondCommit() = runTest {
        val source = Source().apply { failAfterSend = true }
        val store = MemoryAuthoringRecoveryStore()
        val value = intent()
        val repository = AuthoringRepository(source, { actor }, gate, store)
        try {
            repository.submit(value)
            fail("Expected uncertain response")
        } catch (error: AuthoringException) {
            assertEquals(AuthoringFailure.UNCONFIRMED, error.failure)
        }
        assertEquals(value, store.load(scope)?.pending)
        assertEquals(value.id, repository.recover(value)?.id)
        assertEquals(1, source.writes)
        assertNull(store.load(scope))
    }

    @Test
    fun readAbsenceKeepsOriginalIntentAndRejectsNewUuid() = runTest {
        val source = Source().apply { failBeforeCommit = true }
        val store = MemoryAuthoringRecoveryStore()
        val value = intent()
        val repository = AuthoringRepository(source, { actor }, gate, store)
        runCatching { repository.submit(value) }
        assertNull(repository.recover(value))
        assertEquals(value, store.load(scope)?.pending)
        fails(AuthoringRecoveryFailure.PENDING_CONFLICT) { repository.submit(intent()) }
        assertEquals(1, source.writes)
    }

    @Test
    fun coldModelOffersDraftButDoesNotRestoreOrSubmitAutomatically() = runTest {
        val store = MemoryAuthoringRecoveryStore()
        val d = draft()
        store.saveDraft(scope, d, "America/Los_Angeles")
        val source = Source()
        val model = AuthoringViewModel(source, { actor }, gate, store)
        model.show(org.id)
        advanceUntilIdle()
        assertEquals(d, model.state.value.recoveredDraft)
        assertNull(model.state.value.draft)
        assertFalse(model.state.value.canCreate)
        model.create()
        assertNull(model.state.value.draft)
        model.restoreDraft()
        assertEquals(d, model.state.value.draft)
        assertEquals("America/Los_Angeles", model.state.value.draftZoneId)
        assertEquals(0, source.writes)
    }

    @Test
    fun coldPendingBlocksNewUuidDiscardAndAutomaticRetryEvenAfterAbsence() = runTest {
        val store = MemoryAuthoringRecoveryStore()
        val value = intent()
        store.prepareCreation(scope, value)
        val source = Source()
        val model = AuthoringViewModel(source, { actor }, gate, store)
        model.show(org.id)
        advanceUntilIdle()
        assertEquals(value, model.state.value.uncertain)
        assertNull(model.state.value.draft)
        model.create()
        model.discardLocalForm()
        model.retryAbsentCreation()
        advanceUntilIdle()
        assertEquals(0, source.writes)
        model.recover()
        advanceUntilIdle()
        assertTrue(model.state.value.recoveryChecked)
        assertEquals(value, store.load(scope)?.pending)
        assertEquals(0, source.writes)
        model.retryAbsentCreation()
        advanceUntilIdle()
        assertEquals(1, source.writes)
        assertEquals(value.id, model.state.value.confirmed?.id)
    }

    @Test
    fun autosaveDebouncesAndLogoutDeletesOnlyUnsentText() = runTest {
        val sessions = MutableStateFlow<OrganizationSession?>(actor)
        val store = MemoryAuthoringRecoveryStore()
        val source = Source()
        val model = AuthoringViewModel(source, { sessions.value }, gate, store)
        model.observeSessions(sessions)
        model.show(org.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "Last private text") }
        runCurrent()
        assertNull(store.load(scope))
        advanceTimeBy(650)
        runCurrent()
        assertEquals("Last private text", store.load(scope)?.draft?.title)
        sessions.value = null
        runCurrent()
        assertNull(model.state.value.draft)
        assertNull(store.load(scope))
        assertEquals(0, source.writes)
    }

    @Test
    fun sameUidOrganizationNavigationFlushesLatestTextBeforeReplacingScope() = runTest {
        val store = MemoryAuthoringRecoveryStore()
        val source = Source()
        val model = AuthoringViewModel(source, { actor }, gate, store)
        model.show(org.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "Previously acknowledged text") }
        advanceUntilIdle()
        val originalId = requireNotNull(model.state.value.draft).id
        assertEquals("Previously acknowledged text", store.load(scope)?.draft?.title)
        model.change { it.copy(title = "Latest text before navigation") }
        // No dispatcher turn between hide and the next organization: the old immediate save has not
        // run yet.
        model.hide()
        val other =
            org.copy(
                id = "second-recovery-org",
                fields = org.fields + ("id" to "second-recovery-org"),
            )
        source.organization = other
        model.show(other.id)
        advanceUntilIdle()
        assertEquals(other.id, model.state.value.organizationId)
        assertEquals(originalId, store.load(scope)?.draft?.id)
        assertEquals("Latest text before navigation", store.load(scope)?.draft?.title)
        assertEquals(0, source.writes)
    }

    @Test
    fun rapidReturnToOriginalOrganizationWaitsForItsExitFlushBeforeOfferingRecovery() = runTest {
        val store = MemoryAuthoringRecoveryStore()
        val source = Source()
        val model = AuthoringViewModel(source, { actor }, gate, store)
        model.show(org.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "Exact first unsent snapshot") }
        val original = requireNotNull(model.state.value.draft)
        model.hide()
        val other =
            org.copy(
                id = "return-recovery-org",
                fields = org.fields + ("id" to "return-recovery-org"),
            )
        source.organization = other
        model.show(other.id)
        model.hide()
        source.organization = org
        model.show(org.id)
        advanceUntilIdle()
        assertEquals(original, store.load(scope)?.draft)
        assertEquals(original, model.state.value.recoveredDraft)
        assertFalse(model.state.value.canCreate)
        assertNull(model.state.value.draft)
        assertEquals(0, source.writes)
    }

    @Test
    fun logoutBeforeQueuedScopeExitFlushCannotWritePrivateDraftAfterClear() = runTest {
        val sessions = MutableStateFlow<OrganizationSession?>(actor)
        val store = MemoryAuthoringRecoveryStore()
        val source = Source()
        val model = AuthoringViewModel(source, { sessions.value }, gate, store)
        model.observeSessions(sessions)
        model.show(org.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "Never written after logout") }
        model.hide()
        val other =
            org.copy(
                id = "logout-recovery-org",
                fields = org.fields + ("id" to "logout-recovery-org"),
            )
        source.organization = other
        model.show(other.id)
        sessions.value = null
        advanceUntilIdle()
        assertNull(store.load(scope))
        assertNull(model.state.value.draft)
        assertNull(model.state.value.recoveredDraft)
        assertEquals(0, source.writes)
    }

    @Test
    fun otherUidBeforeQueuedScopeExitFlushCannotRestoreOrSaveOriginalAccountText() = runTest {
        val sessions = MutableStateFlow<OrganizationSession?>(actor)
        val store = MemoryAuthoringRecoveryStore()
        val source = Source()
        val model = AuthoringViewModel(source, { sessions.value }, gate, store)
        model.observeSessions(sessions)
        model.show(org.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "Original private text") }
        model.hide()
        val other =
            org.copy(
                id = "switch-recovery-org",
                fields = org.fields + ("id" to "switch-recovery-org"),
            )
        source.organization = other
        model.show(other.id)
        sessions.value = actor.copy(uid = "different-owner", revision = 2, ready = false)
        advanceUntilIdle()
        assertNull(store.load(scope))
        assertNull(store.load(scope.copy(uid = "different-owner")))
        assertNull(model.state.value.draft)
        assertNull(model.state.value.recoveredDraft)
        assertFalse(model.state.value.actionable)
        assertEquals(0, source.writes)
    }

    @Test
    fun failedExitSaveRemainsVisibleAcrossSuccessfulReloadAndRetainsLatestSnapshotUntilExplicitRetry() =
        runTest {
            val memory = MemoryAuthoringRecoveryStore()
            var failing = false
            var saves = 0
            val store =
                object : AuthoringRecoveryStore by memory {
                    override suspend fun saveDraft(
                        scope: AuthoringRecoveryScope,
                        draft: AuthoringDraft,
                        zoneId: String,
                    ) {
                        saves++
                        if (failing) throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO)
                        memory.saveDraft(scope, draft, zoneId)
                    }
                }
            val source = Source()
            val model = AuthoringViewModel(source, { actor }, gate, store)
            model.show(org.id)
            advanceUntilIdle()
            model.create()
            model.change { it.copy(title = "Acknowledged original") }
            advanceUntilIdle()
            model.change { it.copy(title = "Latest unsaved private text") }
            val latest = requireNotNull(model.state.value.draft)
            failing = true
            model.hide()
            val other =
                org.copy(id = "failed-exit-org", fields = org.fields + ("id" to "failed-exit-org"))
            source.organization = other
            model.show(other.id)
            advanceUntilIdle()
            assertEquals(1, model.state.value.unsavedExitCount)
            assertEquals(AuthoringRecoveryFailure.IO, model.state.value.exitSaveError)
            assertEquals("Acknowledged original", memory.load(scope)?.draft?.title)
            val attempts = saves
            model.refresh()
            advanceUntilIdle()
            assertEquals(1, model.state.value.unsavedExitCount)
            assertEquals(AuthoringRecoveryFailure.IO, model.state.value.exitSaveError)
            assertEquals(attempts, saves)
            model.hide()
            source.organization = org
            model.show(org.id)
            advanceUntilIdle()
            assertEquals(latest, model.state.value.recoveredDraft)
            assertTrue(model.state.value.failedCurrentDraft)
            assertFalse(model.state.value.canCreate)
            assertEquals(attempts, saves)
            model.restoreDraft()
            assertEquals(latest, model.state.value.draft)
            assertFalse(model.state.value.draftSaved)
            model.hide()
            model.show(org.id)
            advanceUntilIdle()
            assertEquals(attempts, saves)
            assertEquals(1, model.state.value.unsavedExitCount)
            assertEquals(latest, model.state.value.draft)
            failing = false
            model.retryFailedLocalSave()
            advanceUntilIdle()
            assertEquals(latest, memory.load(scope)?.draft)
            assertEquals(0, model.state.value.unsavedExitCount)
            assertNull(model.state.value.exitSaveError)
            assertTrue(model.state.value.draftSaved)
            assertEquals(0, source.writes)
        }

    @Test
    fun durablePendingAlwaysDominatesFailedUnsentMemorySnapshotAndPreventsLocalOverwrite() =
        runTest {
            val memory = MemoryAuthoringRecoveryStore()
            var failing = false
            var saves = 0
            val store =
                object : AuthoringRecoveryStore by memory {
                    override suspend fun saveDraft(
                        scope: AuthoringRecoveryScope,
                        draft: AuthoringDraft,
                        zoneId: String,
                    ) {
                        saves++
                        if (failing) throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO)
                        memory.saveDraft(scope, draft, zoneId)
                    }
                }
            val source = Source()
            val model = AuthoringViewModel(source, { actor }, gate, store)
            model.show(org.id)
            advanceUntilIdle()
            model.create()
            model.change {
                it.copy(title = "Acknowledged title", summary = "Summary", body = "Body")
            }
            advanceUntilIdle()
            val original = intent(requireNotNull(model.state.value.draft))
            model.change { it.copy(title = "Unsent later memory version") }
            failing = true
            model.hide()
            val other =
                org.copy(
                    id = "pending-dominance-org",
                    fields = org.fields + ("id" to "pending-dominance-org"),
                )
            source.organization = other
            model.show(other.id)
            advanceUntilIdle()
            memory.prepareCreation(scope, original)
            model.hide()
            source.organization = org
            model.show(org.id)
            advanceUntilIdle()
            val attempts = saves
            assertEquals(original, model.state.value.uncertain)
            assertNull(model.state.value.recoveredDraft)
            assertNull(model.state.value.draft)
            assertEquals(1, model.state.value.unsavedExitCount)
            model.restoreDraft()
            model.retryFailedLocalSave()
            model.create()
            advanceUntilIdle()
            assertEquals(attempts, saves)
            assertEquals(original, memory.load(scope)?.pending)
            assertEquals(0, source.writes)
        }

    @Test
    fun logoutClearsFailedExitMemoryAndPreviouslyAcknowledgedUnsentCopy() = runTest {
        val memory = MemoryAuthoringRecoveryStore()
        var failing = false
        val store =
            object : AuthoringRecoveryStore by memory {
                override suspend fun saveDraft(
                    scope: AuthoringRecoveryScope,
                    draft: AuthoringDraft,
                    zoneId: String,
                ) {
                    if (failing) throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO)
                    memory.saveDraft(scope, draft, zoneId)
                }
            }
        val sessions = MutableStateFlow<OrganizationSession?>(actor)
        val source = Source()
        val model = AuthoringViewModel(source, { sessions.value }, gate, store)
        model.observeSessions(sessions)
        model.show(org.id)
        advanceUntilIdle()
        model.create()
        model.change { it.copy(title = "Acknowledged text") }
        advanceUntilIdle()
        model.change { it.copy(title = "Failed latest text") }
        failing = true
        model.hide()
        val other =
            org.copy(id = "failed-logout-org", fields = org.fields + ("id" to "failed-logout-org"))
        source.organization = other
        model.show(other.id)
        advanceUntilIdle()
        assertEquals(1, model.state.value.unsavedExitCount)
        sessions.value = null
        advanceUntilIdle()
        assertEquals(0, model.state.value.unsavedExitCount)
        assertNull(model.state.value.exitSaveError)
        assertNull(memory.load(scope))
        assertNull(model.state.value.draft)
        assertNull(model.state.value.recoveredDraft)
    }

    @Test
    fun thirtyTwoFailedScopesBlockAnotherCreateWithoutEvictingTheFirstSnapshot() = runTest {
        val store =
            object : AuthoringRecoveryStore by MemoryAuthoringRecoveryStore() {
                override suspend fun saveDraft(
                    scope: AuthoringRecoveryScope,
                    draft: AuthoringDraft,
                    zoneId: String,
                ): Unit = throw AuthoringRecoveryException(AuthoringRecoveryFailure.IO)
            }
        val source = Source()
        val model = AuthoringViewModel(source, { actor }, gate, store)
        fun select(number: Int) {
            val id = "failed-cap-$number"
            source.organization = org.copy(id = id, fields = org.fields + ("id" to id))
            model.show(id)
        }
        repeat(32) { number ->
            select(number)
            advanceUntilIdle()
            assertTrue(model.state.value.canCreate)
            model.create()
            model.change { it.copy(title = "Private failed snapshot $number") }
            model.hide()
        }
        select(32)
        advanceUntilIdle()
        assertEquals(32, model.state.value.unsavedExitCount)
        assertFalse(model.state.value.canCreate)
        model.create()
        assertNull(model.state.value.draft)
        model.hide()
        select(0)
        advanceUntilIdle()
        assertEquals("Private failed snapshot 0", model.state.value.recoveredDraft?.title)
        assertEquals(32, model.state.value.unsavedExitCount)
        assertEquals(0, source.writes)
    }

    @Test
    fun accountSwitchHidesButRetainsPendingAndReturningOwnerCanRecheck() = runTest {
        val sessions = MutableStateFlow<OrganizationSession?>(actor)
        val store = MemoryAuthoringRecoveryStore()
        val value = intent()
        store.prepareCreation(scope, value)
        val model = AuthoringViewModel(Source(), { sessions.value }, gate, store)
        model.observeSessions(sessions)
        model.show(org.id)
        advanceUntilIdle()
        sessions.value = actor.copy(uid = "other", revision = 2, ready = false)
        runCurrent()
        assertNull(model.state.value.uncertain)
        assertEquals(value, store.load(scope)?.pending)
        sessions.value = actor.copy(revision = 3)
        advanceUntilIdle()
        assertEquals(value, model.state.value.uncertain)
    }

    @Test
    fun corruptStorageMakesCreateFailClosedWithoutDiscardingTypedText() = runTest {
        val bad =
            object : AuthoringRecoveryStore by MemoryAuthoringRecoveryStore() {
                override suspend fun load(
                    scope: AuthoringRecoveryScope
                ): AuthoringRecoveredCreation? =
                    throw AuthoringRecoveryException(AuthoringRecoveryFailure.LOCKED)
            }
        val source = Source()
        val model = AuthoringViewModel(source, { actor }, gate, bad)
        model.show(org.id)
        advanceUntilIdle()
        model.create()
        assertEquals(AuthoringRecoveryFailure.LOCKED, model.state.value.recoveryError)
        assertFalse(model.state.value.canCreate)
        assertNull(model.state.value.draft)
        assertEquals(0, source.writes)
    }

    @Test
    fun restoredDraftCannotBypassCurrentOrganizationAuthority() = runTest {
        val store = MemoryAuthoringRecoveryStore()
        store.saveDraft(scope, draft(), "Europe/Vienna")
        val source =
            Source().apply {
                organization =
                    org.copy(
                        fields = org.fields + ("ownerId" to "foreign"),
                        authority = OrganizationAuthority.NONE,
                    )
            }
        val model = AuthoringViewModel(source, { actor }, gate, store)
        model.show(org.id)
        advanceUntilIdle()
        model.restoreDraft()
        assertFalse(model.state.value.actionable)
        assertNull(model.state.value.draft)
        assertEquals(0, source.writes)
    }
}
