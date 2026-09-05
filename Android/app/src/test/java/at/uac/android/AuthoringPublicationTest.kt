package at.uac.android

import at.uac.android.feature.authoring.*
import at.uac.android.feature.authoring.recovery.*
import at.uac.android.feature.browse.*
import at.uac.android.feature.organization.*
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class AuthoringPublicationTest {
    private val now = Instant.parse("2026-09-03T06:00:00Z")
    private val actor = OrganizationSession("scheduled-author", 1, true, "Author", "user")
    private val org
        get() =
            OrganizationDraft(
                    "scheduled-org",
                    "Scheduled organization",
                    "A complete synthetic organization",
                    region = "wien",
                    city = "Wien",
                )
                .let {
                    OrganizationContract.record(
                        RawDocument(
                            it.id,
                            OrganizationContract.create(it, actor, now) +
                                mapOf("moderationStatus" to "approved", "ownerId" to actor.uid),
                        ),
                        actor,
                    )
                }

    private val scope
        get() = AuthoringRecoveryScope(actor.uid, org.id, ContentKind.NEWS)

    private fun draft(kind: ContentKind = ContentKind.NEWS) =
        AuthoringContract.newDraft(kind, org, now)
            .copy(
                title = "Scheduled title",
                summary = "Summary",
                body = "Body",
                publicationMode = AuthoringPublicationMode.SCHEDULED,
                scheduledAt = now.plusSeconds(3_600),
            )
            .let {
                if (kind == ContentKind.EVENTS)
                    it.copy(event = it.event.copy(venue = "Synthetic venue"))
                else it
            }

    private fun intent(d: AuthoringDraft = draft(), base: AuthoringItem? = null) =
        AuthoringContract.submission(d, org, actor, base, now, ZoneId.of("Europe/Vienna"))

    private fun item(value: AuthoringSubmission) =
        AuthoringContract.item(
            value.kind,
            RawDocument(value.id, value.fields.filterValues { it != null }),
            org.id,
            AuthoringStatus.entries.first { it.wire == value.fields["moderationStatus"] },
            actor,
        )

    private suspend fun invalid(block: suspend () -> Unit) {
        try {
            block()
            fail("Expected invalid schedule")
        } catch (error: AuthoringException) {
            assertEquals(AuthoringFailure.INVALID, error.failure)
            assertEquals("schedule", error.field)
        }
    }

    private suspend fun invalidRecovery(block: suspend () -> Unit) {
        try {
            block()
            fail("Expected invalid recovery record")
        } catch (error: AuthoringRecoveryException) {
            assertEquals(AuthoringRecoveryFailure.INVALID, error.reason)
        }
    }

    private val gate =
        object : OrganizationMutationGate {
            override suspend fun <T> withSession(
                session: OrganizationSession,
                operation: suspend () -> T,
            ): T = operation()
        }

    private inner class Source : AuthoringSource {
        var actual: AuthoringItem? = null
        var writes = 0

        override suspend fun organization(id: String, session: OrganizationSession) = org

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
        ) = actual

        override fun changes(
            organizationId: String,
            kind: ContentKind,
            status: AuthoringStatus,
            session: OrganizationSession,
            target: AuthoringItem?,
        ) = emptyFlow<Result<Unit>>()

        override suspend fun commit(
            submission: AuthoringSubmission,
            organization: OrganizationRecord,
            session: OrganizationSession,
        ) {
            writes++
            actual = item(submission)
        }
    }

    @Test
    fun exactFiveMinutesIsAcceptedAndOneNanosecondLessIsRejected() {
        assertTrue(AuthoringPublication.hasEnoughLeadTime(now.plusSeconds(300), now))
        assertFalse(AuthoringPublication.hasEnoughLeadTime(now.plusSeconds(300).minusNanos(1), now))
    }

    @Test
    fun missingPastAndCurrentTimesCannotBeScheduled() {
        for (time in listOf(null, now.minusSeconds(1), now, now.plusSeconds(299))) assertFalse(
            AuthoringPublication.hasEnoughLeadTime(time, now)
        )
    }

    @Test
    fun newFormsDefaultToNowWithoutServerSchedule() {
        val d = AuthoringContract.newDraft(ContentKind.NEWS, org, now)
        assertEquals(AuthoringPublicationMode.NOW, d.publicationMode)
        assertNull(d.scheduledAt)
        assertEquals(now.plusSeconds(3_600), AuthoringPublication.initialTime(now))
    }

    @Test
    fun newsScheduleKeepsCanonicalDraftTimestampAndInitialPublishedAt() {
        val value = intent()
        assertEquals("draft", value.fields["moderationStatus"])
        assertEquals(now.plusSeconds(3_600), value.fields["scheduledAt"])
        assertEquals(now, value.fields["publishedAt"])
        assertEquals(0L, value.fields["likeCount"])
        assertEquals("notLiked", value.fields["likeState"])
        assertFalse(item(value).editable)
    }

    @Test
    fun eventScheduleDoesNotRetargetOccurrenceDatesOrCounters() {
        val d = draft(ContentKind.EVENTS)
        val value = intent(d)
        assertEquals("draft", value.fields["moderationStatus"])
        assertEquals(d.event.occurrences.first().start, value.fields["startDate"])
        assertEquals(0L, value.fields["registeredCount"])
        assertEquals("notRegistered", value.fields["registrationState"])
    }

    @Test
    fun nationwideScheduleIsDraftButNowStillNeedsReview() {
        val scheduled = draft().copy(regionScope = "austria")
        assertEquals("draft", intent(scheduled).fields["moderationStatus"])
        val immediate = intent(scheduled.copy(publicationMode = AuthoringPublicationMode.NOW))
        assertEquals("pendingReview", immediate.fields["moderationStatus"])
        assertFalse("scheduledAt" in immediate.fields)
    }

    @Test
    fun nowModeKeepsChosenTimeLocallyButOmitsItOnWire() {
        val value = intent(draft().copy(publicationMode = AuthoringPublicationMode.NOW))
        assertEquals("approved", value.fields["moderationStatus"])
        assertFalse("scheduledAt" in value.fields)
    }

    @Test
    fun ordinaryEditCannotInjectAnyTimingModeOrDate() = runTest {
        val immediate =
            draft().copy(publicationMode = AuthoringPublicationMode.NOW, scheduledAt = null)
        val base = item(intent(immediate))
        invalid {
            intent(
                immediate.copy(
                    publicationMode = AuthoringPublicationMode.SCHEDULED,
                    scheduledAt = now.plusSeconds(3_600),
                ),
                base,
            )
        }
        invalid { intent(immediate.copy(scheduledAt = now.plusSeconds(3_600)), base) }
        assertFalse("scheduledAt" in intent(immediate, base).fields)
    }

    @Test
    fun missingAndTooCloseScheduleFailsBeforeIntentCreation() = runTest {
        for (time in listOf(null, now, now.plusSeconds(299))) invalid {
            intent(draft().copy(scheduledAt = time))
        }
    }

    @Test
    fun canonicalScheduleUsesFirestoreMicrosecondPrecision() {
        val d = draft().copy(scheduledAt = now.plusSeconds(3_600).plusNanos(123_456_789))
        assertEquals(now.plusSeconds(3_600).plusNanos(123_456_000), intent(d).fields["scheduledAt"])
    }

    @Test
    fun viennaDaylightSavingGapIsRejectedInsteadOfShifted() {
        assertNull(
            AuthoringCalendar.resolve(
                LocalDate.of(2026, 3, 29),
                LocalTime.of(2, 30),
                ZoneId.of("Europe/Vienna"),
                now,
            )
        )
    }

    @Test
    fun viennaOverlapPreservesPreviousOffsetAndExactInstant() {
        val zone = ZoneId.of("Europe/Vienna")
        val previous = Instant.parse("2026-10-25T01:30:00Z")
        assertEquals(
            previous,
            AuthoringCalendar.resolve(
                LocalDate.of(2026, 10, 25),
                LocalTime.of(2, 30),
                zone,
                previous,
            ),
        )
    }

    @Test
    fun losAngelesDateSelectionDoesNotUseUtcCalendarDay() {
        val resolved =
            AuthoringCalendar.resolve(
                LocalDate.of(2026, 9, 4),
                LocalTime.of(0, 15),
                ZoneId.of("America/Los_Angeles"),
                now,
            )
        assertEquals(Instant.parse("2026-09-04T07:15:00Z"), resolved)
    }

    @Test
    fun storedDraftV2PreservesModeInstantAndOriginalZone() {
        val value = RecoveryDraft(draft(), "America/Los_Angeles")
        val encoded = AuthoringRecoveryCodec.draft(scope, value)
        assertEquals(2, encoded[4].toInt())
        assertEquals(value, AuthoringRecoveryCodec.readDraft(scope, encoded))
    }

    @Test
    fun legacyDraftV1ReadsWithoutInventingScheduleOrChangingText() {
        val value = draft().copy(publicationMode = AuthoringPublicationMode.NOW, scheduledAt = null)
        val encoded = AuthoringRecoveryCodec.draft(scope, RecoveryDraft(value, "Europe/Vienna"))
        val root = map(AuthoringRecoveryCodec.decode(encoded)).toMutableMap()
        root["draft"] = map(root["draft"]) - setOf("publicationMode", "scheduledAt")
        val legacy = AuthoringRecoveryCodec.encode(root, 1)
        assertEquals(
            RecoveryDraft(value, "Europe/Vienna"),
            AuthoringRecoveryCodec.readDraft(scope, legacy),
        )
    }

    @Test
    fun v1CannotSmuggleV2TimingFieldsAndV2RequiresThem() = runTest {
        val root =
            map(
                AuthoringRecoveryCodec.decode(
                    AuthoringRecoveryCodec.draft(scope, RecoveryDraft(draft(), "Europe/Vienna"))
                )
            )
        invalidRecovery {
            AuthoringRecoveryCodec.readDraft(scope, AuthoringRecoveryCodec.encode(root, 1))
        }
        val missing = root + ("draft" to (map(root["draft"]) - "scheduledAt"))
        invalidRecovery {
            AuthoringRecoveryCodec.readDraft(scope, AuthoringRecoveryCodec.encode(missing, 2))
        }
    }

    @Test
    fun unknownModeInvalidTimestampAndUnknownSchemaFailClosed() = runTest {
        val encoded = AuthoringRecoveryCodec.draft(scope, RecoveryDraft(draft(), "Europe/Vienna"))
        val root = map(AuthoringRecoveryCodec.decode(encoded))
        for ((key, value) in
            listOf("publicationMode" to "AUTO", "scheduledAt" to "tomorrow")) invalidRecovery {
            AuthoringRecoveryCodec.readDraft(
                scope,
                AuthoringRecoveryCodec.encode(
                    root + ("draft" to (map(root["draft"]) + (key to value))),
                    2,
                ),
            )
        }
        invalidRecovery {
            AuthoringRecoveryCodec.readDraft(scope, encoded.copyOf().also { it[4] = 3 })
        }
    }

    @Test
    fun pendingTypedEnvelopeStaysV1AndTimeDoesNotChangeOnRead() {
        val value = intent()
        val bytes = AuthoringRecoveryCodec.pending(scope, value)
        assertEquals(1, bytes[4].toInt())
        assertEquals(value, AuthoringRecoveryCodec.readPending(scope, bytes))
    }

    @Test
    fun legacyNowPendingRemainsReadableAndUnchanged() {
        val value = intent(draft().copy(publicationMode = AuthoringPublicationMode.NOW))
        assertEquals(
            value,
            AuthoringRecoveryCodec.readPending(scope, AuthoringRecoveryCodec.pending(scope, value)),
        )
    }

    @Test
    fun invalidScheduleShapesCannotEnterPendingJournal() = runTest {
        val value = intent()
        for (fields in
            listOf(
                value.fields - "scheduledAt",
                value.fields + ("scheduledAt" to "tomorrow"),
                value.fields + ("moderationStatus" to "approved"),
            )) invalidRecovery {
            AuthoringRecoveryCodec.pending(scope, value.copy(fields = fields))
        }
    }

    @Test
    fun expiredPendingStillLoadsAndLogoutCannotDeleteIt() = runTest {
        val value = intent()
        val store = MemoryAuthoringRecoveryStore()
        store.prepareCreation(scope, value)
        store.clearUnsentForAccount(actor.uid)
        assertEquals(value, store.load(scope)?.pending)
        assertFalse(AuthoringPublication.canSend(value, now.plusSeconds(3_601)))
    }

    @Test
    fun explicitRetryCannotChangeSameIdTimeOrAllocateAnotherId() = runTest {
        val value = intent()
        val store = MemoryAuthoringRecoveryStore()
        store.prepareCreation(scope, value)
        for (changed in
            listOf(
                value.copy(fields = value.fields + ("scheduledAt" to now.plusSeconds(7_200))),
                intent(),
            )) {
            try {
                store.prepareCreation(scope, changed)
                fail("Pending must dominate")
            } catch (error: AuthoringRecoveryException) {
                assertEquals(AuthoringRecoveryFailure.PENDING_CONFLICT, error.reason)
            }
        }
        assertEquals(value, store.load(scope)?.pending)
    }

    @Test
    fun freshScheduleWritesExactlyOneIntentAndClearsConfirmedJournal() = runTest {
        val source = Source()
        val store = MemoryAuthoringRecoveryStore()
        val value = intent()
        assertEquals(
            value.id,
            AuthoringRepository(source, { actor }, gate, store, { now }).submit(value).id,
        )
        assertEquals(1, source.writes)
        assertNull(store.load(scope))
    }

    @Test
    fun expiredAbsentPendingNeverWritesOrClearsAndBlocksNewScopeIntent() = runTest {
        val source = Source()
        val store = MemoryAuthoringRecoveryStore()
        val value = intent()
        store.prepareCreation(scope, value)
        invalid {
            AuthoringRepository(source, { actor }, gate, store, { now.plusSeconds(3_601) })
                .submit(value)
        }
        assertEquals(0, source.writes)
        assertEquals(value, store.load(scope)?.pending)
    }

    @Test
    fun expiredButExactExistingReceiptCanStillReconcileWithoutWrite() = runTest {
        val source = Source()
        val store = MemoryAuthoringRecoveryStore()
        val value = intent()
        store.prepareCreation(scope, value)
        source.actual = item(value)
        assertEquals(
            value.id,
            AuthoringRepository(source, { actor }, gate, store, { now.plusSeconds(3_601) })
                .submit(value)
                .id,
        )
        assertEquals(0, source.writes)
        assertNull(store.load(scope))
    }

    @Test
    fun timePassingDuringDurableSaveKeepsJournalButPreventsSdkCall() = runTest {
        val memory = MemoryAuthoringRecoveryStore()
        var clock = now
        val store =
            object : AuthoringRecoveryStore by memory {
                override suspend fun prepareCreation(
                    scope: AuthoringRecoveryScope,
                    intent: AuthoringSubmission,
                ): AuthoringSubmission =
                    memory.prepareCreation(scope, intent).also { clock = now.plusSeconds(3_601) }
            }
        val source = Source()
        val value = intent()
        invalid { AuthoringRepository(source, { actor }, gate, store, { clock }).submit(value) }
        assertEquals(0, source.writes)
        assertEquals(value, memory.load(scope)?.pending)
    }

    @Test
    fun schedulerTransformedRecordRemainsConflictNotAFalseExactReceipt() = runTest {
        val value = intent()
        val source = Source()
        val store = MemoryAuthoringRecoveryStore()
        store.prepareCreation(scope, value)
        source.actual =
            item(value)
                .copy(
                    status = AuthoringStatus.APPROVED,
                    fields =
                        value.fields - "scheduledAt" +
                            mapOf(
                                "moderationStatus" to "approved",
                                "publishedAt" to now.plusSeconds(3_600),
                            ),
                )
        val recovered =
            AuthoringRepository(source, { actor }, gate, store, { now.plusSeconds(3_601) })
                .recover(value)
        assertNotNull(recovered)
        assertFalse(AuthoringContract.matches(value, requireNotNull(recovered)))
        assertEquals(0, source.writes)
        assertEquals(value, store.load(scope)?.pending)
    }

    private fun map(value: Any?): Map<String, Any?> =
        (value as Map<*, *>).entries.associate { (key, v) -> key as String to v }
}
