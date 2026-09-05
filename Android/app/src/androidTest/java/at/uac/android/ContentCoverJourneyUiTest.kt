package at.uac.android

import android.graphics.Bitmap
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import at.uac.android.core.LocalStorage
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.contentmedia.*
import at.uac.android.feature.organization.*
import com.google.firebase.firestore.Source
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Main navigation → real system picker → explicit callable → exact object/doc → public local
 * renderer.
 */
@RunWith(AndroidJUnit4::class)
class ContentCoverJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val context
        get() = instrumentation.targetContext

    private val store
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val hub
        get() = ViewModelProvider(compose.activity)[OrganizationViewModel::class.java]

    private val management
        get() = ViewModelProvider(compose.activity)[OrganizationManagementViewModel::class.java]

    private val authoring
        get() = ViewModelProvider(compose.activity)[AuthoringViewModel::class.java]

    private val media
        get() = ViewModelProvider(compose.activity)[ContentCoverViewModel::class.java]

    private var phase = "setup"
    private val removalTrace = ArrayDeque<String>()
    private val traceStarted = System.nanoTime()

    private fun control(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun confirmRemoval(target: ContentCoverTarget) {
        // Observe one actual request tap. A server/watch refresh is allowed to revoke its intent;
        // never retry that tap or call the ViewModel action to make this diagnostic pass.
        val observer =
            CoroutineScope(Dispatchers.Main.immediate).launch(start = CoroutineStart.UNDISPATCHED) {
                media.state
                    .map { removalFlags(it, target) }
                    .distinctUntilChanged()
                    .collect {
                        recordRemoval("state: $it")
                    }
            }
        try {
            traceRemoval("before-scroll", target)
            // A listener refresh may finish between ready() and scrolling, changing the height
            // of the image above this control. Wait for actual readiness AND visible geometry;
            // only the read-only scroll can repeat, never the request/confirmation taps below.
            compose.waitUntil(20_000) {
                val state = media.state.value
                if (
                    state.target != target ||
                        state.session != store.state.value.organizationScope() ||
                        !state.canRemove
                )
                    false
                else {
                    val candidate = compose.onNodeWithTag("content-cover-remove")
                    candidate.performScrollTo()
                    candidate.isDisplayed() && media.state.value.canRemove
                }
            }
            val remove = control("content-cover-remove").assertIsDisplayed().assertIsEnabled()
            traceRemoval("before-single-pointer-click", target)
            remove.performClick()
            traceRemoval("after-single-pointer-click", target)
            compose.waitForIdle()
            traceRemoval("after-idle", target)
            compose
                .onNodeWithTag("content-cover-confirm")
                .assertIsDisplayed()
                .assertIsEnabled()
                .performClick()
        } catch (failure: Throwable) {
            traceRemoval("failure", target)
            runCatching { screenshot("remove-confirm-failure") }
            throw failure
        } finally {
            runBlocking { observer.cancelAndJoin() }
        }
    }

    private fun removalFlags(state: ContentCoverState, target: ContentCoverTarget): String =
        "sameTarget=${state.target == target}, sameScope=${state.session == store.state.value.organizationScope()}, " +
            "ready=${store.state.value.readyForActions}, visible=${state.visible}, fresh=${state.fresh}, " +
            "loading=${state.loading}, busy=${state.busy}, locked=${state.locked}, actionable=${state.actionable}, " +
            "canRemove=${state.canRemove}, removable=${state.snapshot?.removable}, " +
            "imagePresent=${state.snapshot?.imageUrl != null}, prepared=${state.prepared != null}, " +
            "confirmation=${state.confirmation != null}, removeIntent=${state.confirmation is ContentCoverIntent.Remove}, " +
            "uncertain=${state.uncertain != null}, confirmed=${state.confirmed}, error=${state.error}"

    private fun recordRemoval(value: String) {
        val entry = "${(System.nanoTime() - traceStarted) / 1_000_000}ms: ${value.take(4_000)}"
        synchronized(removalTrace) {
            if (removalTrace.size == 40) removalTrace.removeFirst()
            removalTrace.addLast(entry)
        }
        println("content-cover-remove-trace: $entry")
    }

    private fun traceRemoval(stage: String, target: ContentCoverTarget) {
        recordRemoval(
            "$stage: ${removalFlags(media.state.value, target)}; " +
                "remove=[${removalGeometry("content-cover-remove")}]; " +
                "confirm=[${removalGeometry("content-cover-confirm")}]"
        )
    }

    private fun removalGeometry(tag: String): String = runCatching {
        val nodes = compose.onAllNodesWithTag(tag).fetchSemanticsNodes()
        val node = nodes.singleOrNull() ?: return@runCatching "count=${nodes.size}"
        var evidence = "unobserved"
        compose.runOnUiThread {
            val placements = mutableListOf<Boolean>()
            var parent: androidx.compose.ui.layout.LayoutInfo? = node.layoutInfo
            while (parent != null && placements.size < 64) {
                placements += parent.isPlaced
                parent = parent.parentInfo
            }
            val root = node.root as? ViewRootForTest
            val view = root?.view
            val global = android.graphics.Rect()
            val shown = view?.getGlobalVisibleRect(global)
            val frame = android.graphics.Rect()
            view?.getWindowVisibleDisplayFrame(frame)
            val location = intArrayOf(0, 0)
            view?.getLocationInWindow(location)
            val insets = view?.let(ViewCompat::getRootWindowInsets)
            val main = compose.activity.window.decorView
            evidence =
                "count=1, placements=$placements, ancestorCap=${parent != null}, " +
                    "shown=${view?.isShown}, attached=${view?.isAttachedToWindow}, globalVisible=$shown, " +
                    "global=$global, frame=$frame, location=${location.toList()}, " +
                    "boundsRoot=${node.boundsInRoot}, boundsWindow=${node.boundsInWindow}, " +
                    "pendingLayout=${root?.hasPendingMeasureOrLayout}, " +
                    "ime=${insets?.isVisible(WindowInsetsCompat.Type.ime())}, " +
                    "imeBottom=${insets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom}, " +
                    "sameWindow=${view?.windowToken == main.windowToken}"
        }
        evidence
    }
        .getOrElse { "geometryFailure=${it.javaClass.simpleName}" }

    private fun ready(target: ContentCoverTarget) {
        compose.waitUntil(20_000) { media.state.value.let { it.target == target && it.actionable } }
        compose.waitForIdle()
    }

    private fun authoringReady(target: ContentCoverTarget) {
        compose.waitUntil(20_000) {
            authoring.state.value.let {
                it.organizationId == target.organizationId &&
                    it.kind == target.kind &&
                    it.actionable &&
                    it.hub?.page?.items?.any { item -> item.id == target.contentId } == true
            }
        }
    }

    private fun pick(
        gallery: PhotoPickerFixtures.Fixture,
        captured: OrganizationSession,
        expected: ByteArray,
    ) {
        control("content-cover-choose").assertIsDisplayed().assertIsEnabled().performClick()
        PhotoPickerFixtures.selectOnlyPhoto(gallery)
        compose.waitUntil(20_000) {
            media.state.value.let {
                it.prepared != null && !it.preparing ||
                    it.error != null ||
                    store.state.value.organizationScope() != captured
            }
        }
        assertNull("Native preparation must succeed", media.state.value.error)
        assertEquals(
            "Native callback retains its exact authorized identity and revision",
            captured,
            store.state.value.organizationScope(),
        )
        val prepared =
            requireNotNull(media.state.value.prepared) {
                "Native picker returned no prepared cover"
            }
        // Fail closed before any upload if a system picker ever selected a different image.
        assertArrayEquals(expected, prepared.jpeg)
        assertEquals(240, prepared.width)
        assertEquals(135, prepared.height)
    }

    @Test
    fun mainSystemPickerConfirmsCoverPublicRenderingAndNewsReferenceRemoval() {
        runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        val args = InstrumentationRegistry.getArguments()
        val online =
            args.getString("expectEmulator") == "true" &&
                args.getString("expectFunctions") == "true"
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", if (online) "emulator" else "synthetic")
            browse.navigate("profile", true)
        }
        compose.waitUntil(15_000) { store.state.value.stage == AuthStage.GUEST }
        if (!online) {
            control("guest-sign-in").assertIsDisplayed()
            compose.onNodeWithTag("account-open-organizations").assertDoesNotExist()
            assertNull(media.state.value.prepared)
            assertNull(media.state.value.snapshot)
            return
        }
        val fixture = ContentCoverFixtures("author4ccoverjourney-${UUID.randomUUID()}")
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        var gallery: PhotoPickerFixtures.Fixture? = null
        var failure: Throwable? = null
        try {
            val owner = runBlocking {
                AuthEmulatorFixtures.seedLegalReference()
                fixture.account("owner").also {
                    fixture.organization(it)
                    auth.signOut()
                }
            }
            gallery = PhotoPickerFixtures.create(context, "UAC-Cover")
            val expected = runBlocking {
                LocalImagePreparation.prepareBytes(gallery.png, LocalImagePolicy.CONTENT_COVER_16_9)
            }
            phase = "real verified UI sign-in and separately committed text"
            compose.openGuestLogin()
            control("auth-email").performTextReplacement(owner.email)
            control("auth-password").performTextReplacement(fixture.password)
            control("auth-login-submit").assertIsEnabled().performClick()
            compose.waitUntil(20_000) { store.state.value.readyForActions }
            val captured = requireNotNull(store.state.value.organizationScope())
            val target = fixture.register(ContentKind.NEWS)
            val title = "Synthetic Native Cover Main"
            val original = runBlocking {
                val source = localAuthoringSource(context)
                val organization =
                    requireNotNull(source.organization(target.organizationId, captured))
                val draft =
                    AuthoringContract.newDraft(target.kind, organization)
                        .copy(
                            id = target.contentId,
                            title = title,
                            summary = "Synthetic cover journey summary",
                            body = "Synthetic local text saved before its separate cover action.",
                        )
                AuthoringRepository(
                        source,
                        { store.state.value.organizationScope() },
                        AuthOrganizationMutationGate(store),
                    )
                    .submit(AuthoringContract.submission(draft, organization, captured, null))
                db.document("news/${target.contentId}").get(Source.SERVER).await()
            }
            assertEquals("approved", original.getString("moderationStatus"))
            assertFalse(original.contains("imageURL"))
            control("account-open-organizations").assertIsEnabled().performClick()
            compose.waitUntil(20_000) {
                !hub.state.value.loading &&
                    hub.state.value.hub?.managed?.any { it.id == target.organizationId } == true
            }
            control("organization-manage-${target.organizationId}").assertIsEnabled().performClick()
            compose.waitUntil(20_000) {
                management.state.value.let {
                    it.organizationId == target.organizationId && it.actionable
                }
            }
            control("organization-authoring-news").assertIsEnabled().performClick()
            authoringReady(target)
            control("authoring-cover-${target.contentId}").assertIsEnabled().performClick()
            ready(target)
            assertEquals(
                "profile/organizations/cover/${target.organizationId}/news/${target.contentId}",
                browse.state.value.route,
            )

            phase = "real native picker cancellation changes neither session nor object"
            recordRemoval(
                "gallery-before-picker: ${PhotoPickerFixtures.publishedState(context, gallery)}"
            )
            control("content-cover-choose").assertIsDisplayed().assertIsEnabled().performClick()
            compose.waitUntil(10_000) { PhotoPickerFixtures.focusedPickerWindow() }
            PhotoPickerFixtures.cancelFocusedPickerOnce()
            compose.waitUntil(15_000) {
                !media.state.value.pickerOpen && !PhotoPickerFixtures.pickerVisible()
            }
            ready(target)
            assertEquals(captured, store.state.value.organizationScope())
            assertNull(media.state.value.prepared)
            assertEquals(404, runBlocking { fixture.storageStatus(target, "GET") })

            phase = "real exact album selection and central16x9 preview before any upload"
            recordRemoval(
                "gallery-before-selection: ${PhotoPickerFixtures.publishedState(context, gallery)}"
            )
            pick(gallery, captured, expected)
            ready(target)
            control("content-cover-preview").assertIsDisplayed()
            assertEquals(404, runBlocking { fixture.storageStatus(target, "GET") })
            screenshot("preview")
            phase =
                "explicit confirmation actual callable and complete canonical file/document read-back"
            control("content-cover-upload").assertIsEnabled().performClick()
            compose
                .onNodeWithTag("content-cover-confirm")
                .assertIsDisplayed()
                .assertIsEnabled()
                .performClick()
            compose.waitUntil(45_000) {
                media.state.value.let { it.confirmed && !it.busy || it.error != null }
            }
            assertNull(media.state.value.error)
            assertTrue(media.state.value.confirmed)
            ready(target)
            val receiptUrl = requireNotNull(media.state.value.snapshot?.imageUrl)
            assertTrue(receiptUrl.startsWith("https://firebasestorage.googleapis.com/"))
            assertNotNull(ContentCoverContract.token(receiptUrl, target))
            assertArrayEquals(expected, requireNotNull(media.state.value.asset).bytes)
            val uploaded = runBlocking {
                assertArrayEquals(
                    expected,
                    LocalStorage.instance(context)
                        .reference
                        .child(target.path)
                        .getBytes(3_000_000)
                        .await(),
                )
                db.document("news/${target.contentId}").get(Source.SERVER).await()
            }
            assertEquals(receiptUrl, uploaded.getString("imageURL"))
            assertEquals(title, uploaded.getString("title"))
            assertEquals(original.getTimestamp("createdAt"), uploaded.getTimestamp("createdAt"))
            assertEquals(owner.uid, uploaded.getString("authorId"))
            assertEquals(0L, uploaded.getLong("likeCount"))
            assertEquals(0L, uploaded.getLong("commentCount"))
            control("content-cover-confirmed").assertIsDisplayed()

            phase =
                "fresh public detail renders canonical server URL through local-only media adapter"
            compose
                .onNodeWithText("Zurück", useUnmergedTree = true)
                .performScrollTo()
                .assertIsEnabled()
                .performClick()
            authoringReady(target)
            assertEquals(
                receiptUrl,
                authoring.state.value.hub
                    ?.page
                    ?.items
                    ?.single { it.id == target.contentId }
                    ?.fields
                    ?.get("imageURL"),
            )
            compose
                .onNode(
                    hasText("Ansehen") and
                        hasAnyAncestor(hasTestTag("authoring-item-${target.contentId}"))
                )
                .performScrollTo()
                .assertIsDisplayed()
                .assertIsEnabled()
                .performClick()
            compose.waitUntil(20_000) {
                browse.state.value.let {
                    val detail = it.data.detail
                    it.route == "news/${target.contentId}" &&
                        !it.data.loading &&
                        it.data.cachedAt == null &&
                        detail != null &&
                        detail.id == target.contentId &&
                        detail.fields["imageURL"] == receiptUrl
                }
            }
            val renderedHero =
                hasTestTag("loaded-media") and
                    hasContentDescription(title) and
                    hasAnyAncestor(hasTestTag("detail-content"))
            compose.waitUntil(15_000) {
                compose.onAllNodes(renderedHero).fetchSemanticsNodes().size == 1
            }
            compose.onNode(renderedHero).performScrollTo().assertIsDisplayed()
            screenshot("public-confirmed")

            phase =
                "News reference removal is separately confirmed and leaves object text and counters intact"
            compose.onNodeWithTag("back").assertIsEnabled().performClick()
            authoringReady(target)
            control("authoring-cover-${target.contentId}").assertIsEnabled().performClick()
            ready(target)
            confirmRemoval(target)
            compose.waitUntil(25_000) {
                media.state.value.let {
                    it.confirmed && it.snapshot?.imageUrl == null && !it.busy || it.error != null
                }
            }
            assertNull(media.state.value.error)
            assertTrue(media.state.value.confirmed)
            ready(target)
            val removed = runBlocking {
                assertArrayEquals(
                    expected,
                    LocalStorage.instance(context)
                        .reference
                        .child(target.path)
                        .getBytes(3_000_000)
                        .await(),
                )
                assertEquals(200, fixture.storageStatus(target, "GET"))
                db.document("news/${target.contentId}").get(Source.SERVER).await()
            }
            assertFalse(removed.contains("imageURL"))
            assertEquals(title, removed.getString("title"))
            assertEquals(owner.uid, removed.getString("authorId"))
            assertEquals(0L, removed.getLong("likeCount"))
            assertEquals(0L, removed.getLong("commentCount"))
            control("content-cover-confirmed").assertIsDisplayed()

            phase = "sign-out clears a real prepared but unsent cover without a second upload"
            pick(gallery, requireNotNull(store.state.value.organizationScope()), expected)
            assertNotNull(media.state.value.prepared)
            runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
            compose.waitUntil(15_000) {
                store.state.value.stage == AuthStage.GUEST &&
                    media.state.value.let {
                        it.session == null &&
                            it.prepared == null &&
                            it.snapshot == null &&
                            it.asset == null &&
                            it.uncertain == null
                    }
            }
            compose.onNodeWithTag("content-cover-preview").assertDoesNotExist()
            assertEquals(200, runBlocking { fixture.storageStatus(target, "GET") })
        } catch (error: Throwable) {
            val state = media.state.value
            gallery?.let {
                recordRemoval(
                    "gallery-on-failure: ${runCatching { PhotoPickerFixtures.publishedState(context, it) }.getOrElse { "inspection-failed:${it.javaClass.simpleName}" }}"
                )
            }
            val paired = runCatching {
                pairedReadBack(state)
            }
                .getOrElse {
                    "pairedReadFailure=${contentCoverDiagnostic(ContentCoverStage.READ_DOCUMENT, it)}"
                }
            runCatching { compose.waitForIdle() }
            runCatching { screenshot("failure") }
            val reported =
                AssertionError(
                    "Content cover Main journey phase=$phase, ready=${store.state.value.readyForActions}, " +
                        "sameSession=${state.session == store.state.value.organizationScope()}, fresh=${state.fresh}, busy=${state.busy}, loading=${state.loading}, " +
                        "pickerOpen=${state.pickerOpen}, preparing=${state.preparing}, selected=${state.prepared != null}, failure=${state.error}, " +
                        "imageFailure=${state.imageError}, diagnostic=${state.diagnostic}, $paired, fontScale=${compose.activity.resources.configuration.fontScale}\n" +
                        "removalTrace=${synchronized(removalTrace) { removalTrace.joinToString("\n") }}\n${PhotoPickerFixtures.diagnosticState()}",
                    error,
                )
            failure = reported
            throw reported
        } finally {
            if (PhotoPickerFixtures.pickerVisible())
                instrumentation.uiAutomation.executeShellCommand("input keyevent 4").close()
            gallery?.let { PhotoPickerFixtures.delete(context, it) }
            runBlocking {
                withContext(Dispatchers.Main) { store.signOut() }.join()
                fixture.cleanup(failure)
            }
        }
    }

    /**
     * Only after a failed upload, before fixture cleanup. No callables, writes, retries, tokens or
     * payload logging.
     */
    private fun pairedReadBack(failed: ContentCoverState): String {
        val intent =
            failed.uncertain as? ContentCoverIntent.Upload
                ?: return "pairedRead=not-an-uncertain-upload"
        val actor = requireNotNull(store.state.value.organizationScope())
        check(actor == failed.session)
        return runBlocking {
            withTimeout(20_000) {
                val target = intent.snapshot.target
                val db = LocalFirebase.firestore(context)
                // The UI maintains a listener for the same bounded query. Compare it to an
                // independent server transaction.
                val query = localContentCoverSource(context).snapshot(target, actor)
                val reference = db.document("${target.kind.collection}/${target.contentId}")
                val direct = reference.get(Source.SERVER).await()
                val transaction =
                    db.runTransaction { read ->
                            val organization =
                                read.get(db.document("organizations/${target.organizationId}"))
                            val document = read.get(reference)
                            // No transaction.set/update/delete: this is a read fence, not a second
                            // mutation.
                            organization to document
                        }
                        .await()
                val objectReference = LocalStorage.instance(context).reference.child(target.path)
                val metadata = objectReference.metadata.await()
                val downloadToken =
                    ContentCoverContract.token(
                        objectReference.downloadUrl.await().toString(),
                        target,
                    )
                val objectBytes = objectReference.getBytes(3_000_000).await()
                check(actor == store.state.value.organizationScope())
                val transactionUrl = transaction.second.getString("imageURL")
                "pairedRead=(queryImagePresent=${query.imageUrl != null}, directImagePresent=${direct.getString("imageURL") != null}, " +
                    "transactionExists=${transaction.second.exists()}, transactionImagePresent=${transactionUrl != null}, " +
                    "queryEqualsTransaction=${query.imageUrl == transactionUrl}, directEqualsTransaction=${direct.getString("imageURL") == transactionUrl}, " +
                    "directFromCache=${direct.metadata.isFromCache}, directPendingWrites=${direct.metadata.hasPendingWrites()}, " +
                    "transactionOwnerMatches=${transaction.first.getString("ownerId") == actor.uid}, " +
                    "transactionContentOrgMatches=${transaction.second.getString("organizationId") == target.organizationId}, " +
                    "transactionTokenMatchesObject=${transactionUrl?.let { ContentCoverContract.token(it, target) } == downloadToken}, " +
                    "objectBytesMatch=${intent.photo.matches(objectBytes)}, objectSizeMatches=${metadata.sizeBytes == intent.photo.byteCount.toLong()})"
            }
        }
    }

    private fun screenshot(name: String) {
        val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: return
        try {
            File(context.externalCacheDir, "content-cover-journey-$name.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        } finally {
            bitmap.recycle()
        }
    }
}
