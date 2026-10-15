package at.uac.android

import android.graphics.Bitmap
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.lifecycle.SavedStateHandle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.feature.browse.*
import java.io.File
import java.time.Instant
import java.time.Duration
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Same bundled content in each appearance; captures real Compose chrome and discovery screens. */
@RunWith(AndroidJUnit4::class)
class Step7VisualParityUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun rootScreensKeepBrandFiltersAndLocalizedTextAcrossAppearances() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val fixtures = ContentJson.fixtures(context).toMutableMap()
        // The banner text and media URL mirror the iOS 107 mock banner. The news media is
        // deliberately absent on both sides, so the fallback presentation is comparable.
        fixtures["featuredBanners/synthetic-banner-welcome"]?.let { original ->
            fixtures["featuredBanners/synthetic-banner-welcome"] = original.copy(fields =
                original.fields + mapOf(
                    "imageURL" to "https://example.com/featured/tirol-event.jpg",
                    "visibleSections" to listOf("home", "events"),
                    "localizations" to mapOf(
                        "de" to mapOf("title" to "Community-Treffen in Tirol",
                            "subtitle" to "Ein regionales Treffen für Familien und Freiwillige."),
                        "uk" to mapOf("title" to "Зустріч громади в Тіролі",
                            "subtitle" to "Регіональна зустріч для родин і волонтерів."),
                    ),
                ))
        }
        fixtures["featuredBanners/synthetic-banner-event"]?.let { original ->
            fixtures["featuredBanners/synthetic-banner-event"] = original.copy(fields =
                original.fields + mapOf(
                    "title" to "Partner legal advice hours",
                    "subtitle" to "Book a consultation with a verified partner organization.",
                    "imageURL" to "https://example.com/featured/partner-advice.jpg",
                    "actionType" to "externalURL",
                    "externalURL" to "https://example.com/legal-advice",
                    "visibleSections" to listOf("organizations"),
                    "priority" to 40,
                    "localizations" to mapOf(
                        "de" to mapOf("title" to "Partner legal advice hours",
                            "subtitle" to "Book a consultation with a verified partner organization."),
                        "uk" to mapOf("title" to "Partner legal advice hours",
                            "subtitle" to "Book a consultation with a verified partner organization."),
                    ),
                ))
        }
        fixtures["news/synthetic-news-18"]?.let { original ->
            fixtures["news/synthetic-news-18"] = original.copy(fields = original.fields +
                mapOf("imageURL" to "", "sourceName" to "Community-Team",
                    "organizationName" to "Community-Team",
                    "publishedAt" to Instant.now().minus(Duration.ofDays(1)),
                    "localizations" to mapOf(
                        "de" to mapOf("title" to "Gemeinschaftszentrum startet wochentliche Rechtsberatung",
                            "subtitle" to "Kostenlose Beratungen zu Aufenthalt und Alltag"),
                        "uk" to mapOf("title" to "Громадський центр відкриває щотижневі години юридичної підтримки",
                            "subtitle" to "Безкоштовні консультації щодо проживання та побуту"),
                    )))
        }
        fixtures["events/synthetic-event-01"]?.let { original ->
            val eventStart = java.time.ZonedDateTime.now(java.time.ZoneId.of("Europe/Vienna"))
                .plusDays(4).withHour(9).withMinute(23).withSecond(0).withNano(0).toInstant()
            fixtures["events/synthetic-event-01"] = original.copy(fields =
                original.fields + mapOf(
                    "imageURL" to "",
                    "startDate" to eventStart,
                    "endDate" to eventStart.plus(Duration.ofHours(2)),
                    "occurrences" to listOf(mapOf(
                        "id" to "occurrence-01",
                        "startDate" to eventStart,
                        "endDate" to eventStart.plus(Duration.ofHours(2)),
                        "isAllDay" to false,
                        "status" to "scheduled",
                    )),
                    "city" to "Innsbruck",
                    "localizations" to mapOf(
                        "de" to mapOf("title" to "Ukrainischer Gemeinschaftsabend",
                            "summary" to "Lernen Sie Nachbarn und Freiwillige kennen."),
                        "uk" to mapOf("title" to "Український вечір спільноти",
                            "summary" to "Зустріньте сусідів, волонтерів і місцевих активістів."),
                    ),
                ))
        }
        // Keep the screenshot comparison on the same single October 2026 event as iOS 107.
        fixtures.keys.removeAll { it.startsWith("events/") && it != "events/synthetic-event-01" }
        fixtures["organizations/synthetic-org-18"]?.let { original ->
            fixtures["organizations/synthetic-org-18"] = original.copy(fields =
                original.fields + mapOf("imageURL" to "",
                    "localizations" to mapOf(
                        "de" to mapOf("name" to "Ukrainisches Haus Tirol",
                            "shortDescription" to "Community-Unterstützung, Sprachaustausch und kulturelle Veranstaltungen."),
                        "uk" to mapOf("name" to "Український дім Тіролю",
                            "shortDescription" to "Підтримка громади, мовний обмін і культурні події."),
                    )))
        }
        val repository = ContentRepository(
            SyntheticContentSource(fixtures), MemoryContentCache())
        val model = BrowseViewModel(repository, repository, SavedStateHandle(), "de", "", "light", { _, _ -> })
        compose.setContent {
            val state = model.state.collectAsState().value
            BrowseScreen(state, model, {})
        }
        val mode = InstrumentationRegistry.getArguments().getString("step7Mode") ?: "compact"
        val appearances = if (mode == "large") listOf("de" to "light")
            else if (mode == "wide") listOf("de" to "light", "uk" to "dark")
            else listOf("de" to "light", "de" to "dark", "uk" to "light", "uk" to "dark")
        for ((language, theme) in appearances) {
            for (route in if (mode == "large") listOf("home") else listOf("home", "events", "organizations")) {
                compose.runOnIdle {
                    model.preference("language", language)
                    model.preference("theme", theme)
                    model.navigate(route, true)
                }
                compose.waitUntil(15_000) {
                    model.state.value.let { it.route == route && it.language == language &&
                        it.theme == theme && !it.data.loading && it.data.banners.isNotEmpty() }
                }
                compose.onNodeWithContentDescription("Ukrainian Community").assertIsDisplayed()
                compose.onNodeWithTag("header-search-toggle").assertIsDisplayed()
                compose.onNodeWithTag("primary-filter-row").assertExists()
                compose.onNodeWithTag("banner-hero").assertExists()
                compose.onNodeWithTag("banner-media").assertExists()
                compose.onNodeWithTag("search-toggle").assertDoesNotExist()
                compose.onNodeWithTag("news-topic").assertDoesNotExist()
                if (route == "organizations")
                    compose.onNodeWithTag("organization-all").assertIsSelected()
                if (mode == "large")
                    compose.onNodeWithTag("banner-caption-below").assertExists()
                capture("$mode-$route-$language-$theme")
            }
        }
        compose.runOnIdle { model.navigate("home", true) }
        compose.waitUntil(15_000) { model.state.value.route == "home" && !model.state.value.data.loading }
        compose.onNodeWithTag("header-search-toggle").performClick()
        compose.onNodeWithTag("header-search-field").assertIsDisplayed()
        compose.onNodeWithTag("header-search-toggle").performClick()
        compose.onNodeWithTag("header-search-field").assertDoesNotExist()
        assertEquals("", model.state.value.search)
        if (mode != "large") {
            for (route in listOf("directory", "profile")) {
                compose.runOnIdle { model.navigate(route, true) }
                compose.waitUntil(15_000) { model.state.value.route == route }
                compose.onNodeWithContentDescription("Ukrainian Community").assertIsDisplayed()
                compose.onNodeWithTag("tab-$route").assertIsDisplayed()
                if (route == "directory") {
                    compose.onNodeWithTag("header-search-toggle").assertIsDisplayed()
                    compose.onNodeWithTag("directory-search").assertDoesNotExist()
                }
                if (route == "directory")
                    capture("$mode-$route-${model.state.value.language}-${model.state.value.theme}")
                if (route == "directory") {
                    compose.onNodeWithTag("header-search-toggle").performClick()
                    compose.onNodeWithTag("directory-search").assertIsDisplayed()
                    compose.onNodeWithTag("header-search-toggle").performClick()
                    compose.onNodeWithTag("directory-search").assertDoesNotExist()
                }
            }
        }
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir,
            "step7-$name.png").outputStream().use {
            check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it))
        }
    }
}
