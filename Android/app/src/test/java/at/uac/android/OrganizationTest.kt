package at.uac.android

import at.uac.android.core.ExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerLease
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import at.uac.android.core.LocalStorage
import at.uac.android.feature.auth.AuthLegalDocument
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organization.*
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.*
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class OrganizationTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    private val now = Instant.parse("2026-09-03T01:00:00.123456Z")
    private val alice = OrganizationSession("synthetic-alice", 1, true, "Alice", "user")
    private val bob = alice.copy(uid = "synthetic-bob", revision = 2)
    private val rules =
        AuthLegalDocument(
            "organizationRules",
            "existing-v1",
            true,
            mapOf("de" to "Rules"),
            mapOf("de" to "Text"),
        )
    private val draft =
        OrganizationDraft(
            "synthetic-organization",
            "Test Community",
            "A real community description",
            "More details",
            region = "wien",
            city = "Wien",
            acceptedRulesVersion = rules.version,
        )

    private fun row(
        status: String = "pendingReview",
        extra: Map<String, Any?> = emptyMap(),
        session: OrganizationSession = alice,
    ) =
        OrganizationContract.record(
            RawDocument(
                draft.id,
                OrganizationContract.create(draft, alice, now) +
                    ("moderationStatus" to status) +
                    extra,
            ),
            session,
        )

    private fun fails(failure: OrganizationFailure, action: () -> Unit) {
        try {
            action()
            fail("Expected $failure")
        } catch (error: OrganizationException) {
            assertEquals(failure, error.failure)
        }
    }

    private suspend fun failsAsync(failure: OrganizationFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $failure")
        } catch (error: OrganizationException) {
            assertEquals(failure, error.failure)
        }
    }

    private val gate =
        object : OrganizationMutationGate {
            override suspend fun <T> withSession(
                session: OrganizationSession,
                operation: suspend () -> T,
            ) = withContext(NonCancellable) { operation() }
        }

    private inner class FakeSource : OrganizationSource {
        var rulesValue = rules
        var hubValue = OrganizationHub(emptyList(), emptyList())
        var targetValue: OrganizationRecord? = null
        var calls = 0
        var discards = 0
        var failLogo = false
        var failRules = false
        var pending: CompletableDeferred<Unit>? = null

        override suspend fun hub(session: OrganizationSession) = hubValue

        override suspend fun request(id: String, session: OrganizationSession) = targetValue

        override suspend fun rules(): AuthLegalDocument {
            if (failRules) throw OrganizationException(OrganizationFailure.OFFLINE)
            return rulesValue
        }

        override fun changes(session: OrganizationSession, requestId: String?) =
            flow<Result<Unit>> {}

        override suspend fun create(
            draft: OrganizationDraft,
            rules: AuthLegalDocument,
            session: OrganizationSession,
            language: String,
        ): OrganizationRecord {
            calls++
            pending?.await()
            return OrganizationContract.record(
                RawDocument(draft.id, OrganizationContract.create(draft, session, now)),
                session,
            )
        }

        override suspend fun revise(
            base: OrganizationRecord,
            draft: OrganizationDraft,
            session: OrganizationSession,
        ): OrganizationRecord {
            calls++
            return base
        }

        override suspend fun discard(base: OrganizationRecord, session: OrganizationSession) {
            discards++
            pending?.await()
        }

        override suspend fun logo(
            base: OrganizationRecord,
            jpeg: ByteArray,
            session: OrganizationSession,
        ): OrganizationRecord {
            if (failLogo) throw OrganizationException(OrganizationFailure.OFFLINE)
            return base
        }
    }

    @Test
    fun createHasZeroCountersNoPrivilegedRolesAndCanonicalIdentity() {
        val fields = OrganizationContract.create(draft, alice, now)
        assertEquals(draft.id, fields["id"])
        assertEquals(alice.uid, fields["submittedByUserId"])
        assertEquals("pendingReview", fields["moderationStatus"])
        assertEquals(now, fields["submittedAt"])
        assertNull(fields["ownerId"])
        assertEquals(emptyList<String>(), fields["adminIds"])
        assertEquals(emptyList<String>(), fields["moderatorIds"])
        OrganizationContract.counterFields.forEach { assertEquals(0L, fields[it]) }
    }

    @Test
    fun explicitConsentAndExactOrganizationRulesVersionAreMandatory() {
        fails(OrganizationFailure.CONSENT) {
            OrganizationContract.acceptancePayload(
                draft.copy(acceptedRulesVersion = null),
                rules,
                "de",
                "test",
            )
        }
        fails(OrganizationFailure.CONSENT) {
            OrganizationContract.acceptancePayload(draft, rules.copy(version = "new"), "de", "test")
        }
        fails(OrganizationFailure.CONSENT) {
            OrganizationContract.acceptancePayload(draft, rules.copy(type = "terms"), "de", "test")
        }
        assertEquals(
            "android",
            OrganizationContract.acceptancePayload(draft, rules, "unknown", "test")[
                    "acceptedFromPlatform"],
        )
        assertEquals(
            "de",
            OrganizationContract.acceptancePayload(draft, rules, "unknown", "test")["locale"],
        )
    }

    @Test
    fun acceptanceResponseRequiresIdVersionAndRealTimestamp() {
        val data =
            mapOf(
                "organizationId" to draft.id,
                "version" to rules.version,
                "acceptedAt" to now.toString(),
            )
        assertEquals(now, OrganizationContract.acceptance(data, draft.id, rules.version))
        listOf(
                data + ("version" to "other"),
                data + ("organizationId" to "other"),
                data + ("acceptedAt" to "now"),
                emptyMap(),
            )
            .forEach {
                fails(OrganizationFailure.UNCONFIRMED) {
                    OrganizationContract.acceptance(it, draft.id, rules.version)
                }
            }
    }

    @Test
    fun invalidIdsNamesAndDescriptionsCannotReachTransport() {
        listOf(
                draft.copy(id = "../bad"),
                draft.copy(id = "ukrainian-community"),
                draft.copy(id = "x".repeat(129)),
                draft.copy(name = " "),
                draft.copy(name = "a".repeat(181)),
                draft.copy(summary = "short"),
                draft.copy(summary = "a".repeat(161)),
                draft.copy(details = "a".repeat(1201)),
            )
            .forEach { fails(OrganizationFailure.INVALID) { OrganizationContract.validate(it) } }
    }

    @Test
    fun requiredRegionCityAndContactBoundsMatchRealRequestForm() {
        listOf(
                draft.copy(region = "other"),
                draft.copy(city = ""),
                draft.copy(email = "not-email"),
                draft.copy(phone = "a".repeat(81)),
                draft.copy(address = "a".repeat(501)),
                draft.copy(profileKind = "owner"),
            )
            .forEach { fails(OrganizationFailure.INVALID) { OrganizationContract.validate(it) } }
        OrganizationContract.profileKinds.forEach {
            assertEquals(
                it,
                OrganizationContract.validate(draft.copy(profileKind = it)).profileKind,
            )
        }
    }

    @Test
    fun webInputsRejectCredentialsUnsupportedSchemesAndWhitespace() {
        assertEquals(
            "https://example.invalid/path",
            OrganizationContract.website("example.invalid/path"),
        )
        assertEquals(
            "http://example.invalid",
            OrganizationContract.website("http://example.invalid"),
        )
        assertEquals(
            "https://example.invalid:8443/path",
            OrganizationContract.website("example.invalid:8443/path"),
        )
        listOf(
                "javascript:alert(1)",
                "file:///tmp/x",
                "ftp://example.invalid",
                "mailto:hello@example.invalid",
                "https://example.invalid:65536",
                "https://user:pass@example.invalid",
                "https://example.invalid/a b",
                "https://example.invalid\\bad",
            )
            .forEach {
                fails(OrganizationFailure.INVALID) { OrganizationContract.website(it) }
            }
    }

    @Test
    fun translationsAndUneditedDirectoryFieldsArePreserved() {
        val original =
            mapOf(
                "directoryProfile" to
                    mapOf("profileKind" to "community", "services" to listOf("Existing")),
                "localizations" to
                    mapOf(
                        "uk" to
                            mapOf(
                                "missionStatement" to "Existing mission",
                                "services" to listOf("Existing"),
                            )
                    ),
            )
        val fields =
            OrganizationContract.editableFields(
                draft.copy(germanName = "Deutsche Gemeinschaft"),
                original,
            )
        assertEquals(listOf("Existing"), (fields["directoryProfile"] as Map<*, *>)["services"])
        val localized = fields["localizations"] as Map<*, *>
        assertEquals("Existing mission", (localized["uk"] as Map<*, *>)["missionStatement"])
        assertEquals("Deutsche Gemeinschaft", (localized["de"] as Map<*, *>)["name"])
    }

    @Test
    fun ordinaryApplicantMayEditOnlyOwnUnpublishedRequest() {
        OrganizationContract.requestStatuses.forEach {
            OrganizationContract.requireEditable(row(it), alice)
        }
        fails(OrganizationFailure.DENIED) { OrganizationContract.requireEditable(row(), bob) }
        fails(OrganizationFailure.DENIED) {
            OrganizationContract.requireEditable(row("approved"), alice)
        }
        fails(OrganizationFailure.DENIED) {
            OrganizationContract.requireEditable(row("retentionDeleting"), alice)
        }
    }

    @Test
    fun nonzeroCountersAndInjectedRolesFailClosed() {
        listOf(
                mapOf("ownerId" to alice.uid),
                mapOf("adminIds" to listOf(alice.uid)),
                mapOf("moderatorIds" to listOf(alice.uid)),
                mapOf("likeCount" to 1),
                mapOf("likeState" to "liked"),
            )
            .forEach {
                fails(OrganizationFailure.INVALID) {
                    OrganizationContract.requireEditable(row(extra = it), alice)
                }
            }
    }

    @Test
    fun authorityComesFromApprovedOrganizationNotMembershipMirrors() {
        assertEquals(
            OrganizationAuthority.OWNER,
            row("approved", mapOf("ownerId" to alice.uid)).authority,
        )
        assertEquals(
            OrganizationAuthority.ADMIN,
            row("approved", mapOf("adminIds" to listOf(alice.uid))).authority,
        )
        assertEquals(
            OrganizationAuthority.MODERATOR,
            row("approved", mapOf("moderatorIds" to listOf(alice.uid))).authority,
        )
        assertEquals(
            OrganizationAuthority.NONE,
            row("approved", mapOf("communityMemberships" to listOf(alice.uid))).authority,
        )
        assertEquals(
            OrganizationAuthority.NONE,
            row("pendingReview", mapOf("ownerId" to alice.uid)).authority,
        )
    }

    @Test
    fun appAdminAndLegacyTopAdminHaveNoAutomaticOrgAuthority() {
        assertEquals(
            OrganizationAuthority.NONE,
            row("approved", session = alice.copy(globalRole = "admin")).authority,
        )
        assertEquals(
            OrganizationAuthority.NONE,
            row("approved", session = alice.copy(globalRole = "topAdmin")).authority,
        )
        assertEquals(
            OrganizationAuthority.PLATFORM_OWNER,
            row("approved", session = alice.copy(globalRole = "owner")).authority,
        )
        assertEquals(
            OrganizationAuthority.NONE,
            row("approved", session = alice.copy(ready = false, globalRole = "owner")).authority,
        )
    }

    @Test
    fun retentionWarnsAt23DaysAndIsDueAt30WithoutPretendingDeletion() {
        val record = row("needsRevision")
        assertEquals(RequestRetention.ACTIVE, record.retention(now.plusSeconds(23 * 86400 - 1)))
        assertEquals(RequestRetention.WARNING, record.retention(now.plusSeconds(23 * 86400)))
        assertEquals(RequestRetention.DUE, record.retention(now.plusSeconds(30 * 86400)))
        assertEquals(RequestRetention.ACTIVE, row().retention(now.plusSeconds(40 * 86400)))
        assertTrue(record.editable(alice))
    }

    @Test
    fun unknownStatusAndMalformedRecordsAreNotSuccessfulEmptyLists() {
        fails(OrganizationFailure.INVALID) { row("future") }
        fails(OrganizationFailure.INVALID) { row(extra = mapOf("id" to "foreign")) }
        fails(OrganizationFailure.INVALID) { row(extra = mapOf("updatedAt" to "now")) }
        fails(OrganizationFailure.INVALID) { row(extra = mapOf("adminIds" to listOf(123))) }
    }

    @Test
    fun guestAndNotReadyCannotCreate() = runTest {
        val source = FakeSource()
        failsAsync(OrganizationFailure.SIGN_IN) {
            OrganizationRepository(source, { null }, gate).submit(draft, rules, null, null, "de")
        }
        failsAsync(OrganizationFailure.NOT_READY) {
            OrganizationRepository(source, { alice.copy(ready = false) }, gate)
                .submit(draft, rules, null, null, "de")
        }
        assertEquals(0, source.calls)
    }

    @Test
    fun missingConsentStopsBeforeAnyMutation() = runTest {
        val source = FakeSource()
        failsAsync(OrganizationFailure.CONSENT) {
            OrganizationRepository(source, { alice }, gate)
                .submit(draft.copy(acceptedRulesVersion = null), rules, null, null, "de")
        }
        assertEquals(0, source.calls)
    }

    @Test
    fun failedOptionalLogoPreservesConfirmedRequestWithoutRollbackDelete() = runTest {
        val source = FakeSource().apply { failLogo = true }
        val result =
            OrganizationRepository(source, { alice }, gate)
                .submit(draft, rules, null, byteArrayOf(1), "de")
        assertEquals(draft.id, result.record.id)
        assertTrue(result.logoIncomplete)
        assertEquals(0, source.discards)
    }

    @Test
    fun missingRulesDoesNotHideExistingRequestsOrBlockTheirRevision() = runTest {
        val source =
            FakeSource().apply {
                failRules = true
                hubValue = OrganizationHub(listOf(row()), emptyList())
            }
        val model = OrganizationViewModel(source, { alice }, gate)
        model.show()
        runCurrent()
        assertEquals(draft.id, model.state.value.hub?.requests?.single()?.id)
        assertNull(model.state.value.rules)
        OrganizationRepository(source, { alice }, gate).submit(draft, null, row(), null, "de")
        assertEquals(1, source.calls)
        model.hide()
    }

    @Test
    fun ownerCannotReachBroaderDeleteBranchInApplicantPackage() = runTest {
        val source = FakeSource()
        failsAsync(OrganizationFailure.DENIED) {
            OrganizationRepository(source, { alice.copy(globalRole = "owner") }, gate)
                .discard(row())
        }
        assertEquals(0, source.discards)
    }

    @Test
    fun accountSwitchSuppressesInFlightCreateResult() = runTest {
        val source = FakeSource().apply { pending = CompletableDeferred() }
        var session = alice
        val task = async {
            OrganizationRepository(source, { session }, gate).submit(draft, rules, null, null, "de")
        }
        runCurrent()
        session = bob
        source.pending!!.complete(Unit)
        try {
            task.await()
            fail("Stale result")
        } catch (_: CancellationException) {}
    }

    @Test
    fun viewModelDoubleTapRunsExactlyOneCreate() = runTest {
        val source = FakeSource().apply { pending = CompletableDeferred() }
        val model = OrganizationViewModel(source, { alice }, gate)
        model.show()
        runCurrent()
        model.create()
        model.change { draft }
        model.submit("de")
        model.submit("de")
        runCurrent()
        // The model rejects a transformed ID; populate values with its own stable UUID.
        assertEquals(0, source.calls)
        model.change { draft.copy(id = it.id) }
        model.consent(true)
        model.submit("de")
        model.submit("de")
        runCurrent()
        assertEquals(1, source.calls)
        source.pending!!.complete(Unit)
        runCurrent()
        model.hide()
    }

    @Test
    fun sessionChangeImmediatelyClearsPrivateRequestsDraftAndLogo() = runTest {
        val sessions = MutableStateFlow<OrganizationSession?>(alice)
        val model =
            OrganizationViewModel(
                FakeSource().apply { hubValue = OrganizationHub(listOf(row()), emptyList()) },
                { sessions.value },
                gate,
            )
        model.observeSessions(sessions)
        model.show()
        runCurrent()
        model.create()
        assertNotNull(model.state.value.draft)
        sessions.value = bob
        runCurrent()
        assertNull(model.state.value.draft)
        assertNull(model.state.value.hub)
        assertFalse(model.state.value.logoSelected)
        model.hide()
    }

    @Test
    fun rulesVersionAndNameChangesClearConsent() = runTest {
        val source = FakeSource()
        val model = OrganizationViewModel(source, { alice }, gate)
        model.show()
        runCurrent()
        model.create()
        model.consent(true)
        assertEquals(rules.version, model.state.value.draft?.acceptedRulesVersion)
        model.change { it.copy(name = "Changed") }
        assertNull(model.state.value.draft?.acceptedRulesVersion)
        model.consent(true)
        source.rulesValue = rules.copy(version = "new-v2")
        model.refresh()
        runCurrent()
        assertNull(model.state.value.draft?.acceptedRulesVersion)
        model.hide()
    }

    @Test
    fun freshReviewChangeMakesOpenDraftReadonlyUntilExplicitReopen() = runTest {
        val original = row()
        val source =
            FakeSource().apply { hubValue = OrganizationHub(listOf(original), emptyList()) }
        val model = OrganizationViewModel(source, { alice }, gate)
        model.show()
        runCurrent()
        model.edit(original)
        model.change { it.copy(name = "Unsaved input") }
        val revised =
            row(
                "needsRevision",
                mapOf("updatedAt" to now.plusSeconds(1), "reviewMessage" to "Please revise"),
            )
        source.hubValue = OrganizationHub(listOf(revised), emptyList())
        model.refresh()
        runCurrent()
        assertEquals(OrganizationFailure.STALE, model.state.value.editorFailure)
        assertEquals("Unsaved input", model.state.value.draft?.name)
        assertFalse(model.state.value.editorWritable)
        model.change { it.copy(name = "Should not change") }
        model.submit("de")
        runCurrent()
        assertEquals("Unsaved input", model.state.value.draft?.name)
        assertEquals(0, source.calls)
        model.edit(revised)
        assertTrue(model.state.value.editorWritable)
        assertEquals(revised, model.state.value.base)
        model.hide()
    }

    @Test
    fun RemovedOrApprovedRequestNeverLeavesOldEditorWritable() = runTest {
        val original = row()
        val source =
            FakeSource().apply { hubValue = OrganizationHub(listOf(original), emptyList()) }
        val model = OrganizationViewModel(source, { alice }, gate)
        model.show()
        runCurrent()
        model.edit(original)
        source.hubValue = OrganizationHub(emptyList(), emptyList())
        model.refresh()
        runCurrent()
        assertEquals(OrganizationFailure.MISSING, model.state.value.editorFailure)
        assertFalse(model.state.value.editorWritable)
        assertNotNull(model.state.value.draft)
        model.submit("de")
        runCurrent()
        assertEquals(0, source.calls)
        model.hide()
    }

    @Test
    fun notificationTargetRequiresMatchingUidIdAndAllowedStatus() = runTest {
        val source = FakeSource()
        val repository = OrganizationRepository(source, { alice }, gate)
        failsAsync(OrganizationFailure.MISSING) { repository.request("../foreign") }
        source.targetValue = row(extra = mapOf("submittedByUserId" to bob.uid))
        assertNull(repository.request(draft.id))
        source.targetValue = row("retentionDeleting")
        assertNull(repository.request(draft.id))
        source.targetValue = row()
        assertNull(repository.request("another-id"))
        assertEquals(draft.id, repository.request(draft.id)?.id)
    }

    @Test
    fun approvedTargetOverridesOlderPendingHubAndNeverOpensEditor() = runTest {
        val original = row()
        val source =
            FakeSource().apply {
                hubValue = OrganizationHub(listOf(original), emptyList())
                targetValue = row("approved")
            }
        val model = OrganizationViewModel(source, { alice }, gate)
        model.show(draft.id)
        runCurrent()
        assertEquals("approved", model.state.value.target?.status)
        assertTrue(model.state.value.hub!!.requests.isEmpty())
        assertNull(model.state.value.draft)
        model.edit(original)
        assertNull(model.state.value.draft)
        model.hide()
    }

    @Test
    fun missingTargetIsUnavailableAndSameAccountTargetSwitchSuppressesOldMutationResult() =
        runTest {
            val source = FakeSource().apply { pending = CompletableDeferred() }
            val model = OrganizationViewModel(source, { alice }, gate)
            model.show()
            runCurrent()
            model.create()
            model.change { draft.copy(id = it.id) }
            model.consent(true)
            model.submit("de")
            runCurrent()
            assertEquals(1, source.calls)
            model.show("other-request")
            runCurrent()
            source.pending!!.complete(Unit)
            runCurrent()
            assertEquals("other-request", model.state.value.targetId)
            assertEquals(OrganizationFailure.MISSING, model.state.value.targetFailure)
            assertNull(model.state.value.target)
            assertNull(model.state.value.draft)
            assertNull(model.state.value.base)
            assertNull(model.state.value.confirmedId)
            model.hide()
        }

    @Test
    fun pickerRequiresExplicitAuthorizationSurvivesOrdinaryPauseAndCancelsOnClose() = runTest {
        val denied = OrganizationViewModel(FakeSource(), { alice }, gate)
        denied.show()
        runCurrent()
        denied.create()
        assertFalse(denied.beginPicker())
        denied.hide()
        var cancelled = 0
        val authorization = ExternalImagePickerAuthorization { uid, revision ->
            assertEquals(alice.uid, uid)
            assertEquals(alice.revision, revision)
            object : ExternalImagePickerLease {
                override fun finish() = Unit

                override fun cancel() {
                    cancelled++
                }
            }
        }
        val model = OrganizationViewModel(FakeSource(), { alice }, gate, authorization)
        model.show()
        runCurrent()
        model.create()
        assertTrue(model.beginPicker())
        assertFalse(model.beginPicker())
        model.hide()
        assertEquals(0, cancelled)
        assertTrue(model.state.value.pickerOpen)
        model.show()
        runCurrent()
        assertNotNull(model.state.value.draft)
        assertTrue(model.state.value.pickerOpen)
        model.closeDraft()
        assertEquals(1, cancelled)
        assertFalse(model.state.value.pickerOpen)
        model.hide()
    }

    @Test
    fun pickerLeaseIsCancelledOnAccountSwitchAndPreviewIsImmutable() = runTest {
        val sessions = MutableStateFlow<OrganizationSession?>(alice)
        var cancelled = 0
        val authorization = ExternalImagePickerAuthorization { _, _ ->
            object : ExternalImagePickerLease {
                override fun finish() = Unit

                override fun cancel() {
                    cancelled++
                }
            }
        }
        val model = OrganizationViewModel(FakeSource(), { sessions.value }, gate, authorization)
        model.observeSessions(sessions)
        model.show()
        runCurrent()
        model.create()
        assertTrue(model.beginPicker())
        sessions.value = bob
        runCurrent()
        assertEquals(1, cancelled)
        assertFalse(model.state.value.pickerOpen)
        assertNull(model.state.value.draft)
        assertNull(model.state.value.logoPreview)
        model.hide()
        val bytes = byteArrayOf(1, 2, 3)
        val selection = OrganizationLogoSelection(bytes)
        bytes[0] = 99
        val copy = selection.copyBytes()
        copy[1] = 99
        assertArrayEquals(byteArrayOf(1, 2, 3), selection.copyBytes())
    }

    @Test
    fun scopedStorageUrlsRejectCloudOtherBucketPathAndCredentials() {
        val url =
            "http://10.0.2.2:9198/v0/b/demo-uac-android.appspot.com/o/organizations%2F${draft.id}%2Flogo.jpg?alt=media&token=synthetic"
        assertTrue(LocalStorage.urlMatches(url, "organizations/${draft.id}/logo.jpg"))
        assertFalse(LocalStorage.urlMatches(url, "organizations/foreign/logo.jpg"))
        assertFalse(
            LocalStorage.urlMatches(
                url.replace("10.0.2.2:9198", "firebasestorage.googleapis.com"),
                "organizations/${draft.id}/logo.jpg",
            )
        )
        assertFalse(
            LocalStorage.urlMatches(
                url.replace("demo-uac-android.appspot.com", "production.appspot.com"),
                "organizations/${draft.id}/logo.jpg",
            )
        )
        assertFalse(
            LocalStorage.urlMatches(
                url.replace("10.0.2.2", "user@10.0.2.2"),
                "organizations/${draft.id}/logo.jpg",
            )
        )
    }

    @Test
    fun localAllowlistAddsOnlyReviewedOrganizationFunctions() {
        assertTrue(
            LocalCallableProtocol.endpoint("acceptOrganizationRules")
                .endsWith("/acceptOrganizationRules")
        )
        assertTrue(
            LocalCallableProtocol.endpoint("deleteOrganization").endsWith("/deleteOrganization")
        )
        try {
            LocalCallableProtocol.endpoint("approveOrganizationRequest")
            fail("Reviewer function outside4A")
        } catch (_: IllegalArgumentException) {}
    }

    @Test
    fun exactFailureMappingsAndTranslationsArePresent() {
        assertEquals(
            OrganizationFailure.LIMIT,
            organizationFailure(LocalCallableException(LocalCallableFailure.RESOURCE_EXHAUSTED)),
        )
        assertEquals(
            OrganizationFailure.LEGAL_CHANGED,
            organizationFailure(LocalCallableException(LocalCallableFailure.FAILED_PRECONDITION)),
        )
        assertEquals(
            OrganizationFailure.UNCONFIRMED,
            organizationFailure(LocalCallableException(LocalCallableFailure.UNCONFIRMED)),
        )
        OrganizationFailure.entries.forEach { failure ->
            listOf("de", "uk").forEach {
                assertTrue(organizationFailureText(failure, it).isNotBlank())
            }
        }
    }
}
