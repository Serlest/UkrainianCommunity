package at.uac.android

import android.annotation.SuppressLint
import android.content.res.Configuration
import android.os.Build
import android.view.View
import android.view.Window
import android.view.WindowManager.LayoutParams
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogWindowProvider
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalWindowPrivacy
import at.uac.android.core.PickerLocale
import at.uac.android.core.ProtectedDialog
import at.uac.android.core.WindowPrivacy
import at.uac.android.core.pickerLocaleConfiguration
import at.uac.android.feature.authoring.AuthoringDateTime
import at.uac.android.feature.organization.OrganizationOfferCalendar
import at.uac.android.feature.organization.OrganizationOfferDate
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.TimeZone
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Real Material components; English is scoped to this test, never a device/process change. */
@OptIn(ExperimentalMaterial3Api::class)
class PickerLocaleUiTest {
    @get:Rule val compose = createComposeRule()
    private val initial = Instant.parse("2026-01-10T00:00:00Z").toEpochMilli()

    @Composable
    private fun EnglishHost(content: @Composable () -> Unit) {
        val currentContext = LocalContext.current
        val incoming = Configuration(LocalConfiguration.current).apply { setLocale(Locale.US) }
        val context =
            remember(currentContext, incoming) {
                currentContext.createConfigurationContext(incoming)
            }
        CompositionLocalProvider(
            LocalConfiguration provides incoming,
            LocalContext provides context,
            LocalDensity provides Density(LocalDensity.current.density, 2f),
        ) {
            MaterialTheme(content = content)
        }
    }

    private fun assertLayoutLocale(text: String, language: String, fontScale: Float = 2f) {
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(text, useUnmergedTree = true).performSemanticsAction(
            SemanticsActions.GetTextLayoutResult
        ) {
            it(layouts)
        }
        assertEquals(1, layouts.size)
        assertEquals(language, layouts.single().layoutInput.style.localeList?.get(0)?.language)
        assertEquals(fontScale, layouts.single().layoutInput.density.fontScale, 0.001f)
        val layout = layouts.single()
        // Intrinsic-width Text can retain a wider shaping paragraph than its final box.
        // didOverflowWidth then reports overflow even when every rendered line fits.
        // Check actual ink/line coverage and ellipsis instead of the shaping container width.
        val clipped =
            layout.lineCount == 0 ||
                (0 until layout.lineCount).any { line ->
                    layout.isLineEllipsized(line) ||
                        layout.getLineLeft(line) < -1f ||
                        layout.getLineRight(line) > layout.size.width + 1f ||
                        layout.getLineBottom(line) > layout.size.height + 1f
                } ||
                layout.getLineEnd(layout.lineCount - 1, visibleEnd = true) < text.trimEnd().length
        if (clipped) {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val screenshot =
                InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
            java.io
                .File(context.getExternalFilesDir(null), "picker-overflow-$language.png")
                .outputStream()
                .use { screenshot.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            screenshot.recycle()
        }
        assertFalse(
            "Picker text=$text language=$language scale=$fontScale size=${layout.size} " +
                "constraints=${layout.layoutInput.constraints} font=${layout.layoutInput.style.fontSize} " +
                "lines=${layout.lineCount} maxLines=${layout.layoutInput.maxLines} " +
                "overflow=${layout.layoutInput.overflow} paragraphWidth=${layout.multiParagraph.width}",
            clipped,
        )
    }

    // This assertion deliberately checks localized Android Resources independently of
    // LocalConfiguration: matching the latter alone would miss an incorrectly scoped Context.
    @SuppressLint("LocalContextConfigurationRead")
    private fun calendarPresentation(language: String) {
        val processLocale = Locale.getDefault()
        val processZone = TimeZone.getDefault()
        var picker: DatePickerState? = null
        var scopedResourceLanguage: String? = null
        var incomingLanguage: String? = null
        val title = if (language == "uk") "Виберіть дату" else "Datum auswählen"
        val inputMode =
            if (language == "uk") "Перейти в режим введення тексту"
            else "In den Texteingabemodus wechseln"
        val nextMonth =
            if (language == "uk") "Перейти до наступного місяця" else "Zum nächsten Monat wechseln"
        val errorPrefix =
            if (language == "uk") "Дата не відповідає очікуваному шаблону:"
            else "Datum entspricht nicht dem erwarteten Format:"
        compose.setContent {
            EnglishHost {
                incomingLanguage = LocalConfiguration.current.locales[0].language
                PickerLocale(language) {
                    val state = rememberDatePickerState(initialSelectedDateMillis = initial)
                    val context = LocalContext.current
                    SideEffect {
                        picker = state
                        scopedResourceLanguage = context.resources.configuration.locales[0].language
                    }
                    Column(Modifier.verticalScroll(rememberScrollState())) { DatePicker(state) }
                }
            }
        }
        compose.onNodeWithText(title).performScrollTo().assertIsDisplayed()
        assertLayoutLocale(title, language)
        compose.onNodeWithContentDescription(nextMonth).assertExists()
        compose.runOnIdle {
            assertEquals("en", incomingLanguage)
            assertEquals(language, requireNotNull(picker).locale.language)
            assertEquals(language, scopedResourceLanguage)
            assertEquals(initial, requireNotNull(picker).selectedDateMillis)
        }
        compose.onNodeWithContentDescription(inputMode).performScrollTo().performClick()
        compose.onNode(hasSetTextAction()).performScrollTo().performTextReplacement("99999999")
        compose.onNodeWithText(errorPrefix, substring = true).assertExists()
        compose.runOnIdle {
            assertNull(picker?.selectedDateMillis)
            assertEquals(processLocale, Locale.getDefault())
            assertEquals(processZone, TimeZone.getDefault())
        }
    }

    @Test
    fun ukrainianCalendarResourcesErrorAndActualTextLayoutMatchAppLanguage() =
        calendarPresentation("uk")

    @Test
    fun germanCalendarResourcesErrorAndActualTextLayoutMatchAppLanguage() =
        calendarPresentation("de")

    private fun editorRoundTrip(language: String) {
        val systemScale =
            InstrumentationRegistry.getInstrumentation()
                .targetContext
                .resources
                .configuration
                .fontScale
        val dateTitle = if (language == "uk") "Виберіть дату" else "Datum auswählen"
        val cancel = if (language == "uk") "Скасувати" else "Abbrechen"
        val apply = if (language == "uk") "Застосувати" else "Übernehmen"
        val hour = if (language == "uk") "Вибрати годину" else "Stunde auswählen"
        val zone = ZoneId.of("Europe/Vienna")
        val original =
            Instant.parse(
                "2026-10-25T01:30:00Z"
            ) // Repeated local hour: retain the original offset.
        val offer =
            OrganizationOfferCalendar.inclusiveEnd(initial, ZoneId.systemDefault()).toString()
        var date by mutableStateOf(original)
        var offerValue by mutableStateOf(offer)
        var changes = 0
        var offers = 0
        compose.setContent {
            EnglishHost {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    AuthoringDateTime(
                        "Synthetic date",
                        date,
                        true,
                        language,
                        true,
                        zone,
                        "locale-date",
                    ) {
                        changes++
                        date = it
                    }
                    OrganizationOfferDate(offerValue, language, true) {
                        offers++
                        offerValue = it
                    }
                }
            }
        }
        compose.onNodeWithTag("locale-date-date").performClick()
        compose.onNodeWithText(dateTitle).assertExists()
        assertLayoutLocale(dateTitle, language, systemScale)
        assertLastCalendarColumnVisible(language)
        compose.onNodeWithText(cancel).performScrollTo().assertHeightIsAtLeast(48.dp).performClick()
        compose.runOnIdle {
            assertEquals(0, changes)
            assertEquals(original, date)
        }
        compose.onNodeWithTag("locale-date-date").performClick()
        compose.onNodeWithText(apply).performScrollTo().assertHeightIsAtLeast(48.dp).performClick()
        compose.runOnIdle {
            assertEquals(1, changes)
            assertEquals(original, date)
        }
        compose.onNodeWithTag("locale-date-time").performClick()
        compose.onNodeWithContentDescription(hour).assertExists()
        compose.onNodeWithText(cancel).performScrollTo().assertHeightIsAtLeast(48.dp).performClick()
        compose.runOnIdle {
            assertEquals(1, changes)
            assertEquals(original, date)
        }
        compose.onNodeWithTag("locale-date-time").performClick()
        compose.onNodeWithText(apply).performScrollTo().assertHeightIsAtLeast(48.dp).performClick()
        compose.runOnIdle {
            assertEquals(2, changes)
            assertEquals(original, date)
        }
        compose.onNodeWithTag("organization-offer-date").performScrollTo().performClick()
        compose.onNodeWithText(dateTitle).assertExists()
        assertLayoutLocale(dateTitle, language, systemScale)
        compose.onNodeWithText(cancel).performScrollTo().assertHeightIsAtLeast(48.dp).performClick()
        compose.runOnIdle {
            assertEquals(0, offers)
            assertEquals(offer, offerValue)
        }
        compose.onNodeWithTag("organization-offer-date").performScrollTo().performClick()
        compose.onNodeWithText(apply).performScrollTo().assertHeightIsAtLeast(48.dp).performClick()
        compose.runOnIdle {
            assertEquals(1, offers)
            assertEquals(offer, offerValue)
        }
    }

    private fun assertLastCalendarColumnVisible(language: String) {
        // 25 October is Sunday, the last column in both app locales. Check the real
        // production dialog, not a full-width isolated Material component.
        val sunday = Instant.parse("2026-10-25T00:00:00Z").toEpochMilli()
        val label =
            requireNotNull(
                DatePickerDefaults.dateFormatter()
                    .formatDate(
                        sunday,
                        Locale.forLanguageTag(language),
                        forContentDescription = true,
                    )
            )
        val cell = compose.onNodeWithText(label, useUnmergedTree = true)
        cell.performScrollTo().assertIsDisplayed().assertHeightIsAtLeast(48.dp)
        val visible = cell.fetchSemanticsNode().boundsInRoot
        val whole = cell.getUnclippedBoundsInRoot()
        val density =
            InstrumentationRegistry.getInstrumentation()
                .targetContext
                .resources
                .displayMetrics
                .density
        assertTrue(
            "Sunday calendar touch target clipped: visible=$visible whole=$whole density=$density",
            visible.width + 1f >= (whole.right - whole.left).value * density &&
                visible.width + 1f >= 48f * density,
        )
    }

    @Test
    fun ukrainianRealPickerSectionsPreserveCancelApplyOnceAndOriginalInstant() =
        editorRoundTrip("uk")

    @Test
    fun germanRealPickerSectionsPreserveCancelApplyOnceAndOriginalInstant() = editorRoundTrip("de")

    @Test
    fun configurationCopiesLocaleOnlyAndNeverMutatesApplicationOrProcess() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val application = Configuration(context.applicationContext.resources.configuration)
        val processLocale = Locale.getDefault()
        val processZone = TimeZone.getDefault()
        val base =
            Configuration(application).apply {
                setLocale(Locale.US)
                fontScale = 2f
                densityDpi = 420
                screenWidthDp = 640
                screenHeightDp = 360
                orientation = Configuration.ORIENTATION_LANDSCAPE
            }
        val unchanged = Configuration(base)
        listOf("uk", "de").forEach { language ->
            val localized = pickerLocaleConfiguration(base, language)
            assertEquals(language, localized.locales[0].language)
            assertEquals(base.fontScale, localized.fontScale, 0f)
            assertEquals(base.densityDpi, localized.densityDpi)
            assertEquals(base.orientation, localized.orientation)
            assertEquals(base.screenWidthDp, localized.screenWidthDp)
            assertEquals(base.screenHeightDp, localized.screenHeightDp)
            assertEquals(base.uiMode, localized.uiMode)
            if (Build.VERSION.SDK_INT >= 31)
                assertEquals(base.fontWeightAdjustment, localized.fontWeightAdjustment)
        }
        assertEquals(unchanged, base)
        assertEquals(application, context.applicationContext.resources.configuration)
        assertEquals(processLocale, Locale.getDefault())
        assertEquals(processZone, TimeZone.getDefault())
        assertTrue(runCatching { pickerLocaleConfiguration(base, "invalid") }.isFailure)
    }

    @Test
    fun changingAppLanguageClosesUncommittedPickerWithoutChangingDraft() {
        var language by mutableStateOf("de")
        var enabled by mutableStateOf(true)
        var changes = 0
        compose.setContent {
            EnglishHost {
                AuthoringDateTime(
                    "Synthetic",
                    Instant.ofEpochMilli(initial),
                    true,
                    language,
                    enabled,
                    ZoneId.of("Europe/Vienna"),
                    "locale-switch",
                ) {
                    changes++
                }
            }
        }
        compose.onNodeWithTag("locale-switch-date").performClick()
        compose.onNodeWithText("Datum auswählen").assertExists()
        compose.runOnIdle { language = "uk" }
        compose.onNodeWithText("Datum auswählen").assertDoesNotExist()
        compose.onNodeWithText("Виберіть дату").assertDoesNotExist()
        compose.runOnIdle { assertEquals(0, changes) }
        compose.onNodeWithTag("locale-switch-date").performClick()
        compose.onNodeWithText("Виберіть дату").assertExists()
        compose.onNodeWithText("Скасувати").performScrollTo().performClick()
        compose.runOnIdle { enabled = false }
        compose.onNodeWithTag("locale-switch-date").assertIsNotEnabled()
        compose.onNodeWithTag("locale-switch-time").assertIsNotEnabled()
        compose.runOnIdle { assertEquals(0, changes) }
    }

    // Verify the new Android Dialog root receives both Resources and composition locale.
    @SuppressLint("LocalContextConfigurationRead")
    @Test
    fun localizedPickerRetainsActualProtectedWindowAndSynchronousInputBlock() {
        val privacy = WindowPrivacy()
        lateinit var window: Window
        var resourceLanguage: String? = null
        var configurationLanguage: String? = null
        var stateLanguage: String? = null
        var month = ""
        fun windowOf(view: View): Window {
            var parent = view.parent
            while (parent != null) {
                (parent as? DialogWindowProvider)?.let {
                    return it.window
                }
                parent = parent.parent
            }
            error("Protected picker window was not found")
        }
        try {
            compose.setContent {
                EnglishHost {
                    CompositionLocalProvider(LocalWindowPrivacy provides privacy) {
                        PickerLocale("uk") {
                            val state = rememberDatePickerState(initialSelectedDateMillis = initial)
                            ProtectedDialog({}) {
                                PickerLocale("uk") {
                                    val view = LocalView.current
                                    val inherited = LocalWindowPrivacy.current
                                    val context = LocalContext.current
                                    val configuration = LocalConfiguration.current
                                    val monthTitle =
                                        requireNotNull(
                                            DatePickerDefaults.dateFormatter()
                                                .formatMonthYear(initial, state.locale)
                                        )
                                    SideEffect {
                                        assertSame(privacy, inherited)
                                        window = windowOf(view)
                                        resourceLanguage =
                                            context.resources.configuration.locales[0].language
                                        configurationLanguage = configuration.locales[0].language
                                        stateLanguage = state.locale.language
                                        month = monthTitle
                                    }
                                    DatePicker(state)
                                }
                            }
                        }
                    }
                }
            }
            compose.onNodeWithText("Виберіть дату").assertExists()
            compose.runOnIdle {
                assertEquals("uk", stateLanguage)
                assertEquals("uk", resourceLanguage)
                assertEquals("uk", configurationLanguage)
                assertTrue(month.isNotBlank())
            }
            compose.onNodeWithText(month, useUnmergedTree = true).assertExists()
            compose.onNodeWithContentDescription("Перейти до наступного місяця").assertExists()
            val systemScale =
                InstrumentationRegistry.getInstrumentation()
                    .targetContext
                    .resources
                    .configuration
                    .fontScale
            assertLayoutLocale("Виберіть дату", "uk", systemScale)
            assertLayoutLocale(month, "uk", systemScale)
            compose.runOnIdle {
                privacy.update(secure = true, blocked = true)
                val required =
                    LayoutParams.FLAG_SECURE or
                        LayoutParams.FLAG_NOT_TOUCHABLE or
                        LayoutParams.FLAG_NOT_FOCUSABLE
                assertEquals(required, window.attributes.flags and required)
                assertEquals(
                    View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS,
                    window.decorView.importantForAccessibility,
                )
            }
        } finally {
            compose.runOnIdle { privacy.close() }
        }
    }
}
