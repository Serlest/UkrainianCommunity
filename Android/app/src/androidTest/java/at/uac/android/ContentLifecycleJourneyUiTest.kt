package at.uac.android

import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.contentlifecycle.*
import at.uac.android.feature.organization.*
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real Main navigation and protected confirmation, separate fresh fixtures and no destructive
 * replay.
 */
@RunWith(AndroidJUnit4::class)
class ContentLifecycleJourneyUiTest {
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

    private val lifecycle
        get() = ViewModelProvider(compose.activity)[ContentLifecycleViewModel::class.java]

    private var phase = "setup"

    private fun control(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun safeState(
        value: ContentLifecycleState,
        target: ContentLifecycleTarget? = value.target,
    ): String =
        "targetMatches=${value.target == target}, ready=${value.session?.ready}, visible=${value.visible}, fresh=${value.fresh}, " +
            "busy=${value.busy}, loading=${value.loading}, snapshot=${value.snapshot != null}, item=${value.snapshot?.item != null}, " +
            "status=${value.snapshot?.item?.status}, scheduled=${value.snapshot?.item?.fields?.get("scheduledAt") != null}, " +
            "cancelled=${value.snapshot?.item?.fields?.get("cancellationState") == "cancelled"}, " +
            "permitted=${ContentLifecycleContract.permitted(value.snapshot?.organization, value.session)}, " +
            "uncertain=${value.uncertain != null}, confirmed=${value.confirmed != null}, error=${value.error}, actionable=${value.actionable}"

    private fun ready(target: ContentLifecycleTarget) {
        var matched: ContentLifecycleState? = null
        compose.waitUntil(20_000) {
            val enabled =
                compose
                    .onAllNodes(hasTestTag("content-lifecycle-request") and isEnabled())
                    .fetchSemanticsNodes()
                    .size == 1
            lifecycle.state.value.let { value ->
                (value.target == target && value.actionable && enabled || value.error != null)
                    .also { if (it) matched = value }
            }
        }
        // Initial listener delivery legitimately revalidates after the first read. Assert one
        // immutable
        // sample, then keep the real enabled-control assertion and current-session guard before any
        // tap.
        val actual = requireNotNull(matched)
        val diagnostic = "Lifecycle ready sample=${safeState(actual, target)}"
        assertNull(diagnostic, actual.error)
        assertTrue(diagnostic, actual.actionable)
        control("content-lifecycle-request").assertIsEnabled()
    }

    private fun authoringReady(target: ContentLifecycleTarget) {
        compose.waitUntil(20_000) {
            authoring.state.value.let {
                it.organizationId == target.organizationId &&
                    it.kind == target.kind &&
                    it.actionable &&
                    it.hub?.page?.items?.any { item -> item.id == target.contentId } == true
            }
        }
    }

    private fun confirm(target: ContentLifecycleTarget) {
        control("content-lifecycle-request").assertIsEnabled().performClick()
        compose
            .onNodeWithTag("content-lifecycle-confirm")
            .assertIsDisplayed()
            .assertIsEnabled()
            .performClick()
        compose.waitUntil(45_000) {
            lifecycle.state.value.let {
                it.target == target && (it.confirmed != null && !it.busy || it.error != null)
            }
        }
        assertNull(lifecycle.state.value.error)
        assertNotNull(lifecycle.state.value.confirmed)
        control("content-lifecycle-confirmed").assertIsDisplayed()
        compose.onNodeWithTag("content-lifecycle-request").assertDoesNotExist()
    }

    @Test
    fun mainOwnerConfirmsNewsDeletionAndRegisteredEventCancellationThenMasksOnLogout() {
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
            assertNull(lifecycle.state.value.snapshot)
            return
        }
        val fixture = ContentLifecycleFixtures("author4clifeui-${UUID.randomUUID()}")
        val auth = LocalFirebase.auth(context)
        var failure: Throwable? = null
        try {
            val accounts = runBlocking {
                AuthEmulatorFixtures.seedLegalReference()
                val owner = fixture.media.account("owner")
                val attendee = fixture.media.account("attendee")
                fixture.media.organization(owner)
                auth.signOut()
                owner to attendee
            }
            phase = "actual Main sign-in and separately persisted text"
            compose.openGuestLogin()
            control("auth-email").performTextReplacement(accounts.first.email)
            control("auth-password").performTextReplacement(fixture.password)
            control("auth-login-submit").assertIsEnabled().performClick()
            compose.waitUntil(20_000) { store.state.value.readyForActions }
            val actor = requireNotNull(store.state.value.organizationScope())
            val news = fixture.register(ContentKind.NEWS)
            val event = fixture.register(ContentKind.EVENTS)
            runBlocking {
                val source = localAuthoringSource(context)
                val repository =
                    AuthoringRepository(
                        source,
                        { store.state.value.organizationScope() },
                        AuthOrganizationMutationGate(store),
                    )
                val org = requireNotNull(source.organization(fixture.organizationId, actor))
                for (target in listOf(news, event)) {
                    val draft =
                        AuthoringContract.newDraft(target.kind, org)
                            .copy(
                                id = target.contentId,
                                title = "Synthetic Main lifecycle ${target.kind.collection}",
                                summary = "Synthetic lifecycle journey summary",
                                body = "This is an isolated local lifecycle confirmation journey.",
                            )
                            .let {
                                if (target.kind == ContentKind.EVENTS)
                                    it.copy(event = it.event.copy(venue = "Synthetic hall"))
                                else it
                            }
                    repository.submit(AuthoringContract.submission(draft, org, actor, null))
                }
                val marker =
                    fixture.reference(
                        event,
                        accounts.second.uid,
                        ContentLifecycleFixtures.Reference.REGISTRATION,
                    )
                fixture.seed(
                    marker,
                    mapOf(
                        "id" to marker.substringAfterLast('/'),
                        "eventId" to event.contentId,
                        "userId" to accounts.second.uid,
                        "registeredAt" to Instant.now(),
                    ),
                )
                fixture.reference(
                    event,
                    accounts.second.uid,
                    ContentLifecycleFixtures.Reference.CANCEL_NOTICE,
                )
            }
            control("account-open-organizations").assertIsEnabled().performClick()
            compose.waitUntil(20_000) {
                !hub.state.value.loading &&
                    hub.state.value.hub?.managed?.any { it.id == fixture.organizationId } == true
            }
            control("organization-manage-${fixture.organizationId}")
                .assertIsEnabled()
                .performClick()
            compose.waitUntil(20_000) {
                management.state.value.let {
                    it.organizationId == fixture.organizationId && it.actionable
                }
            }
            control("organization-authoring-news").assertIsEnabled().performClick()
            authoringReady(news)

            phase =
                "fresh owner list lifecycle hook and cancellation of the first protected confirmation"
            control("authoring-lifecycle-${news.contentId}").assertIsEnabled().performClick()
            ready(news)
            assertEquals(
                "profile/organizations/lifecycle/${news.organizationId}/news/${news.contentId}",
                browse.state.value.route,
            )
            control("content-lifecycle-request").assertIsEnabled().performClick()
            compose.onNodeWithTag("content-lifecycle-confirm").assertIsDisplayed()
            compose.onNodeWithText("Abbrechen").assertIsDisplayed().performClick()
            assertNull(lifecycle.state.value.confirmed)
            assertNull(lifecycle.state.value.confirmation)
            assertTrue(runBlocking { fixture.exists(news) })

            phase = "one confirmed News deletion from Main and fresh absence"
            confirm(news)
            assertTrue(lifecycle.state.value.confirmed?.receipt is ContentLifecycleReceipt.Deleted)
            assertFalse(runBlocking { fixture.exists(news) })
            screenshot("news-confirmed")
            compose
                .onNodeWithText("Zurück", useUnmergedTree = true)
                .performScrollTo()
                .assertIsEnabled()
                .performClick()
            compose.waitUntil(20_000) {
                authoring.state.value.let {
                    it.kind == ContentKind.NEWS &&
                        it.actionable &&
                        it.hub?.page?.items?.none { item -> item.id == news.contentId } == true
                }
            }

            phase =
                "Event list and protected cancellation uses actual registration not zero displayed counter"
            control("authoring-kind-events").assertIsEnabled().performClick()
            authoringReady(event)
            control("authoring-lifecycle-${event.contentId}").assertIsEnabled().performClick()
            ready(event)
            assertEquals(0L, lifecycle.state.value.snapshot?.item?.fields?.get("registeredCount"))
            confirm(event)
            val receipt =
                lifecycle.state.value.confirmed?.receipt as ContentLifecycleReceipt.Cancelled
            assertEquals(1L, receipt.recipientCount)
            assertEquals(1L, receipt.notificationCount)
            assertEquals(
                "cancelled",
                lifecycle.state.value.snapshot?.item?.fields?.get("cancellationState"),
            )
            runBlocking {
                assertTrue(fixture.exists(event))
                assertNotNull(
                    fixture.fields(
                        fixture.reference(
                            event,
                            accounts.second.uid,
                            ContentLifecycleFixtures.Reference.REGISTRATION,
                        )
                    )
                )
                assertNotNull(
                    fixture.fields(
                        fixture.reference(
                            event,
                            accounts.second.uid,
                            ContentLifecycleFixtures.Reference.CANCEL_NOTICE,
                        )
                    )
                )
            }
            screenshot("event-confirmed")

            phase = "logout masks prior private lifecycle state and all destructive callbacks"
            runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
            compose.waitUntil(15_000) {
                store.state.value.stage == AuthStage.GUEST &&
                    lifecycle.state.value.session == null &&
                    lifecycle.state.value.snapshot == null
            }
            compose.onNodeWithText("Synthetic Main lifecycle events").assertDoesNotExist()
            compose.onNodeWithTag("content-lifecycle-confirm").assertDoesNotExist()
            assertNull(lifecycle.state.value.confirmed)
            assertNull(lifecycle.state.value.uncertain)
        } catch (error: Throwable) {
            runCatching { compose.waitForIdle() }
            screenshot("failure")
            val value = lifecycle.state.value
            val reported =
                AssertionError(
                    "Lifecycle Main phase=$phase stage=${store.state.value.stage} sameSession=${value.session == store.state.value.organizationScope()} " +
                        "${safeState(value)} observed=${value.observed}",
                    error,
                )
            failure = reported
            throw reported
        } finally {
            runBlocking {
                withContext(Dispatchers.Main) { store.signOut() }.join()
                fixture.cleanup(failure)
            }
        }
    }

    private fun screenshot(label: String) {
        runCatching {
            val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: return
            try {
                File(context.filesDir, "android-lifecycle-journey-$label.png").outputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
            } finally {
                bitmap.recycle()
            }
        }
    }
}
