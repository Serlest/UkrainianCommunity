package at.uac.android

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
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.ContentRepository
import at.uac.android.feature.browse.FirestoreContentSource
import at.uac.android.feature.browse.MemoryContentCache
import at.uac.android.feature.gallery.*
import at.uac.android.feature.organization.organizationScope
import at.uac.android.feature.safety.SafetyFailure
import at.uac.android.feature.safety.SafetyViewModel
import com.google.firebase.firestore.Source
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Actual Main → fresh management entry → native Photo Picker → protected confirmation → real
 * Storage/callable read-back.
 */
@RunWith(AndroidJUnit4::class)
class GalleryJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AccountDeletionFixtures.context

    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val auth
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val gallery
        get() = ViewModelProvider(compose.activity)[GalleryViewModel::class.java]

    private val safety
        get() = ViewModelProvider(compose.activity)[SafetyViewModel::class.java]

    private var phase = "setup"

    private fun account(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun detail(tag: String) =
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag(tag))

    private fun control(tag: String) {
        var scrollFailure: String? = null
        var lastVisibility: String? = null
        try {
            compose.waitUntil(30_000) {
                if (
                    !gallery.state.value.fresh ||
                        gallery.state.value.loading ||
                        gallery.state.value.busy
                )
                    false
                else
                    runCatching {
                            compose
                                .onNodeWithTag("gallery-list")
                                .performScrollToNode(hasTestTag(tag))
                            compose.onNodeWithTag(tag).isDisplayed().also { displayed ->
                                if (!displayed) lastVisibility = visibilityEvidence(tag)
                            }
                        }
                        .onFailure { scrollFailure = it.javaClass.simpleName }
                        .getOrDefault(false)
            }
        } catch (error: Throwable) {
            val beforeIdle = visibilityEvidence(tag)
            val afterIdle = runCatching {
                compose.waitForIdle()
                "displayed=${compose.onNodeWithTag(tag).isDisplayed()}, ${visibilityEvidence(tag)}"
            }
                .getOrElse { it.javaClass.simpleName }
            var ime: Pair<Boolean?, Int?> = null to null
            compose.runOnUiThread {
                val insets = ViewCompat.getRootWindowInsets(compose.activity.window.decorView)
                ime =
                    insets?.isVisible(WindowInsetsCompat.Type.ime()) to
                        insets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom
            }
            fun bounds(target: String): String = runCatching {
                val nodes = compose.onAllNodesWithTag(target).fetchSemanticsNodes()
                val rectangle = nodes.singleOrNull()?.boundsInRoot
                "count=${nodes.size}, bounds=$rectangle"
            }
                .getOrElse { it.javaClass.simpleName }
            val captionFocused = runCatching {
                compose
                    .onAllNodes(hasTestTag("gallery-caption") and isFocused())
                    .fetchSemanticsNodes()
                    .size == 1
            }
                .getOrDefault(false)
            throw AssertionError(
                "Gallery control=$tag, scrollFailure=$scrollFailure, ime=${ime.first}, " +
                    "imeBottom=${ime.second}, captionFocused=$captionFocused, " +
                    "list=[${bounds("gallery-list")}], target=[${bounds(tag)}], " +
                    "confirmation=[${bounds("gallery-confirm")}], leaving=[${bounds("gallery-leave-confirm")}], " +
                    "lastVisibility=[$lastVisibility], beforeIdle=[$beforeIdle], afterIdle=[$afterIdle]",
                error,
            )
        }
        compose.onNodeWithTag(tag).assertIsDisplayed()
    }

    /** Diagnostic mirrors the public observations used by Compose1.10.6 checkIsDisplayed. */
    private fun visibilityEvidence(tag: String): String = runCatching {
        val node =
            compose.onAllNodesWithTag(tag).fetchSemanticsNodes().singleOrNull()
                ?: return@runCatching "noUniqueNode"
        var result = "unobserved"
        compose.runOnUiThread {
            val placements = mutableListOf<Boolean>()
            var parent: androidx.compose.ui.layout.LayoutInfo? = node.layoutInfo
            while (parent != null && placements.size < 64) {
                placements += parent.isPlaced
                parent = parent.parentInfo
            }
            val root = node.root as? ViewRootForTest
            val global = android.graphics.Rect()
            val visible = root?.view?.getGlobalVisibleRect(global)
            val location = intArrayOf(0, 0)
            root?.view?.getLocationInWindow(location)
            val bounds = node.boundsInRoot
            val windowBounds = node.boundsInWindow
            val translated =
                bounds.translate(
                    androidx.compose.ui.geometry.Offset(
                        location[0].toFloat(),
                        location[1].toFloat(),
                    )
                )
            val rootBounds =
                androidx.compose.ui.geometry.Rect(
                    global.left.toFloat(),
                    global.top.toFloat(),
                    global.right.toFloat(),
                    global.bottom.toFloat(),
                )
            val espresso =
                root?.view?.let {
                    androidx.test.espresso.matcher.ViewMatchers.isDisplayed().matches(it)
                }
            result =
                "placements=$placements, ancestorCap=${parent != null}, " +
                    "rootExists=${root != null}, rootShown=${root?.view?.isShown}, espresso=$espresso, " +
                    "globalVisible=$visible, global=$global, location=${location.toList()}, " +
                    "boundsInWindow=$windowBounds, translated=$translated, " +
                    "intersects=${!translated.intersect(rootBounds).isEmpty}, " +
                    "pendingLayout=${root?.hasPendingMeasureOrLayout}"
        }
        result
    }
        .getOrElse { it.javaClass.simpleName }

    private fun settled() {
        compose.waitUntil(30_000) {
            gallery.state.value.let {
                it.visible && it.fresh && !it.loading && !it.locked && it.snapshot != null
            }
        }
        compose.waitForIdle()
    }

    // Check the actual legacy window option required for the API 26 host and IME insets.
    @Suppress("DEPRECATION")
    private fun assertTopActionRemainsFullyVisibleWithFocusedIme() {
        compose.onAllNodes(hasTestTag("gallery-caption") and isFocused()).assertCountEquals(1)
        val node = compose.onNodeWithTag("gallery-back").assertIsEnabled().fetchSemanticsNode()
        compose.runOnUiThread {
            val root = requireNotNull(node.root as? ViewRootForTest).view
            val insets = requireNotNull(ViewCompat.getRootWindowInsets(root))
            assertTrue(
                "The native IME must still be open before the actual back-button tap",
                insets.isVisible(WindowInsetsCompat.Type.ime()),
            )
            val adjust =
                compose.activity.window.attributes.softInputMode and
                    android.view.WindowManager.LayoutParams.SOFT_INPUT_MASK_ADJUST
            assertEquals(android.view.WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE, adjust)
            val visibleRoot = android.graphics.Rect()
            assertTrue(root.getGlobalVisibleRect(visibleRoot))
            val visibleWindow = android.graphics.Rect()
            root.getWindowVisibleDisplayFrame(visibleWindow)
            val location = intArrayOf(0, 0)
            root.getLocationOnScreen(location)
            val screen =
                node.boundsInRoot.translate(
                    androidx.compose.ui.geometry.Offset(
                        location[0].toFloat(),
                        location[1].toFloat(),
                    )
                )
            val left = maxOf(visibleRoot.left, visibleWindow.left).toFloat()
            val top = maxOf(visibleRoot.top, visibleWindow.top).toFloat()
            val right = minOf(visibleRoot.right, visibleWindow.right).toFloat()
            val bottom = minOf(visibleRoot.bottom, visibleWindow.bottom).toFloat()
            assertTrue(
                "The complete top action must be inside the actual visible native window",
                screen.width > 0f &&
                    screen.height > 0f &&
                    screen.left >= left &&
                    screen.top >= top &&
                    screen.right <= right &&
                    screen.bottom <= bottom,
            )
            println(
                "GALLERY_FOCUSED_IME_TOP_ACTION adjust=$adjust rootLocation=${location.toList()} " +
                    "action=$screen root=$visibleRoot window=$visibleWindow"
            )
        }
    }

    private fun choose(fixture: PhotoPickerFixtures.Fixture, expected: ByteArray) {
        val captured = auth.state.value.organizationScope()
        control("gallery-choose")
        compose.onNodeWithTag("gallery-choose").assertIsEnabled().performClick()
        PhotoPickerFixtures.selectOnlyPhoto(fixture)
        compose.waitUntil(25_000) {
            gallery.state.value.let {
                it.prepared != null && !it.preparing && !it.pickerOpen || it.error != null
            }
        }
        assertEquals(
            "Native picker must keep its exact authorized identity/revision",
            captured,
            auth.state.value.organizationScope(),
        )
        assertNull(gallery.state.value.error)
        assertNotNull(gallery.state.value.prepared)
        // Any wrong album/photo stops before a write; the screenshot alone is not proof of a
        // correct selection.
        assertArrayEquals(expected, gallery.state.value.prepared!!.bytes())
        settled()
        control("gallery-prepared")
        compose.onNodeWithTag("gallery-prepared").assertIsDisplayed()
    }

    @Test
    fun nativePickerRotationPublishDeleteAndLogoutPreserveExactGalleryBoundaries() {
        AccountDeletionFixtures.requireLocalAvd()
        assumeTrue(
            "Gallery Main proof requires guarded local Auth/Firestore/Storage/Functions",
            AccountDeletionFixtures.online(),
        )
        runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", "emulator")
            browse.navigate("profile", true)
        }
        val user = runBlocking {
            AuthEmulatorFixtures.seedLegalReference()
            AccountDeletionFixtures.create("deletion-gallery-journey")
        }
        val fixture = GalleryDeviceTest.Fixture(user)
        val journal = LocalGalleryJournal.get(context)
        var native: PhotoPickerFixtures.Fixture? = null
        var primary: Throwable? = null
        try {
            runBlocking {
                fixture.seed()
                AccountDeletionFixtures.patch(
                    "organizations/${fixture.organizationId}",
                    mapOf("moderationStatus" to "approved"),
                    merge = true,
                )
                // Exercise the actual public document decoder before the UI; an incomplete SDK-only
                // fixture is not a valid detail.
                val read =
                    ContentRepository(
                            FirestoreContentSource(LocalFirebase.firestore(context)),
                            MemoryContentCache(),
                        )
                        .detail(ContentKind.ORGANIZATIONS, fixture.organizationId)
                assertEquals(fixture.organizationId, read.value.id)
                assertNull(read.cachedAt)
            }
            native = PhotoPickerFixtures.create(context, "UAC-Gallery")
            val expected = runBlocking {
                LocalImagePreparation.prepareBytes(native.png, LocalImagePolicy.GALLERY_PHOTO)
            }
            runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
            compose.waitUntil(15_000) { auth.state.value.stage == AuthStage.GUEST }
            compose.openGuestLogin()
            account("auth-email").performTextReplacement(user.email)
            account("auth-password").performTextReplacement(AccountDeletionFixtures.PASSWORD)
            account("auth-login-submit").assertIsEnabled().performClick()
            compose.waitUntil(30_000) { auth.state.value.readyForActions }
            phase = "fresh approved organization entry without protected gallery prefetch"
            compose.runOnIdle { browse.navigate("organizations/${fixture.organizationId}") }
            compose.waitUntil(30_000) {
                browse.state.value.data.detail?.id == fixture.organizationId &&
                    !browse.state.value.data.loading &&
                    browse.state.value.data.cachedAt == null
            }
            compose.waitUntil(25_000) {
                safety.state.value.visibility.loaded || safety.state.value.error != null
            }
            if (safety.state.value.error == SafetyFailure.OFFLINE) {
                println("GALLERY_INITIAL_SAFETY_OFFLINE ${safety.state.value.readDiagnostic}")
                detail("safety-availability-retry")
                compose.onNodeWithTag("safety-availability-retry").performClick()
                compose.waitUntil(25_000) { !safety.state.value.loading }
            }
            assertTrue(safety.state.value.visibility.loaded)
            assertNull(safety.state.value.error)
            assertNull(gallery.state.value.snapshot)
            assertFalse(gallery.state.value.visible)
            detail("gallery-open")
            compose.onNodeWithTag("gallery-open").assertIsEnabled().performClick()
            settled()
            assertEquals(
                "profile/organizations/gallery/${fixture.organizationId}",
                browse.state.value.route,
            )
            assertEquals(0, gallery.state.value.snapshot!!.counter)
            assertTrue(gallery.state.value.pending.isEmpty())

            phase = "real native picker cancellation keeps exact session and writes nothing"
            val beforeCancel = auth.state.value.organizationScope()
            control("gallery-choose")
            compose.onNodeWithTag("gallery-choose").performClick()
            compose.waitUntil(10_000) { PhotoPickerFixtures.pickerVisible() }
            instrumentation.uiAutomation.executeShellCommand("input keyevent 4").close()
            compose.waitUntil(20_000) {
                !PhotoPickerFixtures.pickerVisible() && !gallery.state.value.pickerOpen
            }
            assertEquals(beforeCancel, auth.state.value.organizationScope())
            assertNull(gallery.state.value.prepared)
            settled()
            assertEquals(0, gallery.state.value.snapshot!!.counter)

            phase = "native exact photo and memory-only caption survive Activity recreation"
            choose(native, expected)
            control("gallery-caption")
            compose
                .onNodeWithTag("gallery-caption")
                .performTextReplacement("Gallery draft survives real recreation")
            compose.activityRule.scenario.recreate()
            compose.waitUntil(30_000) { auth.state.value.readyForActions }
            settled()
            assertEquals(user.uid, gallery.state.value.session?.uid)
            assertEquals(auth.state.value.organizationScope(), gallery.state.value.session)
            assertArrayEquals(expected, gallery.state.value.prepared!!.bytes())
            control("gallery-caption")
            compose
                .onNodeWithTag("gallery-caption")
                .assertTextContains("Gallery draft survives real recreation")

            phase = "explicit publish confirmation and actual server receipt"
            control("gallery-upload")
            compose.onNodeWithTag("gallery-upload").assertIsEnabled().performClick()
            val intent = (gallery.state.value.confirmation as GalleryConfirmation.Upload).intent
            fixture.remember(intent.target)
            assertTrue(runBlocking { journal.pending(user.uid).isEmpty() })
            assertEquals(
                0L,
                runBlocking {
                    LocalFirebase.firestore(context)
                        .document("organizations/${fixture.organizationId}")
                        .get(Source.SERVER)
                        .await()
                        .getLong("photoCount")
                },
            )
            compose.onNodeWithTag("gallery-confirm").assertIsDisplayed().performClick()
            compose.waitUntil(40_000) {
                gallery.state.value.let { !it.busy && (it.confirmed || it.error != null) }
            }
            assertNull(gallery.state.value.error)
            assertTrue(gallery.state.value.confirmed)
            settled()
            val saved = gallery.state.value.snapshot!!.photos.single()
            assertEquals(intent.target, saved.target)
            assertEquals(intent.caption, saved.caption)
            assertEquals(user.uid, saved.uploadedBy)
            assertNull(gallery.state.value.prepared)
            assertEquals("", gallery.state.value.caption)
            runBlocking {
                val db = LocalFirebase.firestore(context)
                val record = db.document(intent.target.document).get(Source.SERVER).await()
                assertEquals(intent.caption, record.getString("caption"))
                assertEquals(saved.imageUrl, record.getString("imageURL"))
                val organization =
                    db.document("organizations/${fixture.organizationId}")
                        .get(Source.SERVER)
                        .await()
                assertEquals(1L, organization.getLong("photoCount"))
                assertEquals("keep-this-synthetic-value", organization.getString("sentinel"))
                assertArrayEquals(
                    expected,
                    LocalStorage.instance(context)
                        .reference
                        .child(intent.target.path)
                        .getBytes(3_000_000)
                        .await(),
                )
                assertTrue(journal.pending(user.uid).isEmpty())
            }

            phase = "explicit permanent deletion verifies metadata and file absence"
            control("gallery-remove-${saved.target.photoId}")
            compose
                .onNodeWithTag("gallery-remove-${saved.target.photoId}")
                .assertIsEnabled()
                .performClick()
            assertTrue(
                runBlocking {
                    LocalFirebase.firestore(context)
                        .document(saved.target.document)
                        .get(Source.SERVER)
                        .await()
                        .exists()
                }
            )
            compose.onNodeWithTag("gallery-confirm").assertIsDisplayed().performClick()
            compose.waitUntil(40_000) {
                gallery.state.value.let { !it.busy && (it.confirmed || it.error != null) }
            }
            assertNull(gallery.state.value.error)
            settled()
            assertEquals(0, gallery.state.value.snapshot!!.counter)
            assertTrue(gallery.state.value.snapshot!!.photos.isEmpty())
            runBlocking {
                val source = localGallerySource(context) { auth.state.value.organizationScope() }
                val captured = auth.state.value.organizationScope()!!
                assertNull(source.photo(saved.target, captured))
                assertNull(source.blob(saved.target, captured))
                assertTrue(journal.pending(user.uid).isEmpty())
            }

            phase = "unsent local pixels and caption are cleared by actual logout"
            choose(native, expected)
            control("gallery-caption")
            compose
                .onNodeWithTag("gallery-caption")
                .performTextReplacement("Private unsent gallery draft")
            control("gallery-back")
            assertTopActionRemainsFullyVisibleWithFocusedIme()
            compose.onNodeWithTag("gallery-back").performClick()
            compose.onNodeWithTag("gallery-leave-confirm").assertIsDisplayed().performClick()
            compose.waitUntil(30_000) {
                browse.state.value.route == "organizations/${fixture.organizationId}" &&
                    !browse.state.value.data.loading
            }
            assertFalse(gallery.state.value.visible)
            assertNotNull(gallery.state.value.prepared)
            compose.waitUntil(10_000) { compose.onNodeWithTag("tab-profile").isDisplayed() }
            compose.onNodeWithTag("tab-profile").performClick()
            account("auth-signout").performClick()
            compose.waitUntil(25_000) {
                auth.state.value.stage == AuthStage.GUEST && gallery.state.value.session == null
            }
            assertNull(gallery.state.value.prepared)
            assertEquals("", gallery.state.value.caption)
            assertNull(gallery.state.value.snapshot)
            compose.onNodeWithText("Private unsent gallery draft").assertDoesNotExist()
        } catch (error: Throwable) {
            val state = gallery.state.value
            val navigation = browse.state.value
            val reported =
                AssertionError(
                    "Gallery journey phase=$phase, ready=${auth.state.value.readyForActions}, " +
                        "fresh=${state.fresh}, visible=${state.visible}, loading=${state.loading}, busy=${state.busy}, picker=${state.pickerOpen}, " +
                        "preparing=${state.preparing}, selected=${state.prepared != null}, error=${state.error}, pending=${state.pending.map { it.phase }}, " +
                        "photoCount=${state.snapshot?.counter}, nativePicker=${PhotoPickerFixtures.pickerVisible()}, " +
                        "browseMode=${navigation.mode}, browseLoading=${navigation.data.loading}, browseError=${navigation.data.error}, " +
                        "detailMatches=${navigation.data.detail?.id == fixture.organizationId}, cached=${navigation.data.cachedAt != null}, " +
                        "browseWarnings=${navigation.data.warnings}",
                    error,
                )
            primary = reported
            throw reported
        } finally {
            var failure = primary
            fun cleanup(action: () -> Unit) {
                try {
                    action()
                } catch (error: Throwable) {
                    if (failure == null) failure = error else failure?.addSuppressed(error)
                }
            }
            cleanup {
                if (PhotoPickerFixtures.pickerVisible())
                    instrumentation.uiAutomation.executeShellCommand("input keyevent 4").close()
            }
            native?.let { value -> cleanup { PhotoPickerFixtures.delete(context, value) } }
            cleanup {
                runBlocking {
                    // A failed mutation retains its journal and synthetic actor for a separate
                    // bounded diagnosis.
                    check(journal.pending(user.uid).isEmpty()) {
                        "Gallery journey pending action retained; no automatic fixture cleanup"
                    }
                    val sdk = LocalFirebase.auth(context)
                    if (sdk.currentUser?.uid != user.uid)
                        sdk.signInWithEmailAndPassword(user.email, AccountDeletionFixtures.PASSWORD)
                            .await()
                    fixture.cleanup()
                    AccountDeletionFixtures.clean(
                        user,
                        listOf(
                            "users/${user.uid}/recentViews/organization_${fixture.organizationId}"
                        ),
                    )
                    withContext(Dispatchers.Main) { auth.signOut() }.join()
                }
            }
            if (primary == null) failure?.let { throw it }
        }
    }
}
