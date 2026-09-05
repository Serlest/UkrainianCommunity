package at.uac.android

import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import at.uac.android.feature.browse.PrimaryTab
import org.junit.Assert.*

/** Public label geometry/semantics only; no simulated font scale or privileged state. */
internal fun ComposeContentTestRule.assertNavigationPresentation(expectedFontScale: Float) {
    val grid = onAllNodesWithTag("uac-navigation-grid").fetchSemanticsNodes().isNotEmpty()
    onNodeWithTag(if (grid) "uac-navigation-grid" else "uac-navigation-row").assertIsDisplayed()
    val bounds =
        PrimaryTab.entries.map { tab ->
            val item =
                onNodeWithTag("tab-${tab.route}")
                    .assertIsDisplayed()
                    .assertHeightIsAtLeast(48.dp)
                    .assertWidthIsAtLeast(48.dp)
            val node = item.fetchSemanticsNode()
            assertEquals(Role.Tab, node.config[SemanticsProperties.Role])
            assertEquals(tab.ordinal.toFloat(), node.config[SemanticsProperties.TraversalIndex], 0f)
            val layouts = mutableListOf<TextLayoutResult>()
            onNodeWithTag("tab-label-${tab.route}", useUnmergedTree = true).performSemanticsAction(
                SemanticsActions.GetTextLayoutResult
            ) {
                it(layouts)
            }
            assertEquals(1, layouts.size)
            val layout = layouts.single()
            assertEquals(expectedFontScale, layout.layoutInput.density.fontScale, 0.01f)
            assertFalse("${tab.route} width overflow", layout.didOverflowWidth)
            assertFalse("${tab.route} height overflow", layout.didOverflowHeight)
            if (expectedFontScale > 1.3f) {
                val maximum = if (tab == PrimaryTab.ORGANIZATIONS) 2 else 1
                assertTrue(
                    "${tab.route} must remain legible, lines=${layout.lineCount}",
                    layout.lineCount <= maximum,
                )
                for (line in 0 until layout.lineCount) {
                    assertFalse(layout.isLineEllipsized(line))
                    val visible =
                        layout.layoutInput.text.text
                            .substring(
                                layout.getLineStart(line),
                                layout.getLineEnd(line, visibleEnd = true),
                            )
                            .trim { it.isWhitespace() || it == '-' || it == '\u00AD' }
                    assertTrue(
                        "${tab.route} must not leave a single-letter line",
                        visible.length > 1,
                    )
                }
                assertEquals(
                    layout.layoutInput.text.length,
                    layout.getLineEnd(layout.lineCount - 1, true),
                )
            }
            node.boundsInRoot
        }
    // Layout and explicit accessibility traversal share Home, Events, Organizations, Profile order.
    if (grid) {
        assertEquals(bounds[0].top, bounds[1].top, 1f)
        assertEquals(bounds[2].top, bounds[3].top, 1f)
        assertTrue(bounds[0].right <= bounds[1].left)
        assertTrue(bounds[2].right <= bounds[3].left)
        assertTrue(bounds[0].bottom <= bounds[2].top)
    } else {
        bounds.drop(1).forEach { assertEquals(bounds[0].top, it.top, 1f) }
        bounds.zipWithNext().forEach { (a, b) -> assertTrue(a.right <= b.left) }
    }
    if (expectedFontScale <= 1.3f)
        assertFalse("Normal font retains the original four columns", grid)
}
