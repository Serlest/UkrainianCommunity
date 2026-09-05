package at.uac.android

import android.graphics.Bitmap
import android.graphics.Color
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.core.LocalStorage
import at.uac.android.feature.personal.*
import at.uac.android.feature.profilemedia.*
import java.io.ByteArrayOutputStream
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProfileMediaUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = PersonalSession("synthetic-avatar-ui", true, true, 1)
    private val url =
        "http://10.0.2.2:9198/v0/b/${LocalStorage.BUCKET}/o/profileImages%2F${session.uid}%2Favatar.jpg?alt=media"
    private val profile =
        PersonalProfile(
            session.uid,
            "avatar-ui@example.invalid",
            ProfileDraft("Demo", "Demo", "Wien", "", "", "wien", url),
            Instant.EPOCH,
        )

    private fun photo(): PreparedAvatar {
        val bitmap = Bitmap.createBitmap(16, 16, Bitmap.Config.ARGB_8888)
        try {
            bitmap.eraseColor(Color.BLUE)
            return PreparedAvatar(
                ByteArrayOutputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 82, it)
                    it.toByteArray()
                }
            )
        } finally {
            bitmap.recycle()
        }
    }

    @Test
    fun previewRequiresExplicitSaveAndDisablesDuplicatePendingAction() {
        val state = mutableStateOf(ProfileMediaState(session = session, selection = photo()))
        var saved = 0
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    ProfileAvatarPanel(
                        state.value,
                        "de",
                        true,
                        {},
                        {
                            saved++
                            state.value = state.value.copy(phase = ProfileMediaPhase.UPLOADING)
                        },
                        {},
                        {},
                    )
                }
            }
        }
        compose.onNodeWithTag("profile-avatar-preview").performScrollTo().assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, saved) }
        compose.onNodeWithTag("profile-avatar-upload").performScrollTo().performClick()
        compose.onNodeWithTag("profile-avatar-upload").assertIsNotEnabled()
        compose.onNodeWithTag("profile-avatar-choose").performScrollTo().assertIsNotEnabled()
        compose.runOnIdle { assertEquals(1, saved) }
    }

    @Test
    fun confirmedPhotoIsDeliveredOnlyOnceAcrossEditorReentry() {
        val visible = mutableStateOf(true)
        val state =
            mutableStateOf(
                ProfileMediaState(session = session, selection = photo(), confirmed = profile)
            )
        var deliveries = 0
        compose.setContent {
            MaterialTheme {
                if (visible.value)
                    Column(Modifier.verticalScroll(rememberScrollState())) {
                        ProfileAvatarPanel(
                            state.value,
                            "uk",
                            true,
                            {},
                            {},
                            {},
                            {
                                assertEquals(url, it)
                                deliveries++
                                state.value = state.value.copy(confirmationDelivered = true)
                            },
                        )
                    }
            }
        }
        compose.onNodeWithTag("profile-avatar-confirmed").performScrollTo().assertIsDisplayed()
        compose.runOnIdle {
            assertEquals(1, deliveries)
            visible.value = false
        }
        compose.waitForIdle()
        compose.runOnIdle { visible.value = true }
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(1, deliveries) }
        compose.onNodeWithTag("profile-avatar-upload").assertDoesNotExist()
    }

    @Test
    fun avatarHookKeepsUnsavedTextAndPassesOnlyOwnCanonicalUrl() {
        var saved: ProfileDraft? = null
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    PersonalProfilePanel(
                        PersonalState(
                            session = session,
                            profile = profile.copy(draft = profile.draft.copy(avatarUrl = "")),
                        ),
                        "de",
                        {},
                        { saved = it },
                        avatarEditor = { _, _, onConfirmed ->
                            Button(
                                onClick = { onConfirmed(url) },
                                modifier = Modifier.testTag("synthetic-avatar-confirm"),
                            ) {
                                Text("Confirm photo")
                            }
                        },
                    )
                }
            }
        }
        compose
            .onNodeWithTag("profile-display-name")
            .performScrollTo()
            .performTextReplacement("Unsaved personal name")
        compose.onNodeWithTag("synthetic-avatar-confirm").performScrollTo().performClick()
        compose.onNodeWithTag("profile-save").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals("Unsaved personal name", saved?.displayName)
            assertEquals(url, saved?.avatarUrl)
            assertTrue(saved!!.validFor(session.uid))
        }
        compose.onNodeWithTag("profile-avatar-url").assertDoesNotExist()
    }

    @Test
    fun profileRefreshUpdatesCleanFieldsAndKeepsDirtyNameUntilAccountChanges() {
        var saved: ProfileDraft? = null
        val state = mutableStateOf(PersonalState(session = session, profile = profile))
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    PersonalProfilePanel(state.value, "de", {}, { saved = it })
                }
            }
        }
        compose
            .onNodeWithTag("profile-display-name")
            .performScrollTo()
            .performTextReplacement("Still editing")
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    profile =
                        profile.copy(
                            draft = profile.draft.copy(city = "Graz"),
                            updatedAt = Instant.EPOCH.plusSeconds(1),
                        )
                )
        }
        compose.onNodeWithTag("profile-save").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals("Still editing", saved?.displayName)
            assertEquals("Graz", saved?.city)
        }
        compose.runOnIdle {
            state.value = PersonalState(session = session.copy(revision = 2), profile = profile)
        }
        compose.onNodeWithTag("profile-save").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals("Demo", saved?.displayName)
            assertEquals("Wien", saved?.city)
        }
    }

    @Test
    fun accountMaskRemovesPhotoReceiptAndDisablesPersonalAction() {
        val value =
            mutableStateOf(
                ProfileMediaState(session = session, selection = photo(), confirmed = profile)
            )
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    ProfileAvatarPanel(value.value, "de", true, {}, {}, {}, {})
                }
            }
        }
        compose.onNodeWithTag("profile-avatar-preview").performScrollTo().assertIsDisplayed()
        compose.runOnIdle { value.value = value.value.forSession(null) }
        compose.onNodeWithTag("profile-avatar-preview").assertDoesNotExist()
        compose.onNodeWithTag("profile-avatar-confirmed").assertDoesNotExist()
        compose.onNodeWithTag("profile-avatar-choose").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun explicitAvatarRemovalClearsOldConfirmedPreviewWithoutRestoringUrl() {
        val currentUrl = mutableStateOf("")
        val source =
            object : ProfileMediaSource {
                override suspend fun upload(
                    uid: String,
                    photo: PreparedAvatar,
                    operation: AvatarOperation,
                    onProgress: (Float) -> Unit,
                ) = url

                override suspend fun saveAvatar(
                    uid: String,
                    url: String,
                    stillCurrent: () -> Boolean,
                ) = profile
            }
        val model = ProfileMediaViewModel(source, ProfilePhotoPreparation { photo() }, { session })
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    ProfileAvatarEditor(
                        model.state.collectAsState().value,
                        "de",
                        true,
                        currentUrl.value,
                        model,
                    ) {
                        currentUrl.value = it
                    }
                }
            }
        }
        compose.runOnIdle {
            model.bind(session)
            model.select("content://synthetic/avatar", session)
        }
        compose.waitUntil { model.state.value.selection != null }
        compose.onNodeWithTag("profile-avatar-upload").performScrollTo().performClick()
        compose.waitUntil { model.state.value.confirmationDelivered }
        compose.runOnIdle {
            assertEquals(url, currentUrl.value)
            currentUrl.value = ""
        }
        compose.waitUntil { model.state.value.confirmed == null }
        compose.onNodeWithTag("profile-avatar-preview").assertDoesNotExist()
        compose.runOnIdle { assertEquals("", currentUrl.value) }
    }
}
