package at.uac.android

import android.graphics.Bitmap
import android.os.SystemClock
import android.util.Log
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalImagePolicy
import at.uac.android.core.LocalImagePreparation
import at.uac.android.core.LocalStorage
import at.uac.android.feature.auth.AuthRegistration
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.auth.registeredProfileFields
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.personal.PersonalViewModel
import at.uac.android.feature.personal.personalScope
import at.uac.android.feature.profilemedia.ProfileMediaViewModel
import at.uac.android.feature.profilemedia.profileAvatarPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.Source
import com.google.firebase.storage.StorageException
import java.io.File
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
 * Actual MainActivity → system Photo Picker → Storage → private/public profile, not a injected
 * picker callback.
 */
@RunWith(AndroidJUnit4::class)
class ProfileAvatarJourneyUiTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val instrumentation
        get() = InstrumentationRegistry.getInstrumentation()

    private val context
        get() = instrumentation.targetContext

    private val store
        get() = LocalAuthSession.get(context)

    private val browse
        get() = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]

    private val personal
        get() = ViewModelProvider(compose.activity)[PersonalViewModel::class.java]

    private val media
        get() = ViewModelProvider(compose.activity)[ProfileMediaViewModel::class.java]

    private val password = "Synthetic-avatar-journey-only!"

    private fun account(tag: String) {
        compose.onNodeWithTag(tag).performScrollTo()
    }

    @Test
    fun realSystemPickerPreservesSessionDirtyTextAndConfirmsOwnAvatar() {
        runBlocking { withContext(Dispatchers.Main) { store.signOut() }.join() }
        compose.runOnIdle {
            browse.preference("language", "de")
            browse.navigate("profile", true)
        }
        if (InstrumentationRegistry.getArguments().getString("expectEmulator") != "true") {
            account("guest-sign-in")
            compose.onNodeWithTag("guest-sign-in").assertIsDisplayed()
            assertNull(media.state.value.selection)
            return
        }
        val email = "avatar-journey-${UUID.randomUUID()}@example.invalid"
        val auth = LocalFirebase.auth(context)
        val db = LocalFirebase.firestore(context)
        var uid: String? = null
        var gallery: PhotoPickerFixtures.Fixture? = null
        try {
            runBlocking {
                AuthEmulatorFixtures.seedLegalReference()
                val user = auth.createUserWithEmailAndPassword(email, password).await().user!!
                uid = user.uid
                db.document("users/${user.uid}")
                    .set(
                        registeredProfileFields(
                            user.uid,
                            AuthRegistration(
                                email,
                                "Avatar Journey Demo",
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
                auth.applyActionCode(AuthEmulatorFixtures.actionCode(email, "VERIFY_EMAIL")).await()
                user.reload().await()
                auth.currentUser!!.getIdToken(true).await()
                assertTrue(auth.currentUser!!.isEmailVerified)
                auth.signOut()
            }
            gallery = PhotoPickerFixtures.create(context, "UAC-Avatar")
            val expected = runBlocking {
                LocalImagePreparation.prepareBytes(gallery.png, LocalImagePolicy.AVATAR)
            }
            compose.openGuestLogin()
            account("auth-email")
            compose.onNodeWithTag("auth-email").performTextReplacement(email)
            account("auth-password")
            compose.onNodeWithTag("auth-password").performTextReplacement(password)
            account("auth-login-submit")
            compose.onNodeWithTag("auth-login-submit").performClick()
            compose.waitUntil(30_000) { store.state.value.readyForActions }
            val captured = store.state.value.personalScope()!!
            account("account-open-edit")
            compose.onNodeWithTag("account-open-edit").performClick()
            compose.waitUntil(15_000) {
                personal.state.value.profile?.uid == uid && !personal.state.value.profileLoading
            }
            account("profile-display-name")
            compose
                .onNodeWithTag("profile-display-name")
                .performTextReplacement("Draft survives system picker")

            // Real cancellation is also a controlled foreground return, never a sign-out/refresh
            // that erases the form.
            account("profile-avatar-choose")
            compose.onNodeWithTag("profile-avatar-choose").performClick()
            compose.waitUntil(10_000) { PhotoPickerFixtures.focusedPickerWindow() }
            val cancellationStarted = SystemClock.elapsedRealtime()
            fun cancellationState(): String {
                val automation = instrumentation.uiAutomation
                val root = automation.rootInActiveWindow
                val windows =
                    automation.windows.joinToString(";") {
                        "type=${it.type},active=${it.isActive},focused=${it.isFocused},package=${it.root?.packageName}"
                    }
                return "pickerOpen=${media.state.value.pickerOpen},pickerVisible=${PhotoPickerFixtures.pickerVisible()}," +
                    "scopeMatches=${store.state.value.personalScope() == captured},stage=${store.state.value.stage}," +
                    "gate=${store.state.value.gate},activityState=${compose.activity.lifecycle.currentState}," +
                    "appWindowFocus=${compose.activity.hasWindowFocus()},activePackage=${root?.packageName},windows=[$windows]"
            }
            Log.i("UACJourneyTrace", "avatar before-single-back ${cancellationState()}")
            PhotoPickerFixtures.cancelFocusedPickerOnce()
            var lastCancellationState = ""
            try {
                compose.waitUntil(15_000) {
                    val trace = cancellationState()
                    if (trace != lastCancellationState) {
                        Log.i(
                            "UACJourneyTrace",
                            "avatar after-single-back elapsed=${SystemClock.elapsedRealtime() - cancellationStarted} $trace",
                        )
                        lastCancellationState = trace
                    }
                    !media.state.value.pickerOpen && !PhotoPickerFixtures.pickerVisible()
                }
            } catch (failure: Throwable) {
                Log.i("UACJourneyTrace", "avatar cancel-timeout ${cancellationState()}")
                runCatching { screenshot("android-profile-avatar-cancel-timeout.png") }
                throw failure
            }
            assertEquals(captured, store.state.value.personalScope())
            account("profile-display-name")
            compose
                .onNodeWithTag("profile-display-name")
                .assertTextContains("Draft survives system picker")
            assertNull(media.state.value.selection)

            account("profile-avatar-choose")
            compose.onNodeWithTag("profile-avatar-choose").performClick()
            try {
                PhotoPickerFixtures.selectOnlyPhoto(gallery)
                compose.waitUntil(20_000) {
                    media.state.value.selection != null && !media.state.value.busy ||
                        media.state.value.error != null ||
                        store.state.value.personalScope() != captured
                }
                assertNull("Picker preparation must succeed", media.state.value.error)
                assertEquals(
                    "Picker result must retain its exact authorized session",
                    captured,
                    store.state.value.personalScope(),
                )
                assertNotNull(
                    "Native picker must return a prepared image",
                    media.state.value.selection,
                )
            } catch (error: Throwable) {
                screenshot("android-profile-avatar-picker-diagnostic.png")
                val state = media.state.value
                val authState = store.state.value
                throw AssertionError(
                    "Avatar picker result: stage=${authState.stage}, gate=${authState.gate}, revision=${authState.revision}, expectedRevision=${captured.revision}, pickerOpen=${state.pickerOpen}, preparing=${state.preparing}, selected=${state.selection != null}, phase=${state.phase}, error=${state.error}\n${PhotoPickerFixtures.diagnosticState()}",
                    error,
                )
            }
            assertEquals(captured, store.state.value.personalScope())
            // A wrong native selection stops here before any upload, even if the system UI ever
            // changes.
            assertArrayEquals(expected, media.state.value.selection!!.jpeg)
            account("profile-display-name")
            compose
                .onNodeWithTag("profile-display-name")
                .assertTextContains("Draft survives system picker")
            account("profile-avatar-preview")
            compose.onNodeWithTag("profile-avatar-preview").assertIsDisplayed()
            screenshot("android-profile-avatar-preview.png")
            account("profile-avatar-upload")
            compose.onNodeWithTag("profile-avatar-upload").performClick()
            compose.waitUntil(30_000) {
                media.state.value.confirmed != null || media.state.value.error != null
            }
            assertNull(media.state.value.error)
            assertNotNull(media.state.value.confirmed)
            account("profile-avatar-confirmed")
            compose.onNodeWithTag("profile-avatar-confirmed").assertIsDisplayed()
            val uploadedUrl = media.state.value.confirmed!!.draft.avatarUrl
            runBlocking {
                val privateProfile = db.document("users/$uid").get(Source.SERVER).await()
                val publicProfile = db.document("publicProfiles/$uid").get(Source.SERVER).await()
                assertEquals("Avatar Journey Demo", privateProfile.getString("displayName"))
                assertEquals(uploadedUrl, privateProfile.getString("avatarURL"))
                assertEquals(uploadedUrl, publicProfile.getString("avatarURL"))
                assertArrayEquals(
                    expected,
                    LocalStorage.instance(context)
                        .reference
                        .child(profileAvatarPath(uid!!))
                        .getBytes(1_500_000)
                        .await(),
                )
                assertFalse(publicProfile.contains("email"))
                assertFalse(publicProfile.contains("bio"))
            }
            account("profile-display-name")
            compose
                .onNodeWithTag("profile-display-name")
                .assertTextContains("Draft survives system picker")
            account("profile-save")
            compose.onNodeWithTag("profile-save").performClick()
            compose.waitUntil(15_000) {
                personal.state.value.profileSaved || personal.state.value.profileError != null
            }
            assertNull(personal.state.value.profileError)
            runBlocking {
                assertEquals(
                    "Draft survives system picker",
                    db.document("users/$uid").get(Source.SERVER).await().getString("displayName"),
                )
            }
            account("profile-saved")
            compose.onNodeWithTag("profile-saved").assertIsDisplayed()
            screenshot("android-profile-avatar-confirmed.png")
            compose.onNodeWithTag("back").performClick()
            account("auth-signout")
            compose.onNodeWithTag("auth-signout").performClick()
            compose.waitUntil(15_000) {
                store.state.value.stage == AuthStage.GUEST && media.state.value.session == null
            }
            assertNull(media.state.value.selection)
            assertNull(media.state.value.confirmed)
            assertNull(personal.state.value.profile)
        } finally {
            if (PhotoPickerFixtures.pickerVisible())
                instrumentation.uiAutomation.executeShellCommand("input keyevent 4").close()
            gallery?.let { PhotoPickerFixtures.delete(context, it) }
            runBlocking {
                if (uid != null) {
                    if (auth.currentUser?.uid != uid)
                        auth.signInWithEmailAndPassword(email, password).await()
                    try {
                        LocalStorage.instance(context)
                            .reference
                            .child(profileAvatarPath(uid))
                            .delete()
                            .await()
                    } catch (error: StorageException) {
                        if (error.errorCode != StorageException.ERROR_OBJECT_NOT_FOUND) throw error
                    }
                    auth.currentUser?.delete()?.await()
                    withContext(Dispatchers.IO) {
                        listOf("users/$uid", "publicProfiles/$uid").forEach {
                            AuthEmulatorFixtures.adminRequest(
                                8088,
                                AuthEmulatorFixtures.documentPath(it),
                                "DELETE",
                            )
                        }
                    }
                }
                withContext(Dispatchers.Main) { store.signOut() }.join()
            }
        }
    }

    private fun screenshot(name: String) {
        instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
            try {
                File(context.externalCacheDir, name).outputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
            } finally {
                bitmap.recycle()
            }
        }
    }
}
