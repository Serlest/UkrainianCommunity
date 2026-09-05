package at.uac.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.unit.dp

/**
 * Journeys enter authentication through the actual guest welcome action, not a hidden route
 * override.
 */
fun ComposeContentTestRule.openGuestLogin() {
    waitUntil(15_000) { onAllNodesWithTag("guest-sign-in").fetchSemanticsNodes().isNotEmpty() }
    onNodeWithTag("guest-sign-in")
        .performScrollTo()
        .assertIsEnabled()
        .assertHeightIsAtLeast(48.dp)
        .performClick()
    onNodeWithTag("auth-email").assertExists()
}

/**
 * Native dialog presentation can finish after Compose is idle, especially while the IME is closing.
 */
fun ComposeContentTestRule.assertLegalReferenceVisible(text: String) {
    waitUntil(15_000) {
        onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty()
    }
    onNodeWithText(text, substring = true).performScrollTo().assertIsDisplayed()
}
