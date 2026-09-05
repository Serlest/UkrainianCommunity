package at.uac.android

import android.graphics.Bitmap
import android.graphics.Color
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.gallery.*
import at.uac.android.feature.organization.OrganizationSession
import java.io.ByteArrayOutputStream
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GalleryUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = OrganizationSession("private-gallery-user", 1, true, "Synthetic", "user")
    private val id = "synthetic-ui-gallery"
    private val target = GalleryTarget(id, "synthetic-photo")
    private val organization =
        RawDocument(
            id,
            mapOf(
                "id" to id,
                "name" to "Gallery test",
                "ownerId" to session.uid,
                "moderationStatus" to "pendingReview",
                "photoCount" to 1,
            ),
        )
    private val photo =
        GalleryPhoto(
            target,
            GalleryContract.alias(target, "synthetic-token"),
            "Synthetic photo caption",
            session.uid,
            Instant.EPOCH,
            null,
        )
    private val snapshot = GallerySnapshot(organization, listOf(photo), false, 1)

    private fun state() = GalleryState(session, id, true, snapshot, fresh = true)

    private fun scroll(tag: String) =
        compose.onNodeWithTag("gallery-list").performScrollToNode(hasTestTag(tag))

    private fun prepared(width: Int = 32, height: Int = 16): PreparedGalleryPhoto {
        val bitmap =
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
                eraseColor(Color.BLUE)
            }
        try {
            return PreparedGalleryPhoto(
                ByteArrayOutputStream()
                    .also { assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 82, it)) }
                    .toByteArray(),
                width,
                height,
            )
        } finally {
            bitmap.recycle()
        }
    }

    private fun pending(phase: GalleryPhase = GalleryPhase.CREATE_SUBMITTED) =
        GalleryJournalEntry(
            GalleryContract.accountHash(session.uid),
            target,
            phase,
            "a".repeat(64),
            GalleryContract.hashText("Synthetic photo caption"),
            GalleryContract.accountHash(session.uid),
            "synthetic-token",
        )

    @Test
    fun preparedPreviewCaptionLimitAndExplicitUploadRemainReachableAtLargeFont() {
        val value = mutableStateOf(state().copy(prepared = prepared()))
        var requested = 0
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, 2f)) {
                MaterialTheme {
                    GalleryContent(
                        value.value,
                        "uk",
                        GalleryActions(
                            caption = { value.value = value.value.copy(caption = it) },
                            upload = { requested++ },
                        ),
                    )
                }
            }
        }
        scroll("gallery-prepared")
        compose.onNodeWithTag("gallery-prepared").assertIsDisplayed()
        scroll("gallery-caption")
        compose.onNodeWithTag("gallery-caption").performTextReplacement("x".repeat(501))
        scroll("gallery-upload")
        compose.onNodeWithTag("gallery-upload").assertIsNotEnabled()
        scroll("gallery-caption")
        compose
            .onNodeWithTag("gallery-caption")
            .performTextReplacement("Приватний чернетковий підпис")
        scroll("gallery-upload")
        compose.onNodeWithTag("gallery-upload").assertIsEnabled().performClick()
        compose.runOnIdle { assertEquals(1, requested) }
    }

    @Test
    fun sessionAndFreshPolicyLossRemoveAllCaptionsAndPrivatePreviewControls() {
        val value = mutableStateOf(state())
        val visible = mutableStateOf(true)
        compose.setContent {
            MaterialTheme { GalleryContent(value.value, "de", GalleryActions()) { visible.value } }
        }
        scroll("gallery-photo-${target.photoId}")
        compose.onNodeWithText(photo.caption!!).assertIsDisplayed()
        compose.runOnIdle { visible.value = false }
        compose.onNodeWithText(photo.caption!!).assertDoesNotExist()
        compose.onNodeWithTag("gallery-choose").assertDoesNotExist()
        compose.runOnIdle {
            visible.value = true
            value.value = value.value.forSession(null, id)
        }
        scroll("gallery-account")
        compose.onNodeWithTag("gallery-account").assertIsEnabled()
        compose.onNodeWithText(session.uid).assertDoesNotExist()
    }

    @Test
    fun uncertainCreateOffersOnlyReadOnlyReconciliation() {
        val entry = pending()
        var checked = false
        compose.setContent {
            MaterialTheme {
                GalleryContent(
                    state().copy(pending = listOf(entry), recovery = GalleryRecovery.UNRESOLVED),
                    "uk",
                    GalleryActions(
                        reconcile = {
                            assertEquals(entry, it)
                            checked = true
                        }
                    ),
                )
            }
        }
        scroll("gallery-reconcile-${target.photoId}")
        compose.onNodeWithTag("gallery-reconcile-${target.photoId}").performClick()
        compose.runOnIdle { assertTrue(checked) }
        compose.onNodeWithTag("gallery-cleanup-${target.photoId}").assertDoesNotExist()
        scroll("gallery-choose")
        compose.onNodeWithTag("gallery-choose").assertIsNotEnabled()
    }

    @Test
    fun cleanupRequiresConfirmedEligibilityAndSeparateExplicitConfirmation() {
        val entry = pending(GalleryPhase.METADATA_REMOVED)
        val value =
            mutableStateOf(
                state()
                    .copy(
                        pending = listOf(entry),
                        recovery = GalleryRecovery.CLEANUP_AVAILABLE,
                        recoveryFor = entry,
                    )
            )
        var cleanups = 0
        compose.setContent {
            MaterialTheme {
                GalleryContent(
                    value.value,
                    "de",
                    GalleryActions(
                        cleanup = {
                            value.value =
                                value.value.copy(confirmation = GalleryConfirmation.Cleanup(it))
                        },
                        confirm = { cleanups++ },
                    ),
                )
            }
        }
        scroll("gallery-cleanup-${target.photoId}")
        compose.onNodeWithTag("gallery-cleanup-${target.photoId}").performClick()
        compose.runOnIdle { assertEquals(0, cleanups) }
        compose.onNodeWithTag("gallery-confirm").assertIsDisplayed().performClick()
        compose.runOnIdle { assertEquals(1, cleanups) }
    }

    @Test
    fun legacyOverflowIsHonestReadOnlyWindow() {
        compose.setContent {
            MaterialTheme {
                GalleryContent(
                    state().copy(snapshot = snapshot.copy(overflow = true, counter = 99)),
                    "de",
                    GalleryActions(),
                )
            }
        }
        scroll("gallery-overflow")
        compose.onNodeWithTag("gallery-overflow").assertIsDisplayed()
        scroll("gallery-choose")
        compose.onNodeWithTag("gallery-choose").assertIsNotEnabled()
        scroll("gallery-preview-${target.photoId}")
        compose.onNodeWithTag("gallery-preview-${target.photoId}").assertIsEnabled()
        scroll("gallery-remove-${target.photoId}")
        compose.onNodeWithTag("gallery-remove-${target.photoId}").assertIsNotEnabled()
    }

    @Test
    fun accessUsesFreshHostRecordAndExactSystemRoleWithoutPhotoPrefetch() {
        val content = mutableStateOf(Content(ContentKind.ORGANIZATIONS, id, organization.fields))
        val current = mutableStateOf(session)
        val fresh = mutableStateOf(true)
        var opened = false
        compose.setContent {
            MaterialTheme {
                GalleryAccessPanel(
                    content.value,
                    current.value,
                    "uk",
                    {
                        assertEquals(id, it)
                        opened = true
                    },
                    { fresh.value },
                )
            }
        }
        compose.onNodeWithTag("gallery-open").performClick()
        compose.runOnIdle {
            assertTrue(opened)
            fresh.value = false
        }
        compose.onNodeWithTag("gallery-open").assertDoesNotExist()
        compose.runOnIdle {
            fresh.value = true
            content.value =
                content.value.copy(fields = content.value.fields + ("isSystemManaged" to true))
        }
        compose.onNodeWithTag("gallery-open").assertDoesNotExist()
        compose.runOnIdle { current.value = session.copy(globalRole = "owner") }
        compose.onNodeWithTag("gallery-open").assertIsEnabled()
    }

    @Test
    fun extremePortraitAndPanoramaPreviewHaveBoundedHeightWithoutChangingJpeg() {
        val tall = prepared(1, 1600)
        val wide = prepared(1600, 1)
        val landscape = prepared(240, 160)
        val value = mutableStateOf(state().copy(prepared = tall))
        compose.setContent { MaterialTheme { GalleryContent(value.value, "de", GalleryActions()) } }
        for (photo in listOf(tall, wide, landscape)) {
            val original = photo.bytes()
            compose.runOnIdle { value.value = value.value.copy(prepared = photo) }
            scroll("gallery-prepared")
            compose.onNodeWithTag("gallery-prepared").assertIsDisplayed()
            val bounds = compose.onNodeWithTag("gallery-prepared").getUnclippedBoundsInRoot()
            val height = bounds.bottom.value - bounds.top.value
            val width = bounds.right.value - bounds.left.value
            assertTrue(height in 0.9f..320.1f)
            assertTrue(width > 0f)
            val expectedHeight = (width * photo.height / photo.width).coerceIn(1f, 320f)
            assertEquals(expectedHeight, height, 1f)
            assertArrayEquals(original, value.value.prepared!!.bytes())
            scroll("gallery-upload")
            compose.onNodeWithTag("gallery-upload").assertIsDisplayed().assertIsEnabled()
        }
    }
}
