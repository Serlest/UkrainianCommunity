package at.uac.android

import android.content.ContentValues
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.provider.MediaStore
import android.view.inputmethod.InputMethodManager
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.accountdeletion.AccountDeletionViewModel
import at.uac.android.feature.auth.AuthGate
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.LocalAuthSession
import at.uac.android.feature.browse.BrowseViewModel
import at.uac.android.feature.contentlifecycle.ContentLifecycleViewModel
import at.uac.android.feature.gallery.GalleryViewModel
import at.uac.android.feature.organization.OrganizationViewModel
import at.uac.android.feature.personal.PersonalViewModel
import at.uac.android.feature.personal.PersonalProfileEditorViewModel
import at.uac.android.feature.personal.personalScope
import at.uac.android.feature.profilemedia.ProfileMediaViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Only disposable users supplied by test-profile-deletion-staging.mjs. */
@RunWith(AndroidJUnit4::class)
class StagingProfileDeletionJourneyTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    private val args get() = InstrumentationRegistry.getArguments()
    private val suffix get() = args.getString("profileSuffix").orEmpty()

    private fun login(which: String) {
        assertEquals("at.serlest.ukrainiancommunity.staging", compose.activity.packageName)
        assertTrue(suffix.matches(Regex("[a-f0-9]{16}")))
        val email = args.getString("${which}Email").orEmpty()
        val password = args.getString("${which}Password").orEmpty()
        assertEquals("profile-step5-$which-$suffix@example.invalid", email)
        assertTrue(password.length >= 20)
        val auth = LocalAuthSession.get(compose.activity)
        compose.runOnIdle { auth.signOut() }
        compose.waitUntil(60_000) { compose.onAllNodesWithTag("auth-login-submit").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("auth-email").performScrollTo().performTextInput(email)
        compose.onNodeWithTag("auth-password").performScrollTo().performTextInput(password)
        compose.onNodeWithTag("auth-login-submit").performScrollTo().performClick()
        compose.waitUntil(60_000) {
            auth.state.value.let { it.stage == AuthStage.AUTHENTICATED && it.gate == AuthGate.READY }
        }
        compose.runOnIdle {
            compose.activity.currentFocus?.clearFocus()
            (compose.activity.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager)
                .hideSoftInputFromWindow(compose.activity.window.decorView.windowToken, 0)
        }
    }

    @Test fun avatarAndProfileEditThroughUi() {
        login("a")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val personal = ViewModelProvider(compose.activity)[PersonalViewModel::class.java]
        val editor = ViewModelProvider(compose.activity)[PersonalProfileEditorViewModel::class.java]
        val media = ViewModelProvider(compose.activity)[ProfileMediaViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/edit") }
        compose.waitUntil(60_000) { personal.state.value.profile != null && media.state.value.session?.ready == true }
        val bitmap = Bitmap.createBitmap(320, 320, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.rgb(42, 92, 142)) }
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "uac-step5-$suffix.jpg")
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
        }
        val resolver = compose.activity.contentResolver
        val uri = requireNotNull(resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values))
        try {
            resolver.openOutputStream(uri)!!.use { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
            val session = LocalAuthSession.get(compose.activity).state.value.personalScope()
            compose.runOnIdle { media.select(uri.toString(), session) }
            compose.waitUntil(60_000) { media.state.value.selection != null && !media.state.value.busy }
            compose.onNodeWithTag("account-scroll").performScrollToNode(hasTestTag("profile-avatar-upload"))
            compose.onNodeWithTag("profile-avatar-upload").performClick()
            compose.waitUntil(90_000) {
                !media.state.value.busy && (media.state.value.confirmed != null || media.state.value.error != null)
            }
            assertNull(media.state.value.error)
            compose.waitUntil(60_000) {
                compose.onAllNodesWithTag("profile-avatar-confirmed").fetchSemanticsNodes().isNotEmpty()
            }
            compose.waitUntil(60_000) {
                editor.state.value.draft.avatarUrl == media.state.value.confirmed?.draft?.avatarUrl &&
                    editor.state.value.confirmedSession == personal.state.value.session
            }
            compose.onNodeWithTag("account-scroll").performScrollToNode(hasTestTag("profile-bio"))
            compose.onNodeWithTag("profile-bio").performTextInput("Step5 profile $suffix")
            compose.waitUntil(30_000) { editor.state.value.draft.bio == "Step5 profile $suffix" }
            compose.onNodeWithTag("account-scroll").performScrollToNode(hasTestTag("profile-save"))
            compose.onNodeWithTag("profile-save").performClick()
            compose.waitUntil(60_000) { personal.state.value.let {
                it.profileError != null || it.profile?.draft?.bio == "Step5 profile $suffix" && it.profileSaved
            } }
            assertNull(personal.state.value.profileError)
            assertTrue(personal.state.value.profileSaved)
        } finally {
            resolver.delete(uri, null, null)
            bitmap.recycle()
        }
    }

    @Test fun accountSwitchKeepsProfilesSeparate() {
        login("a")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val personal = ViewModelProvider(compose.activity)[PersonalViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/edit") }
        compose.waitUntil(60_000) { personal.state.value.profile?.draft?.bio == "Step5 profile $suffix" }
        login("b")
        compose.runOnIdle { browse.navigate("profile/edit") }
        compose.waitUntil(60_000) { personal.state.value.profile?.email?.startsWith("profile-step5-b-") == true }
        assertEquals("", personal.state.value.profile?.draft?.avatarUrl)
        assertEquals("", personal.state.value.profile?.draft?.bio)
    }

    @Test fun deleteOwnAccountThroughUi() {
        login("a")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val deletion = ViewModelProvider(compose.activity)[AccountDeletionViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/delete") }
        compose.waitUntil(60_000) { deletion.state.value.policy != null && !deletion.state.value.busy }
        assertEquals(false, deletion.state.value.policy?.platformOwner)
        assertEquals(false, deletion.state.value.policy?.ownsOrganization)
        compose.onNodeWithTag("account-delete-open").performScrollTo().performClick()
        compose.onNodeWithTag("account-delete-password").performTextInput(args.getString("aPassword").orEmpty())
        compose.onNodeWithTag("account-delete-confirmation").performTextInput("LÖSCHEN")
        compose.onNodeWithTag("account-delete-acknowledge").performClick()
        compose.onNodeWithTag("account-delete-submit").performClick()
        compose.waitUntil(180_000) {
            browse.state.value.route == "profile/deleted" || deletion.state.value.receipt != null ||
                deletion.state.value.error != null
        }
        assertNull(deletion.state.value.error)
        assertTrue(browse.state.value.route == "profile/deleted" || deletion.state.value.receipt != null)
    }

    @Test fun galleryUploadThroughUi() {
        login("b")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val gallery = ViewModelProvider(compose.activity)[GalleryViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/organizations/gallery/step5-gallery-$suffix") }
        compose.waitUntil(60_000) { gallery.state.value.readable && gallery.state.value.snapshot?.photos?.isEmpty() == true }
        val bitmap = Bitmap.createBitmap(480, 320, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.rgb(72, 126, 88)) }
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, "uac-gallery-step5-$suffix.jpg")
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
        }
        val resolver = compose.activity.contentResolver
        val uri = requireNotNull(resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values))
        try {
            resolver.openOutputStream(uri)!!.use { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it)) }
            compose.runOnIdle { assertTrue(gallery.beginPicker()) }
            compose.runOnIdle { gallery.pickerResult(uri.toString()) }
            compose.waitUntil(60_000) { gallery.state.value.prepared != null && !gallery.state.value.locked }
            compose.onNodeWithTag("gallery-list").performScrollToNode(hasTestTag("gallery-caption"))
            compose.onNodeWithTag("gallery-caption").performTextInput("Step5 gallery $suffix")
            compose.onNodeWithTag("gallery-list").performScrollToNode(hasTestTag("gallery-upload"))
            compose.onNodeWithTag("gallery-upload").performClick()
            compose.onNodeWithTag("gallery-confirm").performClick()
            compose.waitUntil(120_000) {
                gallery.state.value.let { !it.busy && (it.snapshot?.photos?.size == 1 || it.error != null) }
            }
            assertNull(gallery.state.value.error)
            assertEquals("Step5 gallery $suffix", gallery.state.value.snapshot?.photos?.single()?.caption)
        } finally {
            resolver.delete(uri, null, null)
            bitmap.recycle()
        }
    }

    @Test fun galleryRemoveThroughUi() {
        login("b")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val gallery = ViewModelProvider(compose.activity)[GalleryViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/organizations/gallery/step5-gallery-$suffix") }
        compose.waitUntil(60_000) { gallery.state.value.readable && gallery.state.value.snapshot?.photos?.size == 1 }
        compose.waitForIdle()
        val id = gallery.state.value.snapshot!!.photos.single().target.photoId
        compose.onNodeWithTag("gallery-list").performScrollToNode(hasTestTag("gallery-remove-$id"))
        compose.onNodeWithTag("gallery-remove-$id").performClick()
        compose.onNodeWithTag("gallery-confirm").performClick()
        compose.waitUntil(120_000) {
            gallery.state.value.let { !it.busy && (it.snapshot?.photos?.isEmpty() == true || it.error != null) }
        }
        assertNull(gallery.state.value.error)
        assertTrue(gallery.state.value.snapshot?.photos?.isEmpty() == true)
    }

    @Test fun organizationRequestCreateThroughUi() {
        login("b")
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val organization = ViewModelProvider(compose.activity)[OrganizationViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/organizations") }
        compose.waitUntil(60_000) { organization.state.value.hub != null && organization.state.value.rules != null && !organization.state.value.loading }
        compose.onNodeWithTag("organization-create").performScrollTo().performClick()
        compose.onNodeWithTag("organization-name").performScrollTo().performTextInput("Step5 Request $suffix")
        compose.onNodeWithTag("organization-summary").performScrollTo().performTextInput("Synthetic organization application for Android step five")
        compose.onNodeWithTag("organization-region").performScrollTo().performClick()
        compose.onNodeWithTag("organization-region-wien").performClick()
        compose.onNodeWithTag("organization-city").performScrollTo().performTextInput("Wien")
        compose.onNodeWithTag("organization-consent").performScrollTo().performClick()
        compose.onNodeWithTag("organization-submit").performScrollTo().performClick()
        compose.waitUntil(90_000) { organization.state.value.let { !it.busy && (it.confirmedId != null || it.error != null) } }
        assertNull(organization.state.value.error)
        assertEquals("pendingReview", organization.state.value.base?.status)
    }

    @Test fun organizationRequestReviseThroughUi() {
        login("b")
        val id = args.getString("requestId").orEmpty()
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val organization = ViewModelProvider(compose.activity)[OrganizationViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/organizations") }
        compose.waitUntil(60_000) { organization.state.value.hub?.requests?.any { it.id == id } == true && !organization.state.value.loading }
        compose.onNodeWithTag("organization-edit-$id").performScrollTo().performClick()
        compose.onNodeWithTag("organization-summary").performScrollTo()
            .performTextReplacement("Revised organization application for Android step five")
        compose.onNodeWithTag("organization-submit").performScrollTo().performClick()
        compose.waitUntil(90_000) { organization.state.value.let { !it.busy && (it.confirmedId == id || it.error != null) } }
        assertNull(organization.state.value.error)
        assertEquals("pendingReview", organization.state.value.base?.status)
    }

    @Test fun organizationRequestDiscardThroughUi() {
        login("b")
        val id = args.getString("requestId").orEmpty()
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val organization = ViewModelProvider(compose.activity)[OrganizationViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/organizations") }
        compose.waitUntil(60_000) { organization.state.value.hub?.requests?.any { it.id == id } == true && !organization.state.value.loading }
        compose.onNodeWithTag("organization-discard-$id").performScrollTo().performClick()
        compose.onNodeWithTag("organization-confirm-discard").performClick()
        compose.waitUntil(90_000) { organization.state.value.let { !it.busy && (it.confirmedId == id || it.error != null) } }
        assertNull(organization.state.value.error)
        compose.waitUntil(60_000) { organization.state.value.hub?.requests?.none { it.id == id } == true }
    }

    @Test fun newsDeleteThroughUi() {
        login("b")
        val newsId = args.getString("newsId").orEmpty()
        val browse = ViewModelProvider(compose.activity)[BrowseViewModel::class.java]
        val lifecycle = ViewModelProvider(compose.activity)[ContentLifecycleViewModel::class.java]
        compose.runOnIdle { browse.navigate("profile/organizations/lifecycle/step5-gallery-$suffix/news/$newsId") }
        var submitted = false
        for (attempt in 0 until 4) {
            compose.waitUntil(90_000) { lifecycle.state.value.actionable || lifecycle.state.value.error != null }
            assertNull(lifecycle.state.value.error)
            compose.onNodeWithTag("content-lifecycle-request").performScrollTo().performClick()
            compose.waitForIdle()
            if (lifecycle.state.value.confirmation == null) continue
            try {
                compose.onNodeWithTag("content-lifecycle-confirm").performClick()
                submitted = true
                break
            } catch (error: AssertionError) {
                if (lifecycle.state.value.confirmation != null) throw error
            }
        }
        assertTrue("News confirmation never became actionable", submitted)
        compose.waitUntil(180_000) { lifecycle.state.value.let { it.confirmed != null || it.error != null } }
        assertNull(lifecycle.state.value.error)
        assertTrue(lifecycle.state.value.confirmed != null)
    }
}
