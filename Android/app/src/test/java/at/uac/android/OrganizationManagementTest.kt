package at.uac.android

import at.uac.android.core.ExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerLease
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.organization.*
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class OrganizationManagementTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    private val now = Instant.parse("2026-09-03T02:00:00.123456Z")

    @Test
    fun offerDateReopensSameLosAngelesCalendarDay() {
        val zone = ZoneId.of("America/Los_Angeles")
        val persisted = Instant.parse("2026-09-04T06:59:59.999999Z")
        val selected = OrganizationOfferCalendar.pickerMillis(persisted, zone)
        assertEquals(Instant.parse("2026-09-03T00:00:00Z").toEpochMilli(), selected)
        assertEquals(persisted, OrganizationOfferCalendar.inclusiveEnd(selected, zone))
    }

    @Test
    fun offerDateViennaSpringDstUsesNextLocalMidnight() {
        val zone = ZoneId.of("Europe/Vienna")
        val selected = Instant.parse("2026-03-29T00:00:00Z").toEpochMilli()
        val persisted = OrganizationOfferCalendar.inclusiveEnd(selected, zone)
        assertEquals(Instant.parse("2026-03-29T21:59:59.999999Z"), persisted)
        assertEquals(selected, OrganizationOfferCalendar.pickerMillis(persisted, zone))
    }

    @Test
    fun offerDateViennaAutumnDstUsesNextLocalMidnight() {
        val zone = ZoneId.of("Europe/Vienna")
        val selected = Instant.parse("2026-10-25T00:00:00Z").toEpochMilli()
        val persisted = OrganizationOfferCalendar.inclusiveEnd(selected, zone)
        assertEquals(Instant.parse("2026-10-25T22:59:59.999999Z"), persisted)
        assertEquals(selected, OrganizationOfferCalendar.pickerMillis(persisted, zone))
    }

    private val alice = OrganizationSession("synthetic-owner", 1, true, "Alice", "user")
    private val target = "synthetic-subscriber"
    private val basics =
        OrganizationDraft(
            "synthetic-managed-org",
            "Managed Organization",
            "A verified local organization",
            region = "wien",
            city = "Wien",
        )

    private fun row(
        extra: Fields = emptyMap(),
        session: OrganizationSession = alice,
    ): OrganizationRecord =
        OrganizationContract.record(
            RawDocument(
                basics.id,
                OrganizationContract.create(basics, alice, now) +
                    mapOf(
                        "moderationStatus" to "approved",
                        "ownerId" to alice.uid,
                        "likeCount" to 7L,
                    ) +
                    extra,
            ),
            session,
        )

    private val gate =
        object : OrganizationMutationGate {
            override suspend fun <T> withSession(
                session: OrganizationSession,
                operation: suspend () -> T,
            ): T = withContext(NonCancellable) { operation() }
        }

    private fun failWith(expected: OrganizationManagementFailure, action: () -> Unit) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: OrganizationManagementException) {
            assertEquals(expected, error.failure)
        }
    }

    private suspend fun failAsync(
        expected: OrganizationManagementFailure,
        action: suspend () -> Unit,
    ) {
        try {
            action()
            fail("Expected $expected")
        } catch (error: OrganizationManagementException) {
            assertEquals(expected, error.failure)
        }
    }

    private fun intent(
        action: OrganizationTeamAction = OrganizationTeamAction.ADMIN,
        previous: OrganizationTeamRole = OrganizationTeamRole.MEMBER,
    ) = OrganizationRoleIntent(target, action, previous)

    private fun receipt(
        intent: OrganizationRoleIntent = intent(),
        extra: Fields = emptyMap(),
    ): Fields =
        mapOf(
            "organizationId" to basics.id,
            "targetUserId" to intent.targetId,
            "previousRole" to intent.previousRole.wire,
            "newRole" to OrganizationManagementContract.desired(intent).wire,
            "updatedAt" to now.toString(),
        ) + extra

    private inner class FakeSource : OrganizationManagementSource {
        var record: OrganizationRecord? = row()
        var pending: CompletableDeferred<Unit>? = null
        var roleError: OrganizationManagementFailure? = null
        var readError: OrganizationManagementFailure? = null
        var offlineAfterRole = false
        var logoError = false
        var roles = 0
        var updates = 0
        var updateFields: Fields = emptyMap()
        var page =
            OrganizationSubscriberPage(
                listOf(OrganizationSubscriber(target, now, "subscription-$target")),
                null,
            )
        val events = MutableSharedFlow<Result<Unit>>(extraBufferCapacity = 1)

        override suspend fun organization(
            id: String,
            session: OrganizationSession,
        ): OrganizationRecord? {
            readError?.let { throw OrganizationManagementException(it) }
            return record?.let { OrganizationManagementContract.canonical(it, session) }
        }

        override suspend fun subscribers(
            id: String,
            after: OrganizationSubscriberCursor?,
            session: OrganizationSession,
        ) = page

        override suspend fun profiles(ids: List<String>, session: OrganizationSession) = ids.map {
            OrganizationPublicMember(it, "Public $it", "Wien")
        }

        override fun changes(id: String, session: OrganizationSession) = events

        override suspend fun update(
            base: OrganizationRecord,
            fields: Fields,
            session: OrganizationSession,
        ) {
            updates++
            pending?.await()
            updateFields = fields
            record =
                row(
                    base.fields + fields + ("updatedAt" to now.plusSeconds(updates.toLong())),
                    session,
                )
        }

        override suspend fun logo(
            base: OrganizationRecord,
            jpeg: ByteArray,
            session: OrganizationSession,
        ): OrganizationRecord {
            if (logoError)
                throw OrganizationManagementException(OrganizationManagementFailure.OFFLINE)
            return base
        }

        override suspend fun role(
            base: OrganizationRecord,
            intent: OrganizationRoleIntent,
            session: OrganizationSession,
        ): Any? {
            roles++
            pending?.await()
            roleError?.let { throw OrganizationManagementException(it) }
            val admins = (base.fields["adminIds"] as List<*>).filterNot { it == target }
            val moderators = (base.fields["moderatorIds"] as List<*>).filterNot { it == target }
            val fields =
                when (intent.action) {
                    OrganizationTeamAction.ADMIN ->
                        mapOf("adminIds" to admins + target, "moderatorIds" to moderators)
                    OrganizationTeamAction.MODERATOR ->
                        mapOf("adminIds" to admins, "moderatorIds" to moderators + target)
                    OrganizationTeamAction.REMOVE ->
                        mapOf("adminIds" to admins, "moderatorIds" to moderators)
                    OrganizationTeamAction.TRANSFER ->
                        mapOf(
                            "ownerId" to target,
                            "adminIds" to emptyList<String>(),
                            "moderatorIds" to emptyList<String>(),
                        )
                }
            record =
                row(
                    base.fields + fields + ("updatedAt" to now.plusSeconds(roles.toLong())),
                    session,
                )
            if (offlineAfterRole) readError = OrganizationManagementFailure.OFFLINE
            return if (intent.action == OrganizationTeamAction.TRANSFER)
                mapOf(
                    "organizationId" to base.id,
                    "previousOwnerId" to base.fields["ownerId"],
                    "newOwnerId" to target,
                    "updatedAt" to now.toString(),
                )
            else receipt(intent)
        }
    }

    @Test
    fun approvedInformationAuthorityUsesExactCanonicalRoles() {
        assertTrue(OrganizationManagementContract.canEdit(row(), alice))
        assertTrue(
            OrganizationManagementContract.canEdit(
                row(mapOf("ownerId" to "other", "adminIds" to listOf(alice.uid))),
                alice,
            )
        )
        assertFalse(
            OrganizationManagementContract.canEdit(
                row(mapOf("ownerId" to "other", "moderatorIds" to listOf(alice.uid))),
                alice,
            )
        )
        assertTrue(OrganizationManagementContract.canEdit(row(), alice.copy(globalRole = "owner")))
        for (role in listOf("admin", "topAdmin", "user")) assertFalse(
            OrganizationManagementContract.canEdit(
                row(mapOf("ownerId" to "other")),
                alice.copy(globalRole = role),
            )
        )
    }

    @Test
    fun moderatorsCanViewButNeverGainInformationOrTeamRights() {
        val org = row(mapOf("ownerId" to "other", "moderatorIds" to listOf(alice.uid)))
        assertEquals(
            OrganizationAuthority.MODERATOR,
            OrganizationManagementContract.requireApproved(org, alice).authority,
        )
        assertFalse(OrganizationManagementContract.canEdit(org, alice))
        assertFalse(OrganizationManagementContract.canManage(org, alice))
    }

    @Test
    fun teamAndTransferPermissionsAreSeparate() {
        assertTrue(OrganizationManagementContract.canManage(row(), alice))
        assertFalse(OrganizationManagementContract.canTransfer(row(), alice))
        val admin = row(mapOf("ownerId" to "other", "adminIds" to listOf(alice.uid)))
        assertFalse(OrganizationManagementContract.canManage(admin, alice))
        assertTrue(
            OrganizationManagementContract.canTransfer(row(), alice.copy(globalRole = "owner"))
        )
    }

    @Test
    fun unapprovedSystemAndNotReadyNeverBecomeWritable() {
        for (status in
            OrganizationContract.requestStatuses +
                listOf("archived", "retentionDeleting")) assertFalse(
            OrganizationManagementContract.canEdit(row(mapOf("moderationStatus" to status)), alice)
        )
        val system =
            row().let {
                it.copy(
                    id = "ukrainian-community",
                    fields = it.fields + ("id" to "ukrainian-community"),
                )
            }
        assertFalse(
            OrganizationManagementContract.canEdit(system, alice.copy(globalRole = "owner"))
        )
        assertFalse(OrganizationManagementContract.canManage(row(), alice.copy(ready = false)))
    }

    @Test
    fun callerSuppliedAuthorityFlagCannotForgeOwnership() {
        val unrelated =
            row(mapOf("ownerId" to "other")).copy(authority = OrganizationAuthority.PLATFORM_OWNER)
        assertFalse(OrganizationManagementContract.canManage(unrelated, alice))
    }

    @Test
    fun canonicalRolePrecedenceAndTeamDeduplicationMatchBackend() {
        val org =
            row(
                mapOf(
                    "adminIds" to listOf(alice.uid, target, target),
                    "moderatorIds" to listOf(target, "other"),
                )
            )
        assertEquals(
            OrganizationTeamRole.OWNER,
            OrganizationManagementContract.role(org, alice.uid),
        )
        assertEquals(OrganizationTeamRole.ADMIN, OrganizationManagementContract.role(org, target))
        assertEquals(
            listOf(alice.uid, target, "other"),
            OrganizationManagementContract.teamIds(org),
        )
    }

    @Test
    fun safeDocumentSegmentsAllowLegacyColonButRejectPathsWhitespaceAndOverflow() {
        assertTrue(OrganizationManagementContract.userId("legacy:member.1"))
        listOf("", "../u", "a/b", " a", "a b", "x\n", ".", "..", "x".repeat(129)).forEach {
            assertFalse(OrganizationManagementContract.userId(it))
        }
    }

    @Test
    fun exactRoleCallableNamesAndWireFieldsHaveNoInventedCASFields() {
        assertEquals("assignOrganizationAdmin", OrganizationManagementContract.callable(intent()))
        assertEquals(
            "assignOrganizationModerator",
            OrganizationManagementContract.callable(intent(OrganizationTeamAction.MODERATOR)),
        )
        assertEquals(
            "removeOrganizationAdmin",
            OrganizationManagementContract.callable(
                intent(OrganizationTeamAction.REMOVE, OrganizationTeamRole.ADMIN)
            ),
        )
        assertEquals(
            "removeOrganizationModerator",
            OrganizationManagementContract.callable(
                intent(OrganizationTeamAction.REMOVE, OrganizationTeamRole.MODERATOR)
            ),
        )
        assertEquals(
            "transferOrganizationOwnership",
            OrganizationManagementContract.callable(intent(OrganizationTeamAction.TRANSFER)),
        )
        assertEquals(
            setOf("organizationId", "targetUserId", "reason"),
            OrganizationManagementContract.payload(row(), intent()).keys,
        )
    }

    @Test
    fun ownerRemovalAndNonPlatformTransferFailBeforeTransport() {
        failWith(OrganizationManagementFailure.DENIED) {
            OrganizationManagementContract.requireIntent(
                row(),
                OrganizationRoleIntent(
                    alice.uid,
                    OrganizationTeamAction.REMOVE,
                    OrganizationTeamRole.OWNER,
                ),
                alice,
            )
        }
        failWith(OrganizationManagementFailure.DENIED) {
            OrganizationManagementContract.requireIntent(
                row(),
                intent(OrganizationTeamAction.TRANSFER),
                alice,
            )
        }
    }

    @Test
    fun allRoleMutationsAreExplicitlyNonIdempotentAndLocalOnly() {
        for (action in OrganizationTeamAction.entries) {
            val name = OrganizationManagementContract.callable(intent(action))
            assertTrue(
                LocalCallableProtocol.endpoint(name)
                    .startsWith("http://10.0.2.2:5008/demo-uac-android/")
            )
            assertEquals(
                LocalCallableFailure.UNCONFIRMED,
                LocalCallableProtocol.transportFailure(
                    name,
                    true,
                    LocalCallableFailure.UNAVAILABLE,
                ),
            )
        }
    }

    @Test
    fun roleResponseRequiresIdentityKnownEnumsAndValidTimestamp() {
        assertEquals(
            OrganizationTeamRole.MEMBER,
            OrganizationManagementContract.receipt(receipt(), row(), intent()).previousRole,
        )
        for (extra in
            listOf(
                mapOf("organizationId" to "foreign"),
                mapOf("targetUserId" to "foreign"),
                mapOf("newRole" to "owner"),
                mapOf("previousRole" to "unknown"),
                mapOf("previousRole" to "communityOwner"),
                mapOf("updatedAt" to "later"),
            )) failWith(OrganizationManagementFailure.UNCONFIRMED) {
            OrganizationManagementContract.receipt(receipt(extra = extra), row(), intent())
        }
    }

    @Test
    fun ownershipResponseAllowsNullPreviousOwnerButRejectsAbsentAndForeignTarget() {
        val action = intent(OrganizationTeamAction.TRANSFER)
        val response =
            mapOf(
                "organizationId" to basics.id,
                "previousOwnerId" to null,
                "newOwnerId" to target,
                "updatedAt" to now.toString(),
            )
        assertNull(OrganizationManagementContract.receipt(response, row(), action).previousOwnerId)
        failWith(OrganizationManagementFailure.UNCONFIRMED) {
            OrganizationManagementContract.receipt(response - "previousOwnerId", row(), action)
        }
        failWith(OrganizationManagementFailure.UNCONFIRMED) {
            OrganizationManagementContract.receipt(
                response + ("newOwnerId" to "other"),
                row(),
                action,
            )
        }
    }

    @Test
    fun exactRoleReadbackRejectsBothArraysDuplicatesAndTransferFallback() {
        val receipt = OrganizationRoleReceipt(OrganizationTeamRole.MEMBER, null, now)
        OrganizationManagementContract.verifyRole(
            row(mapOf("adminIds" to listOf(target))),
            intent(),
            receipt,
        )
        for (extra in
            listOf(
                mapOf("adminIds" to listOf(target, target)),
                mapOf("adminIds" to listOf(target), "moderatorIds" to listOf(target)),
            )) failWith(OrganizationManagementFailure.UNCONFIRMED) {
            OrganizationManagementContract.verifyRole(row(extra), intent(), receipt)
        }
        failWith(OrganizationManagementFailure.UNCONFIRMED) {
            OrganizationManagementContract.verifyRole(
                row(mapOf("ownerId" to target, "adminIds" to listOf(alice.uid))),
                intent(OrganizationTeamAction.TRANSFER),
                OrganizationRoleReceipt(null, alice.uid, now),
            )
        }
    }

    @Test
    fun publicProfileProjectionCannotLeakEmailGlobalRoleOrWrongIdentity() {
        val fields =
            mapOf(
                "id" to target,
                "displayName" to "  Public\nName ",
                "city" to "Wien",
                "email" to "private@example.invalid",
                "globalRole" to "owner",
            )
        assertEquals(
            OrganizationPublicMember(target, "PublicName", "Wien"),
            OrganizationManagementContract.profile(target, fields),
        )
        assertNull(
            OrganizationManagementContract.profile(target, fields + ("id" to "foreign")).displayName
        )
        assertNull(OrganizationManagementContract.profile(target, null).displayName)
    }

    @Test
    fun missingPublicProfileStillAllowsCanonicalRoleCleanupWithoutInventingIdentity() {
        val org = row(mapOf("adminIds" to listOf(target)))
        val members = OrganizationManagementContract.members(org, listOf(target), emptyList())
        assertEquals(2, members.size)
        assertEquals(OrganizationTeamRole.ADMIN, members.last().role)
        assertNull(members.last().profile.displayName)
    }

    @Test
    fun subscriberCursorUsesTimestampAndDocumentIdAndRejectsCrossOrganizationRows() {
        fun item(id: String, time: Instant = now, org: String = basics.id) =
            RawDocument(
                id,
                mapOf("userId" to target, "createdAt" to time, "subscribedOrganizationId" to org),
            )
        val page =
            OrganizationManagementContract.page(listOf(item("z"), item("a")), basics.id, null)
        assertEquals(2, page.items.size)
        assertNull(page.next)
        failWith(OrganizationManagementFailure.INVALID) {
            OrganizationManagementContract.page(listOf(item("a"), item("z")), basics.id, null)
        }
        failWith(OrganizationManagementFailure.INVALID) {
            OrganizationManagementContract.page(listOf(item("a", org = "other")), basics.id, null)
        }
        failWith(OrganizationManagementFailure.INVALID) {
            OrganizationManagementContract.page(
                listOf(item("a")),
                basics.id,
                OrganizationSubscriberCursor(now, "a"),
            )
        }
    }

    @Test
    fun subscriberPageIsBoundedAndUsesLastDisplayedNotLookaheadCursor() {
        val rows =
            (100 downTo 50).map {
                RawDocument(
                    "relation-$it",
                    mapOf(
                        "userId" to target,
                        "createdAt" to now.plusSeconds(it.toLong()),
                        "subscribedOrganizationId" to basics.id,
                    ),
                )
            }
        val page = OrganizationManagementContract.page(rows, basics.id, null)
        assertEquals(50, page.items.size)
        assertEquals("relation-51", page.next?.documentId)
        failWith(OrganizationManagementFailure.INVALID) {
            OrganizationManagementContract.page(rows + rows.last(), basics.id, null)
        }
    }

    @Test
    fun approvedInformationNeverEmitsRolesCountersStatusOrSubmissionFields() {
        val org = row()
        val draft = OrganizationManagementContract.draft(org)
        val fields = OrganizationManagementContract.informationFields(draft, org)
        assertTrue(fields.keys.all { it in OrganizationManagementContract.safeFields })
        assertTrue(
            (OrganizationContract.counterFields +
                    listOf(
                        "id",
                        "ownerId",
                        "adminIds",
                        "moderatorIds",
                        "moderationStatus",
                        "createdAt",
                        "submittedAt",
                        "reviewMessage",
                    ))
                .none { it in fields }
        )
    }

    @Test
    fun advancedDirectoryAndGermanFallbackPreserveOpaqueUneditedFields() {
        val org =
            row(
                mapOf(
                    "coverURL" to "https://example.invalid/cover",
                    "socialLinks" to mapOf("custom" to "https://example.invalid"),
                    "latitude" to 48.2,
                    "localizations" to mapOf("fr" to mapOf("name" to "French")),
                )
            )
        val draft =
            OrganizationManagementContract.draft(org)
                .copy(
                    category = "support",
                    foundedYear = "2020",
                    foundedMonth = "4",
                    languages = "Ukrainisch, Deutsch",
                    directory =
                        OrganizationDirectoryDraft(
                            services = "Advice\nEvents",
                            offerUntil = now.toString(),
                        ),
                    german = OrganizationDirectoryTranslation(mission = "Deutsche Mission"),
                )
        val fields = OrganizationManagementContract.informationFields(draft, org)
        assertEquals(2020L, fields["foundedYear"])
        assertEquals(4L, fields["foundedMonth"])
        assertFalse(fields.containsKey("coverURL"))
        assertFalse(fields.containsKey("socialLinks"))
        assertFalse(fields.containsKey("latitude"))
        val localized = fields["localizations"] as Map<*, *>
        assertEquals(mapOf("name" to "French"), localized["fr"])
        assertEquals(basics.name, (localized["de"] as Map<*, *>)["name"])
        assertEquals(now, (fields["directoryProfile"] as Map<*, *>)["currentOfferValidUntil"])
    }

    @Test
    fun invalidAdvancedFieldsCannotBeWritten() {
        val org = row()
        val draft = OrganizationManagementContract.draft(org)
        val invalid =
            listOf(
                draft.copy(foundedYear = "999"),
                draft.copy(foundedMonth = "2"),
                draft.copy(languages = (1..13).joinToString(",")),
                draft.copy(category = "owner"),
                draft.copy(links = mapOf("ownerId" to "forged")),
                draft.copy(links = mapOf("telegramURL" to "javascript:alert(1)")),
                draft.copy(
                    directory =
                        OrganizationDirectoryDraft(regularHours = mapOf("monday" to "25:00-26:00"))
                ),
                draft.copy(
                    directory =
                        OrganizationDirectoryDraft(regularHours = mapOf("unknown" to "closed"))
                ),
                draft.copy(
                    directory = OrganizationDirectoryDraft(services = (1..9).joinToString("\n"))
                ),
                draft.copy(directory = OrganizationDirectoryDraft(offerUntil = "tomorrow")),
            )
        invalid.forEach {
            failWith(OrganizationManagementFailure.INVALID) {
                OrganizationManagementContract.informationFields(it, org, 2026)
            }
        }
    }

    @Test
    fun offerTimestampNormalizesToServerMicrosecondsBeforeExactReadback() {
        val org = row()
        val draft =
            OrganizationManagementContract.draft(org)
                .copy(
                    directory =
                        OrganizationDirectoryDraft(offerUntil = now.plusNanos(789).toString())
                )
        val fields = OrganizationManagementContract.informationFields(draft, org)
        assertEquals(now, (fields["directoryProfile"] as Map<*, *>)["currentOfferValidUntil"])
        val decodedServer = row(org.fields + fields)
        assertEquals(fields["directoryProfile"], decodedServer.fields["directoryProfile"])
    }

    @Test
    fun guestNotReadyAndUnrelatedUsersCannotLoadManagement() = runTest {
        val source = FakeSource()
        failAsync(OrganizationManagementFailure.SIGN_IN) {
            OrganizationManagementRepository(source, { null }, gate).load(basics.id)
        }
        failAsync(OrganizationManagementFailure.NOT_READY) {
            OrganizationManagementRepository(source, { alice.copy(ready = false) }, gate)
                .load(basics.id)
        }
        failAsync(OrganizationManagementFailure.DENIED) {
            OrganizationManagementRepository(source, { alice.copy(uid = "other") }, gate)
                .load(basics.id)
        }
    }

    @Test
    fun ownerInfoSaveChecksActualFieldsAndPreservesCounters() = runTest {
        val source = FakeSource()
        val base = source.record!!
        val draft =
            OrganizationManagementContract.draft(base)
                .copy(basics = basics.copy(name = "Updated organization"))
        val result =
            OrganizationManagementRepository(source, { alice }, gate).save(base, draft, null)
        assertEquals("Updated organization", result.organization.name)
        assertEquals(7L, result.organization.fields["likeCount"])
        assertEquals(1, source.updates)
    }

    @Test
    fun revokedAuthorityAndStaleDraftStopBeforeInformationWrite() = runTest {
        val source = FakeSource()
        val base = source.record!!
        val repo = OrganizationManagementRepository(source, { alice }, gate)
        source.record = row(mapOf("ownerId" to "new-owner"))
        failAsync(OrganizationManagementFailure.DENIED) {
            repo.save(base, OrganizationManagementContract.draft(base), null)
        }
        source.record = row(mapOf("updatedAt" to now.plusSeconds(1)))
        failAsync(OrganizationManagementFailure.STALE) {
            repo.save(base, OrganizationManagementContract.draft(base), null)
        }
        assertEquals(0, source.updates)
    }

    @Test
    fun logoFailureDoesNotRollBackConfirmedInformation() = runTest {
        val source = FakeSource().apply { logoError = true }
        val base = source.record!!
        assertTrue(
            OrganizationManagementRepository(source, { alice }, gate)
                .save(base, OrganizationManagementContract.draft(base), byteArrayOf(1))
                .logoIncomplete
        )
        assertNotNull(source.record)
    }

    @Test
    fun roleAssignmentAndDemotionVerifyBothCanonicalArrays() = runTest {
        val source = FakeSource()
        val repo = OrganizationManagementRepository(source, { alice }, gate)
        val assigned = repo.apply(source.record!!, intent())
        val demoted =
            repo.apply(
                assigned,
                intent(OrganizationTeamAction.MODERATOR, OrganizationTeamRole.ADMIN),
            )
        assertEquals(
            OrganizationTeamRole.MODERATOR,
            OrganizationManagementContract.role(demoted, target),
        )
        assertEquals(emptyList<String>(), demoted.fields["adminIds"])
        assertEquals(2, source.roles)
    }

    @Test
    fun recoveredDesiredStateDoesNotAppendAnotherRoleReceipt() = runTest {
        val source = FakeSource()
        val repo = OrganizationManagementRepository(source, { alice }, gate)
        val base = source.record!!
        repo.apply(base, intent())
        repo.apply(base, intent())
        assertEquals(1, source.roles)
    }

    @Test
    fun staleTargetRoleNeverBlindlyExecutesOldConfirmation() = runTest {
        val source = FakeSource()
        val base = source.record!!
        source.record =
            row(mapOf("moderatorIds" to listOf(target), "updatedAt" to now.plusSeconds(1)))
        failAsync(OrganizationManagementFailure.STALE) {
            OrganizationManagementRepository(source, { alice }, gate).apply(base, intent())
        }
        assertEquals(0, source.roles)
    }

    @Test
    fun postCommitReadFailureIsUnconfirmedNotASafeRetrySignal() = runTest {
        val source = FakeSource().apply { offlineAfterRole = true }
        failAsync(OrganizationManagementFailure.UNCONFIRMED) {
            OrganizationManagementRepository(source, { alice }, gate)
                .apply(source.record!!, intent())
        }
        assertEquals(1, source.roles)
        assertEquals(
            OrganizationTeamRole.ADMIN,
            OrganizationManagementContract.role(source.record!!, target),
        )
    }

    @Test
    fun accountSwitchSuppressesInFlightRoleResult() = runTest {
        val source = FakeSource().apply { pending = CompletableDeferred() }
        var actor = alice
        val task = async {
            OrganizationManagementRepository(source, { actor }, gate)
                .apply(source.record!!, intent())
        }
        runCurrent()
        actor = alice.copy(uid = "other", revision = 2)
        source.pending!!.complete(Unit)
        try {
            task.await()
            fail("Stale result")
        } catch (_: CancellationException) {}
    }

    @Test
    fun viewModelRequiresExplicitConfirmationAndRejectsDoubleTap() = runTest {
        val source = FakeSource().apply { pending = CompletableDeferred() }
        val model = OrganizationManagementViewModel(source, { alice }, gate)
        model.show(basics.id)
        runCurrent()
        model.choose(target, OrganizationTeamAction.ADMIN)
        assertEquals(0, source.roles)
        assertNotNull(model.state.value.confirmation)
        model.confirm()
        model.confirm()
        runCurrent()
        assertEquals(1, source.roles)
        source.pending!!.complete(Unit)
        runCurrent()
        assertTrue(model.state.value.confirmed)
        model.hide()
    }

    @Test
    fun unconfirmedRoleBlocksRepeatUntilFreshReadAndExplicitNewDecision() = runTest {
        val source = FakeSource().apply { roleError = OrganizationManagementFailure.UNCONFIRMED }
        val model = OrganizationManagementViewModel(source, { alice }, gate)
        model.show(basics.id)
        runCurrent()
        model.choose(target, OrganizationTeamAction.ADMIN)
        model.confirm()
        runCurrent()
        assertNotNull(model.state.value.uncertain)
        assertEquals(1, source.roles)
        model.choose(target, OrganizationTeamAction.ADMIN)
        model.confirm()
        runCurrent()
        assertEquals(1, source.roles)
        model.acknowledgeUncertain()
        assertNull(model.state.value.uncertain)
        assertNull(model.state.value.confirmation)
        assertEquals(1, source.roles)
        model.hide()
    }

    @Test
    fun uncertainCommitRecoversThroughReadWithoutDuplicateSend() = runTest {
        val source = FakeSource().apply { offlineAfterRole = true }
        val model = OrganizationManagementViewModel(source, { alice }, gate)
        model.show(basics.id)
        runCurrent()
        model.choose(target, OrganizationTeamAction.ADMIN)
        model.confirm()
        runCurrent()
        assertNotNull(model.state.value.uncertain)
        assertFalse(model.state.value.fresh)
        source.readError = null
        model.refresh()
        runCurrent()
        assertNull(model.state.value.uncertain)
        assertNull(model.state.value.error)
        assertTrue(model.state.value.confirmed)
        assertEquals(1, source.roles)
        model.hide()
    }

    @Test
    fun sessionChangeClearsNamesDraftAndPendingConfirmationImmediately() = runTest {
        val actors = MutableStateFlow<OrganizationSession?>(alice)
        val source = FakeSource()
        val model = OrganizationManagementViewModel(source, { actors.value }, gate)
        model.observeSessions(actors)
        model.show(basics.id)
        runCurrent()
        model.edit()
        model.choose(target, OrganizationTeamAction.ADMIN)
        actors.value = null
        runCurrent()
        assertNull(model.state.value.snapshot)
        assertNull(model.state.value.draft)
        assertNull(model.state.value.confirmation)
        model.hide()
    }

    @Test
    fun serverRoleChangeMakesOpenInfoFormReadonlyWithoutLosingText() = runTest {
        val source = FakeSource()
        val model = OrganizationManagementViewModel(source, { alice }, gate)
        model.show(basics.id)
        runCurrent()
        model.edit()
        model.change { it.copy(mission = "Unsaved mission") }
        source.record = row(mapOf("updatedAt" to now.plusSeconds(2), "adminIds" to listOf(target)))
        source.events.emit(Result.success(Unit))
        runCurrent()
        assertEquals("Unsaved mission", model.state.value.draft?.mission)
        assertFalse(model.state.value.draftWritable)
        model.hide()
    }

    @Test
    fun watcherFailureDoesNotLeaveStaleManagementActionsEnabled() = runTest {
        val source = FakeSource()
        val model = OrganizationManagementViewModel(source, { alice }, gate)
        model.show(basics.id)
        runCurrent()
        source.events.emit(
            Result.failure(OrganizationManagementException(OrganizationManagementFailure.OFFLINE))
        )
        runCurrent()
        assertFalse(model.state.value.actionable)
        model.choose(target, OrganizationTeamAction.ADMIN)
        assertNull(model.state.value.confirmation)
        model.hide()
    }

    @Test
    fun actionErrorSurvivesSuccessfulReadbackRefresh() = runTest {
        val source =
            FakeSource().apply { roleError = OrganizationManagementFailure.TARGET_UNAVAILABLE }
        val model = OrganizationManagementViewModel(source, { alice }, gate)
        model.show(basics.id)
        runCurrent()
        model.choose(target, OrganizationTeamAction.ADMIN)
        model.confirm()
        runCurrent()
        assertEquals(OrganizationManagementFailure.TARGET_UNAVAILABLE, model.state.value.error)
        assertTrue(model.state.value.fresh)
        model.hide()
    }

    @Test
    fun pickerLeaseSurvivesOrdinaryPauseAndIsCancelledByAccountSwitch() = runTest {
        var cancelled = 0
        var finished = 0
        val actors = MutableStateFlow<OrganizationSession?>(alice)
        val authorization = ExternalImagePickerAuthorization { uid, revision ->
            assertEquals(alice.uid, uid)
            assertEquals(alice.revision, revision)
            object : ExternalImagePickerLease {
                override fun finish() {
                    finished++
                }

                override fun cancel() {
                    cancelled++
                }
            }
        }
        val model =
            OrganizationManagementViewModel(FakeSource(), { actors.value }, gate, authorization)
        model.observeSessions(actors)
        model.show(basics.id)
        runCurrent()
        model.edit()
        assertTrue(model.beginPicker())
        model.hide()
        assertEquals(0, cancelled)
        actors.value = null
        runCurrent()
        assertEquals(1, cancelled)
        assertEquals(0, finished)
    }

    @Test
    fun roleFailureClassificationDoesNotConfuseTargetStateWithLegalVersion() {
        assertEquals(
            OrganizationManagementFailure.TARGET_UNAVAILABLE,
            organizationManagementFailure(
                LocalCallableException(LocalCallableFailure.FAILED_PRECONDITION)
            ),
        )
        assertEquals(
            OrganizationManagementFailure.UNCONFIRMED,
            organizationManagementFailure(LocalCallableException(LocalCallableFailure.UNCONFIRMED)),
        )
    }
}
