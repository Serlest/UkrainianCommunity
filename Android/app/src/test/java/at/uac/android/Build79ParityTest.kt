package at.uac.android

import androidx.lifecycle.SavedStateHandle
import at.uac.android.feature.browse.*
import at.uac.android.feature.owneranalytics.metricDelta
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class Build79ParityTest {
    private val now = Instant.parse("2026-09-08T10:00:00Z")

    @Before fun setup() = Dispatchers.setMain(StandardTestDispatcher())

    @After fun finish() = Dispatchers.resetMain()

    @Test
    fun newsCalendarBoundsUseViennaDaysIncludingDst() {
        val spring = Instant.parse("2026-03-29T10:00:00Z")
        val range = newsDateRange(NewsPeriod.TODAY, spring, ZoneId.of("Europe/Vienna"))
        assertEquals(23, Duration.between(range.startInclusive, range.endExclusive).toHours())
        val custom =
            newsDateRange(
                NewsPeriod.CUSTOM,
                now,
                customStart = LocalDate.parse("2026-09-01"),
                customEnd = LocalDate.parse("2026-09-03"),
            )
        assertEquals(72, Duration.between(custom.startInclusive, custom.endExclusive).toHours())
    }

    @Test
    fun topicSearchAndPersonalScopesMatchCompleteNewsMetadata() {
        val row =
            RawDocument(
                "news-1",
                mapOf(
                    "title" to "Titel",
                    "body" to "Text",
                    "createdAt" to now,
                    "updatedAt" to now,
                    "publishedAt" to now,
                    "moderationStatus" to "approved",
                    "sourceType" to "organization",
                    "regionScope" to "austria",
                    "category" to "education",
                    "additionalCategories" to listOf("culture"),
                    "organizationId" to "org-1",
                    "publisherName" to "UAC Wien",
                ),
            )
        val item = decodeContent(ContentKind.NEWS, row)
        assertTrue(item.matches(ContentQuery(ContentKind.NEWS, search = "wien")))
        assertTrue(item.matches(ContentQuery(ContentKind.NEWS, category = "culture")))
        assertTrue(
            ContentQuery(
                    ContentKind.NEWS,
                    newsSource = NewsSource.SAVED,
                    allowedNewsIds = setOf("news-1"),
                )
                .acceptsRaw(row)
        )
        assertTrue(
            ContentQuery(
                    ContentKind.NEWS,
                    newsSource = NewsSource.SUBSCRIBED,
                    allowedOrganizationIds = setOf("org-1"),
                )
                .acceptsRaw(row)
        )
    }

    @Test
    fun newsFilterStatePersistsAndUsesPersonalMembership() = runTest {
        val recentlyPublished = Instant.now()
        val row =
            RawDocument(
                "saved-news",
                mapOf(
                    "title" to "Saved",
                    "body" to "Body",
                    "createdAt" to now,
                    "updatedAt" to now,
                    "publishedAt" to recentlyPublished,
                    "moderationStatus" to "approved",
                    "sourceType" to "organization",
                    "regionScope" to "austria",
                    "category" to "education",
                    "organizationId" to "org-1",
                ),
            )
        val repository =
            ContentRepository(
                SyntheticContentSource(mapOf("news/saved-news" to row)),
                MemoryContentCache(),
            )
        val saved = SavedStateHandle()
        val model =
            BrowseViewModel(
                repository,
                repository,
                saved,
                "de",
                "",
                "system",
                { _, _ -> },
                NewsPersonalScopeSource { NewsPersonalScope(newsIds = setOf("saved-news")) },
            )
        model.navigate("news", true)
        model.filters(
            newsPeriod = NewsPeriod.THIRTY_DAYS,
            newsOrder = NewsOrder.OLDEST,
            newsSource = NewsSource.SAVED,
        )
        advanceUntilIdle()
        assertEquals(listOf("saved-news"), model.state.value.data.items.map { it.id })
        assertEquals(NewsPeriod.THIRTY_DAYS, model.state.value.newsPeriod)
        assertEquals(NewsOrder.OLDEST, model.state.value.newsOrder)
        assertEquals(NewsSource.SAVED, model.state.value.newsSource)
    }

    @Test
    fun analyticsDeltaIsStableAndExplicit() {
        assertEquals("-77.4%", metricDelta(7, 31))
        assertEquals("+100%", metricDelta(3, 0))
        assertEquals("0%", metricDelta(0, 0))
    }
}
