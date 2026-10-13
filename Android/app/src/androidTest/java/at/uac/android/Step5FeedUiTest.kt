package at.uac.android

import androidx.compose.runtime.collectAsState
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.lifecycle.SavedStateHandle
import androidx.test.ext.junit.runners.AndroidJUnit4
import at.uac.android.feature.browse.*
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class Step5FeedUiTest {
    @get:Rule val compose = createComposeRule()

    private fun capture(name: String) {
        val tag = when {
            name.endsWith("filters") -> "browse-filter-sheet"
            name == "navigation" -> "uac-navigation-row"
            else -> "browse-list"
        }
        val bitmap = compose.onNodeWithTag(tag).captureToImage().asAndroidBitmap()
        java.io.File(androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
            .targetContext.cacheDir, "step5-$name.png")
            .outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun model(): BrowseViewModel {
        val now = Instant.now()
        fun common(id: String) = mapOf<String, Any?>(
            "id" to id,
            "moderationStatus" to "approved",
            "sourceType" to "organization",
            "regionScope" to "austria",
            "createdAt" to now,
            "updatedAt" to now,
            "category" to "education",
        )
        val documents = buildMap {
            (1..8).forEach { number ->
                val id = "step5-news-$number"
                put("news/$id", RawDocument(id, common(id) + mapOf(
                    "title" to "News $number", "body" to "Body $number",
                    "publishedAt" to now.plusSeconds(number.toLong()),
                )))
            }
            val eventId = "step5-event"
            put("events/$eventId", RawDocument(eventId, common(eventId) + mapOf(
                "title" to "Event", "summary" to "Summary", "details" to "Details",
                "startDate" to now.plusSeconds(3600), "endDate" to now.plusSeconds(7200),
                "audience" to "everyone", "minimumAge" to 10, "maximumAge" to 15,
            )))
            (1..7).forEach { number ->
                val id = "step5-past-$number"
                val start = now.minusSeconds(number * 86_400L)
                put("events/$id", RawDocument(id, common(id) + mapOf(
                    "title" to "Past event $number", "summary" to "Summary",
                    "details" to "Details", "startDate" to start,
                    "endDate" to start.plusSeconds(3600),
                )))
            }
            val organizationId = "step5-org"
            put("organizations/$organizationId", RawDocument(organizationId,
                common(organizationId) + mapOf(
                    "name" to "Organization", "city" to "Wien",
                    "description" to "Description",
                )))
        }
        val repository = ContentRepository(SyntheticContentSource(documents), MemoryContentCache())
        return BrowseViewModel(repository, repository, SavedStateHandle(), "de", "", "light", { _, _ -> })
    }

    @Test fun newsTabIsPaginatedAndEventsAreGroupedByMonth() {
        val model = model()
        compose.setContent {
            val state = model.state.collectAsState().value
            BrowseScreen(state, model, {})
        }
        compose.waitUntil(10_000) { !model.state.value.data.loading }
        compose.onNodeWithTag("tab-home").assertIsSelected()
        compose.onNodeWithTag("primary-filter-row").assertExists()
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("card-step5-news-8"))
        compose.onNodeWithTag("card-step5-news-8").assertIsDisplayed()
        compose.onNodeWithTag("browse-list").performScrollToIndex(0)
        capture("news")
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("load-more"))
        compose.onNodeWithTag("load-more").performClick()
        compose.waitUntil(10_000) { !model.state.value.data.loading }
        compose.runOnIdle { assertEquals(8, model.state.value.data.items.size) }

        compose.runOnIdle { model.navigate("events", true) }
        compose.waitUntil(10_000) { !model.state.value.data.loading }
        val month = model.state.value.data.items.first().fields
            .displayEventOccurrence(Instant.now())!!.start
            .atZone(ZoneId.systemDefault()).toLocalDate().withDayOfMonth(1)
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("event-month-$month"))
        compose.onNodeWithTag("event-month-$month").assertIsDisplayed()
        capture("events")
        capture("navigation")
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("card-step5-event"))
        compose.onNodeWithTag("card-step5-event").assertIsDisplayed()
        compose.onNodeWithTag("browse-list")
            .performScrollToNode(hasTestTag("past-events-heading"))
        compose.onNodeWithTag("past-events-heading").assertIsDisplayed()
        compose.onNodeWithTag("browse-list")
            .performScrollToNode(hasTestTag("card-step5-past-2"))
        capture("past-events")
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("load-more-past"))
        compose.onNodeWithTag("load-more-past").performClick()
        compose.waitUntil(10_000) { !model.state.value.data.pastLoading }
        compose.runOnIdle { assertEquals(7, model.state.value.data.pastItems.size) }
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("card-step5-event"))
        compose.onNodeWithTag("news-filters").performScrollTo().performClick()
        compose.onNodeWithTag("event-period-TODAY").performScrollTo().performClick()
        compose.onNodeWithTag("event-age-TEEN").performScrollTo().performClick()
        compose.onNodeWithTag("content-filter-done").performScrollTo().performClick()
        compose.waitUntil(10_000) { !model.state.value.data.loading }
        compose.onNodeWithTag("browse-list").performScrollToNode(hasTestTag("card-step5-event"))
        compose.onNodeWithTag("card-step5-event").assertIsDisplayed()
    }

    @Test fun guestPersonalScopeShowsSignInInsteadOfGenericPermissionFailure() {
        val model = model()
        compose.setContent {
            val state = model.state.collectAsState().value
            BrowseScreen(state, model, {})
        }
        compose.runOnIdle { model.navigate("organizations", true) }
        compose.waitUntil(10_000) { !model.state.value.data.loading }
        compose.runOnIdle { assertEquals("organizations", model.state.value.route) }
        capture("organizations")
        compose.onNodeWithTag("organization-quick-scope-BOOKMARKED")
            .performScrollTo().performClick()
        compose.waitUntil(10_000) { !model.state.value.data.loading }
        compose.onNodeWithTag("browse-sign-in").performScrollTo().assertIsDisplayed()
    }
}
