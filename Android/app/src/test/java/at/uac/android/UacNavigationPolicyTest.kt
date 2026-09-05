package at.uac.android

import at.uac.android.design.useLargeTextNavigationGrid
import org.junit.Assert.*
import org.junit.Test

class UacNavigationPolicyTest {
    @Test
    fun normalFontAndExactThresholdPreserveFourColumns() {
        for (font in listOf(1f, 1.3f, Float.NaN, Float.POSITIVE_INFINITY)) {
            assertFalse(useLargeTextNavigationGrid(font, listOf(2, 1, 3, 2)))
        }
    }

    @Test
    fun largeFontChangesOnlyWhenMeasuredLabelsNeedIt() {
        assertFalse(useLargeTextNavigationGrid(2f, listOf(1, 1, 1, 1)))
        assertFalse(useLargeTextNavigationGrid(2f, listOf(1, 1, 2, 1)))
        assertTrue(useLargeTextNavigationGrid(1.3001f, listOf(1, 1, 3, 1)))
        for (index in listOf(0, 1, 3)) {
            val lines = mutableListOf(1, 1, 2, 1)
            lines[index] = 2
            assertTrue(useLargeTextNavigationGrid(2f, lines))
        }
    }

    @Test
    fun invalidLargeFontMeasurementsChooseRoomierPresentation() {
        assertTrue(useLargeTextNavigationGrid(2f, emptyList()))
        assertTrue(useLargeTextNavigationGrid(2f, listOf(1, 0, 1, 1)))
        assertFalse(useLargeTextNavigationGrid(1f, emptyList()))
    }
}
