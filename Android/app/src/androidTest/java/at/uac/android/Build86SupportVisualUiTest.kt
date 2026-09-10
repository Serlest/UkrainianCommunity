package at.uac.android

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.test.espresso.Espresso.onView
import androidx.test.espresso.action.ViewActions.click
import androidx.test.espresso.assertion.ViewAssertions.matches
import androidx.test.espresso.matcher.ViewMatchers.isAssignableFrom
import androidx.test.espresso.matcher.ViewMatchers.withId
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.design.*
import at.uac.android.feature.announcements.*
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.feedback.*
import java.io.File
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** Synthetic populated UI only. No account, network calls, publish or support mutations. */
class Build86SupportVisualUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val at = Instant.parse("2026-09-11T10:00:00Z")
    private val actor = FeedbackSession("synthetic-support", 86, true, true, "Олена · Tirol")

    @Composable
    private fun Host(language: String, theme: String, content: @Composable () -> Unit) {
        SideEffect {
            WindowCompat.getInsetsController(
                    compose.activity.window,
                    compose.activity.window.decorView,
                )
                .isAppearanceLightStatusBars = theme == "light"
        }
        UacTheme(theme) {
            UacPageBackground(Modifier.fillMaxSize(), plain = true) {
                Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                    UacHeader(language, true, {}, {}, compact = true)
                    Box(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 16.dp)) {
                        CompositionLocalProvider(
                            LocalEmbeddedNavigation provides true,
                            content = content,
                        )
                    }
                }
            }
        }
    }

    private fun capture(name: String, tag: String? = null, nativeWindow: Boolean = false) {
        compose.waitForIdle()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        // Synthetic protected dialogs/case context use Compose capture; FLAG_SECURE is preserved.
        val bitmap =
            if (tag != null)
                compose.onNodeWithTag(tag).assertIsDisplayed().captureToImage().asAndroidBitmap()
            else if (nativeWindow) {
                instrumentation.uiAutomation.waitForIdle(250, 3000)
                checkNotNull(instrumentation.uiAutomation.takeScreenshot())
            } else compose.onRoot().assertIsDisplayed().captureToImage().asAndroidBitmap()
        try {
            File(instrumentation.targetContext.cacheDir, "build86-support-$name.png")
                .outputStream()
                .use {
                    check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
                }
        } finally {
            bitmap.recycle()
        }
    }

    private fun item() =
        FeedbackContract.item(
                RawDocument(
                    "request",
                    FeedbackContract.creation(
                        "request",
                        actor,
                        FeedbackDraft(
                            message =
                                "Після зміни міста я не знаходжу збережену подію. Können Sie bitte helfen?"
                        ),
                        at,
                    ),
                )
            )
            .copy(subject = "Збережена подія · Gespeicherte Veranstaltung", unreadForOwner = true)

    private fun support(language: String, theme: String) {
        val original = item()
        val state =
            mutableStateOf(
                FeedbackState(
                    session = actor,
                    audience = FeedbackAudience.MANAGEMENT,
                    page =
                        FeedbackPage(
                            listOf(
                                original,
                                original.copy(id = "answered", status = FeedbackStatus.ANSWERED),
                            ),
                            null,
                            true,
                        ),
                )
            )
        var closes = 0
        val caseOnly = mutableStateOf(false)
        compose.setContent {
            Host(language, theme) {
                when {
                    caseOnly.value ->
                        Column(Modifier.verticalScroll(rememberScrollState())) {
                            FeedbackCaseContextCard(state.value, language)
                        }
                    state.value.selectedId == null ->
                        FeedbackList(
                            state.value,
                            language,
                            {},
                            {},
                            {},
                            {},
                            {},
                            onSearch = {
                                state.value =
                                    state.value.copy(inbox = state.value.inbox.copy(query = it))
                            },
                            onFilter = {
                                state.value =
                                    state.value.copy(inbox = state.value.inbox.copy(filter = it))
                            },
                            onSort = {
                                state.value =
                                    state.value.copy(inbox = state.value.inbox.copy(sort = it))
                            },
                        )
                    else ->
                        FeedbackDetail(
                            state.value,
                            language,
                            {},
                            {},
                            { closes++ },
                            {},
                            {},
                            onReadDecision = {},
                            onMore = {},
                        )
                }
            }
        }
        capture("inbox-top-$language-$theme")
        compose
            .onNodeWithTag("feedback-list")
            .performScrollToNode(hasTestTag("feedback-item-request"))
        capture("inbox-items-$language-$theme")
        val populated = state.value
        compose.runOnIdle {
            state.value = populated.copy(page = FeedbackPage(emptyList(), null, false))
        }
        compose.onNodeWithTag("feedback-list").performScrollToNode(hasTestTag("feedback-empty"))
        capture("inbox-empty-$language-$theme")
        compose.runOnIdle { state.value = populated.copy(error = FeedbackFailure.OFFLINE) }
        compose.onNodeWithTag("feedback-list").performScrollToNode(hasTestTag("feedback-error"))
        capture("inbox-offline-$language-$theme")
        compose.runOnIdle { state.value = populated.copy(session = actor.copy(canManage = false)) }
        compose.onNodeWithTag("feedback-inbox-access").assertExists()
        capture("inbox-denied-$language-$theme")
        compose.runOnIdle {
            state.value =
                populated.copy(
                    audience = FeedbackAudience.OWN,
                    draft = FeedbackDraft(message = "Потрібна допомога із збереженням події."),
                )
        }
        compose.onNodeWithTag("feedback-list").performScrollToNode(hasTestTag("feedback-submit"))
        capture("own-composer-$language-$theme")
        compose.runOnIdle {
            state.value =
                populated.copy(
                    selectedId = original.id,
                    conversation =
                        FeedbackConversation(
                            original,
                            listOf(
                                FeedbackMessage(
                                    "one",
                                    original.id,
                                    actor.uid,
                                    actor.displayName,
                                    false,
                                    original.message,
                                    at,
                                ),
                                FeedbackMessage(
                                    "two",
                                    original.id,
                                    "support",
                                    "Support",
                                    true,
                                    "Дякуємо за опис. Bitte prüfen Sie die ausgewählte Region in den Einstellungen.",
                                    at,
                                ),
                            ),
                            limited = true,
                        ),
                    reply = "Дякуємо, перевіряємо ваше звернення.",
                )
        }
        capture("conversation-top-$language-$theme")
        compose
            .onNodeWithTag("feedback-conversation")
            .performScrollToNode(hasTestTag("feedback-send"))
        capture("conversation-reply-$language-$theme")
        compose.onNodeWithTag("feedback-close").performScrollTo().performClick()
        compose.onNodeWithTag("feedback-confirm-close").assertIsDisplayed()
        capture("conversation-close-dialog-$language-$theme", "feedback-close-dialog")
        compose.onNodeWithTag("feedback-cancel-close").performClick()
        compose.runOnIdle { assertEquals(0, closes) }
        for (status in listOf(FeedbackStatus.CLOSED, FeedbackStatus.UNKNOWN)) {
            compose.runOnIdle {
                state.value =
                    state.value.copy(
                        conversation =
                            state.value.conversation!!.copy(item = original.copy(status = status))
                    )
            }
            compose
                .onNodeWithTag("feedback-conversation")
                .performScrollToNode(hasTestTag("feedback-reply-section"))
            compose.onNodeWithTag("feedback-send").assertDoesNotExist()
            capture("conversation-${status.name}-$language-$theme")
        }
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    conversation = state.value.conversation!!.copy(item = original),
                    replyRetryPending = true,
                    actionError = FeedbackFailure.UNCONFIRMED,
                )
        }
        compose
            .onNodeWithTag("feedback-conversation")
            .performScrollToNode(hasTestTag("feedback-send"))
        capture("conversation-retry-$language-$theme")
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    session = actor.copy(ready = false),
                    replyRetryPending = false,
                    actionError = null,
                )
        }
        compose
            .onNodeWithTag("feedback-conversation")
            .performScrollToNode(hasTestTag("feedback-reply-section"))
        compose.onNodeWithTag("feedback-send").assertDoesNotExist()
        capture("conversation-account-gate-$language-$theme")
        val case =
            FeedbackCaseContext(
                "SYN-86",
                "appealed",
                "other",
                "https://example.invalid/synthetic-content",
                "Синтетичний опис для перевірки читабельності та перенесення довгих рядків.",
                "Синтетична правова підстава",
                "Синтетичні докази",
                true,
                at,
                language,
                FeedbackCaseAppeal(
                    "pending",
                    "Прошу повторно перевірити контекст публікації.",
                    null,
                ),
            )
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    session = actor,
                    conversation =
                        FeedbackConversation(
                            original.copy(hasDsaCase = true, caseContext = case),
                            emptyList(),
                        ),
                    actionError = null,
                )
            caseOnly.value = true
        }
        compose.onNodeWithTag("feedback-case-context").assertExists()
        for (field in
            listOf("location", "explanation", "basis", "evidence", "appeal", "good-faith")) {
            compose.onNodeWithTag("feedback-case-$field").performScrollTo().assertIsDisplayed()
            capture("case-$field-$language-$theme", "feedback-case-$field")
            capture("case-layout-$field-$language-$theme")
        }
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    conversation =
                        FeedbackConversation(original.copy(hasDsaCase = true), emptyList())
                )
        }
        compose.onNodeWithTag("feedback-case-invalid").assertIsDisplayed()
        capture("case-invalid-$language-$theme", "feedback-case-context")
        compose.runOnIdle {
            state.value =
                state.value.copy(
                    conversation =
                        FeedbackConversation(
                            original.copy(
                                hasDsaCase = true,
                                caseContext = case.copy(goodFaithConfirmed = false, appeal = null),
                            ),
                            emptyList(),
                        )
                )
        }
        compose.onNodeWithTag("feedback-case-good-faith").performScrollTo()
        capture("case-unconfirmed-good-faith-$language-$theme", "feedback-case-good-faith")
    }

    @Test fun supportGermanLight() = support("de", "light")

    @Test fun supportUkrainianDark() = support("uk", "dark")

    private fun notice() =
        UserAnnouncement(
            "visual_86",
            1,
            1,
            AnnouncementText("Зустріч громади в Тіролі", "Gemeinschaftstreffen in Tirol"),
            AnnouncementText(
                "Запрошуємо ознайомитися з оновленим розкладом і зберегти потрібні події.",
                "Bitte prüfen Sie den aktualisierten Veranstaltungskalender und speichern Sie passende Termine.",
            ),
            listOf("registered"),
            emptyList(),
            listOf("tirol"),
            listOf("ios", "android"),
            "acknowledge",
            true,
            true,
            System.currentTimeMillis(),
            System.currentTimeMillis() + 86_400_000L,
            "published",
            null,
            null,
        )

    private fun announcements(language: String, theme: String) {
        val published = notice()
        val state =
            mutableStateOf(
                AnnouncementOwnerState(
                    draft =
                        AnnouncementDraft(
                            revision = 1,
                            titleUk = published.title.uk,
                            titleDe = published.title.de,
                            bodyUk = published.body.uk,
                            bodyDe = published.body.de,
                        ),
                    items = listOf(published, published.copy(id = "draft_86", status = "draft")),
                    users =
                        listOf(
                            AnnouncementUser("synthetic_one", "Олена · Innsbruck", "tirol"),
                            AnnouncementUser("synthetic_two", "Maximilian · Wien", "wien"),
                        ),
                    usersCursor = "next",
                    itemsCursor = "next",
                    audience = AnnouncementAudience(184, true),
                    statistics =
                        mapOf(
                            published.id to
                                AnnouncementStatistics(128, 96, 14, 32, 20, 156, 4, "completed")
                        ),
                )
            )
        var publishes = 0
        compose.setContent {
            Host(language, theme) {
                AnnouncementOwnerScreen(
                    state.value,
                    language,
                    {},
                    {},
                    {},
                    { edit -> state.value = state.value.copy(draft = edit(state.value.draft!!)) },
                    {},
                    {},
                    {},
                    {},
                    { publishes++ },
                    {},
                    {},
                    {},
                )
            }
        }
        capture("announcements-top-$language-$theme")
        for (tag in
            listOf(
                "announcement-content-de",
                "announcement-audience-section",
                "announcement-regions-section",
                "announcement-delivery-section",
                "announcement-release-section",
            )) {
            compose.onNodeWithTag(tag).performScrollTo().assertExists()
            capture("$tag-$language-$theme")
        }
        for (dateTag in listOf("announcement-start", "announcement-end")) {
            compose.onNodeWithTag(dateTag).performScrollTo().performClick()
            onView(isAssignableFrom(android.widget.DatePicker::class.java))
                .check(matches(androidx.test.espresso.matcher.ViewMatchers.isDisplayed()))
            capture("$dateTag-date-$language-$theme", nativeWindow = true)
            onView(withId(android.R.id.button1)).perform(click())
            onView(isAssignableFrom(android.widget.TimePicker::class.java))
                .check(matches(androidx.test.espresso.matcher.ViewMatchers.isDisplayed()))
            capture("$dateTag-time-$language-$theme", nativeWindow = true)
            onView(withId(android.R.id.button2)).perform(click())
        }
        compose.onNodeWithTag("announcement-users").performScrollTo().performClick()
        capture("announcement-user-picker-$language-$theme", "announcement-user-dialog")
        compose
            .onNodeWithTag("announcement-user-search")
            .performTextReplacement("No matching synthetic person")
        androidx.test.espresso.Espresso.closeSoftKeyboard()
        compose.onNodeWithTag("announcement-users-empty").assertExists()
        capture("announcement-user-picker-empty-$language-$theme", "announcement-user-dialog")
        compose.onNodeWithTag("announcement-users-done").performClick()
        compose.onNodeWithTag("announcement-preview").performScrollTo().performClick()
        capture("announcement-preview-$language-$theme", "announcement-preview-dialog")
        compose.onNodeWithTag("announcement-preview-close").performClick()
        compose.onNodeWithTag("announcement-reviewed").performScrollTo().performClick()
        compose
            .onNodeWithTag("announcement-publish")
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        capture("announcement-confirm-$language-$theme", "announcement-publish-dialog")
        compose.onNodeWithTag("announcement-publish-dismiss").performClick()
        compose.runOnIdle { assertEquals(0, publishes) }
        for (id in listOf("visual_86", "draft_86")) {
            compose.onNodeWithTag("announcement-item-$id").performScrollTo()
            capture("announcement-item-$id-$language-$theme")
        }
        compose.runOnIdle {
            state.value = AnnouncementOwnerState(error = AnnouncementFailure.OFFLINE)
        }
        compose.onNodeWithTag("announcement-owner-error").performScrollTo()
        capture("announcement-empty-offline-$language-$theme")
    }

    @Test fun announcementsGermanLight() = announcements("de", "light")

    @Test fun announcementsUkrainianDark() = announcements("uk", "dark")

    private fun popups(language: String, theme: String) {
        val value = mutableStateOf(notice())
        val actions = mutableStateOf(true)
        compose.setContent {
            Host(language, theme) {
                AnnouncementPopup(value.value, language, {}, {}, {}, actions.value)
            }
        }
        capture("announcement-popup-acknowledge-$language-$theme", "announcement-popup-dialog")
        compose.runOnIdle { value.value = value.value.copy(mode = "once", feedback = false) }
        compose.onNodeWithTag("announcement-dismiss").assertDoesNotExist()
        capture("announcement-popup-once-$language-$theme", "announcement-popup-dialog")
        compose.runOnIdle {
            value.value = value.value.copy(mode = "acknowledge")
            actions.value = false
        }
        compose.onNodeWithTag("announcement-feedback").assertDoesNotExist()
        capture("announcement-popup-disabled-$language-$theme", "announcement-popup-dialog")
    }

    @Test fun popupsGermanLight() = popups("de", "light")

    @Test fun popupsUkrainianDark() = popups("uk", "dark")
}
