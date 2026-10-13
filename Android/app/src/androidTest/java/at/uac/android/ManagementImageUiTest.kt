package at.uac.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import at.uac.android.feature.featuredmanagement.FeaturedDraft
import at.uac.android.feature.featuredmanagement.FeaturedImagePreview
import at.uac.android.feature.organization.OrganizationAuthority
import at.uac.android.feature.organization.OrganizationRecord
import at.uac.android.feature.organization.OrganizationRecordIdentity
import java.time.Instant
import org.junit.Rule
import org.junit.Test

/** Actual emulator HTTP fetch and JPEG decode; no bundled vector or cloud access. */
class ManagementImageUiTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun managedOrganizationRendersRetainedLogo() = withLocalImageFixture { fixture ->
        val row =
            OrganizationRecord(
                "image-org",
                mapOf("logoURL" to fixture),
                "Organisation",
                "approved",
                "owner",
                Instant.EPOCH,
                Instant.EPOCH,
                OrganizationAuthority.OWNER,
                null,
                null,
            )
        compose.setContent { MaterialTheme { OrganizationRecordIdentity(row, "de") } }
        compose.onNodeWithTag("organization-record-image-image-org").assertExists()
        awaitImage()
    }

    @Test
    fun ownRequestRendersLegacyImageField() = withLocalImageFixture { fixture ->
        val row =
            OrganizationRecord(
                "request",
                mapOf("imageURL" to fixture),
                "Request",
                "pendingReview",
                "owner",
                Instant.EPOCH,
                Instant.EPOCH,
                OrganizationAuthority.NONE,
                null,
                null,
            )
        compose.setContent { MaterialTheme { OrganizationRecordIdentity(row, "uk") } }
        awaitImage()
    }

    @Test
    fun bannerPreviewRendersAndUpdatesUploadedImageUrl() = withLocalImageFixture { fixture ->
        val draft = mutableStateOf(FeaturedDraft(id = "banner-image"))
        compose.setContent { MaterialTheme { FeaturedImagePreview(draft.value, "uk") } }
        compose.onNodeWithTag("featured-preview-banner-image").assertExists()
        compose.runOnIdle { draft.value = draft.value.copy(imageUrl = fixture, title = "Banner") }
        awaitImage()
    }

    private fun awaitImage() {
        compose.waitUntil(10_000) {
            compose.onAllNodesWithTag("loaded-media").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("loaded-media").assertIsDisplayed()
    }
}
