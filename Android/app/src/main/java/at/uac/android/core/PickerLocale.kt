package at.uac.android.core

import android.content.res.Configuration
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.intl.LocaleList
import androidx.compose.ui.unit.LayoutDirection
import java.util.Locale

/** Copy, never mutate the Activity/application resources or process locale. */
internal fun pickerLocaleConfiguration(base: Configuration, language: String): Configuration {
    require(language == "de" || language == "uk")
    return Configuration(base).apply { setLocale(Locale.forLanguageTag(language)) }
}

/**
 * Material3 1.4 uses LocalConfiguration for its calendar and LocalContext.resources for labels.
 * Explicit typography locales also cover Text calls that supply a Material typography style.
 * Density, font scale, colors, geometry and the parent's protected-window registry are unchanged.
 */
@Composable
fun PickerLocale(language: String, content: @Composable () -> Unit) {
    val context = LocalContext.current
    val base = Configuration(LocalConfiguration.current)
    val configuration = remember(base, language) { pickerLocaleConfiguration(base, language) }
    val localizedContext =
        remember(context, configuration) { context.createConfigurationContext(configuration) }
    val locales = remember(language) { LocaleList(language) }
    val typography = MaterialTheme.typography
    val localizedTypography = remember(typography, locales) { typography.withPickerLocale(locales) }
    val textStyle = LocalTextStyle.current.copy(localeList = locales)
    CompositionLocalProvider(
        LocalConfiguration provides configuration,
        LocalContext provides localizedContext,
        LocalLayoutDirection provides LayoutDirection.Ltr,
    ) {
        MaterialTheme(typography = localizedTypography) {
            ProvideTextStyle(textStyle, content)
        }
    }
}

internal fun Typography.withPickerLocale(locales: LocaleList): Typography =
    copy(
        displayLarge = displayLarge.copy(localeList = locales),
        displayMedium = displayMedium.copy(localeList = locales),
        displaySmall = displaySmall.copy(localeList = locales),
        headlineLarge = headlineLarge.copy(localeList = locales),
        headlineMedium = headlineMedium.copy(localeList = locales),
        headlineSmall = headlineSmall.copy(localeList = locales),
        titleLarge = titleLarge.copy(localeList = locales),
        titleMedium = titleMedium.copy(localeList = locales),
        titleSmall = titleSmall.copy(localeList = locales),
        bodyLarge = bodyLarge.copy(localeList = locales),
        bodyMedium = bodyMedium.copy(localeList = locales),
        bodySmall = bodySmall.copy(localeList = locales),
        labelLarge = labelLarge.copy(localeList = locales),
        labelMedium = labelMedium.copy(localeList = locales),
        labelSmall = labelSmall.copy(localeList = locales),
    )
