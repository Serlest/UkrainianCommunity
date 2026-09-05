package at.uac.android

import android.graphics.Bitmap
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Density
import at.uac.android.feature.authoring.*
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.contentmedia.*
import at.uac.android.feature.organization.*
import java.io.ByteArrayOutputStream
import java.time.Instant
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ContentCoverUiTest {
    @get:Rule val compose = createComposeRule()
    private val actor = OrganizationSession("cover-ui-owner", 1, true, "Owner", "user")
    private val now = Instant.parse("2026-09-03T03:00:00Z")

    private fun snapshot(
        kind: ContentKind = ContentKind.NEWS,
        existing: Boolean = false,
    ): ContentCoverSnapshot {
        val basics =
            OrganizationDraft(
                "cover-ui-org",
                "Cover organization",
                "A complete synthetic organization",
                region = "wien",
                city = "Wien",
            )
        val org =
            OrganizationContract.record(
                RawDocument(
                    basics.id,
                    OrganizationContract.create(basics, actor, now) +
                        mapOf("ownerId" to actor.uid, "moderationStatus" to "approved"),
                ),
                actor,
            )
        val draft =
            AuthoringContract.newDraft(kind, org, now)
                .copy(
                    id = "cover-ui-content",
                    title = "Private synthetic title",
                    summary = "Summary",
                    body = "Body",
                )
                .let {
                    if (kind == ContentKind.EVENTS) it.copy(event = it.event.copy(venue = "Hall"))
                    else it
                }
        val fields =
            AuthoringContract.submission(draft, org, actor, null, now).fields +
                if (existing) mapOf("imageURL" to "https://example.invalid/existing")
                else emptyMap()
        val item =
            AuthoringContract.item(
                kind,
                RawDocument(draft.id, fields),
                org.id,
                AuthoringStatus.APPROVED,
                actor,
            )
        return ContentCoverSnapshot(ContentCoverTarget(org.id, kind, draft.id), org, item)
    }

    private fun photo(): PreparedContentCover {
        val image = Bitmap.createBitmap(160, 90, Bitmap.Config.ARGB_8888)
        val bytes =
            try {
                ByteArrayOutputStream().use {
                    image.compress(Bitmap.CompressFormat.JPEG, 82, it)
                    it.toByteArray()
                }
            } finally {
                image.recycle()
            }
        return PreparedContentCover(bytes, 160, 90)
    }

    private fun state(
        snapshot: ContentCoverSnapshot = snapshot(),
        photo: PreparedContentCover? = null,
    ) =
        ContentCoverState(
            actor,
            snapshot.target,
            true,
            snapshot = snapshot,
            fresh = true,
            prepared = photo,
            preparedFor = snapshot.takeIf { photo != null },
        )

    @Test
    fun guestCannotSeeCachedTitleOrPhoto() {
        compose.setContent {
            MaterialTheme {
                ContentCoverContent(
                    state(photo = photo()).copy(session = null),
                    "de",
                    ContentCoverActions(),
                )
            }
        }
        compose.onNodeWithTag("content-cover-account").assertIsDisplayed()
        compose.onNodeWithText("Private synthetic title").assertDoesNotExist()
        compose.onNodeWithTag("content-cover-preview").assertDoesNotExist()
        compose.onNodeWithTag("content-cover-choose").assertDoesNotExist()
    }

    @Test
    fun previewDoesNotUploadBeforeExplicitAction() {
        var requested = false
        compose.setContent {
            MaterialTheme {
                ContentCoverContent(
                    state(photo = photo()),
                    "de",
                    ContentCoverActions(upload = { requested = true }),
                )
            }
        }
        assertFalse(requested)
        compose.onNodeWithTag("content-cover-preview").performScrollTo().assertIsDisplayed()
        compose
            .onNodeWithTag("content-cover-upload")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        assertTrue(requested)
    }

    @Test
    fun staleSelectionStaysVisibleButCannotOverwriteFreshDifferentContent() {
        val original = snapshot()
        val current =
            original.copy(
                item =
                    original.item.copy(
                        fields = original.item.fields + ("title" to "Changed server text")
                    )
            )
        val value = state(original, photo()).copy(snapshot = current)
        compose.setContent {
            MaterialTheme { ContentCoverContent(value, "de", ContentCoverActions()) }
        }
        compose.onNodeWithTag("content-cover-preview").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("content-cover-selection-stale").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("content-cover-upload").performScrollTo().assertIsNotEnabled()
    }

    @Test
    fun uncertainOutcomeOffersReadOnlyCheckNotRetryOrDelete() {
        val value = state(photo = photo())
        val intent = ContentCoverIntent.Upload(value.snapshot!!, value.prepared!!)
        compose.setContent {
            MaterialTheme {
                ContentCoverContent(value.copy(uncertain = intent), "uk", ContentCoverActions())
            }
        }
        compose.onNodeWithTag("content-cover-recover").performScrollTo().assertIsEnabled()
        compose.onNodeWithTag("content-cover-upload").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("content-cover-choose").performScrollTo().assertIsNotEnabled()
        compose.onNodeWithTag("content-cover-remove").assertDoesNotExist()
    }

    @Test
    fun eventHasNoInventedRemoveAction() {
        compose.setContent {
            MaterialTheme {
                ContentCoverContent(
                    state(snapshot(ContentKind.EVENTS, true)),
                    "de",
                    ContentCoverActions(),
                )
            }
        }
        compose.onNodeWithTag("content-cover-remove").assertDoesNotExist()
        compose.onNodeWithTag("content-cover-choose").performScrollTo().assertIsEnabled()
    }

    @Test
    fun newsRemovalNeedsProtectedExplicitConfirmation() {
        val value = state(snapshot(existing = true))
        var removed = false
        compose.setContent {
            MaterialTheme {
                ContentCoverContent(
                    value.copy(confirmation = ContentCoverIntent.Remove(value.snapshot!!)),
                    "de",
                    ContentCoverActions(confirm = { removed = true }),
                )
            }
        }
        assertFalse(removed)
        compose
            .onNodeWithText(
                "Text, Reaktionen und die gespeicherte Datei bleiben bestehen.",
                substring = true,
            )
            .assertIsDisplayed()
        compose.onNodeWithTag("content-cover-confirm").assertIsDisplayed().performClick()
        assertTrue(removed)
    }

    @Test
    fun allPhotoActionsRemainReachableAtTwoHundredPercent() {
        val value = state(photo = photo())
        compose.setContent {
            CompositionLocalProvider(
                LocalDensity provides Density(LocalDensity.current.density, 2f)
            ) {
                MaterialTheme { ContentCoverContent(value, "de", ContentCoverActions()) }
            }
        }
        for (tag in
            listOf("content-cover-choose", "content-cover-upload", "content-cover-discard")) compose
            .onNodeWithTag(tag)
            .performScrollTo()
            .assertIsDisplayed()
            .assertIsEnabled()
    }
}
