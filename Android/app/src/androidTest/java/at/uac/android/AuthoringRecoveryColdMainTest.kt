package at.uac.android

import android.graphics.Bitmap
import android.os.Process
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.authoring.*
import at.uac.android.feature.authoring.recovery.localAuthoringRecoveryStore
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.OrganizationManagementViewModel
import at.uac.android.feature.organization.OrganizationViewModel
import at.uac.android.feature.organization.organizationScope
import java.io.File
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test

/**
 * Explicit phases. Root proves process absence between prepare and restore; no in-process reset is
 * labelled cold.
 */
class AuthoringRecoveryColdMainTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AuthoringRecoveryFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val authoring
        get() = ViewModelProvider(compose.activity)[AuthoringViewModel::class.java]

    private val hub
        get() = ViewModelProvider(compose.activity)[OrganizationViewModel::class.java]

    private val management
        get() = ViewModelProvider(compose.activity)[OrganizationManagementViewModel::class.java]

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private var stage = "phase guard"

    private fun phase(expected: String) {
        AuthoringRecoveryFixtures.requireAvd()
        assumeTrue(
            "Explicit cold-authoring phase required; a skip is not proof",
            InstrumentationRegistry.getArguments().let {
                it.getString("expectEmulator") == "true" &&
                    it.getString("authoringColdPhase") == expected
            },
        )
    }

    private fun control(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun tap(tag: String) {
        compose.waitUntil(20_000) {
            runCatching { control(tag).assertIsEnabled().isDisplayed() }.getOrDefault(false)
        }
        control(tag).assertIsEnabled().performClick()
    }

    private fun ready(owned: AuthoringRecoveryFixtures.Marker) {
        compose.waitUntil(20_000) {
            authoring.state.value.let {
                it.organizationId == owned.organizationId &&
                    it.kind == owned.kind &&
                    it.actionable &&
                    it.recoveryLoaded
            }
        }
        compose.waitForIdle()
    }

    private fun navigate(owned: AuthoringRecoveryFixtures.Marker) {
        tap("account-open-organizations")
        compose.waitUntil(20_000) {
            hub.state.value.let {
                !it.loading &&
                    it.hub?.managed?.any { org -> org.id == owned.organizationId } == true
            }
        }
        tap("organization-manage-${owned.organizationId}")
        compose.waitUntil(20_000) {
            management.state.value.let {
                it.organizationId == owned.organizationId && it.fresh && !it.loading && !it.busy
            }
        }
        tap("organization-authoring-${owned.kind.collection}")
        ready(owned)
        assertEquals(
            "profile/organizations/author/${owned.organizationId}/${owned.kind.collection}",
            browse.state.value.route,
        )
    }

    private fun failure(error: Throwable): Nothing {
        runCatching {
            compose.waitForIdle()
            InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()?.let { bitmap
                ->
                try {
                    File(context.externalCacheDir, "authoring-recovery-cold-failure.png")
                        .outputStream()
                        .use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                } finally {
                    bitmap.recycle()
                }
            }
        }
        val state = authoring.state.value
        throw AssertionError(
            "Authoring cold Main stage=$stage authStage=${auth.state.value.stage} route=${browse.state.value.route} ready=${auth.state.value.readyForActions} sameSession=${state.session == auth.state.value.organizationScope()} " +
                "fresh=${state.fresh} loading=${state.loading} busy=${state.busy} recoveryLoaded=${state.recoveryLoaded} storageError=${state.recoveryError} " +
                "hasDraft=${state.draft != null} hasSavedDraft=${state.recoveredDraft != null} hasPending=${state.uncertain != null}; fixture retained",
            error,
        )
    }

    @Test
    fun prepareTypedUnsentFutureEventThroughActualMain() {
        phase("prepare")
        try {
            stage = "synthetic verified account and recoverable fixture marker"
            var owned = runBlocking { AuthoringRecoveryFixtures.create(ContentKind.EVENTS) }
            runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
            stage = "actual login and organization authoring navigation"
            compose.waitUntil(20_000) {
                auth.state.value.stage == at.uac.android.feature.auth.AuthStage.GUEST &&
                    auth.state.value.identity == null
            }
            compose.waitUntil(20_000) { compose.onNodeWithTag("tab-profile").isDisplayed() }
            compose.onNodeWithTag("tab-profile").performClick()
            compose.openGuestLogin()
            control("auth-email").performTextReplacement(owned.email)
            control("auth-password").performTextReplacement(AuthoringRecoveryFixtures.PASSWORD)
            tap("auth-login-submit")
            compose.waitUntil(20_000) {
                auth.state.value.readyForActions && auth.state.value.identity?.uid == owned.uid
            }
            navigate(owned)
            tap("authoring-create")
            compose.waitUntil(10_000) { authoring.state.value.draft != null }
            owned = owned.copy(contentId = requireNotNull(authoring.state.value.draft).id)
            AuthoringRecoveryFixtures.write(owned)
            stage = "type real form and await encrypted unsent readback"
            control("authoring-title")
                .assertIsEnabled()
                .performTextReplacement("Private cold future event")
            control("authoring-summary")
                .performTextReplacement("Synthetic local cold recovery summary")
            control("authoring-body")
                .performTextReplacement(
                    "Synthetic private body survives cold start without sending."
                )
            tap("authoring-section-2")
            control("authoring-venue").performTextReplacement("Private synthetic future venue")
            compose.waitUntil(15_000) {
                authoring.state.value.let {
                    it.draftSaved && it.recoveryError == null && it.draft?.id == owned.contentId
                }
            }
            val current = authoring.state.value
            val expected = requireNotNull(current.draft)
            assertTrue(expected.event.occurrences.first().start > Instant.now())
            val stored = runBlocking { localAuthoringRecoveryStore(context).load(owned.scope) }
            assertEquals(expected, stored?.draft)
            assertEquals(current.draftZoneId, stored?.draftZoneId)
            assertNull(stored?.pending)
            val session = requireNotNull(auth.state.value.organizationScope())
            assertNull(
                runBlocking {
                    localAuthoringSource(context)
                        .find(owned.organizationId, owned.kind, owned.contentId, session)
                }
            )
            assertNull(current.confirmation)
            assertNull(current.confirmed)
            println(
                "AUTHORING_COLD_PREPARED typedUi=true encryptedDraft=true futureOccurrence=true pending=0 serverDocument=absent pid=${Process.myPid()}"
            )
            // Keep exactly this fixture and SDK identity for root-controlled process death. No
            // successful cleanup here.
        } catch (error: Throwable) {
            failure(error)
        }
    }

    @Test
    fun restoreAfterDifferentProcessShowsExplicitDraftWithoutSending() {
        phase("restore")
        try {
            stage = "different process and persisted original SDK identity"
            val owned = AuthoringRecoveryFixtures.read()
            assertNotEquals(
                "A new ViewModel alone is not cold proof",
                owned.preparingPid,
                Process.myPid(),
            )
            assertEquals(ContentKind.EVENTS, owned.kind)
            val actualUser = requireNotNull(LocalFirebase.auth(context).currentUser)
            assertEquals(owned.uid, actualUser.uid)
            assertEquals(owned.email, actualUser.email)
            assertTrue(actualUser.isEmailVerified)
            val saved =
                requireNotNull(
                    runBlocking { localAuthoringRecoveryStore(context).load(owned.scope) }
                )
            val expected = requireNotNull(saved.draft)
            assertNull(saved.pending)
            assertEquals(owned.contentId, expected.id)
            compose.waitUntil(20_000) {
                auth.state.value.readyForActions && auth.state.value.identity?.uid == owned.uid
            }
            stage = "real Main route offers saved draft but no editor or automatic request"
            compose.waitUntil(20_000) { compose.onNodeWithTag("tab-profile").isDisplayed() }
            compose.onNodeWithTag("tab-profile").performClick()
            navigate(owned)
            assertNull(authoring.state.value.draft)
            assertEquals(expected, authoring.state.value.recoveredDraft)
            control("authoring-create").assertIsNotEnabled()
            compose.onNodeWithTag("authoring-title").assertDoesNotExist()
            assertNull(authoring.state.value.confirmation)
            assertNull(authoring.state.value.uncertain)
            assertNull(authoring.state.value.confirmed)
            val session = requireNotNull(auth.state.value.organizationScope())
            assertNull(
                runBlocking {
                    localAuthoringSource(context)
                        .find(owned.organizationId, owned.kind, owned.contentId, session)
                }
            )
            stage = "explicit restore preserves exact UUID text venue dates and zone"
            tap("authoring-restore-draft")
            assertEquals(expected, authoring.state.value.draft)
            assertEquals(saved.draftZoneId, authoring.state.value.draftZoneId)
            control("authoring-title")
                .assertIsEnabled()
                .assertTextContains("Private cold future event")
            tap("authoring-section-2")
            control("authoring-venue").assertTextContains("Private synthetic future venue")
            assertEquals(
                expected.event.occurrences,
                authoring.state.value.draft?.event?.occurrences,
            )
            assertNull(
                runBlocking {
                    localAuthoringSource(context)
                        .find(owned.organizationId, owned.kind, owned.contentId, session)
                }
            )
            println(
                "AUTHORING_COLD_RESTORED newProcess=true explicitUiRestore=true exactUuidTextDatesZone=true automaticWrites=0 pending=0"
            )
            // Cleanup has its own explicit phase and must not delete a journal after a failed
            // assertion.
        } catch (error: Throwable) {
            failure(error)
        }
    }

    @Test
    fun cleanupOnlyTheExactColdFixtureAfterInspection() {
        phase("cleanup")
        try {
            stage = "exact unsent-only cleanup with server absence readback"
            val owned = AuthoringRecoveryFixtures.read()
            val recovered = runBlocking { localAuthoringRecoveryStore(context).load(owned.scope) }
            assertNull(recovered?.pending)
            assertTrue(recovered?.draft == null || recovered.draft.id == owned.contentId)
            runBlocking {
                withContext(Dispatchers.Main) { auth.signOut() }.join()
                AuthoringRecoveryFixtures.cleanup()
            }
            assertFalse(AuthoringRecoveryFixtures.exists())
            println(
                "AUTHORING_COLD_CLEANUP_CONFIRMED pending=0 exactFixtureRemoved=true markerAbsent=true"
            )
        } catch (error: Throwable) {
            failure(error)
        }
    }
}
