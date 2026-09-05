package at.uac.android

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.intl.LocaleList
import androidx.compose.ui.unit.sp
import at.uac.android.core.withPickerLocale
import org.junit.Assert.*
import org.junit.Test

class PickerTypographyTest {
    private fun styles(value: Typography): List<TextStyle> =
        listOf(
            value.displayLarge,
            value.displayMedium,
            value.displaySmall,
            value.headlineLarge,
            value.headlineMedium,
            value.headlineSmall,
            value.titleLarge,
            value.titleMedium,
            value.titleSmall,
            value.bodyLarge,
            value.bodyMedium,
            value.bodySmall,
            value.labelLarge,
            value.labelMedium,
            value.labelSmall,
        )

    @Test
    fun everyMaterialTextStyleReceivesLocaleWithoutChangingAnyOtherProperty() {
        val original =
            Typography(
                bodyLarge = TextStyle(fontSize = 23.sp, lineHeight = 31.sp, letterSpacing = 0.3.sp)
            )
        listOf("de", "uk").forEach { language ->
            val locales = LocaleList(language)
            val localized = original.withPickerLocale(locales)
            styles(original).zip(styles(localized)).forEach { (before, after) ->
                assertEquals(before.copy(localeList = locales), after)
                assertEquals(language, after.localeList?.get(0)?.language)
            }
        }
    }

    @Test
    fun switchingLocaleDoesNotRetainPriorLanguageOrMutateOriginalTypography() {
        val original = Typography()
        val german = original.withPickerLocale(LocaleList("de"))
        val ukrainian = german.withPickerLocale(LocaleList("uk"))
        assertEquals(original.withPickerLocale(LocaleList("uk")), ukrainian)
        assertNull(original.bodyLarge.localeList)
        assertEquals("de", german.bodyLarge.localeList?.get(0)?.language)
    }
}
