package at.uac.android

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleCallback
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
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
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real Main navigation and form input, actual Auth/Firestore transactions, no fake ready session.
 */
@RunWith(AndroidJUnit4::class)
class AuthoringJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val hub
        get() = ViewModelProvider(compose.activity)[OrganizationViewModel::class.java]

    private val management
        get() = ViewModelProvider(compose.activity)[OrganizationManagementViewModel::class.java]

    private val authoring
        get() = ViewModelProvider(compose.activity)[AuthoringViewModel::class.java]

    private val authStore
        get() = LocalAuthSession.get(context)

    private var phase = "setup"
    private val confirmationTrace = ArrayDeque<String>()
    private val traceStarted = System.nanoTime()

    private fun control(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun section(index: Int) =
        control("authoring-section-$index")
            .assertIsDisplayed()
            .assertIsEnabled()
            .performClick()
            .assertIsSelected()

    private fun ready(id: String, kind: ContentKind) {
        compose.waitUntil(20_000) {
            authoring.state.value.let {
                it.organizationId == id && it.kind == kind && it.actionable
            }
        }
        compose.waitForIdle()
    }

    private fun text(title: String) {
        control("authoring-title").assertIsEnabled().performTextReplacement(title)
        control("authoring-summary")
            .performTextReplacement("Synthetic summary from the actual Android form")
        control("authoring-body")
            .performTextReplacement(
                "Only synthetic local authoring text. No production publication."
            )
    }

    private fun confirm(id: String) {
        // A confirmation can also be invalidated by a fresh read. Observe only redacted state
        // transitions to distinguish that from a pointer landing during a native IME/scroll change.
        val observer =
            CoroutineScope(Dispatchers.Main.immediate).launch(start = CoroutineStart.UNDISPATCHED) {
                authoring.state.map(::confirmationFlags).distinctUntilChanged().collect {
                    recordConfirmationTrace("state: $it")
                }
            }
        try {
            traceConfirmation("before-scroll")
            val submit = control("authoring-submit").assertIsEnabled()
            traceConfirmation("before-single-pointer-click")
            submit.performClick()
            traceConfirmation("after-single-pointer-click")
            compose.waitForIdle()
            traceConfirmation("after-idle")
            compose
                .onNodeWithTag("authoring-confirm")
                .assertIsDisplayed()
                .assertIsEnabled()
                .performClick()
            compose.waitUntil(25_000) {
                authoring.state.value.let { it.confirmed?.id == id && !it.busy }
            }
        } catch (error: Throwable) {
            traceConfirmation("failure")
            throw error
        } finally {
            runBlocking { observer.cancelAndJoin() }
        }
    }

    private fun confirmationFlags(state: AuthoringState): String =
        "confirmation=${state.confirmation != null}, preview=${state.preview}, " +
            "fresh=${state.fresh}, loading=${state.loading}, busy=${state.busy}, " +
            "writable=${state.draftWritable}, visible=${state.visible}, " +
            "sameScope=${state.session == authStore.state.value.organizationScope()}, " +
            "failure=${state.error}, invalidField=${state.invalidField}"

    private fun recordConfirmationTrace(value: String) {
        val bounded = "${(System.nanoTime() - traceStarted) / 1_000_000}ms: ${value.take(4_000)}"
        synchronized(confirmationTrace) {
            if (confirmationTrace.size == 40) confirmationTrace.removeFirst()
            confirmationTrace.addLast(bounded)
        }
        // Synthetic-only test evidence: no titles, identifiers, document paths or account data.
        println("authoring-confirm-trace: $bounded")
    }

    private fun traceConfirmation(stage: String) {
        val flags = confirmationFlags(authoring.state.value)
        recordConfirmationTrace(
            "$stage: $flags; submit=[${confirmationGeometry("authoring-submit")}]; " +
                "dialog=[${confirmationGeometry("authoring-confirm")}]"
        )
    }

    /**
     * Read-only public geometry used by Compose visibility checks; never scrolls or retries a tap.
     */
    private fun confirmationGeometry(tag: String): String = runCatching {
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
            val globallyVisible = view?.getGlobalVisibleRect(global)
            val frame = android.graphics.Rect()
            view?.getWindowVisibleDisplayFrame(frame)
            val location = intArrayOf(0, 0)
            view?.getLocationInWindow(location)
            val insets = view?.let(ViewCompat::getRootWindowInsets)
            val activityWindow = compose.activity.window
            val mainInsets = ViewCompat.getRootWindowInsets(activityWindow.decorView)
            evidence =
                "count=1, placements=$placements, ancestorCap=${parent != null}, " +
                    "shown=${view?.isShown}, attached=${view?.isAttachedToWindow}, " +
                    "windowFocus=${view?.hasWindowFocus()}, viewFocus=${view?.hasFocus()}, " +
                    "globalVisible=$globallyVisible, global=$global, frame=$frame, " +
                    "location=${location.toList()}, boundsRoot=${node.boundsInRoot}, " +
                    "boundsWindow=${node.boundsInWindow}, pendingLayout=${root?.hasPendingMeasureOrLayout}, " +
                    "ime=${insets?.isVisible(WindowInsetsCompat.Type.ime())}, " +
                    "imeBottom=${insets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom}, " +
                    "mainIme=${mainInsets?.isVisible(WindowInsetsCompat.Type.ime())}, " +
                    "mainImeBottom=${mainInsets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom}, " +
                    "sameWindow=${view?.windowToken == activityWindow.decorView.windowToken}"
        }
        evidence
    }
        .getOrElse { "diagnosticFailure=${it.javaClass.simpleName}" }

    @Test
    fun mainCreatesNewsSubmitsAustriaCreatesEventAndRevalidatesUnsentDraft() {
        val trackedHost = compose.activity
        val originalLaunchIntent = Intent(trackedHost.intent)
        runBlocking { withContext(Dispatchers.Main) { authStore.signOut() }.join() }
        val online = InstrumentationRegistry.getArguments().getString("expectEmulator") == "true"
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", if (online) "emulator" else "synthetic")
            browse.navigate("profile", true)
        }
        compose.waitUntil(15_000) { authStore.state.value.stage == AuthStage.GUEST }
        if (!online) {
            control("guest-sign-in").assertIsDisplayed()
            compose.onNodeWithTag("account-open-organizations").assertDoesNotExist()
            assertNull(authoring.state.value.draft)
            assertNull(authoring.state.value.hub)
            return
        }
        val prefix = "author4cjourney-${UUID.randomUUID()}"
        val fixture = AuthoringFixtures(prefix)
        val orgId = fixture.organizationId
        val password = "Synthetic-authoring-journey-only!"
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        var ownerUid = ""
        var targetUid = ""
        var ownerEmail = ""
        var failure: Throwable? = null
        try {
            runBlocking {
                AuthEmulatorFixtures.seedLegalReference()
                for (label in listOf("owner", "target")) {
                    auth.signOut()
                    val email = "$prefix-$label@example.invalid"
                    val user = auth.createUserWithEmailAndPassword(email, password).await().user!!
                    fixture.uids += user.uid
                    db.document("users/${user.uid}")
                        .set(
                            registeredProfileFields(
                                user.uid,
                                AuthRegistration(
                                    email,
                                    "Synthetic $label",
                                    "wien",
                                    acceptedTerms = true,
                                    acceptedPrivacy = true,
                                    minimumAgeConfirmed = true,
                                ),
                                FieldValue.serverTimestamp(),
                            )
                        )
                        .await()
                    user.sendEmailVerification().await()
                    auth
                        .applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL"))
                        .await()
                    user.reload().await()
                    user.getIdToken(true).await()
                    assertTrue(user.isEmailVerified)
                    fixture.seed(
                        "publicProfiles/${user.uid}",
                        mapOf(
                            "id" to user.uid,
                            "displayName" to "Public $label",
                            "city" to "Wien",
                            "updatedAt" to Instant.now(),
                        ),
                    )
                    if (label == "owner") {
                        ownerUid = user.uid
                        ownerEmail = email
                    } else targetUid = user.uid
                }
                auth.signOut()
                val basics =
                    OrganizationDraft(
                        orgId,
                        "Synthetic Main Authoring",
                        "An approved synthetic local community",
                        region = "wien",
                        city = "Wien",
                    )
                fixture.seed(
                    "organizations/$orgId",
                    OrganizationContract.create(
                        basics,
                        OrganizationSession(ownerUid, 1, true, "Synthetic owner", "user"),
                        Instant.now(),
                    ) + mapOf("moderationStatus" to "approved", "ownerId" to ownerUid),
                )
            }
            phase = "real verified sign-in and management route"
            compose.openGuestLogin()
            control("auth-email").performTextReplacement(ownerEmail)
            control("auth-password").performTextReplacement(password)
            control("auth-login-submit").assertIsEnabled().performClick()
            compose.waitUntil(20_000) { authStore.state.value.readyForActions }
            control("account-open-organizations").assertIsEnabled().performClick()
            compose.waitUntil(20_000) {
                !hub.state.value.loading &&
                    hub.state.value.hub?.managed?.any { it.id == orgId } == true
            }
            control("organization-manage-$orgId").assertIsEnabled().performClick()
            compose.waitUntil(20_000) {
                management.state.value.let {
                    it.organizationId == orgId && it.fresh && !it.loading && !it.busy
                }
            }
            control("organization-authoring-news").assertIsEnabled().performClick()
            ready(orgId, ContentKind.NEWS)
            assertEquals("profile/organizations/author/$orgId/news", browse.state.value.route)

            phase = "news form and explicit local preview before any write"
            control("authoring-create").assertIsEnabled().performClick()
            text("Synthetic News Main Original")
            control("authoring-de-title").performTextReplacement("Synthetische Nachricht Main")
            val newsId = requireNotNull(authoring.state.value.draft).id
            fixture.ownContent(ContentKind.NEWS, newsId)
            control("authoring-preview").assertIsEnabled().performClick()
            compose.onNodeWithText("Lokale Vorschau · nicht gesendet").assertIsDisplayed()
            compose.onNodeWithText("Zurück zum Formular").performScrollTo().performClick()
            assertNull(
                runBlocking {
                    localAuthoringSource(context)
                        .find(
                            orgId,
                            ContentKind.NEWS,
                            newsId,
                            requireNotNull(authStore.state.value.organizationScope()),
                        )
                }
            )
            phase = "news confirmed actual transaction and exact readback"
            confirm(newsId)
            ready(orgId, ContentKind.NEWS)
            val news = runBlocking { db.document("news/$newsId").get(Source.SERVER).await() }
            assertEquals("Synthetic News Main Original", news.getString("title"))
            assertEquals("approved", news.getString("moderationStatus"))
            assertEquals(ownerUid, news.getString("authorId"))
            assertEquals(orgId, news.getString("organizationId"))
            assertEquals(0L, news.getLong("likeCount"))
            assertEquals(0L, news.getLong("commentCount"))
            assertEquals("Synthetische Nachricht Main", news.getString("localizations.de.title"))
            screenshot("news-confirmed")

            phase = "approved news edit to Austria explicitly enters review"
            control("authoring-edit-$newsId").assertIsEnabled().performClick()
            compose.waitUntil(20_000) {
                authoring.state.value.let { it.base?.id == newsId && it.draftWritable }
            }
            control("authoring-title")
                .performTextReplacement("Synthetic News Main Austria Revision")
            section(1)
            compose
                .onNodeWithText("Reichweite: Bundesland der Organisation")
                .performScrollTo()
                .assertIsEnabled()
                .performClick()
            compose
                .onNodeWithText("Ganz Österreich · eventuell Prüfung")
                .performScrollTo()
                .performClick()
            control("authoring-submit").assertTextContains("Zur Prüfung einreichen")
            confirm(newsId)
            ready(orgId, ContentKind.NEWS)
            val review = runBlocking { db.document("news/$newsId").get(Source.SERVER).await() }
            assertEquals("pendingReview", review.getString("moderationStatus"))
            assertEquals("austria", review.getString("regionScope"))
            assertEquals("Synthetic News Main Austria Revision", review.getString("title"))
            assertEquals(news.getTimestamp("createdAt"), review.getTimestamp("createdAt"))
            assertEquals(AuthoringStatus.REVIEW, authoring.state.value.status)
            assertEquals(listOf(newsId), authoring.state.value.hub?.page?.items?.map { it.id })

            phase = "management event route creates a distinct event form"
            compose
                .onNodeWithText("Zurück", useUnmergedTree = true)
                .performScrollTo()
                .performClick()
            compose.waitUntil(20_000) {
                management.state.value.let { it.fresh && !it.loading && !it.busy } &&
                    browse.state.value.route == "profile/organizations/manage/$orgId"
            }
            control("organization-authoring-events").assertIsEnabled().performClick()
            ready(orgId, ContentKind.EVENTS)
            assertEquals("profile/organizations/author/$orgId/events", browse.state.value.route)
            control("authoring-create").assertIsEnabled().performClick()
            text("Synthetic Event Main")
            assertEquals(ContentKind.EVENTS, authoring.state.value.draft?.kind)
            val eventId = requireNotNull(authoring.state.value.draft).id
            fixture.ownContent(ContentKind.EVENTS, eventId)
            section(2)
            control("authoring-venue").performTextReplacement("Synthetic Main Hall")
            control("authoring-address").performTextReplacement("Synthetic Main Address")
            section(3)
            control("authoring-capacity").performTextReplacement("8")
            phase = "event explicit confirmation and actual occurrence readback"
            confirm(eventId)
            ready(orgId, ContentKind.EVENTS)
            val event = runBlocking { db.document("events/$eventId").get(Source.SERVER).await() }
            assertEquals("Synthetic Event Main", event.getString("title"))
            assertEquals("approved", event.getString("moderationStatus"))
            assertEquals(ownerUid, event.getString("authorId"))
            assertEquals(true, event.getBoolean("requiresRegistration"))
            assertEquals(8L, event.getLong("capacity"))
            assertEquals(0L, event.getLong("registeredCount"))
            assertTrue((event.get("occurrences") as List<*>).isNotEmpty())
            assertTrue(event.getTimestamp("startDate")!! < event.getTimestamp("endDate")!!)

            phase = "same UID HOME and foreground preserves unsent text but revalidates authority"
            control("authoring-create").assertIsEnabled().performClick()
            text("Private unsent event after HOME")
            val unsentId = requireNotNull(authoring.state.value.draft).id
            fixture.ownContent(ContentKind.EVENTS, unsentId)
            val before = requireNotNull(authoring.state.value.session)
            assertTrue(
                InstrumentationRegistry.getInstrumentation()
                    .uiAutomation
                    .performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
            )
            compose.waitUntil(10_000) { !authoring.state.value.visible }
            assertEquals(unsentId, authoring.state.value.draft?.id)
            assertFalse(authoring.state.value.draftWritable)
            context.startActivity(
                Intent(context, MainActivity::class.java)
                    .addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
            )
            compose.waitUntil(20_000) {
                authoring.state.value.let {
                    it.visible &&
                        it.session?.uid == ownerUid &&
                        it.session.revision != before.revision &&
                        it.draftWritable
                }
            }
            assertEquals(unsentId, authoring.state.value.draft?.id)
            assertEquals("Private unsent event after HOME", authoring.state.value.draft?.title)
            assertEquals(ContentKind.EVENTS, authoring.state.value.kind)
            assertNull(
                runBlocking {
                    localAuthoringSource(context)
                        .find(
                            orgId,
                            ContentKind.EVENTS,
                            unsentId,
                            requireNotNull(authStore.state.value.organizationScope()),
                        )
                }
            )

            phase =
                "canonical authority revoked while draft visible becomes readonly without sending"
            runBlocking {
                fixture.patch(
                    "organizations/$orgId",
                    mapOf(
                        "ownerId" to targetUid,
                        "adminIds" to emptyList<String>(),
                        "moderatorIds" to emptyList<String>(),
                        "updatedAt" to Instant.now(),
                    ),
                )
            }
            compose.waitUntil(20_000) {
                authoring.state.value.let {
                    it.error == AuthoringFailure.DENIED && !it.draftWritable && !it.loading
                }
            }
            assertEquals("Private unsent event after HOME", authoring.state.value.draft?.title)
            control("authoring-readonly").assertIsDisplayed()
            control("authoring-submit").assertIsNotEnabled()
            assertEquals(
                "Synthetic Event Main",
                runBlocking { db.document("events/$eventId").get(Source.SERVER).await() }
                    .getString("title"),
            )
            screenshot("revoked-readonly")
            phase = "sign-out clears private unsent authoring state"
            runBlocking { withContext(Dispatchers.Main) { authStore.signOut() }.join() }
            compose.waitUntil(15_000) {
                authoring.state.value.let {
                    it.session == null && it.draft == null && it.hub == null
                }
            }
            compose.onNodeWithText("Private unsent event after HOME").assertDoesNotExist()
        } catch (error: Throwable) {
            runCatching { screenshot("failure") }
            val state = authoring.state.value
            val reported =
                AssertionError(
                    "Authoring journey phase=$phase, ready=${authStore.state.value.readyForActions}, " +
                        "sameSession=${state.session == authStore.state.value.organizationScope()}, fresh=${state.fresh}, busy=${state.busy}, loading=${state.loading}, " +
                        "failure=${state.error}, invalidField=${state.invalidField}, kind=${state.kind}, hasDraft=${state.draft != null}, editorFresh=${state.editorFresh}, " +
                        "participation=${state.draft?.event?.participation}, fontScale=${compose.activity.resources.configuration.fontScale}, " +
                        "confirmation=${state.confirmation != null}, preview=${state.preview}\n" +
                        synchronized(confirmationTrace) { confirmationTrace.joinToString("\n") },
                    error,
                )
            failure = reported
            throw reported
        } finally {
            val cleanupFailures = mutableListOf<Throwable>()
            fun cleanup(step: String, action: () -> Unit) {
                try {
                    action()
                } catch (error: Throwable) {
                    cleanupFailures += AssertionError("Authoring cleanup failed: $step", error)
                }
            }
            cleanup("Auth session") {
                runBlocking { withContext(Dispatchers.Main) { authStore.signOut() }.join() }
            }
            cleanup("exact fixtures") { runBlocking { fixture.cleanup(failure) } }
            cleanup("tracked scenario host") {
                finishScenarioHost(trackedHost, originalLaunchIntent)
            }
            if (cleanupFailures.isNotEmpty()) {
                val primary = failure ?: AssertionError("Authoring cleanup is incomplete")
                cleanupFailures.forEach(primary::addSuppressed)
                if (failure == null) throw primary
            }
        }
    }

    private fun finishScenarioHost(tracked: MainActivity, original: Intent) {
        // Main legitimately replaces its intent on the HOME/foreground path. ActivityScenario1.7
        // filters lifecycle callbacks by the original launch action/data. Restore only that test
        // identity AFTER the real assertions/fixture cleanup, then require actual destruction.
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val monitor = ActivityLifecycleMonitorRegistry.getInstance()
        val destroyed = CountDownLatch(1)
        val observer = ActivityLifecycleCallback { activity, stage ->
            if (activity === tracked && stage == Stage.DESTROYED) destroyed.countDown()
        }
        var registered = false
        try {
            // Retained actual host, not scenario.onActivity: the changed intent may already have
            // caused Scenario to miss foreground lifecycle callbacks.
            instrumentation.runOnMainSync {
                check(
                    tracked.componentName.className == MainActivity::class.java.name &&
                        tracked.packageName == context.packageName &&
                        !tracked.isDestroyed
                )
                val resumed =
                    monitor.getActivitiesInStage(Stage.RESUMED).filterIsInstance<MainActivity>()
                check(resumed.isEmpty() || resumed.singleOrNull() === tracked) {
                    "A different Main host must not be silently closed"
                }
                println(
                    "authoring-host: sameResumedHost=${resumed.singleOrNull() === tracked}, " +
                        "launchFilterChanged=${!original.filterEquals(tracked.intent)}"
                )
                monitor.addLifecycleCallback(observer)
                registered = true
                tracked.intent = Intent(original)
                tracked.finish()
            }
            assertTrue(
                "Actual tracked Main must be destroyed",
                destroyed.await(10, TimeUnit.SECONDS),
            )
            assertEquals(Lifecycle.State.DESTROYED, compose.activityRule.scenario.state)
            compose.activityRule.scenario.close()
            println("authoring-host: actualDestroyed=true, scenarioCloseCompleted=true")
        } finally {
            if (registered)
                instrumentation.runOnMainSync { monitor.removeLifecycleCallback(observer) }
        }
    }

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val bitmap =
            InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: return
        try {
            File(context.externalCacheDir, "authoring-journey-$name.png").outputStream().use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            }
        } finally {
            bitmap.recycle()
        }
    }
}
