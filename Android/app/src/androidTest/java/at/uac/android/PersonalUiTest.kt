package at.uac.android

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.decodeContent
import at.uac.android.feature.personal.*
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PersonalUiTest {
    @get:Rule val compose = createComposeRule()
    private val session = PersonalSession("synthetic-ui-personal", true, true, 1)
    private val profile =
        PersonalProfile(
            session.uid,
            "demo@example.invalid",
            ProfileDraft("Demo Person", "Demo", "Wien", "", "", "wien"),
            Instant.EPOCH,
        )

    @Test
    fun profileFormValidatesAndSendsOnlyEditableDraft() {
        var saved: ProfileDraft? = null
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    PersonalProfilePanel(
                        PersonalState(session = session, profile = profile),
                        "de",
                        {},
                        { saved = it },
                    )
                }
            }
        }
        compose
            .onNodeWithTag("profile-display-name")
            .performScrollTo()
            .performTextReplacement("Neuer Name")
        compose.onNodeWithTag("profile-save").performScrollTo().performClick()
        compose.runOnIdle {
            assertNotNull(saved)
            assertEquals("Neuer Name", saved?.displayName)
        }
        compose.onNodeWithTag("profile-display-name").performScrollTo().performTextReplacement(" ")
        compose.onNodeWithTag("profile-save").performScrollTo().performClick()
        compose.runOnIdle { assertEquals("Neuer Name", saved?.displayName) }
        compose
            .onNodeWithText(personalFailureText(PersonalFailure.INVALID, "de"))
            .assertIsDisplayed()
    }

    @Test
    fun actionStateReflectsServerAndDuplicatePendingTapIsDisabled() {
        val target = PersonalTarget(ContentKind.ORGANIZATIONS, "synthetic-org-ui")
        val state =
            mutableStateOf(
                PersonalState(session = session, actions = mapOf(target to PersonalActions()))
            )
        var changes = 0
        compose.setContent {
            MaterialTheme {
                PersonalActionsRow(
                    target,
                    state.value,
                    "uk",
                    {},
                    { action, enabled ->
                        changes++
                        state.value =
                            state.value.copy(
                                actions = mapOf(target to PersonalActions().with(action, enabled)),
                                actionsPending = setOf(target),
                            )
                    },
                    {},
                )
            }
        }
        compose.onNodeWithTag("personal-subscribe").performClick()
        compose.onNodeWithTag("personal-subscribe").assertIsSelected().assertIsNotEnabled()
        compose.runOnIdle { assertEquals(1, changes) }
        compose.onNodeWithText("Ви підписані").assertIsDisplayed()
    }

    @Test
    fun savedListChangesSegmentAndOpensActualContent() {
        val row =
            RawDocument(
                "synthetic-news-ui",
                mapOf(
                    "title" to "Lokale Nachricht",
                    "body" to "Body",
                    "summary" to "Text",
                    "sourceType" to "organization",
                    "moderationStatus" to "approved",
                    "createdAt" to Instant.EPOCH,
                    "updatedAt" to Instant.EPOCH,
                    "publishedAt" to Instant.EPOCH,
                ),
            )
        val content = decodeContent(ContentKind.NEWS, row)
        var opened: String? = null
        val state =
            PersonalState(
                session = session,
                saved =
                    mapOf(ContentKind.NEWS to PersonalListPage(listOf(content), row.id, false, 1)),
            )
        compose.setContent {
            MaterialTheme { PersonalSavedScreen(state, "de", {}, { opened = it.id }) }
        }
        compose.onNodeWithText("Lokale Nachricht").performClick()
        compose.runOnIdle { assertEquals(row.id, opened) }
        compose.onNodeWithText("Veranstaltungen", useUnmergedTree = true).performClick()
        compose
            .onNodeWithText(
                "Hier erscheinen deine gespeicherten Nachrichten, Veranstaltungen und Organisationen."
            )
            .assertIsDisplayed()
    }

    @Test
    fun accountSwitchImmediatelyRemovesOldPrivateFields() {
        val authority = mutableStateOf<PersonalSession?>(session)
        val snapshot = PersonalState(session = session, profile = profile)
        compose.setContent {
            MaterialTheme {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    PersonalProfilePanel(snapshot.forSession(authority.value), "uk", {}, {})
                }
            }
        }
        compose.onNodeWithTag("profile-display-name").assertExists()
        compose.runOnIdle {
            authority.value = session.copy(uid = "other-synthetic-user", revision = 2)
        }
        compose.onNodeWithTag("profile-display-name").assertDoesNotExist()
        compose.onNodeWithText("demo@example.invalid").assertDoesNotExist()
    }
}
