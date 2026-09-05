package at.uac.android

import at.uac.android.core.ExternalImagePickerAuthorization
import at.uac.android.core.ExternalImagePickerLease
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.gallery.*
import at.uac.android.feature.organization.OrganizationMutationGate
import at.uac.android.feature.organization.OrganizationSession
import java.time.Instant
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GalleryTest {
    private val session = OrganizationSession("synthetic-owner", 4, true, "Synthetic", "user")
    private var current: OrganizationSession? = session
    private val id = "synthetic-gallery"
    private val target = GalleryTarget(id, "synthetic-photo")
    private val time = Instant.parse("2026-09-03T10:00:00Z")
    private val token = "synthetic-token"
    private val bytes =
        byteArrayOf(0xff.toByte(), 0xd8.toByte(), 1, 2, 0xff.toByte(), 0xd9.toByte())
    private val prepared
        get() = PreparedGalleryPhoto(bytes, 2, 3)

    private fun intent() = GalleryUploadIntent(target, "Memory-only caption", prepared)

    private val gate =
        object : OrganizationMutationGate {
            override suspend fun <T> withSession(
                session: OrganizationSession,
                operation: suspend () -> T,
            ): T = operation()
        }

    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    private fun org(extra: Map<String, Any?> = emptyMap()) =
        RawDocument(
            id,
            mapOf(
                "id" to id,
                "name" to "Synthetic gallery",
                "ownerId" to session.uid,
                "adminIds" to emptyList<String>(),
                "moderatorIds" to emptyList<String>(),
                "moderationStatus" to "approved",
                "photoCount" to 0,
            ) + extra,
        )

    private fun photo(
        target: GalleryTarget = this.target,
        caption: String? = "Memory-only caption",
    ) =
        GalleryPhoto(
            target,
            GalleryContract.alias(target, token),
            caption,
            session.uid,
            time,
            null,
        )

    private fun raw(photo: GalleryPhoto) =
        RawDocument(
            photo.target.photoId,
            mapOf(
                "id" to photo.target.photoId,
                "organizationId" to photo.target.organizationId,
                "imageURL" to photo.imageUrl,
                "caption" to photo.caption,
                "uploadedBy" to photo.uploadedBy,
                "createdAt" to photo.createdAt,
                "updatedAt" to photo.updatedAt,
            ),
        )

    private fun entry(
        phase: GalleryPhase = GalleryPhase.CREATE_SUBMITTED,
        token: String? = this.token,
    ) =
        GalleryJournalEntry(
            GalleryContract.accountHash(session.uid),
            target,
            phase,
            prepared.hash,
            GalleryContract.hashText("Memory-only caption"),
            GalleryContract.accountHash(session.uid),
            token,
        )

    private class Journal : GalleryJournal {
        var entries = emptyList<GalleryJournalEntry>()
        var failWrites = false
        var writes = 0

        override suspend fun pending(uid: String) = entries.filter {
            it.accountHash == GalleryContract.accountHash(uid)
        }

        override suspend fun put(
            uid: String,
            entry: GalleryJournalEntry,
            expected: GalleryJournalEntry?,
        ): GalleryJournalEntry {
            if (failWrites) throw GalleryException(GalleryFailure.JOURNAL)
            assertEquals(GalleryContract.accountHash(uid), entry.accountHash)
            assertEquals(
                expected,
                entries.firstOrNull {
                    it.accountHash == entry.accountHash && it.target == entry.target
                },
            )
            entries = entries.filterNot { it == expected } + entry
            writes++
            return entry
        }

        override suspend fun clear(uid: String, expected: GalleryJournalEntry) {
            assertTrue(expected in pending(uid))
            entries = entries.filterNot { it == expected }
        }
    }

    private inner class Fake : GallerySource {
        var organization = org()
        val metadata = linkedMapOf<GalleryTarget, GalleryPhoto>()
        val images = linkedMapOf<GalleryTarget, GalleryBlob>()
        val changes = MutableSharedFlow<Result<Unit>>(extraBufferCapacity = 8)
        var reads = 0
        var uploads = 0
        var creates = 0
        var removes = 0
        var cleanups = 0
        var uploadDelay = 0L
        var uploadFailure: Exception? = null
        var commitUploadOnFailure = false
        var createFailure: Exception? = null
        var commitCreateOnFailure = false
        var removeFailure: Exception? = null
        var cleanupFailure: Exception? = null
        var transform: (GalleryPhoto) -> GalleryPhoto = { it }

        override suspend fun snapshot(
            organizationId: String,
            session: OrganizationSession,
        ): GallerySnapshot {
            reads++
            assertEquals(id, organizationId)
            return GalleryContract.snapshot(
                organization.copy(fields = organization.fields + ("photoCount" to metadata.size)),
                metadata.values.sortedByDescending { it.createdAt }.take(31).map(::raw),
                session,
            )
        }

        override suspend fun photo(target: GalleryTarget, session: OrganizationSession) =
            metadata[target]

        override suspend fun blob(target: GalleryTarget, session: OrganizationSession) =
            images[target]

        override suspend fun upload(
            target: GalleryTarget,
            photo: PreparedGalleryPhoto,
            session: OrganizationSession,
        ): GalleryBlob {
            uploads++
            delay(uploadDelay)
            val image = GalleryBlob(photo.bytes(), token)
            if (uploadFailure == null || commitUploadOnFailure) images[target] = image
            uploadFailure?.let { throw it }
            return image
        }

        override suspend fun create(
            intent: GalleryUploadIntent,
            imageUrl: String,
            session: OrganizationSession,
        ): GalleryReceipt {
            creates++
            if (createFailure == null || commitCreateOnFailure)
                metadata[intent.target] =
                    transform(
                        GalleryPhoto(
                            intent.target,
                            imageUrl,
                            intent.caption,
                            session.uid,
                            time,
                            null,
                        )
                    )
            createFailure?.let { throw it }
            val actual = metadata.getValue(intent.target)
            return GalleryReceipt(
                intent.target,
                metadata.size,
                true,
                actual.uploadedBy,
                actual.createdAt,
            )
        }

        override suspend fun remove(
            target: GalleryTarget,
            session: OrganizationSession,
        ): GalleryReceipt {
            removes++
            removeFailure?.let { throw it }
            return GalleryReceipt(
                target,
                metadata.size - if (target in metadata) 1 else 0,
                metadata.remove(target) != null,
                null,
                null,
            )
        }

        override suspend fun removeBlob(target: GalleryTarget, session: OrganizationSession) {
            cleanups++
            cleanupFailure?.let { throw it }
            images.remove(target)
        }

        override fun changes(organizationId: String, session: OrganizationSession) = changes
    }

    private fun repository(source: Fake, journal: Journal, visible: Boolean = true) =
        GalleryRepository(source, journal, { current }, gate) { visible }

    private suspend fun fails(reason: GalleryFailure, action: suspend () -> Any?) {
        try {
            action()
            fail("Expected $reason")
        } catch (error: GalleryException) {
            assertEquals(reason, error.failure)
        }
    }

    private fun invalid(action: () -> Any?) {
        try {
            action()
            fail("Invalid input")
        } catch (_: Exception) {}
    }

    @Test
    fun ownerAdminAndModeratorButNotUnassignedAppAdminCanManage() {
        assertTrue(GalleryContract.canManage(org(), session))
        assertTrue(
            GalleryContract.canManage(
                org(mapOf("ownerId" to "other", "adminIds" to listOf(session.uid))),
                session,
            )
        )
        assertTrue(
            GalleryContract.canManage(
                org(mapOf("ownerId" to "other", "moderatorIds" to listOf(session.uid))),
                session,
            )
        )
        assertFalse(
            GalleryContract.canManage(
                org(mapOf("ownerId" to "other")),
                session.copy(globalRole = "admin"),
            )
        )
        assertFalse(
            GalleryContract.canManage(
                org(mapOf("ownerId" to "other", "submittedByUserId" to session.uid)),
                session,
            )
        )
    }

    @Test
    fun systemGalleryKeepsBuild65PlatformOwnerBoundary() {
        assertFalse(GalleryContract.canManage(org(mapOf("isSystemManaged" to true)), session))
        assertTrue(
            GalleryContract.canManage(
                org(mapOf("isSystemManaged" to true)),
                session.copy(globalRole = "owner"),
            )
        )
        val system =
            org()
                .copy(
                    id = "ukrainian-community",
                    fields = org().fields + ("id" to "ukrainian-community"),
                )
        assertFalse(GalleryContract.canManage(system, session))
        assertTrue(GalleryContract.canManage(system, session.copy(globalRole = "owner")))
    }

    @Test
    fun managementDoesNotInventApprovedOnlyGateAndNeverUsesNotReadyRole() {
        assertTrue(
            GalleryContract.canManage(org(mapOf("moderationStatus" to "pendingReview")), session)
        )
        assertFalse(GalleryContract.canManage(org(), session.copy(ready = false)))
        assertFalse(GalleryContract.canManage(org(), null))
    }

    @Test
    fun captionTrimAndUtf16LimitMatchActualCallable() = runTest {
        assertNull(GalleryContract.caption(" \n "))
        assertEquals("Text", GalleryContract.caption("  Text  "))
        assertEquals(500, GalleryContract.caption("😀".repeat(250))!!.length)
        fails(GalleryFailure.INVALID) { GalleryContract.caption("😀".repeat(251)) }
        fails(GalleryFailure.INVALID) { GalleryContract.caption("unsafe\u0000") }
    }

    @Test
    fun pathsRejectForeignAndTraversalIds() {
        assertEquals("organizations/$id/photos/synthetic-photo.jpg", target.path)
        for (bad in listOf("../escape", "a/b", "", "x".repeat(129))) invalid {
            GalleryTarget(id, bad)
        }
    }

    @Test
    fun onlyExactDemoAliasAndLocalObjectAreAccepted() {
        val alias = GalleryContract.alias(target, token)
        assertEquals(token, GalleryContract.token(alias, target))
        assertEquals(
            token,
            GalleryContract.token(
                alias.replace("https://firebasestorage.googleapis.com", "http://10.0.2.2:9198"),
                target,
            ),
        )
        assertNull(GalleryContract.token(alias.replace("demo-uac-android", "production"), target))
        assertNull(GalleryContract.token(alias, target.copy(photoId = "other")))
        assertNull(
            GalleryContract.token(
                alias.replace("googleapis.com", "googleapis.com.evil.invalid"),
                target,
            )
        )
    }

    @Test
    fun tokenQueriesCannotCarryRedirectsDuplicatesOrCredentials() {
        val url = GalleryContract.alias(target, token)
        for (unsafe in
            listOf(
                "$url&redirect=https://example.invalid",
                "$url&token=other",
                "$url#fragment",
                url.replace("https://", "https://user@"),
                url.replace("token=$token", "token=%0a"),
                url.replace("alt=media", "alt=other"),
            )) assertNull(GalleryContract.token(unsafe, target))
    }

    @Test
    fun preparedJpegAndIntentAreImmutableAndRedacted() {
        val input = bytes.copyOf()
        val photo = PreparedGalleryPhoto(input, 2, 3)
        val hash = photo.hash
        input[2] = 7
        photo.bytes()[2] = 8
        assertEquals(hash, photo.hash)
        assertArrayEquals(bytes, photo.bytes())
        assertFalse(intent().toString().contains("Memory-only"))
        assertFalse(photo.toString().contains(token))
    }

    @Test
    fun boundedThirtyPlusOneSnapshotReportsOverflowWithoutCounterRepair() {
        val rows = (0..30).map { raw(photo(GalleryTarget(id, "photo-$it"))) }
        val result = GalleryContract.snapshot(org(mapOf("photoCount" to 700)), rows, session)
        assertEquals(30, result.photos.size)
        assertTrue(result.overflow)
        assertEquals(700, result.counter)
    }

    @Test
    fun malformedPhotoOrUnorderedWindowFailsClosed() = runTest {
        fails(GalleryFailure.INVALID) {
            GalleryContract.photo(
                id,
                raw(photo()).copy(fields = raw(photo()).fields + ("uploadedBy" to 1)),
            )
        }
        fails(GalleryFailure.IMAGE_UNAVAILABLE) {
            GalleryContract.photo(
                id,
                raw(photo()).copy(fields = raw(photo()).fields + ("imageURL" to "file:///photo")),
            )
        }
        val a = photo()
        val b = photo(GalleryTarget(id, "second")).copy(createdAt = time.plusSeconds(1))
        fails(GalleryFailure.INVALID) {
            GalleryContract.snapshot(org(), listOf(raw(a), raw(b)), session)
        }
    }

    @Test
    fun journalCodecRoundTripStoresNoCaptionPixelsRawIdentityOrReady() {
        val value = entry()
        val encoded = GalleryJournalCodec.encode(listOf(value))
        assertEquals(listOf(value), GalleryJournalCodec.decode(encoded))
        val text = String(encoded, Charsets.ISO_8859_1)
        assertFalse(text.contains(session.uid))
        assertFalse(text.contains("Memory-only caption"))
        assertFalse(text.contains("content://"))
        assertFalse(text.contains("READY"))
    }

    @Test
    fun journalRejectsCorruptionTrailingBytesAndOverCapacity() {
        val encoded = GalleryJournalCodec.encode(listOf(entry()))
        invalid { GalleryJournalCodec.decode(encoded + 0) }
        invalid { GalleryJournalCodec.decode(encoded.copyOf(8)) }
        invalid {
            GalleryJournalCodec.encode(
                List(17) { entry().copy(target = target.copy(photoId = "photo-$it")) }
            )
        }
        invalid { GalleryJournalCodec.encode(listOf(entry(), entry())) }
    }

    @Test
    fun journalPhaseRequiresTokenExceptKnownPreMetadataStates() {
        invalid { GalleryJournalCodec.encode(listOf(entry(token = null))) }
        for (phase in listOf(GalleryPhase.UPLOADING, GalleryPhase.UPLOAD_REJECTED)) assertEquals(
            phase,
            GalleryJournalCodec.decode(GalleryJournalCodec.encode(listOf(entry(phase, null))))
                .single()
                .phase,
        )
    }

    @Test
    fun uploadConfirmsExactFileMetadataCounterAndClearsDurableJournal() = runTest {
        val source = Fake()
        val journal = Journal()
        val result = repository(source, journal).upload(intent())
        assertEquals(1, result.snapshot.photos.size)
        assertEquals(1, result.snapshot.counter)
        assertNull(result.pending)
        assertEquals(1, source.uploads)
        assertEquals(1, source.creates)
        assertEquals(0, source.cleanups)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun journalWriteFailurePreventsAnyRemoteMutation() = runTest {
        val source = Fake()
        val journal = Journal().apply { failWrites = true }
        fails(GalleryFailure.JOURNAL) { repository(source, journal).upload(intent()) }
        assertEquals(0, source.uploads)
        assertEquals(0, source.creates)
    }

    @Test
    fun existingObjectIsNeverOverwritten() = runTest {
        val source = Fake()
        source.images[target] = GalleryBlob(bytes, token)
        fails(GalleryFailure.CONFLICT) { repository(source, Journal()).upload(intent()) }
        assertEquals(0, source.uploads)
    }

    @Test
    fun guestPolicyAndLostRoleCannotStartUpload() = runTest {
        val source = Fake()
        val journal = Journal()
        current = null
        fails(GalleryFailure.SIGN_IN) { repository(source, journal).upload(intent()) }
        current = session
        fails(GalleryFailure.POLICY) { repository(source, journal, false).upload(intent()) }
        source.organization = org(mapOf("ownerId" to "foreign"))
        fails(GalleryFailure.DENIED) { repository(source, journal).upload(intent()) }
        assertEquals(0, source.uploads)
    }

    @Test
    fun lostSuccessfulCreateReceiptIsReconciledWithoutBlobRollback() = runTest {
        val source =
            Fake().apply {
                createFailure = GalleryException(GalleryFailure.UNCONFIRMED)
                commitCreateOnFailure = true
            }
        val journal = Journal()
        val repository = repository(source, journal)
        fails(GalleryFailure.UNCONFIRMED) { repository.upload(intent()) }
        assertEquals(GalleryPhase.CREATE_SUBMITTED, journal.entries.single().phase)
        assertEquals(0, source.cleanups)
        assertEquals(
            GalleryRecovery.PUBLISHED,
            repository.reconcile(journal.entries.single()).status,
        )
        assertEquals(1, source.creates)
        assertEquals(1, source.uploads)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun missingCreateSubmissionIsUnresolvedAndCannotBeRetriedOrCleaned() = runTest {
        val source = Fake().apply { createFailure = GalleryException(GalleryFailure.UNCONFIRMED) }
        val journal = Journal()
        val repository = repository(source, journal)
        fails(GalleryFailure.UNCONFIRMED) { repository.upload(intent()) }
        val entry = journal.entries.single()
        assertEquals(GalleryRecovery.UNRESOLVED, repository.reconcile(entry).status)
        fails(GalleryFailure.UNCONFIRMED) { repository.upload(intent()) }
        fails(GalleryFailure.UNCONFIRMED) { repository.cleanup(entry) }
        assertEquals(0, source.cleanups)
        assertEquals(1, source.creates)
        assertEquals(1, source.uploads)
    }

    @Test
    fun terminalPutRejectionCanReconcileAbsenceWithoutClaimingUpload() = runTest {
        val source = Fake().apply { uploadFailure = GalleryUploadRejected(IllegalStateException()) }
        val journal = Journal()
        val repository = repository(source, journal)
        fails(GalleryFailure.DENIED) { repository.upload(intent()) }
        assertEquals(GalleryPhase.UPLOAD_REJECTED, journal.entries.single().phase)
        assertEquals(
            GalleryRecovery.UNCHANGED,
            repository.reconcile(journal.entries.single()).status,
        )
        assertTrue(journal.entries.isEmpty())
        assertEquals(0, source.creates)
        assertEquals(0, source.cleanups)
    }

    @Test
    fun postPutDeniedIsNotMisclassifiedAsRejectedWrite() = runTest {
        val source =
            Fake().apply {
                uploadFailure = GalleryException(GalleryFailure.DENIED)
                commitUploadOnFailure = true
            }
        val journal = Journal()
        val repository = repository(source, journal)
        fails(GalleryFailure.DENIED) { repository.upload(intent()) }
        assertEquals(GalleryPhase.UPLOADING, journal.entries.single().phase)
        val recovery = repository.reconcile(journal.entries.single())
        assertEquals(GalleryRecovery.CLEANUP_AVAILABLE, recovery.status)
        assertEquals(token, recovery.pending?.token)
        assertEquals(0, source.cleanups)
        repository.cleanup(recovery.pending!!)
        assertEquals(1, source.cleanups)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun unknownPutWithNoBlobCannotClearUnprovenJournal() = runTest {
        val source = Fake()
        val journal = Journal().apply { entries = listOf(entry(GalleryPhase.UPLOADING, null)) }
        val repository = repository(source, journal)
        assertEquals(
            GalleryRecovery.UNRESOLVED,
            repository.reconcile(journal.entries.single()).status,
        )
        fails(GalleryFailure.UNCONFIRMED) { repository.cleanup(journal.entries.single()) }
        assertEquals(1, journal.entries.size)
        assertEquals(0, source.cleanups)
    }

    @Test
    fun existingReceiptMismatchNeverCountsAsSuccessfulCreate() = runTest {
        val source = Fake().apply { transform = { it.copy(caption = "Some other caption") } }
        val journal = Journal()
        val repository = repository(source, journal)
        fails(GalleryFailure.UNCONFIRMED) { repository.upload(intent()) }
        fails(GalleryFailure.CONFLICT) { repository.reconcile(journal.entries.single()) }
        assertEquals(0, source.cleanups)
    }

    @Test
    fun deleteConfirmsMetadataAndFileAbsenceWithoutManualCounterWrite() = runTest {
        val source =
            Fake().apply {
                metadata[target] = photo()
                images[target] = GalleryBlob(bytes, token)
            }
        val journal = Journal()
        val result = repository(source, journal).remove(photo())
        assertTrue(result.snapshot.photos.isEmpty())
        assertEquals(0, result.snapshot.counter)
        assertTrue(journal.entries.isEmpty())
        assertEquals(1, source.removes)
        assertEquals(1, source.cleanups)
    }

    @Test
    fun failedBlobCleanupKeepsMetadataDeletedAndOffersExplicitCleanupOnly() = runTest {
        val source =
            Fake().apply {
                metadata[target] = photo()
                images[target] = GalleryBlob(bytes, token)
                cleanupFailure = GalleryException(GalleryFailure.OFFLINE)
            }
        val journal = Journal()
        val repository = repository(source, journal)
        assertNotNull(repository.remove(photo()).pending)
        assertTrue(source.metadata.isEmpty())
        val recovery = repository.reconcile(journal.entries.single())
        assertEquals(GalleryRecovery.CLEANUP_AVAILABLE, recovery.status)
        source.cleanupFailure = null
        repository.cleanup(recovery.pending!!)
        assertEquals(1, source.removes)
        assertEquals(2, source.cleanups)
        assertTrue(journal.entries.isEmpty())
    }

    @Test
    fun foreignReplacementBlocksCleanupInsteadOfDeletingPublishedFile() = runTest {
        val source =
            Fake().apply {
                images[target] = GalleryBlob(bytes, token)
                metadata[target] = photo(caption = "replacement")
            }
        val journal = Journal().apply { entries = listOf(entry(GalleryPhase.METADATA_REMOVED)) }
        fails(GalleryFailure.CONFLICT) {
            repository(source, journal).cleanup(journal.entries.single())
        }
        assertEquals(0, source.cleanups)
        assertEquals(1, source.metadata.size)
    }

    @Test
    fun accountChangeWaitsForPutAndNeverSubmitsMetadataAsNextIdentity() = runTest {
        val source = Fake().apply { uploadDelay = 100 }
        val journal = Journal()
        val job = launch { repository(source, journal).upload(intent()) }
        runCurrent()
        assertEquals(1, source.uploads)
        current = session.copy(uid = "new-user", revision = 5)
        job.cancel()
        runCurrent()
        assertTrue(job.isActive.not())
        assertFalse(job.isCompleted)
        advanceUntilIdle()
        assertTrue(job.isCompleted)
        assertEquals(1, source.images.size)
        assertEquals(0, source.creates)
        assertEquals(GalleryPhase.UPLOADING, journal.entries.single().phase)
    }

    @Test
    fun foreignJournalCannotBeReconciledUnderAnotherAccount() = runTest {
        val source = Fake()
        val journal = Journal().apply { entries = listOf(entry()) }
        current = session.copy(uid = "other")
        fails(GalleryFailure.JOURNAL) {
            repository(source, journal).reconcile(journal.entries.single())
        }
        assertEquals(0, source.reads)
        assertEquals(0, source.cleanups)
    }

    @Test
    fun renderedPolicyAndSessionMaskStaleGallery() {
        val snapshot = GalleryContract.snapshot(org(), emptyList(), session)
        val state = GalleryState(session, id, true, snapshot, fresh = true)
        assertTrue(state.canChoose)
        assertFalse(state.copy(fresh = false).canChoose)
        assertFalse(state.copy(busy = true).canChoose)
        assertNull(state.forSession(session.copy(revision = 5), id).snapshot)
        val overflow = state.copy(snapshot = snapshot.copy(overflow = true))
        assertTrue(overflow.readable)
        assertFalse(overflow.actionable)
        assertFalse(overflow.copy(fresh = false).readable)
        assertFalse(overflow.copy(visible = false).readable)
    }

    @Test
    fun viewModelPickerRequiresExactLeaseAndClearsAnotherAccountDraft() = runTest {
        val source = Fake()
        val journal = Journal()
        var finished = 0
        var canceled = 0
        val authorization = ExternalImagePickerAuthorization { uid, revision ->
            assertEquals(session.uid, uid)
            assertEquals(session.revision, revision)
            object : ExternalImagePickerLease {
                override fun finish() {
                    finished++
                }

                override fun cancel() {
                    canceled++
                }
            }
        }
        val model =
            GalleryViewModel(source, journal, { prepared }, { current }, gate, authorization)
        model.show(id)
        advanceUntilIdle()
        assertTrue(model.beginPicker())
        assertFalse(model.beginPicker())
        model.hide()
        model.show(id)
        advanceUntilIdle()
        model.pickerResult("content://synthetic/own")
        advanceUntilIdle()
        assertNotNull(model.state.value.prepared)
        assertEquals(1, finished)
        model.caption("Private draft")
        current = session.copy(uid = "other", revision = 5)
        model.bind(current)
        assertNull(model.state.value.prepared)
        assertEquals("", model.state.value.caption)
        assertEquals(0, canceled)
        model.hide()
    }

    @Test
    fun sameUidRefreshKeepsDraftMemoryButNeverKeepsAuthorityOrOldPickerResult() = runTest {
        val source = Fake()
        val journal = Journal()
        var canceled = 0
        val authorization = ExternalImagePickerAuthorization { _, _ ->
            object : ExternalImagePickerLease {
                override fun finish() = Unit

                override fun cancel() {
                    canceled++
                }
            }
        }
        val model =
            GalleryViewModel(source, journal, { prepared }, { current }, gate, authorization)
        model.show(id)
        advanceUntilIdle()
        model.beginPicker()
        model.pickerResult("content://synthetic/own")
        advanceUntilIdle()
        model.caption("Draft survives refresh")
        model.beginPicker()
        current = session.copy(revision = 5)
        model.bind(current)
        assertEquals("Draft survives refresh", model.state.value.caption)
        assertFalse(model.state.value.fresh)
        model.pickerResult("content://late/old-revision")
        advanceUntilIdle()
        assertEquals(1, canceled)
        assertTrue(model.state.value.fresh)
        assertNotNull(model.state.value.prepared)
        model.hide()
    }

    @Test
    fun duplicateConfirmCannotCreateAnotherPhotoOrRepeatRequest() = runTest {
        val source = Fake().apply { uploadDelay = 50 }
        val journal = Journal()
        val authorization = ExternalImagePickerAuthorization { _, _ ->
            object : ExternalImagePickerLease {
                override fun finish() = Unit

                override fun cancel() = Unit
            }
        }
        val model =
            GalleryViewModel(source, journal, { prepared }, { current }, gate, authorization)
        model.show(id)
        advanceUntilIdle()
        model.beginPicker()
        model.pickerResult("content://synthetic/own")
        advanceUntilIdle()
        model.requestUpload()
        val request = (model.state.value.confirmation as GalleryConfirmation.Upload).intent
        model.confirm()
        model.confirm()
        runCurrent()
        assertEquals(1, source.uploads)
        advanceUntilIdle()
        assertEquals(setOf(request.target), source.metadata.keys)
        assertEquals(1, source.creates)
        assertTrue(model.state.value.confirmed)
        assertNull(model.state.value.prepared)
        model.hide()
    }

    @Test
    fun deletingAnExistingPhotoDoesNotDiscardUnsubmittedNewPhotoDraft() = runTest {
        val source =
            Fake().apply {
                metadata[target] = photo()
                images[target] = GalleryBlob(bytes, token)
            }
        val journal = Journal()
        val authorization = ExternalImagePickerAuthorization { _, _ ->
            object : ExternalImagePickerLease {
                override fun finish() = Unit

                override fun cancel() = Unit
            }
        }
        val model =
            GalleryViewModel(source, journal, { prepared }, { current }, gate, authorization)
        model.show(id)
        advanceUntilIdle()
        model.beginPicker()
        model.pickerResult("content://synthetic/own")
        advanceUntilIdle()
        model.caption("Unsaved new-photo caption")
        model.requestRemove(photo())
        model.confirm()
        advanceUntilIdle()
        assertTrue(source.metadata.isEmpty())
        assertEquals(0, source.uploads)
        assertNotNull(model.state.value.prepared)
        assertEquals("Unsaved new-photo caption", model.state.value.caption)
        model.hide()
    }
}
