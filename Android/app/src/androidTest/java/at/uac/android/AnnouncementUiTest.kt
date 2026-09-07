package at.uac.android

import androidx.activity.ComponentActivity
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import at.uac.android.feature.announcements.AnnouncementDraft
import at.uac.android.feature.announcements.AnnouncementOwnerState
import at.uac.android.feature.announcements.AnnouncementPopup
import at.uac.android.feature.announcements.AnnouncementText
import at.uac.android.feature.announcements.AnnouncementOwnerScreen
import at.uac.android.feature.announcements.UserAnnouncement
import at.uac.android.feature.translation.ContentTranslationButton
import at.uac.android.feature.translation.ContentTranslationSource
import at.uac.android.feature.translation.TranslationField
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class AnnouncementUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private fun item(mode: String = "acknowledge") =
        UserAnnouncement(
            id = "notice_72",
            schemaVersion = 1,
            revision = 1,
            title = AnnouncementText("Заголовок", "Titel"),
            body = AnnouncementText("Повідомлення", "Mitteilung"),
            groups = listOf("registered"),
            userIds = emptyList(),
            regions = emptyList(),
            targetPlatforms = listOf("android"),
            mode = mode,
            feedback = true,
            push = true,
            startsAt = 1_800_000_000_000L,
            expiresAt = 1_800_086_400_000L,
            status = "published",
            presentedAt = null,
            acknowledgedAt = null,
        )

    @Test
    fun acknowledgementPopupCannotBeDismissedAndProvidesFeedbackAction() {
        var acknowledged = false
        compose.setContent {
            MaterialTheme {
                AnnouncementPopup(item(), "uk", {}, { acknowledged = true }, {})
            }
        }
        compose.onNodeWithTag("announcement-popup").assertIsDisplayed()
        compose.onNodeWithTag("announcement-feedback").assertIsDisplayed()
        compose.onNodeWithTag("announcement-confirm").performClick()
        compose.runOnIdle { assertTrue(acknowledged) }
    }

    @Test
    fun ownerEditorExposesAudiencePlatformsScheduleAndReleaseActions() {
        val draft =
            AnnouncementDraft(
                revision = 1,
                titleUk = "Заголовок",
                titleDe = "Titel",
                bodyUk = "Текст",
                bodyDe = "Text",
            )
        compose.setContent {
            MaterialTheme {
                AnnouncementOwnerScreen(
                    state = AnnouncementOwnerState(draft = draft, items = listOf(item())),
                    language = "uk",
                    onLoad = {},
                    onLoadMore = {},
                    onNew = {},
                    onChange = {},
                    onSave = {},
                    onTest = {},
                    onPreview = {},
                    onLoadUsers = {},
                    onPublish = {},
                    onEdit = {},
                    onStats = {},
                    onCancel = {},
                )
            }
        }
        compose.onNodeWithTag("announcement-users").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("announcement-publish").performScrollTo().assertIsDisplayed()
    }

    @Test
    fun sharedTranslationRequiresReviewBeforeApplyingExactFieldMapping() {
        var applied: Map<String, String>? = null
        val source = object : ContentTranslationSource {
            override suspend fun translate(kind: String, texts: List<String>, sourceLanguage: String) =
                listOf("Titel", "Text")
        }
        compose.setContent {
            MaterialTheme {
                ContentTranslationButton(
                    kind = "news",
                    language = "uk",
                    fields = listOf(
                        TranslationField("title", "Заголовок", "Назва", "", 120),
                        TranslationField("body", "Текст", "Текст", "", 2_000),
                    ),
                    enabled = true,
                    translationSource = source,
                ) { applied = it }
            }
        }
        compose.onNodeWithTag("translate-news").performClick()
        compose.waitUntil(5_000) {
            compose.onAllNodes(androidx.compose.ui.test.hasTestTag("translation-apply"))
                .fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("translation-apply").performClick()
        compose.runOnIdle { assertTrue(applied == mapOf("title" to "Titel", "body" to "Text")) }
    }
}
