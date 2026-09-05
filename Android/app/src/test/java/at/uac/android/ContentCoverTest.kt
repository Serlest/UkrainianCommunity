package at.uac.android

import at.uac.android.core.*
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.contentmedia.*
import at.uac.android.feature.organization.*
import java.net.URLEncoder
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
class ContentCoverTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun cleanup() {
        Dispatchers.resetMain()
    }

    private val now = Instant.parse("2026-09-03T03:00:00Z")
    private val actor = OrganizationSession("cover-alice", 1, true, "Alice", "user")
    private val token = "synthetic-cover-token-00001"
    private val target = ContentCoverTarget("cover-org", ContentKind.NEWS, "cover-news")

    private fun jpeg(mark: Byte = 1) =
        ByteArray(32) { mark }
            .apply {
                this[0] = -1
                this[1] = -40
                this[size - 2] = -1
                this[size - 1] = -39
            }

    private fun url(value: ContentCoverTarget = target, key: String = token) =
        "https://firebasestorage.googleapis.com/v0/b/${LocalStorage.BUCKET}/o/${URLEncoder.encode(value.path, "UTF-8")}?alt=media&token=$key"

    private fun snapshot(
        kind: ContentKind = ContentKind.NEWS,
        image: Boolean = false,
    ): ContentCoverSnapshot {
        val basics =
            OrganizationDraft(
                target.organizationId,
                "Synthetic cover community",
                "A complete local organization",
                region = "wien",
                city = "Wien",
            )
        val org =
            OrganizationContract.record(
                RawDocument(
                    basics.id,
                    OrganizationContract.create(basics, actor, now) +
                        mapOf("ownerId" to actor.uid, "moderationStatus" to "approved"),
                ),
                actor,
            )
        val draft =
            AuthoringContract.newDraft(kind, org, now)
                .copy(
                    id = target.contentId,
                    title = "Synthetic title",
                    summary = "Summary",
                    body = "Body",
                )
                .let {
                    if (kind == ContentKind.EVENTS) it.copy(event = it.event.copy(venue = "Hall"))
                    else it
                }
        val scoped = target.copy(kind = kind)
        val fields =
            AuthoringContract.submission(draft, org, actor, null, now).fields +
                mapOf("likeCount" to 7L, "mediaMetadata" to mapOf("credit" to "Keep credit")) +
                if (image) mapOf("imageURL" to url(scoped, "synthetic-cover-old-token"))
                else emptyMap()
        val item =
            AuthoringContract.item(
                kind,
                RawDocument(draft.id, fields),
                org.id,
                AuthoringStatus.APPROVED,
                actor,
            )
        return ContentCoverSnapshot(scoped, org, item)
    }

    private fun change(
        value: ContentCoverSnapshot,
        fields: Map<String, Any?>,
    ): ContentCoverSnapshot {
        val data = value.item.fields.toMutableMap()
        fields.forEach { (key, field) ->
            if (field == null) data.remove(key) else data[key] = field
        }
        data["updatedAt"] = now.plusSeconds(1)
        val status = AuthoringStatus.entries.first { it.wire == data["moderationStatus"] }
        return value.copy(
            item =
                AuthoringContract.item(
                    value.target.kind,
                    RawDocument(value.target.contentId, data),
                    value.target.organizationId,
                    status,
                    actor,
                )
        )
    }

    private val gate =
        object : OrganizationMutationGate {
            override suspend fun <T> withSession(
                session: OrganizationSession,
                operation: suspend () -> T,
            ): T = withContext(NonCancellable) { operation() }
        }

    private inner class FakeSource(initial: ContentCoverSnapshot = snapshot()) :
        ContentCoverSource {
        var current = initial
        var asset: ContentCoverAsset? =
            if (initial.imageUrl == null) null
            else ContentCoverAsset(jpeg(2), "synthetic-cover-old-token")
        var reads = 0
        var uploads = 0
        var removals = 0
        var watches = 0
        var error: ContentCoverFailure? = null
        var commits = true
        var alterCounter = false
        var wrongResponse = false
        var pending: CompletableDeferred<Unit>? = null
        val changes = MutableSharedFlow<Result<Unit>>(extraBufferCapacity = 8)

        override suspend fun snapshot(
            target: ContentCoverTarget,
            session: OrganizationSession,
        ): ContentCoverSnapshot {
            reads++
            return current
        }

        override suspend fun image(snapshot: ContentCoverSnapshot, session: OrganizationSession) =
            if (snapshot.imageUrl == null) null else asset

        override fun changes(snapshot: ContentCoverSnapshot, session: OrganizationSession) =
            changes.also {
                watches++
            }

        override suspend fun upload(
            intent: ContentCoverIntent.Upload,
            session: OrganizationSession,
        ): ContentCoverResponse {
            uploads++
            pending?.await()
            if (commits) {
                current =
                    change(
                        current,
                        mapOf("imageURL" to url(current.target)) +
                            if (alterCounter) mapOf("likeCount" to 99L) else emptyMap(),
                    )
                asset = ContentCoverAsset(intent.photo.jpeg, token)
            }
            error?.let { ContentCoverContract.fail(it) }
            return ContentCoverResponse(
                current.target,
                if (wrongResponse) url(current.target, "synthetic-wrong-response-token")
                else url(current.target),
                intent.photo.byteCount,
            )
        }

        override suspend fun remove(
            intent: ContentCoverIntent.Remove,
            session: OrganizationSession,
        ) {
            removals++
            current = change(current, mapOf("imageURL" to null))
        }
    }

    private suspend fun fails(reason: ContentCoverFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $reason")
        } catch (error: ContentCoverException) {
            assertEquals(reason, error.reason)
        }
    }

    private fun picker() = ExternalImagePickerAuthorization { _, _ ->
        object : ExternalImagePickerLease {
            override fun finish() {}

            override fun cancel() {}
        }
    }

    @Test
    fun preparedPhotoAndAssetCannotBeMutatedThroughExposedArrays() {
        val bytes = jpeg()
        val selected = PreparedContentCover(bytes, 160, 90)
        val digest = selected.digest
        bytes[5] = 9
        selected.jpeg[5] = 10
        assertEquals(digest, selected.digest)
        assertTrue(selected.matches(jpeg()))
        val asset = ContentCoverAsset(jpeg(), token)
        asset.bytes[5] = 10
        assertArrayEquals(jpeg(), asset.bytes)
    }

    @Test
    fun onlyExactCanonicalLocalObjectAndTokenAreAccepted() {
        assertEquals(token, ContentCoverContract.token(url(), target))
        assertEquals(
            token,
            ContentCoverContract.token(
                url().replace("https://firebasestorage.googleapis.com", "http://10.0.2.2:9198"),
                target,
            ),
        )
        for (value in
            listOf(
                url().replace(LocalStorage.BUCKET, "production.appspot.com"),
                url().replace("cover-news", "foreign-news"),
                url().replace("https://firebasestorage.googleapis.com", "https://attacker.invalid"),
                url() + "&token=duplicate",
                url() + "#fragment",
                url().replace("https://", "https://name:password@"),
                url().replace("alt=media", "alt=json"),
            )) assertNull(ContentCoverContract.token(value, target))
    }

    @Test
    fun invalidTargetsNeverReachAnySource() {
        for (id in listOf("../foreign", "news/foreign", "", "x".repeat(129))) {
            try {
                ContentCoverTarget("cover-org", ContentKind.NEWS, id)
                fail("Invalid target")
            } catch (_: IllegalArgumentException) {}
        }
        try {
            ContentCoverTarget("cover-org", ContentKind.ORGANIZATIONS, "content")
            fail("Wrong kind")
        } catch (_: IllegalArgumentException) {}
    }

    @Test
    fun responseRequiresExactKeysKindIdBytesAndCanonicalUrl() = runTest {
        val photo = PreparedContentCover(jpeg(), 160, 90)
        val fields =
            mapOf(
                "kind" to "news",
                "contentId" to target.contentId,
                "imageURL" to url(),
                "byteCount" to 32L,
            )
        assertEquals(32, ContentCoverContract.response(fields, target, photo).byteCount)
        for (bad in
            listOf(
                fields + ("kind" to "events"),
                fields + ("contentId" to "foreign"),
                fields + ("byteCount" to 32.1),
                fields + ("byteCount" to Double.NaN),
                fields + ("extra" to true),
                fields + ("imageURL" to "https://example.invalid/image"),
            )) fails(ContentCoverFailure.UNCONFIRMED) {
            ContentCoverContract.response(bad, target, photo)
        }
    }

    @Test
    fun guestAndNotReadyNeverReadOrWrite() = runTest {
        val source = FakeSource()
        fails(ContentCoverFailure.SIGN_IN) {
            ContentCoverRepository(source, { null }, gate).load(target)
        }
        fails(ContentCoverFailure.NOT_READY) {
            ContentCoverRepository(source, { actor.copy(ready = false) }, gate).load(target)
        }
        assertEquals(0, source.reads)
        assertEquals(0, source.uploads)
    }

    @Test
    fun sourceCannotReturnForeignTarget() = runTest {
        val source =
            FakeSource().apply {
                current = current.copy(target = target.copy(contentId = "foreign"))
            }
        fails(ContentCoverFailure.INVALID) {
            ContentCoverRepository(source, { actor }, gate).load(target)
        }
    }

    @Test
    fun changedBaselineNeverReachesUpload() = runTest {
        val source = FakeSource()
        val intent =
            ContentCoverIntent.Upload(source.current, PreparedContentCover(jpeg(), 160, 90))
        source.current = change(source.current, mapOf("title" to "Other editor title"))
        fails(ContentCoverFailure.STALE) {
            ContentCoverRepository(source, { actor }, gate).execute(intent)
        }
        assertEquals(0, source.uploads)
    }

    @Test
    fun actualUploadContractRequiresBytesLinkAndPreservedFields() = runTest {
        val source = FakeSource()
        val before = source.current
        val result =
            ContentCoverRepository(source, { actor }, gate)
                .execute(ContentCoverIntent.Upload(before, PreparedContentCover(jpeg(), 160, 90)))
        assertEquals(url(), result.snapshot.imageUrl)
        assertArrayEquals(jpeg(), result.asset!!.bytes)
        assertEquals(7L, result.snapshot.item.fields["likeCount"])
        assertEquals(
            before.item.fields["mediaMetadata"],
            result.snapshot.item.fields["mediaMetadata"],
        )
        assertEquals(1, source.uploads)
    }

    @Test
    fun changedReadbackCounterIsUnconfirmedNotSilentlyAccepted() = runTest {
        val source = FakeSource().apply { alterCounter = true }
        try {
            ContentCoverRepository(source, { actor }, gate)
                .execute(
                    ContentCoverIntent.Upload(source.current, PreparedContentCover(jpeg(), 160, 90))
                )
            fail("Changed counters must remain unconfirmed")
        } catch (error: ContentCoverException) {
            assertEquals(ContentCoverFailure.UNCONFIRMED, error.reason)
            val diagnostic = contentCoverDiagnostic(ContentCoverStage.MUTATION, error)
            assertEquals(ContentCoverStage.VERIFY_UPLOAD, diagnostic.stage)
            assertEquals(setOf(ContentCoverCheck.PRESERVED_FIELDS), diagnostic.failedChecks)
            assertEquals(setOf("likeCount"), diagnostic.changedFields)
        }
    }

    @Test
    fun responseLinkMismatchIsUnconfirmed() = runTest {
        val source = FakeSource().apply { wrongResponse = true }
        fails(ContentCoverFailure.UNCONFIRMED) {
            ContentCoverRepository(source, { actor }, gate)
                .execute(
                    ContentCoverIntent.Upload(source.current, PreparedContentCover(jpeg(), 160, 90))
                )
        }
    }

    @Test
    fun lostCommittedResponseRecoversReadOnlyWithoutSecondUpload() = runTest {
        val source = FakeSource().apply { error = ContentCoverFailure.UNCONFIRMED }
        val repo = ContentCoverRepository(source, { actor }, gate)
        val intent =
            ContentCoverIntent.Upload(source.current, PreparedContentCover(jpeg(), 160, 90))
        fails(ContentCoverFailure.UNCONFIRMED) { repo.execute(intent) }
        assertNotNull(repo.recover(intent).confirmed)
        assertEquals(1, source.uploads)
        assertEquals(0, source.removals)
    }

    @Test
    fun absentUnconfirmedUploadDoesNotRetryOrDelete() = runTest {
        val source =
            FakeSource().apply {
                error = ContentCoverFailure.UNCONFIRMED
                commits = false
            }
        val repo = ContentCoverRepository(source, { actor }, gate)
        val intent =
            ContentCoverIntent.Upload(source.current, PreparedContentCover(jpeg(), 160, 90))
        fails(ContentCoverFailure.UNCONFIRMED) { repo.execute(intent) }
        assertNull(repo.recover(intent).confirmed)
        assertEquals(1, source.uploads)
        assertEquals(0, source.removals)
    }

    @Test
    fun partialObjectReplacementWithoutNewDocumentTokenCannotRecoverAsSuccess() = runTest {
        val source = FakeSource(snapshot(image = true))
        val intent =
            ContentCoverIntent.Upload(source.current, PreparedContentCover(jpeg(), 160, 90))
        source.asset = ContentCoverAsset(jpeg(), token)
        assertNull(ContentCoverRepository(source, { actor }, gate).recover(intent).confirmed)
        assertEquals(0, source.uploads)
    }

    @Test
    fun newsRemovalClearsOnlyReferenceAndNeverDeletesObject() = runTest {
        val source = FakeSource(snapshot(image = true))
        val before = source.current
        val bytes = source.asset!!.bytes
        val result =
            ContentCoverRepository(source, { actor }, gate)
                .execute(ContentCoverIntent.Remove(before))
        assertNull(result.snapshot.imageUrl)
        assertNull(result.asset)
        assertArrayEquals(bytes, source.asset!!.bytes)
        assertTrue(ContentCoverContract.preserved(before, result.snapshot))
        assertEquals(1, source.removals)
        assertEquals(0, source.uploads)
    }

    @Test
    fun eventRemovalAndArchivedUploadRemainReadOnly() = runTest {
        val events = FakeSource(snapshot(ContentKind.EVENTS, true))
        fails(ContentCoverFailure.READ_ONLY) {
            ContentCoverRepository(events, { actor }, gate)
                .execute(ContentCoverIntent.Remove(events.current))
        }
        assertEquals(0, events.removals)
        val archived =
            FakeSource().apply {
                current = change(current, mapOf("moderationStatus" to "archived"))
            }
        fails(ContentCoverFailure.READ_ONLY) {
            ContentCoverRepository(archived, { actor }, gate)
                .execute(
                    ContentCoverIntent.Upload(
                        archived.current,
                        PreparedContentCover(jpeg(), 160, 90),
                    )
                )
        }
        assertEquals(0, archived.uploads)
    }

    @Test
    fun sessionSwitchDuringUploadSuppressesOldResult() = runTest {
        val source = FakeSource().apply { pending = CompletableDeferred() }
        var current = actor
        val repo = ContentCoverRepository(source, { current }, gate)
        val work = async {
            repo.execute(
                ContentCoverIntent.Upload(source.current, PreparedContentCover(jpeg(), 160, 90))
            )
        }
        runCurrent()
        current = actor.copy(uid = "other", revision = 2)
        source.pending!!.complete(Unit)
        try {
            work.await()
            fail("Old session result")
        } catch (_: CancellationException) {}
        assertEquals(1, source.uploads)
    }

    @Test
    fun duplicateConfirmationCannotSubmitTwice() = runTest {
        val source = FakeSource().apply { pending = CompletableDeferred() }
        val model =
            ContentCoverViewModel(
                source,
                { PreparedContentCover(jpeg(), 160, 90) },
                { actor },
                gate,
                picker(),
            )
        model.show(target)
        advanceUntilIdle()
        assertTrue(model.beginPicker())
        model.pickerResult("content://synthetic/photo")
        advanceUntilIdle()
        model.requestUpload()
        model.confirm()
        model.confirm()
        runCurrent()
        assertEquals(1, source.uploads)
        source.pending!!.complete(Unit)
        advanceUntilIdle()
        assertTrue(model.state.value.confirmed)
        assertNull(model.state.value.prepared)
    }

    @Test
    fun pickerResultFromAnotherAccountIsDiscardedBeforePreparation() = runTest {
        val sessions = MutableStateFlow<OrganizationSession?>(actor)
        val source = FakeSource()
        var prepared = 0
        var cancelled = 0
        val authorization = ExternalImagePickerAuthorization { _, _ ->
            object : ExternalImagePickerLease {
                override fun finish() {}

                override fun cancel() {
                    cancelled++
                }
            }
        }
        val model =
            ContentCoverViewModel(
                source,
                {
                    prepared++
                    PreparedContentCover(jpeg(), 160, 90)
                },
                { sessions.value },
                gate,
                authorization,
            )
        model.observeSessions(sessions)
        model.show(target)
        advanceUntilIdle()
        assertTrue(model.beginPicker())
        sessions.value = actor.copy(uid = "other", revision = 2, ready = false)
        runCurrent()
        model.pickerResult("content://synthetic/private")
        advanceUntilIdle()
        assertEquals(0, prepared)
        assertEquals(1, cancelled)
        assertNull(model.state.value.prepared)
        assertNull(model.state.value.snapshot)
    }

    @Test
    fun pickerLeaseSurvivesOrdinaryScreenPauseButNeedsExactSession() = runTest {
        val source = FakeSource()
        var finished = 0
        val authorization = ExternalImagePickerAuthorization { _, _ ->
            object : ExternalImagePickerLease {
                override fun finish() {
                    finished++
                }

                override fun cancel() {}
            }
        }
        val model =
            ContentCoverViewModel(
                source,
                { PreparedContentCover(jpeg(), 160, 90) },
                { actor },
                gate,
                authorization,
            )
        model.show(target)
        advanceUntilIdle()
        assertTrue(model.beginPicker())
        model.hide()
        model.pickerResult("content://synthetic/photo")
        model.show(target)
        advanceUntilIdle()
        assertEquals(1, finished)
        assertTrue(model.state.value.canUpload)
        assertEquals(0, source.uploads)
    }

    @Test
    fun sameUidRefreshKeepsPhotoButClearsPermissionUntilNewReadyRead() = runTest {
        val sessions = MutableStateFlow<OrganizationSession?>(actor)
        val source = FakeSource()
        val model =
            ContentCoverViewModel(
                source,
                { PreparedContentCover(jpeg(), 160, 90) },
                { sessions.value },
                gate,
                picker(),
            )
        model.observeSessions(sessions)
        model.show(target)
        advanceUntilIdle()
        assertTrue(model.beginPicker())
        model.pickerResult("content://synthetic/photo")
        advanceUntilIdle()
        val digest = model.state.value.prepared!!.digest
        sessions.value = actor.copy(revision = 2, ready = false)
        runCurrent()
        assertFalse(model.state.value.canUpload)
        assertEquals(digest, model.state.value.prepared!!.digest)
        sessions.value = actor.copy(revision = 3)
        advanceUntilIdle()
        assertTrue(model.state.value.canUpload)
        assertEquals(0, source.uploads)
    }

    @Test
    fun uncertainModelHasReadOnlyRecoveryAndNoChooseOrRepeat() = runTest {
        val source =
            FakeSource().apply {
                commits = false
                error = ContentCoverFailure.UNCONFIRMED
            }
        val model =
            ContentCoverViewModel(
                source,
                { PreparedContentCover(jpeg(), 160, 90) },
                { actor },
                gate,
                picker(),
            )
        model.show(target)
        advanceUntilIdle()
        assertTrue(model.beginPicker())
        model.pickerResult("content://synthetic/photo")
        advanceUntilIdle()
        model.requestUpload()
        model.confirm()
        advanceUntilIdle()
        assertNotNull(model.state.value.uncertain)
        assertFalse(model.state.value.canChoose)
        assertFalse(model.state.value.canUpload)
        model.requestUpload()
        model.confirm()
        advanceUntilIdle()
        model.recover()
        advanceUntilIdle()
        assertTrue(model.state.value.recoveryChecked)
        assertEquals(1, source.uploads)
    }

    @Test
    fun pureFailureMappingDoesNotInitializeAndroidSdkEnums() {
        assertEquals(
            ContentCoverFailure.DENIED,
            contentCoverFailure(LocalCallableException(LocalCallableFailure.PERMISSION_DENIED)),
        )
        assertEquals(
            ContentCoverFailure.UNCONFIRMED,
            contentCoverFailure(LocalCallableException(LocalCallableFailure.UNCONFIRMED)),
        )
        assertEquals(
            ContentCoverFailure.TOO_LARGE,
            contentCoverFailure(LocalImageException(LocalImageFailure.TOO_LARGE)),
        )
    }

    @Test
    fun listenerFailureRetryAttachesFreshListenersInsteadOfReusingClosedRegistration() = runTest {
        val source = FakeSource()
        val model =
            ContentCoverViewModel(
                source,
                { PreparedContentCover(jpeg(), 160, 90) },
                { actor },
                gate,
                picker(),
            )
        model.show(target)
        advanceUntilIdle()
        assertEquals(1, source.watches)
        source.changes.emit(Result.failure(ContentCoverException(ContentCoverFailure.OFFLINE)))
        advanceUntilIdle()
        assertFalse(model.state.value.fresh)
        model.refresh()
        advanceUntilIdle()
        assertTrue(model.state.value.fresh)
        assertEquals(2, source.watches)
    }

    @Test
    fun safeDiagnosticsNeverRetainThrowableMessagesDetailsUrlsTokensOrBytes() {
        val error =
            LocalCallableException(
                LocalCallableFailure.UNCONFIRMED,
                details = mapOf("token" to "private-token", "imageBase64" to "private-image"),
                cause =
                    IllegalStateException(
                        "https://private.invalid/private-user?token=private-token"
                    ),
            )
        val diagnostic = contentCoverDiagnostic(ContentCoverStage.UPLOAD_CALL, error)
        assertEquals(
            listOf(
                ContentCoverCause("LocalCallableException", "UNCONFIRMED"),
                ContentCoverCause("IllegalStateException", null),
            ),
            diagnostic.causes,
        )
        val text = diagnostic.toString()
        for (privateValue in
            listOf(
                "private-token",
                "private-image",
                "private-user",
                "private.invalid",
                "imageBase64",
            )) assertFalse(text.contains(privateValue))
    }

    @Test
    fun nestedDiagnosticKeepsExactReadStageWithoutReplacingItWithGenericMutation() {
        val original =
            ContentCoverDiagnostic(
                ContentCoverStage.READ_IMAGE,
                listOf(ContentCoverCause("StorageException", "-13021")),
            )
        val wrapped =
            ContentCoverException(
                ContentCoverFailure.UNCONFIRMED,
                ContentCoverException(ContentCoverFailure.DENIED, diagnostic = original),
            )
        assertEquals(original, contentCoverDiagnostic(ContentCoverStage.MUTATION, wrapped))
    }

    @Test
    fun uncertainModelExposesOnlySafeFailureCodesAndNeverAutomaticallyResends() = runTest {
        val source =
            FakeSource().apply {
                commits = false
                error = ContentCoverFailure.UNCONFIRMED
            }
        val model =
            ContentCoverViewModel(
                source,
                { PreparedContentCover(jpeg(), 160, 90) },
                { actor },
                gate,
                picker(),
            )
        model.show(target)
        advanceUntilIdle()
        assertTrue(model.beginPicker())
        model.pickerResult("content://synthetic/private")
        advanceUntilIdle()
        model.requestUpload()
        model.confirm()
        advanceUntilIdle()
        assertEquals(ContentCoverStage.MUTATION, model.state.value.diagnostic?.stage)
        assertEquals(
            listOf(ContentCoverCause("ContentCoverException", "UNCONFIRMED")),
            model.state.value.diagnostic?.causes,
        )
        assertFalse(model.state.value.canUpload)
        model.confirm()
        advanceUntilIdle()
        assertEquals(1, source.uploads)
    }
}
