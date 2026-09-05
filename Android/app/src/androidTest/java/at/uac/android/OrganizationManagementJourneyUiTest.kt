package at.uac.android

import android.graphics.Bitmap
import android.os.Build
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.organization.*
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import java.io.File
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real Main route, verified synthetic owner, actual edit/role confirmations and realtime authority
 * revocation.
 */
@RunWith(AndroidJUnit4::class)
class OrganizationManagementJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val hub
        get() = ViewModelProvider(compose.activity)[OrganizationViewModel::class.java]

    private val management
        get() = ViewModelProvider(compose.activity)[OrganizationManagementViewModel::class.java]

    private val authStore
        get() = LocalAuthSession.get(context)

    private var phase = "setup"

    private fun control(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun ready(id: String) {
        compose.waitUntil(20_000) {
            management.state.value.let {
                it.organizationId == id &&
                    it.fresh &&
                    !it.loading &&
                    !it.busy &&
                    it.snapshot != null
            }
        }
        compose.waitForIdle()
    }

    @Test
    fun approvedOrganizationEditorTeamAndRevokedAuthorityOrOfflineGate() {
        runBlocking { withContext(Dispatchers.Main) { authStore.signOut() }.join() }
        val online = InstrumentationRegistry.getArguments().getString("expectFunctions") == "true"
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", if (online) "emulator" else "synthetic")
            browse.navigate("profile", true)
        }
        compose.waitUntil(15_000) { authStore.state.value.stage == AuthStage.GUEST }
        if (!online) {
            control("guest-sign-in").assertIsDisplayed()
            compose.onNodeWithTag("account-open-organizations").assertDoesNotExist()
            assertNull(management.state.value.snapshot)
            return
        }
        check(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        check(
            (Build.HARDWARE in setOf("ranchu", "goldfish") &&
                Build.MODEL.startsWith("sdk_gphone")) || isExplicitApi26CompatibilityAvd()
        )
        val prefix = "org4bjourney-${UUID.randomUUID()}"
        val orgId = "$prefix-org"
        val fixture = OrganizationManagementFixtures(prefix, orgId)
        val password = "Synthetic-managed-journey-only!"
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        var actor: OrganizationSession? = null
        var ownerEmail = ""
        var targetUid = ""
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
                        actor = OrganizationSession(user.uid, 1, true, "Synthetic owner", "user")
                        ownerEmail = email
                    } else targetUid = user.uid
                }
                auth.signOut()
                val basic =
                    OrganizationDraft(
                        orgId,
                        "Synthetic Management Journey",
                        "A complete synthetic management profile",
                        region = "wien",
                        city = "Wien",
                    )
                fixture.seed(
                    "organizations/$orgId",
                    OrganizationContract.create(basic, actor!!, Instant.now()) +
                        mapOf(
                            "moderationStatus" to "approved",
                            "ownerId" to actor.uid,
                            "subscriberCount" to 1L,
                        ),
                )
                fixture.seed(
                    "likes/organization_follow_${orgId}_$targetUid",
                    mapOf(
                        "id" to "organization_follow_${orgId}_$targetUid",
                        "userId" to targetUid,
                        "subscribedOrganizationId" to orgId,
                        "createdAt" to Instant.now(),
                    ),
                )
            }
            phase = "Main verified owner sign-in"
            compose.openGuestLogin()
            control("auth-email").performTextReplacement(ownerEmail)
            control("auth-password").performTextReplacement(password)
            control("auth-login-submit").assertIsEnabled().performClick()
            compose.waitUntil(20_000) { authStore.state.value.readyForActions }
            phase = "profile to own organization management route"
            control("account-open-organizations").assertIsEnabled().performClick()
            compose.waitUntil(20_000) {
                !hub.state.value.loading &&
                    hub.state.value.hub?.managed?.any { it.id == orgId } == true
            }
            control("organization-manage-$orgId").assertIsEnabled().performClick()
            ready(orgId)
            assertTrue(browse.state.value.route == "profile/organizations/manage/$orgId")
            phase = "approved information edit and server confirmation"
            control("organization-management-edit").assertIsEnabled().performClick()
            control("organization-name")
                .performTextReplacement("Managed title updated through Main")
            control("organization-management-save").assertIsEnabled().performClick()
            compose.waitUntil(25_000) {
                management.state.value.confirmed && !management.state.value.busy
            }
            ready(orgId)
            val edited = runBlocking {
                db.document("organizations/$orgId").get(Source.SERVER).await()
            }
            assertEquals("Managed title updated through Main", edited.getString("name"))
            assertEquals(actor!!.uid, edited.getString("ownerId"))
            assertEquals(1L, edited.getLong("subscriberCount"))
            phase = "explicit assign admin confirmation"
            control("organization-team-admin-$targetUid").assertIsEnabled().performClick()
            compose
                .onNodeWithTag("organization-management-confirm-role")
                .assertIsDisplayed()
                .performClick()
            compose.waitUntil(25_000) {
                management.state.value.snapshot?.organization?.fields?.get("adminIds") ==
                    listOf(targetUid) && !management.state.value.busy
            }
            ready(orgId)
            val assigned = runBlocking {
                db.document("organizations/$orgId").get(Source.SERVER).await()
            }
            assertEquals(listOf(targetUid), assigned.get("adminIds"))
            assertEquals(emptyList<String>(), assigned.get("moderatorIds"))
            screenshot("admin-confirmed")
            phase = "explicit full organization role removal"
            control("organization-team-remove-$targetUid").assertIsEnabled().performClick()
            compose
                .onNodeWithText("auch wenn sie seit dem Öffnen geändert wurde", substring = true)
                .assertIsDisplayed()
            compose.onNodeWithTag("organization-management-confirm-role").performClick()
            compose.waitUntil(25_000) {
                management.state.value.snapshot?.organization?.fields?.get("adminIds") ==
                    emptyList<String>() && !management.state.value.busy
            }
            ready(orgId)
            assertEquals(
                emptyList<String>(),
                runBlocking { db.document("organizations/$orgId").get(Source.SERVER).await() }
                    .get("adminIds"),
            )
            phase = "realtime canonical authority revocation preserves unsaved text readonly"
            control("organization-management-edit").assertIsEnabled().performClick()
            control("organization-name").performTextReplacement("Unsaved text must not be sent")
            runBlocking {
                fixture.patch(
                    "organizations/$orgId",
                    mapOf(
                        "ownerId" to targetUid,
                        "moderatorIds" to listOf(actor.uid),
                        "updatedAt" to Instant.now(),
                    ),
                )
            }
            compose.waitUntil(20_000) {
                management.state.value.snapshot?.organization?.authority ==
                    OrganizationAuthority.MODERATOR && !management.state.value.loading
            }
            assertEquals(
                "Unsaved text must not be sent",
                management.state.value.draft?.basics?.name,
            )
            control("organization-management-readonly").assertIsDisplayed()
            control("organization-management-save").assertIsNotEnabled()
            compose.onNodeWithTag("organization-team-admin-$targetUid").assertDoesNotExist()
            assertEquals(
                "Managed title updated through Main",
                runBlocking { db.document("organizations/$orgId").get(Source.SERVER).await() }
                    .getString("name"),
            )
            screenshot("revoked-readonly")
            phase = "account switch immediately clears management state"
            runBlocking { withContext(Dispatchers.Main) { authStore.signOut() }.join() }
            compose.waitUntil(15_000) {
                management.state.value.session == null &&
                    management.state.value.snapshot == null &&
                    management.state.value.draft == null
            }
            compose.onNodeWithText("Public target").assertDoesNotExist()
        } catch (error: Throwable) {
            runCatching { screenshot("failure") }
            val state = management.state.value
            val reported =
                AssertionError(
                    "Organization management journey phase=$phase, ready=${authStore.state.value.readyForActions}, " +
                        "sameSession=${state.session == authStore.state.value.organizationScope()}, fresh=${state.fresh}, busy=${state.busy}, loading=${state.loading}, " +
                        "failure=${state.error}, targetMatches=${state.organizationId == orgId}, memberCount=${state.snapshot?.members?.size}",
                    error,
                )
            failure = reported
            throw reported
        } finally {
            runBlocking {
                withContext(Dispatchers.Main) { authStore.signOut() }.join()
                fixture.cleanup(failure)
            }
        }
    }

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val bitmap =
            InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot() ?: return
        try {
            File(context.externalCacheDir, "organization-management-journey-$name.png")
                .outputStream()
                .use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        } finally {
            bitmap.recycle()
        }
    }
}
