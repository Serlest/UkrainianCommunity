package at.uac.android

import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.moderation.*
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ModerationTest {
    private val actor = ModerationSession("synthetic-reviewer", 1, "admin", true)
    private var live: ModerationSession? = actor
    private val now = Instant.parse("2026-09-03T10:00:00Z")

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun teardown() {
        Dispatchers.resetMain()
    }

    private fun target(kind: ModerationKind = ModerationKind.NEWS, id: String = "synthetic-item") =
        ModerationTarget(kind, id)

    private fun row(target: ModerationTarget = target(), extra: Fields = emptyMap()) =
        RawDocument(
            target.id,
            mapOf(
                "id" to target.id,
                "sourceType" to "organization",
                "organizationId" to "synthetic-org",
                "moderationStatus" to "pendingReview",
                "createdAt" to now,
                "updatedAt" to now,
                "title" to "Private title",
                "name" to "Private organization",
                "subtitle" to "Summary",
                "summary" to "Summary",
                "description" to "Description",
                "body" to "Full private body",
                "details" to "Full event details",
                "fullDescription" to "Full organization details",
                "submittedByDisplayName" to "Private submitter",
            ) + extra,
        )

    private class Fake : ModerationSource {
        val rows = mutableMapOf<ModerationKind, List<RawDocument>>()
        val previews = mutableMapOf<ModerationTarget, RawDocument>()
        val changes = MutableSharedFlow<Unit>(extraBufferCapacity = 10)
        var reads = 0
        var previewReads = 0
        var delay: CompletableDeferred<Unit>? = null
        var previewDelay: CompletableDeferred<Unit>? = null
        var afterRead: (() -> Unit)? = null
        var afterPreview: (() -> Unit)? = null
        val failures = mutableMapOf<ModerationKind, ModerationFailure>()

        override suspend fun head(
            session: ModerationSession,
            kind: ModerationKind,
        ): List<RawDocument> {
            reads++
            delay?.let { withContext(NonCancellable) { it.await() } }
            afterRead?.invoke()
            failures[kind]?.let { throw ModerationException(it) }
            return rows[kind].orEmpty()
        }

        override suspend fun preview(
            session: ModerationSession,
            target: ModerationTarget,
        ): RawDocument? {
            previewReads++
            previewDelay?.let { withContext(NonCancellable) { it.await() } }
            afterPreview?.invoke()
            return previews[target]
        }

        override fun changes(
            session: ModerationSession,
            kind: ModerationKind,
            selected: ModerationTarget?,
        ) = changes.asSharedFlow()
    }

    private fun repository(fake: Fake) = ModerationRepository(fake, { live })

    private fun model(fake: Fake, scope: CoroutineScope) =
        ModerationViewModel(fake, { live }, scope)

    private suspend fun fails(expected: ModerationFailure, operation: suspend () -> Any?) {
        try {
            operation()
            fail("Expected $expected")
        } catch (error: ModerationException) {
            assertEquals(expected, error.failure)
        }
    }

    @Test
    fun roleAndReadyBothRequired() = runTest {
        for (role in listOf("user", "topAdmin", "moderator", "communityOwner", "")) {
            live = actor.copy(role = role)
            val fake = Fake()
            fails(ModerationFailure.DENIED) { repository(fake).head(ModerationKind.NEWS) }
            assertEquals(0, fake.reads)
        }
        live = actor.copy(ready = false)
        fails(ModerationFailure.NOT_READY) { repository(Fake()).head(ModerationKind.NEWS) }
        live = null
        fails(ModerationFailure.SIGN_IN) { repository(Fake()).head(ModerationKind.NEWS) }
    }

    @Test
    fun sessionProjectionRequiresActivatedAndRealTotpAndLegalGate() {
        val profile =
            AuthProfile(
                uid = actor.uid,
                email = "synthetic@example.invalid",
                displayName = "Private",
                globalRole = "admin",
                requiresMultiFactorAuth = true,
            )
        val session =
            AuthSession(
                AuthStage.AUTHENTICATED,
                AuthIdentity(actor.uid, "synthetic@example.invalid", true, false),
                profile,
                gate = AuthGate.READY,
                totpAuthenticated = true,
            )
        assertTrue(session.moderationScope()!!.allowed)
        assertFalse(session.copy(totpAuthenticated = false).moderationScope()!!.allowed)
        assertFalse(
            session
                .copy(profile = profile.copy(requiresMultiFactorAuth = false))
                .moderationScope()!!
                .allowed
        )
        assertFalse(session.copy(gate = AuthGate.LEGAL_REQUIRED).moderationScope()!!.allowed)
        assertFalse(
            session
                .copy(profile = profile.copy(blockState = "deactivated"))
                .moderationScope()!!
                .allowed
        )
        assertFalse(session.copy(busy = true).moderationScope()!!.allowed)
    }

    @Test
    fun ordinaryReadyAccountIsDeniedByRoleNotAskedToCompletePrivilegedTotp() = runTest {
        val uid = "synthetic-ordinary"
        val session =
            AuthSession(
                AuthStage.AUTHENTICATED,
                AuthIdentity(uid, "synthetic@example.invalid", true),
                AuthProfile(uid, "synthetic@example.invalid", "Synthetic", globalRole = "user"),
                gate = AuthGate.READY,
            )
        val projected = session.moderationScope()!!
        assertTrue(projected.ready)
        assertFalse(projected.allowed)
        live = projected
        val fake = Fake()
        fails(ModerationFailure.DENIED) { repository(fake).head(ModerationKind.NEWS) }
        assertEquals(0, fake.reads)
    }

    @Test
    fun delayedOldPresentationDisposeCannotHideNewSameScopeHost() = runTest {
        val fake = Fake().apply { rows[ModerationKind.NEWS] = listOf(row()) }
        val vm = model(fake, backgroundScope)
        val first = vm.present(ModerationSection.CONTENT)
        runCurrent()
        val second = vm.present(ModerationSection.CONTENT)
        runCurrent()
        assertFalse(vm.owns(first))
        assertTrue(vm.owns(second))
        vm.dismiss(first)
        runCurrent()
        assertTrue(vm.state.value.visible)
        assertEquals(1, ModerationContract.visible(vm.state.value, "de").size)
        vm.dismiss(second)
        assertFalse(vm.state.value.visible)
    }

    @Test
    fun presentationDismissalIsOneUseAndCannotDismissLaterRoute() = runTest {
        val vm = model(Fake(), backgroundScope)
        val first = vm.present(ModerationSection.CONTENT)
        runCurrent()
        vm.dismiss(first)
        assertFalse(vm.owns(first))
        val next = vm.present(ModerationSection.ORGANIZATION_REQUESTS)
        runCurrent()
        vm.dismiss(first)
        assertTrue(vm.owns(next))
        assertEquals(ModerationSection.ORGANIZATION_REQUESTS, vm.state.value.section)
        vm.dismiss(next)
        vm.dismiss(next)
        assertFalse(vm.state.value.visible)
    }

    @Test
    fun presentationDoesNotSurviveAccountScopeChange() = runTest {
        val vm = model(Fake(), backgroundScope)
        val old = vm.present(ModerationSection.CONTENT)
        runCurrent()
        live = actor.copy(uid = "synthetic-next", revision = 2)
        vm.bind(live)
        runCurrent()
        assertFalse(vm.owns(old))
        val next = vm.present(ModerationSection.CONTENT)
        runCurrent()
        vm.dismiss(old)
        assertTrue(vm.owns(next))
        vm.dismiss(next)
    }

    @Test
    fun presentingMalformedRequestedRouteDoesNotIntroduceRefreshQuery() = runTest {
        val fake = Fake()
        val vm = model(fake, backgroundScope)
        val token = vm.present(ModerationSection.ORGANIZATION_REQUESTS, "../other")
        runCurrent()
        assertEquals(0, fake.reads)
        assertEquals(0, fake.previewReads)
        assertEquals(ModerationFailure.INVALID, vm.state.value.previewError)
        vm.dismiss(token)
    }

    @Test
    fun rawHundredCutoffPrecedesOrganizationFilter() {
        val rows =
            (0 until 100).map { index ->
                row(
                    target(id = "item-$index"),
                    mapOf("sourceType" to if (index == 99) "organization" else "app"),
                )
            }
        val head = ModerationContract.head(ModerationKind.NEWS, rows)
        assertEquals(100, head.rawCount)
        assertEquals(1, head.items.size)
        assertTrue(head.capped)
    }

    @Test
    fun emptyOrganizationIdsAreFilteredLikeIos() {
        assertTrue(
            ModerationContract.head(
                    ModerationKind.EVENT,
                    listOf(row(extra = mapOf("organizationId" to "  "))),
                )
                .items
                .isEmpty()
        )
    }

    @Test
    fun oversizedDuplicateUnorderedAndWrongStatusHeadsFailClosed() = runTest {
        val r = row()
        for (rows in
            listOf(
                List(101) { row(target(id = "row-$it")) },
                listOf(r, r),
                listOf(r, row(target(id = "new"), mapOf("createdAt" to now.plusSeconds(1)))),
                listOf(row(extra = mapOf("moderationStatus" to "approved"))),
            )) fails(ModerationFailure.INVALID) {
            ModerationContract.head(ModerationKind.NEWS, rows)
        }
    }

    @Test
    fun malformedIdentityTimestampAndUnknownStatusAreNotGuessed() = runTest {
        for (fields in
            listOf(
                mapOf("id" to "other"),
                mapOf("createdAt" to "today"),
                mapOf("updatedAt" to null),
                mapOf("moderationStatus" to "mystery"),
                mapOf("title" to true),
            )) fails(ModerationFailure.INVALID) {
            ModerationContract.preview(target(), row(extra = fields))
        }
    }

    @Test
    fun previewKeepsFullPrivateBodyAndBothLanguages() {
        val preview =
            ModerationContract.preview(
                target(),
                row(
                    extra =
                        mapOf(
                            "body" to "long ".repeat(500),
                            "localizations" to
                                mapOf(
                                    "de" to
                                        mapOf(
                                            "title" to "Deutscher Titel",
                                            "body" to "Deutscher Text",
                                        ),
                                    "uk" to mapOf("body" to "Український текст"),
                                ),
                        )
                ),
            )
        assertEquals(2499, preview.body.base.length)
        assertEquals("Deutscher Text", preview.body.value("de"))
        assertEquals("Український текст", preview.body.value("uk"))
    }

    @Test
    fun organizationPreviewIncludesApplicantReviewContactAndDirectory() {
        val t = target(ModerationKind.ORGANIZATION)
        val p =
            ModerationContract.preview(
                t,
                row(
                    t,
                    mapOf(
                        "submittedByUserId" to "synthetic-applicant",
                        "reviewMessage" to "Required changes",
                        "email" to "synthetic@example.invalid",
                        "directoryProfile" to
                            mapOf(
                                "services" to listOf("Service one", "Service two"),
                                "regularHours" to mapOf("monday" to "closed"),
                            ),
                        "localizations" to
                            mapOf("de" to mapOf("services" to listOf("Leistung eins"))),
                    ),
                ),
            )
        assertEquals("Required changes", p.fields.first { it.key == "reviewMessage" }.text.base)
        assertEquals("Leistung eins", p.fields.first { it.key == "services" }.text.de)
        assertTrue(p.fields.any { it.key == "submittedByUserId" })
        assertTrue(p.fields.any { it.key == "hours.monday" })
    }

    @Test
    fun approvedRequestedOrganizationIsReadOnlyAndUnsupportedStatusIsInvalid() = runTest {
        val t = target(ModerationKind.ORGANIZATION)
        assertEquals(
            "approved",
            ModerationContract.preview(t, row(t, mapOf("moderationStatus" to "approved")))
                .item
                .status,
        )
        fails(ModerationFailure.INVALID) {
            ModerationContract.preview(t, row(t, mapOf("moderationStatus" to "unknown")))
        }
    }

    @Test
    fun eventPreviewKeepsEveryOccurrenceAndCancellation() {
        val t = target(ModerationKind.EVENT)
        val p =
            ModerationContract.preview(
                t,
                row(
                    t,
                    mapOf(
                        "cancellationReason" to "Synthetic cancellation",
                        "occurrences" to
                            listOf(
                                mapOf(
                                    "startDate" to now,
                                    "endDate" to now.plusSeconds(3600),
                                    "status" to "scheduled",
                                ),
                                mapOf(
                                    "startDate" to now.plusSeconds(86400),
                                    "endDate" to now.plusSeconds(90000),
                                    "status" to "cancelled",
                                ),
                            ),
                    ),
                ),
            )
        assertEquals(2, p.fields.count { it.key.startsWith("occurrence.") })
        assertTrue(p.fields.any { it.key == "cancellationReason" })
    }

    @Test
    fun excessiveTextAndControlCharactersFailWithoutTruncatingReview() = runTest {
        for (value in listOf("x".repeat(50_001), "private\u0000text")) fails(
            ModerationFailure.INVALID
        ) {
            ModerationContract.preview(target(), row(extra = mapOf("body" to value)))
        }
    }

    @Test
    fun targetTraversalFailsBeforeSourceRead() = runTest {
        val fake = Fake()
        for (id in listOf("../users", "", "a/b", "x".repeat(129))) fails(
            ModerationFailure.INVALID
        ) {
            repository(fake).preview(target(id = id))
        }
        assertEquals(0, fake.previewReads)
    }

    @Test
    fun accountSwitchDuringHeadReadSuppressesResult() = runTest {
        val fake = Fake().apply { afterRead = { live = actor.copy(uid = "new-account") } }
        try {
            repository(fake).head(ModerationKind.NEWS)
            fail("Expected cancellation")
        } catch (_: CancellationException) {}
    }

    @Test
    fun sameUidRoleOrRevisionChangeDuringPreviewSuppressesResult() = runTest {
        for (next in
            listOf(
                actor.copy(revision = 2),
                actor.copy(role = "user"),
                actor.copy(ready = false),
            )) {
            live = actor
            val fake =
                Fake().apply {
                    previews[target()] = row()
                    afterPreview = { live = next }
                }
            try {
                repository(fake).preview(target())
                fail("Expected cancellation")
            } catch (_: CancellationException) {}
        }
    }

    @Test
    fun delayedHostBindCannotExposeOldRowsThroughSnapshot() = runTest {
        val fake = Fake().apply { rows[ModerationKind.NEWS] = listOf(row()) }
        val vm = model(fake, backgroundScope)
        vm.show(ModerationSection.CONTENT)
        runCurrent()
        assertEquals(1, ModerationContract.visible(vm.state.value, "de").size)
        live = actor.copy(revision = 2)
        assertTrue(vm.snapshot(actor, ModerationSection.CONTENT).parts.isEmpty())
        assertFalse(vm.isCurrent(actor, ModerationSection.CONTENT))
        vm.hide()
    }

    @Test
    fun perSectionFailureDoesNotInventEmptySuccessOrEraseFreshOtherSection() = runTest {
        val fake =
            Fake().apply {
                rows[ModerationKind.NEWS] = listOf(row())
                failures[ModerationKind.EVENT] = ModerationFailure.INDEX
            }
        val vm = model(fake, backgroundScope)
        vm.show(ModerationSection.CONTENT)
        runCurrent()
        assertEquals(1, vm.state.value.parts[ModerationKind.NEWS]!!.head!!.items.size)
        assertNull(vm.state.value.parts[ModerationKind.EVENT]!!.head)
        assertEquals(ModerationFailure.INDEX, vm.state.value.parts[ModerationKind.EVENT]!!.error)
        vm.hide()
    }

    @Test
    fun refreshFailureRemovesOldPrivateData() = runTest {
        val fake = Fake().apply { rows[ModerationKind.NEWS] = listOf(row()) }
        val vm = model(fake, backgroundScope)
        vm.show(ModerationSection.CONTENT)
        runCurrent()
        fake.failures[ModerationKind.NEWS] = ModerationFailure.OFFLINE
        vm.refresh(ModerationKind.NEWS)
        runCurrent()
        assertNull(vm.state.value.parts[ModerationKind.NEWS]!!.head)
        vm.hide()
    }

    @Test
    fun hideClearsRowsSearchAndSelectedPreviewAndStopsListeners() = runTest {
        val fake =
            Fake().apply {
                rows[ModerationKind.NEWS] = listOf(row())
                previews[target()] = row()
            }
        val vm = model(fake, backgroundScope)
        vm.show(ModerationSection.CONTENT)
        runCurrent()
        vm.select(target())
        runCurrent()
        vm.search("Private")
        vm.hide()
        runCurrent()
        fake.changes.emit(Unit)
        runCurrent()
        assertTrue(vm.state.value.parts.isEmpty())
        assertNull(vm.state.value.preview)
        assertEquals("", vm.state.value.search)
        assertFalse(vm.state.value.visible)
    }

    @Test
    fun nonCancellableOldReadCannotPublishAfterNewScope() = runTest {
        val release = CompletableDeferred<Unit>()
        val fake =
            Fake().apply {
                delay = release
                rows[ModerationKind.NEWS] = listOf(row())
            }
        val vm = model(fake, backgroundScope)
        vm.show(ModerationSection.CONTENT)
        runCurrent()
        live = null
        vm.bind(null)
        release.complete(Unit)
        runCurrent()
        assertNull(vm.state.value.session)
        assertTrue(vm.state.value.parts.isEmpty())
        vm.hide()
    }

    @Test
    fun olderPreviewCannotReplaceNewSelection() = runTest {
        val release = CompletableDeferred<Unit>()
        val first = target()
        val next = target(id = "second")
        val fake =
            Fake().apply {
                previewDelay = release
                previews[first] = row(first)
                previews[next] = row(next)
            }
        val vm = model(fake, backgroundScope)
        vm.show(ModerationSection.CONTENT)
        runCurrent()
        vm.select(first)
        runCurrent()
        fake.previewDelay = null
        vm.select(next)
        runCurrent()
        release.complete(Unit)
        runCurrent()
        assertEquals(next, vm.state.value.preview!!.item.target)
        vm.hide()
    }

    @Test
    fun requestedApplicationUsesPrivateExactPreviewNotPublicContentRoute() = runTest {
        val t = target(ModerationKind.ORGANIZATION)
        val fake = Fake().apply { previews[t] = row(t) }
        val vm = model(fake, backgroundScope)
        vm.show(ModerationSection.ORGANIZATION_REQUESTS, t.id)
        runCurrent()
        assertEquals(t, vm.state.value.preview!!.item.target)
        assertEquals(1, fake.previewReads)
        vm.hide()
    }

    @Test
    fun malformedRequestedRouteDoesNotReadAnyPrivateCollection() = runTest {
        val fake = Fake()
        val vm = model(fake, backgroundScope)
        vm.show(ModerationSection.CONTENT, "org")
        runCurrent()
        assertEquals(ModerationFailure.INVALID, vm.state.value.previewError)
        assertEquals(0, fake.reads)
        vm.hide()
    }

    @Test
    fun filtersSearchAndStableTieSortStayWithinFreshLoadedRows() {
        val news =
            ModerationContract.head(
                ModerationKind.NEWS,
                listOf(row(target(id = "b")), row(target(id = "a"))),
            )
        val state =
            ModerationState(
                actor,
                visible = true,
                parts = mapOf(ModerationKind.NEWS to ModerationPart(head = news)),
            )
        assertEquals(listOf("a", "b"), ModerationContract.visible(state, "uk").map { it.target.id })
        assertEquals(
            1,
            ModerationContract.visible(state.copy(search = "a"), "de")
                .filter { it.target.id == "a" }
                .size,
        )
        assertTrue(
            ModerationContract.visible(state.copy(filter = ModerationKind.EVENT), "de").isEmpty()
        )
        assertTrue(
            ModerationContract.visible(
                    state.copy(
                        parts =
                            mapOf(
                                ModerationKind.NEWS to
                                    ModerationPart(head = news, error = ModerationFailure.OFFLINE)
                            )
                    ),
                    "de",
                )
                .isEmpty()
        )
    }

    @Test
    fun everyFailureHasSeparateGermanAndUkrainianDescription() {
        ModerationFailure.entries.forEach {
            assertTrue(moderationFailureText(it, "de").isNotBlank())
            assertNotEquals(moderationFailureText(it, "de"), moderationFailureText(it, "uk"))
        }
    }

    @Test
    fun representationsNeverPrintApplicantOrPrivateContent() {
        val item = ModerationContract.item(ModerationKind.NEWS, row())
        val preview = ModerationContract.preview(target(), row())
        for (value in
            listOf(
                actor,
                target(),
                item.title,
                item,
                preview,
                ModerationField("email", ModerationText("synthetic@example.invalid")),
                ModerationState(actor, preview = preview),
            )) {
            assertFalse(value.toString().contains("Private"))
            assertFalse(value.toString().contains("synthetic"))
            assertFalse(value.toString().contains("@example"))
        }
    }
}
