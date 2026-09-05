package at.uac.android.design

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import at.uac.android.R

/** iOS build 65 brand values. Foregrounds are separate from decorative fills. */
object UacDesign {
    val blue = Color(0xFF1A428F)
    val yellow = Color(0xFFEDC23B)
    val red = Color(0xFFB8242E)
    val successLight = Color(0xFF05662B)
    val successDark = Color(0xFF57D17D)
    val successFillLight = Color(0xFFE6F6EB)
    val successFillDark = Color(0xFF1D3B2A)
    val bannerScrim = Color(0xFF263247)
    val bannerSubtitle = Color(0xFFE2E7F0)
    val pageInset = 16.dp
    val sectionGap = 16.dp
    val cardInset = 18.dp
    val detailInset = 20.dp
    val readableWidth = 760.dp
    val cardRadius = 17.dp
    val planeRadius = 26.dp
    val imageRadius = 16.dp
    val chipRadius = 14.dp
    val minimumTouch = 48.dp

    val light =
        lightColorScheme(
            primary = blue,
            onPrimary = Color.White,
            primaryContainer = Color(0xFFE7EEFA),
            onPrimaryContainer = Color(0xFF12366F),
            secondary = Color(0xFF7D4F03),
            onSecondary = Color.White,
            secondaryContainer = Color(0xFFFAEFC8),
            onSecondaryContainer = Color(0xFF412A00),
            tertiary = Color(0xFF5D4892),
            onTertiary = Color.White,
            tertiaryContainer = Color(0xFFEEE8F7),
            onTertiaryContainer = Color(0xFF382666),
            background = Color(0xFFF2F2F7),
            onBackground = Color(0xFF171A21),
            surface = Color.White,
            onSurface = Color(0xFF171A21),
            surfaceVariant = Color(0xFFECEDF3),
            onSurfaceVariant = Color(0xFF525967),
            surfaceDim = Color(0xFFE5E7EF),
            surfaceBright = Color.White,
            surfaceContainerLowest = Color.White,
            surfaceContainerLow = Color(0xFFFCFCFE),
            surfaceContainer = Color(0xFFF5F6FA),
            surfaceContainerHigh = Color(0xFFEEEFF5),
            surfaceContainerHighest = Color(0xFFE6E8F0),
            outline = Color(0xFF727A87),
            outlineVariant = Color(0xFFD5DBE5),
            error = red,
            onError = Color.White,
            errorContainer = Color(0xFFFDE7E9),
            onErrorContainer = Color(0xFF74131D),
            inverseSurface = Color(0xFF202632),
            inverseOnSurface = Color(0xFFF5F6FA),
            inversePrimary = Color(0xFFA7C8FF),
            surfaceTint = blue,
        )
    val dark =
        darkColorScheme(
            primary = Color(0xFF8AB3FF),
            onPrimary = Color(0xFF08214C),
            primaryContainer = Color(0xFF233C62),
            onPrimaryContainer = Color(0xFFD5E4FF),
            secondary = Color(0xFFF5C74F),
            onSecondary = Color(0xFF2D2000),
            secondaryContainer = Color(0xFF493B12),
            onSecondaryContainer = Color(0xFFFFE8A2),
            tertiary = Color(0xFFC3B4F2),
            onTertiary = Color(0xFF2E1F50),
            tertiaryContainer = Color(0xFF443460),
            onTertiaryContainer = Color(0xFFEDE3FF),
            background = Color(0xFF080C14),
            onBackground = Color(0xFFF5F5F7),
            surface = Color(0xFF151D2B),
            onSurface = Color(0xFFF5F5F7),
            surfaceVariant = Color(0xFF263247),
            onSurfaceVariant = Color(0xFFCBD2E0),
            surfaceDim = Color(0xFF101722),
            surfaceBright = Color(0xFF2C374A),
            surfaceContainerLowest = Color(0xFF0D131E),
            surfaceContainerLow = Color(0xFF151D2B),
            surfaceContainer = Color(0xFF1B2434),
            surfaceContainerHigh = Color(0xFF222D40),
            surfaceContainerHighest = Color(0xFF2A374C),
            outline = Color(0xFF97A3B9),
            outlineVariant = Color(0xFF414D62),
            error = Color(0xFFFF9EA6),
            onError = Color(0xFF560616),
            errorContainer = Color(0xFF591D25),
            onErrorContainer = Color(0xFFFFDADD),
            inverseSurface = Color(0xFFE8EBF2),
            inverseOnSurface = Color(0xFF1B2434),
            inversePrimary = blue,
            surfaceTint = Color(0xFF8AB3FF),
        )
}

val LocalUacDark = staticCompositionLocalOf { false }

private val uacTypography =
    Typography(
        headlineLarge =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Bold,
                fontSize = 30.sp,
                lineHeight = 36.sp,
            ),
        headlineMedium =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Bold,
                fontSize = 26.sp,
                lineHeight = 32.sp,
            ),
        headlineSmall =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Bold,
                fontSize = 22.sp,
                lineHeight = 28.sp,
            ),
        titleLarge =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.SemiBold,
                fontSize = 20.sp,
                lineHeight = 26.sp,
            ),
        titleMedium =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.SemiBold,
                fontSize = 17.sp,
                lineHeight = 23.sp,
            ),
        titleSmall =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                lineHeight = 21.sp,
            ),
        bodyLarge =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Normal,
                fontSize = 17.sp,
                lineHeight = 25.sp,
            ),
        bodyMedium =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Normal,
                fontSize = 15.sp,
                lineHeight = 23.sp,
            ),
        bodySmall =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Normal,
                fontSize = 13.sp,
                lineHeight = 19.sp,
            ),
        labelLarge =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp,
                lineHeight = 20.sp,
            ),
        labelMedium =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Medium,
                fontSize = 12.sp,
                lineHeight = 17.sp,
            ),
        labelSmall =
            TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Medium,
                fontSize = 11.sp,
                lineHeight = 16.sp,
            ),
    )

@Composable
fun UacTheme(selected: String = "system", content: @Composable () -> Unit) {
    val dark = selected == "dark" || selected == "system" && isSystemInDarkTheme()
    CompositionLocalProvider(LocalUacDark provides dark) {
        MaterialTheme(
            colorScheme = if (dark) UacDesign.dark else UacDesign.light,
            typography = uacTypography,
            shapes =
                Shapes(
                    extraSmall = RoundedCornerShape(10.dp),
                    small = RoundedCornerShape(12.dp),
                    medium = RoundedCornerShape(UacDesign.cardRadius),
                    large = RoundedCornerShape(UacDesign.planeRadius),
                    extraLarge = RoundedCornerShape(32.dp),
                ),
        ) {
            // A transparent Scaffold cannot infer onSurface from its container color.
            // Keep bare page/header text themed as well as text inside Material surfaces.
            CompositionLocalProvider(
                LocalContentColor provides MaterialTheme.colorScheme.onBackground,
                content = content,
            )
        }
    }
}

/**
 * The original bundled iPhone backdrop, with its original appearance-dependent readability overlay.
 */
@Composable
fun UacPageBackground(modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    val overlay =
        if (LocalUacDark.current)
            listOf(
                Color(0xFF04060A).copy(alpha = .52f),
                Color(0xFF05080E).copy(alpha = .58f),
                Color(0xFF030408).copy(alpha = .66f),
            )
        else
            listOf(
                Color.White.copy(alpha = .12f),
                Color.White.copy(alpha = .08f),
                UacDesign.yellow.copy(alpha = .06f),
            )
    Box(modifier) {
        Image(
            painterResource(R.drawable.uac_background),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Crop,
        )
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(overlay)))
        content()
    }
}
