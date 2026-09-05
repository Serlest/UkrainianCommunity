package at.uac.android

import android.graphics.Bitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import at.uac.android.core.LocalStorage
import at.uac.android.feature.auth.*
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.organization.*
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Real Main UI, exact synthetic system-picker album, Auth + callable + unchanged Rules. */
@RunWith(AndroidJUnit4::class)
class OrganizationJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val organizations
        get() = ViewModelProvider(compose.activity)[OrganizationViewModel::class.java]

    private val store
        get() = LocalAuthSession.get(context)

    private fun control(tag: String) = compose.onNodeWithTag(tag).performScrollTo()

    private fun ready() {
        compose.waitUntil(30_000) {
            !organizations.state.value.loading && organizations.state.value.hub != null
        }
        compose.waitForIdle()
    }

    @Test
    fun ownApplicationPickerReviewResubmitAndDiscardOrOfflineGate() {
        runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        val online = InstrumentationRegistry.getArguments().getString("expectFunctions") == "true"
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.preference("mode", if (online) "emulator" else "synthetic")
            browse.navigate("profile", true)
        }
        compose.waitUntil(15_000) { store.state.value.stage == AuthStage.GUEST }
        if (!online) {
            control("guest-sign-in").assertIsDisplayed()
            compose.onNodeWithTag("account-open-organizations").assertDoesNotExist()
            assertNull(organizations.state.value.hub)
            return
        }
        check(InstrumentationRegistry.getArguments().getString("expectEmulator") == "true")
        val fixtures = LocalEmulatorFixtures(context)
        val email = "orgjourney-${UUID.randomUUID()}@example.invalid"
        val password = "Synthetic-org-journey-only!"
        val uid = prepareAccount(fixtures, email, password)
        val photo = PhotoPickerFixtures.create(context, "uac-org-journey")
        var requestId: String? = null
        try {
            compose.openGuestLogin()
            control("auth-email").performTextReplacement(email)
            control("auth-password").performTextReplacement(password)
            control("auth-login-submit").performClick()
            compose.waitUntil(20_000) { store.state.value.readyForActions }
            control("account-open-organizations").performClick()
            ready()
            control("organization-create").performClick()
            control("organization-name").performTextReplacement("Synthetic Journey Organization")
            control("organization-summary")
                .performTextReplacement("A complete synthetic organization application")
            control("organization-region").performClick()
            compose
                .onNodeWithTag("organization-region-wien")
                .performScrollTo()
                .assertTextContains("Wien")
                .performClick()
            compose.runOnIdle { assertEquals("wien", organizations.state.value.draft?.region) }
            control("organization-region").assertTextContains("Bundesland: Wien")
            control("organization-city").performTextReplacement("Wien")
            requestId = organizations.state.value.draft!!.id
            val revision = store.state.value.revision
            var pickerPhase = "button-enabled"
            try {
                control("organization-logo").assertIsEnabled().performClick()
                pickerPhase = "native-selection"
                PhotoPickerFixtures.selectOnlyPhoto(photo)
                pickerPhase = "prepared-preview"
                compose.waitUntil(20_000) {
                    organizations.state.value.logoPreview != null &&
                        !organizations.state.value.imageLoading
                }
            } catch (error: Throwable) {
                val current = organizations.state.value
                val auth = store.state.value
                runCatching { screenshot("picker-failure") }
                throw AssertionError(
                    "Organization picker phase=$pickerPhase: nativePicker=${PhotoPickerFixtures.pickerVisible()}, " +
                        "authRevision=${auth.revision}, expectedRevision=$revision, ready=${auth.readyForActions}, " +
                        "pickerOpen=${current.pickerOpen}, imageLoading=${current.imageLoading}, logoSelected=${current.logoSelected}, " +
                        "error=${current.error}, editorFailure=${current.editorFailure}, draftPresent=${current.draft != null}, " +
                        "visible=${current.visible}, loading=${current.loading}, busy=${current.busy}, writable=${current.editorWritable}, " +
                        "sameDraft=${current.draft?.id == requestId}, sameSession=${current.session == auth.organizationScope()}",
                    error,
                )
            }
            assertEquals(
                "Known picker round trip keeps the same authorized session",
                revision,
                store.state.value.revision,
            )
            assertEquals(requestId, organizations.state.value.draft?.id)
            assertEquals("Synthetic Journey Organization", organizations.state.value.draft?.name)
            val expected = runBlocking {
                LocalImagePreparation.prepareBytes(photo.png, LocalImagePolicy.ORG_LOGO)
            }
            assertArrayEquals(
                "Never submit an image unless it matches our own selected fixture",
                expected,
                organizations.state.value.logoPreview!!.copyBytes(),
            )
            control("organization-logo-preview").assertIsDisplayed()
            screenshot("preview")
            control("organization-consent").performClick()
            control("organization-submit").assertIsEnabled().performClick()
            compose.waitUntil(30_000) {
                !organizations.state.value.busy &&
                    organizations.state.value.confirmedId == requestId
            }
            assertFalse(organizations.state.value.logoIncomplete)
            val created = runBlocking {
                LocalFirebase.firestore(context)
                    .document("organizations/$requestId")
                    .get(Source.SERVER)
                    .await()
            }
            assertEquals(uid, created.getString("submittedByUserId"))
            assertEquals("pendingReview", created.getString("moderationStatus"))
            assertEquals("Synthetic Journey Organization", created.getString("name"))
            val url = created.getString("logoURL")!!
            assertTrue(LocalStorage.urlMatches(url, "organizations/$requestId/logo.jpg"))
            assertArrayEquals(
                expected,
                runBlocking {
                    LocalStorage.instance(context)
                        .reference
                        .child("organizations/$requestId/logo.jpg")
                        .getBytes(3_000_000)
                        .await()
                },
            )
            ready()
            control("organization-confirmed").assertIsDisplayed()
            screenshot("submitted")
            control("organization-close-draft").performClick()
            compose.onNodeWithTag("organization-confirm-close-draft").performClick()
            seedRevision(requestId)
            compose.waitUntil(20_000) {
                organizations.state.value.hub?.requests?.any {
                    it.id == requestId && it.status == "needsRevision"
                } == true
            }
            ready()
            control("organization-edit-$requestId").performClick()
            control("organization-summary")
                .performTextReplacement("Revised synthetic description with clearer purpose")
            control("organization-submit").assertIsEnabled().performClick()
            compose.waitUntil(30_000) {
                !organizations.state.value.busy &&
                    organizations.state.value.confirmedId == requestId
            }
            ready()
            val revised = runBlocking {
                LocalFirebase.firestore(context)
                    .document("organizations/$requestId")
                    .get(Source.SERVER)
                    .await()
            }
            assertEquals("pendingReview", revised.getString("moderationStatus"))
            assertFalse(revised.contains("reviewMessage"))
            assertEquals(
                "Revised synthetic description with clearer purpose",
                revised.getString("shortDescription"),
            )
            control("organization-discard-$requestId").performClick()
            compose.onNodeWithTag("organization-confirm-discard").assertIsDisplayed().performClick()
            compose.waitUntil(30_000) {
                !organizations.state.value.busy &&
                    organizations.state.value.hub?.requests?.none { it.id == requestId } == true
            }
            val remaining = runBlocking {
                LocalFirebase.firestore(context)
                    .collection("organizations")
                    .whereEqualTo("submittedByUserId", uid)
                    .whereIn("moderationStatus", OrganizationContract.requestStatuses + "approved")
                    .whereGreaterThanOrEqualTo(FieldPath.documentId(), requestId)
                    .whereLessThanOrEqualTo(FieldPath.documentId(), requestId)
                    .get(Source.SERVER)
                    .await()
            }
            assertTrue(remaining.isEmpty)
            assertNull(organizations.state.value.draft)
            screenshot("discarded")
        } finally {
            PhotoPickerFixtures.delete(context, photo)
            requestId?.let { id ->
                deleteLogo(id)
                adminRequest("organizations/$id", "DELETE")
                adminRequest("organizationCreationProofs/$id", "DELETE")
            }
            runBlocking {
                runCatching { LocalFirebase.auth(context).currentUser?.delete()?.await() }
            }
            adminRequest("users/$uid", "DELETE")
            adminRequest("publicProfiles/$uid", "DELETE")
            runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        }
    }

    private fun prepareAccount(
        fixtures: LocalEmulatorFixtures,
        email: String,
        password: String,
    ): String = runBlocking {
        for (document in bundledReferenceLegal(context)) {
            fixtures.seed(
                "legalDocuments/${document.type}",
                mapOf(
                    "activeVersion" to document.version,
                    "status" to "published",
                    "requiresAcceptance" to document.requiresAcceptance,
                ),
            )
            fixtures.seed(
                "legalDocuments/${document.type}/versions/${document.version}",
                mapOf(
                    "version" to document.version,
                    "status" to "published",
                    "requiresAcceptance" to document.requiresAcceptance,
                    "locales" to
                        document.texts.mapValues { (locale, text) ->
                            mapOf("title" to document.title(locale), "contentText" to text)
                        },
                ),
            )
        }
        val auth = LocalFirebase.auth(context)
        val user = auth.createUserWithEmailAndPassword(email, password).await().user!!
        LocalFirebase.firestore(context)
            .document("users/${user.uid}")
            .set(
                registeredProfileFields(
                    user.uid,
                    AuthRegistration(
                        email,
                        "Synthetic Org Journey",
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
        auth.applyActionCode(fixtures.verificationCode(email)).await()
        user.reload().await()
        user.getIdToken(true).await()
        assertTrue(user.isEmailVerified)
        auth.signOut()
        user.uid
    }

    private fun seedRevision(id: String) {
        val fields =
            JSONObject()
                .put("moderationStatus", JSONObject().put("stringValue", "needsRevision"))
                .put(
                    "reviewMessage",
                    JSONObject().put("stringValue", "Synthetic review: please clarify"),
                )
                .put("updatedAt", JSONObject().put("timestampValue", Instant.now().toString()))
        adminRequest(
            "organizations/$id",
            "PATCH",
            JSONObject().put("fields", fields),
            "?updateMask.fieldPaths=moderationStatus&updateMask.fieldPaths=reviewMessage&updateMask.fieldPaths=updatedAt",
        )
    }

    private fun adminRequest(
        path: String,
        method: String,
        body: JSONObject? = null,
        suffix: String = "",
    ) =
        runBlocking(Dispatchers.IO) {
            LocalEnvironment.requireSafe()
            require(
                path.split('/').size == 2 &&
                    path.substringBefore('/') in
                        setOf(
                            "organizations",
                            "organizationCreationProofs",
                            "users",
                            "publicProfiles",
                        )
            )
            require(path.split('/').all { it.matches(Regex("[A-Za-z0-9_-]{1,128}")) })
            val connection =
                URL(
                        "http://10.0.2.2:8088/v1/projects/demo-uac-android/databases/(default)/documents/$path$suffix"
                    )
                    .openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                connection.instanceFollowRedirects = false
                connection.requestMethod = method
                connection.setRequestProperty("Authorization", "Bearer owner")
                if (body != null) {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.outputStream.use { it.write(body.toString().toByteArray()) }
                }
                check(
                    connection.responseCode in 200..299 ||
                        method == "DELETE" && connection.responseCode == 404
                ) {
                    "Synthetic organization fixture ${connection.responseCode}"
                }
            } finally {
                connection.disconnect()
            }
        }

    private fun screenshot(name: String) {
        compose.waitForIdle()
        val bitmap =
            InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
                ?: error("Screenshot unavailable")
        File(
                context.externalCacheDir ?: error("Screenshot directory unavailable"),
                "organization-journey-$name.png",
            )
            .outputStream()
            .use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        bitmap.recycle()
    }

    private fun deleteLogo(id: String) =
        runBlocking(Dispatchers.IO) {
            LocalEnvironment.requireSafe()
            require(OrganizationContract.id(id))
            val connection =
                URL(
                        "http://10.0.2.2:9198/v0/b/demo-uac-android.appspot.com/o/organizations%2F$id%2Flogo.jpg"
                    )
                    .openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 5000
                connection.readTimeout = 5000
                connection.instanceFollowRedirects = false
                connection.requestMethod = "DELETE"
                connection.setRequestProperty("Authorization", "Bearer owner")
                check(connection.responseCode in setOf(200, 204, 404)) {
                    "Synthetic journey logo cleanup failed"
                }
            } finally {
                connection.disconnect()
            }
        }
}
