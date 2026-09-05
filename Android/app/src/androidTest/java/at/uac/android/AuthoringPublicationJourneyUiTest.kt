package at.uac.android

import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.authoring.*
import at.uac.android.feature.authoring.recovery.localAuthoringRecoveryStore
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.organization.*
import com.google.firebase.firestore.Source
import java.io.File
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test

/**
 * Real Main form, Material date dialog, explicit scheduling confirmation and exact server receipt.
 */
class AuthoringPublicationJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = AuthoringRecoveryFixtures.context

    private val auth
        get() = LocalAuthSession.get(context)

    private val model
        get() = ViewModelProvider(compose.activity)[AuthoringViewModel::class.java]

    private val hub
        get() = ViewModelProvider(compose.activity)[OrganizationViewModel::class.java]

    private val management
        get() = ViewModelProvider(compose.activity)[OrganizationManagementViewModel::class.java]

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private var phase = "fixture"

    private fun control(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun tap(tag: String) {
        compose.waitUntil(20_000) {
            runCatching { control(tag).assertIsEnabled().isDisplayed() }.getOrDefault(false)
        }
        control(tag).assertIsEnabled().performClick()
    }

    private fun ready(org: String) {
        compose.waitUntil(20_000) {
            model.state.value.let {
                it.organizationId == org &&
                    it.kind == ContentKind.NEWS &&
                    it.actionable &&
                    it.recoveryLoaded &&
                    it.session == auth.state.value.organizationScope()
            }
        }
        compose.waitForIdle()
    }

    @Test
    fun mainSchedulesOnlyAfterDateDialogAndExplicitConfirmationThenShowsOwnReadOnlyDraft() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        AuthoringRecoveryFixtures.requireAvd()
        var fixtureId: String? = null
        var primary: Throwable? = null
        try {
            var owned = runBlocking { AuthoringRecoveryFixtures.create(ContentKind.NEWS) }
            fixtureId = owned.suffix
            runBlocking { withContext(Dispatchers.Main) { auth.signOut() }.join() }
            compose.runOnIdle {
                browse.preference("language", "de")
                browse.preference("mode", "emulator")
            }
            phase = "actual profile login and fresh owner management route"
            compose.waitUntil(20_000) {
                auth.state.value.stage == AuthStage.GUEST && auth.state.value.identity == null
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
            tap("organization-authoring-news")
            ready(owned.organizationId)
            assertEquals(
                "profile/organizations/author/${owned.organizationId}/news",
                browse.state.value.route,
            )
            tap("authoring-create")
            compose.waitUntil(10_000) { model.state.value.draft != null }
            owned = owned.copy(contentId = requireNotNull(model.state.value.draft).id)
            AuthoringRecoveryFixtures.write(owned)

            phase = "real typed form and explicit Later selection without server write"
            control("authoring-title").performTextReplacement("Synthetic Main scheduled news")
            control("authoring-summary").performTextReplacement("Local schedule Main summary")
            control("authoring-body")
                .performTextReplacement(
                    "Only synthetic scheduling proof. No background publication worker is invoked."
                )
            control("authoring-publication-now").performScrollTo().assertIsSelected()
            tap("authoring-publication-scheduled")
            val selectedBeforeDialog = requireNotNull(model.state.value.draft?.scheduledAt)
            assertTrue(AuthoringPublication.hasEnoughLeadTime(selectedBeforeDialog))
            phase = "actual protected Material date dialog retains selected day and exact zone"
            tap("authoring-publication-date")
            compose.onAllNodes(isDialog()).assertCountEquals(1)
            compose
                .onNodeWithText("Übernehmen")
                .assertIsDisplayed()
                .assertIsEnabled()
                .performClick()
            compose.onAllNodes(isDialog()).assertCountEquals(0)
            assertEquals(selectedBeforeDialog, model.state.value.draft?.scheduledAt)
            control("authoring-publication-zone")
                .performScrollTo()
                .assertTextContains(model.state.value.draftZoneId, substring = true)
            compose.waitUntil(15_000) {
                model.state.value.let {
                    it.draftSaved && it.recoveryError == null && it.draft?.id == owned.contentId
                }
            }
            val chosen = requireNotNull(model.state.value.draft)
            val journal = localAuthoringRecoveryStore(context)
            val local = runBlocking { journal.load(owned.scope) }
            assertEquals(chosen, local?.draft)
            assertNull(local?.pending)
            val actor = requireNotNull(auth.state.value.organizationScope())
            val source = localAuthoringSource(context)
            assertNull(
                runBlocking {
                    source.find(owned.organizationId, owned.kind, owned.contentId, actor)
                }
            )
            assertNull(model.state.value.confirmed)

            phase = "protected preview and immutable schedule confirmation"
            tap("authoring-preview")
            compose.onNodeWithText("Geplante Veröffentlichung:", substring = true).assertExists()
            compose.onNodeWithText("Zurück zum Formular").performScrollTo().performClick()
            tap("authoring-submit")
            val intent = requireNotNull(model.state.value.confirmation)
            assertEquals(chosen.scheduledAt, intent.fields["scheduledAt"])
            assertEquals("draft", intent.fields["moderationStatus"])
            assertEquals(owned.contentId, intent.id)
            compose.onNodeWithText("Ein geplanter Server-Entwurf", substring = true).assertExists()
            assertNull(
                runBlocking {
                    source.find(owned.organizationId, owned.kind, owned.contentId, actor)
                }
            )
            compose
                .onNodeWithTag("authoring-confirm")
                .assertIsDisplayed()
                .assertIsEnabled()
                .performClick()

            phase = "fresh scheduled receipt and own read-only list"
            compose.waitUntil(25_000) {
                model.state.value.let { it.confirmed?.id == owned.contentId && !it.busy }
            }
            ready(owned.organizationId)
            val actual = requireNotNull(model.state.value.confirmed)
            assertTrue(AuthoringContract.matches(intent, actual))
            assertEquals(AuthoringStatus.SCHEDULED, actual.status)
            assertFalse(actual.editable)
            val remote = runBlocking {
                LocalFirebase.firestore(context)
                    .document("news/${owned.contentId}")
                    .get(Source.SERVER)
                    .await()
            }
            val timestamp = requireNotNull(remote.getTimestamp("scheduledAt"))
            assertEquals(
                chosen.scheduledAt,
                Instant.ofEpochSecond(timestamp.seconds, timestamp.nanoseconds.toLong()),
            )
            assertEquals("draft", remote.getString("moderationStatus"))
            assertEquals(owned.uid, remote.getString("authorId"))
            assertNull(runBlocking { journal.load(owned.scope) })
            assertEquals(listOf(owned.contentId), model.state.value.hub?.page?.items?.map { it.id })
            control("authoring-item-${owned.contentId}").assertExists()
            compose.onNodeWithTag("authoring-edit-${owned.contentId}").assertDoesNotExist()
            compose.onNodeWithTag("authoring-cover-${owned.contentId}").assertDoesNotExist()
            compose.onNodeWithTag("authoring-lifecycle-${owned.contentId}").assertDoesNotExist()
        } catch (error: Throwable) {
            runCatching {
                compose.waitForIdle()
                InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()?.let {
                    bitmap ->
                    try {
                        File(context.externalCacheDir, "authoring-publication-journey-failure.png")
                            .outputStream()
                            .use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                    } finally {
                        bitmap.recycle()
                    }
                }
            }
            val state = model.state.value
            val reported =
                AssertionError(
                    "Schedule Main phase=$phase auth=${auth.state.value.stage} sameSession=${state.session == auth.state.value.organizationScope()} " +
                        "fresh=${state.fresh} loading=${state.loading} busy=${state.busy} error=${state.error} invalid=${state.invalidField} stored=${state.draftSaved} pending=${state.uncertain != null}",
                    error,
                )
            primary = reported
            throw reported
        } finally {
            if (fixtureId != null && AuthoringRecoveryFixtures.exists()) {
                try {
                    check(AuthoringRecoveryFixtures.read().suffix == fixtureId)
                    runBlocking {
                        // Unknown pending is retained with its account/marker, never erased by test
                        // cleanup.
                        check(
                            localAuthoringRecoveryStore(context)
                                .load(AuthoringRecoveryFixtures.read().scope)
                                ?.pending == null
                        )
                        withContext(Dispatchers.Main) { auth.signOut() }.join()
                        AuthoringRecoveryFixtures.cleanup()
                    }
                } catch (error: Throwable) {
                    if (primary == null) throw error else primary.addSuppressed(error)
                }
            }
        }
    }
}
