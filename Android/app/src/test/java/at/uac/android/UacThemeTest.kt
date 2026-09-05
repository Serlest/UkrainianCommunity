package at.uac.android

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import at.uac.android.design.UacDesign
import org.junit.Assert.*
import org.junit.Test

/**
 * Numeric palette proof only; image overlays, type scaling and actual screens need device checks.
 */
class UacThemeTest {
    private fun contrast(first: Color, second: Color): Float {
        val a = first.luminance()
        val b = second.luminance()
        return (maxOf(a, b) + .05f) / (minOf(a, b) + .05f)
    }

    @Test
    fun primaryBrandFillsMatchTheIphoneReference() {
        assertEquals(Color(0xFF1A428F), UacDesign.blue)
        assertEquals(Color(0xFFEDC23B), UacDesign.yellow)
        assertEquals(Color(0xFFB8242E), UacDesign.red)
    }

    @Test
    fun regularTextContrastMeetsFourPointFiveOnItsOpaqueSemanticSurface() {
        for (scheme in listOf(UacDesign.light, UacDesign.dark)) {
            val pairs =
                listOf(
                    scheme.primary to scheme.onPrimary,
                    scheme.primaryContainer to scheme.onPrimaryContainer,
                    scheme.secondary to scheme.onSecondary,
                    scheme.secondaryContainer to scheme.onSecondaryContainer,
                    scheme.tertiary to scheme.onTertiary,
                    scheme.tertiaryContainer to scheme.onTertiaryContainer,
                    scheme.error to scheme.onError,
                    scheme.errorContainer to scheme.onErrorContainer,
                    scheme.background to scheme.onBackground,
                    scheme.surface to scheme.onSurface,
                    scheme.surfaceVariant to scheme.onSurfaceVariant,
                    scheme.surfaceContainerHighest to scheme.onSurfaceVariant,
                    scheme.inverseSurface to scheme.inverseOnSurface,
                )
            for ((background, foreground) in pairs) {
                assertEquals(1f, background.alpha)
                assertEquals(1f, foreground.alpha)
                assertTrue(
                    "Semantic text contrast was ${contrast(background, foreground)}",
                    contrast(background, foreground) >= 4.5f,
                )
            }
        }
    }

    @Test
    fun interactiveOutlinesAndLinksStayDistinctFromMainSurfaces() {
        for (scheme in listOf(UacDesign.light, UacDesign.dark)) {
            for (surface in
                listOf(scheme.background, scheme.surface, scheme.surfaceContainerHighest)) {
                assertTrue("Control outline contrast", contrast(scheme.outline, surface) >= 3f)
                assertTrue("Text link contrast", contrast(scheme.primary, surface) >= 4.5f)
            }
        }
    }

    @Test
    fun touchAndSpacingTokensKeepAndroidTargetsWhileFollowingTheReference() {
        assertEquals(48f, UacDesign.minimumTouch.value)
        assertEquals(16f, UacDesign.pageInset.value)
        assertEquals(18f, UacDesign.cardInset.value)
        assertEquals(17f, UacDesign.cardRadius.value)
        assertEquals(26f, UacDesign.planeRadius.value)
    }

    @Test
    fun newsSuccessChipUsesReadableIphoneForegroundsOnOpaqueFills() {
        assertTrue(contrast(UacDesign.successLight, UacDesign.successFillLight) >= 4.5f)
        assertTrue(contrast(UacDesign.successDark, UacDesign.successFillDark) >= 4.5f)
    }

    @Test
    fun heroTextHasReliableContrastIndependentOfTheImageBehindIt() {
        assertEquals(1f, UacDesign.bannerScrim.alpha)
        assertTrue(contrast(Color.White, UacDesign.bannerScrim) >= 4.5f)
        assertTrue(contrast(UacDesign.bannerSubtitle, UacDesign.bannerScrim) >= 4.5f)
        assertTrue(contrast(Color.White, UacDesign.blue) >= 4.5f)
    }
}
