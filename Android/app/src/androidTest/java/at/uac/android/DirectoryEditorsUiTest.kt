package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import at.uac.android.design.UacTheme
import at.uac.android.feature.directory.DirectoryCandidates
import at.uac.android.feature.directory.DirectoryEditorsScreen
import at.uac.android.feature.directory.DirectoryEditorsSource
import at.uac.android.feature.directory.DirectoryGrant
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.usermanagement.ManagedUser
import com.google.firebase.Timestamp
import com.google.firebase.firestore.DocumentSnapshot
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class DirectoryEditorsUiTest {
    @get:Rule val compose = createComposeRule()
    private val owner = ModerationSession("owner", 1, "owner", true)
    private val editor = ManagedUser("editor", "Test Editor", "", "editor@example.invalid", "", "", "",
        "user", "active", "active", null, null, "", null, null)
    private val date = Timestamp(1_700_000_000, 0)

    @Test fun ownerGrantsAndConfirmsRevocation() {
        var grant: DirectoryGrant? = null
        val actions = mutableListOf<Boolean>()
        val source = object : DirectoryEditorsSource {
            override suspend fun grants(session: ModerationSession) = listOfNotNull(grant)
            override suspend fun candidates(session: ModerationSession, after: DocumentSnapshot?) =
                DirectoryCandidates(listOf(editor), null)
            override suspend fun search(session: ModerationSession, query: String) = listOf(editor)
            override suspend fun change(session: ModerationSession, uid: String, expected: Timestamp?, enable: Boolean) {
                assertEquals("editor", uid)
                assertEquals(if (enable) null else date, expected)
                actions += enable
                grant = if (enable) DirectoryGrant("editor", "Test Editor", "owner", date) else null
            }
        }
        compose.setContent { UacTheme("light") { DirectoryEditorsScreen(owner, "de", source, {}) } }
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("directory-grant-editor").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("directory-editors-screen")
            .performScrollToNode(hasTestTag("directory-grant-editor"))
        compose.onNodeWithTag("directory-grant-editor").performClick()
        compose.waitUntil(5_000) { actions == listOf(true) }
        compose.onNodeWithTag("directory-editors-screen")
            .performScrollToNode(hasTestTag("directory-revoke-editor"))
        compose.onNodeWithTag("directory-revoke-editor").performClick()
        assertEquals(listOf(true), actions)
        compose.onNodeWithTag("directory-editors-confirm-revoke").performClick()
        compose.waitUntil(5_000) { actions == listOf(true, false) }
    }

    @Test fun ordinaryRoleNeverReadsOrMutatesGrants() {
        var calls = 0
        val source = object : DirectoryEditorsSource {
            override suspend fun grants(session: ModerationSession): List<DirectoryGrant> { calls++; return emptyList() }
            override suspend fun candidates(session: ModerationSession, after: DocumentSnapshot?): DirectoryCandidates {
                calls++; return DirectoryCandidates(emptyList(), null)
            }
            override suspend fun search(session: ModerationSession, query: String): List<ManagedUser> {
                calls++; return emptyList()
            }
            override suspend fun change(session: ModerationSession, uid: String, expected: Timestamp?, enable: Boolean) {
                calls++
            }
        }
        compose.setContent {
            UacTheme("light") {
                DirectoryEditorsScreen(ModerationSession("reader", 1, "user", true), "uk", source, {})
            }
        }
        compose.onNodeWithTag("directory-editors-denied").assertExists()
        compose.onNodeWithTag("directory-editors-screen").assertDoesNotExist()
        assertEquals(0, calls)
    }
}
