package at.uac.android

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.hasTestTag
import at.uac.android.feature.featuredmanagement.*
import at.uac.android.feature.moderation.ModerationSession
import org.junit.Rule
import org.junit.Test

class FeaturedManagementUiTest {
    @get:Rule val compose = createComposeRule()

    private class EmptySource : FeaturedManagementSource {
        override suspend fun list(session: ModerationSession) = emptyList<FeaturedBanner>()
        override suspend fun find(session: ModerationSession, id: String) = null
        override suspend fun save(session: ModerationSession, draft: FeaturedDraft, create: Boolean) = error("not sent")
        override suspend fun setActive(session: ModerationSession, id: String, active: Boolean) = error("not sent")
        override suspend fun delete(session: ModerationSession, id: String) = error("not sent")
        override suspend fun upload(session: ModerationSession, bannerId: String, jpeg: ByteArray) = error("not sent")
    }

    @Test fun ownerSeesGermanManagementAndValidatedEditor() {
        val session = ModerationSession("owner-1", 1, "owner", true)
        val model = FeaturedManagementViewModel(FeaturedManagementRepository(EmptySource()) { session }, FeaturedImagePreparation { error("not used") })
        compose.setContent { FeaturedManagementScreen(model, session, "de", {}) }
        compose.onNodeWithTag("featured-management").assertIsDisplayed()
        compose.onNodeWithText("Banner erstellen").performClick()
        compose.onNodeWithTag("featured-editor").assertIsDisplayed()
        compose.onNodeWithTag("featured-title-uk").assertIsDisplayed()
        compose.onNodeWithTag("featured-title-de").assertIsDisplayed()
        compose.onNodeWithTag("featured-editor").performScrollToNode(hasTestTag("featured-save"))
        compose.onNodeWithTag("featured-save").assertIsNotEnabled()
    }

    @Test fun nonOwnerCannotOpenCreator() {
        val session = ModerationSession("admin-1", 1, "admin", true)
        val model = FeaturedManagementViewModel(FeaturedManagementRepository(EmptySource()) { session }, FeaturedImagePreparation { error("not used") })
        compose.setContent { FeaturedManagementScreen(model, session, "uk", {}) }
        compose.onNodeWithText("Створити банер").assertIsNotEnabled()
    }
}
