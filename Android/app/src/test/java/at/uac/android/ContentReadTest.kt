package at.uac.android

import at.uac.android.feature.browse.*
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class ContentReadTest {
    private val now = Instant.parse("2026-09-02T10:00:00.123456789Z")

    private fun row(id: String, extra: Fields = emptyMap()) =
        RawDocument(
            id,
            mapOf(
                "title" to "Root $id",
                "body" to "Body",
                "summary" to "Root summary",
                "moderationStatus" to "approved",
                "sourceType" to "organization",
                "createdAt" to now,
                "updatedAt" to now,
                "publishedAt" to now,
                "regionScope" to "austria",
                "category" to "education",
            ) + extra,
        )

    private fun source(rows: List<RawDocument>, kind: ContentKind = ContentKind.NEWS) =
        SyntheticContentSource(rows.associateBy { "${kind.collection}/${it.id}" })

    private fun repo(rows: List<RawDocument>) =
        ContentRepository(source(rows), MemoryContentCache()) { now }

    private suspend fun failure(expected: ReadFailure, action: suspend () -> Unit) {
        try {
            action()
            fail("Expected $expected")
        } catch (e: ReadException) {
            assertEquals(expected, e.reason)
        }
    }

    @Test
    fun nestedNewsSubtitleAndLocaleFallback() {
        val item =
            decodeContent(
                ContentKind.NEWS,
                row(
                    "a",
                    mapOf(
                        "localizations" to
                            mapOf(
                                "uk" to
                                    mapOf(
                                        "title" to "Українська",
                                        "subtitle" to "Підзаголовок",
                                        "body" to "Текст",
                                    ),
                                "de" to
                                    mapOf(
                                        "title" to "Deutsch",
                                        "subtitle" to "Untertitel",
                                        "body" to "Text",
                                    ),
                            )
                    ),
                ),
            )
        assertEquals("Untertitel", item.summary("de"))
        assertEquals("Українська", item.title("fr"))
        assertEquals("Root summary", decodeContent(ContentKind.NEWS, row("b")).summary("de"))
    }

    @Test
    fun thirdLocaleFallbackIsDeterministic() {
        val item =
            decodeContent(
                ContentKind.NEWS,
                row(
                    "a",
                    mapOf(
                        "localizations" to
                            linkedMapOf(
                                "fr" to mapOf("title" to "fr"),
                                "en" to mapOf("title" to "en"),
                            )
                    ),
                ),
            )
        assertEquals("en", item.title("de"))
    }

    @Test
    fun malformedAndDeniedAreNotEmptySuccess() = runTest {
        failure(ReadFailure.INVALID) {
            decodeContent(ContentKind.NEWS, row("a", mapOf("body" to 9)))
        }
        failure(ReadFailure.DENIED) {
            decodeContent(ContentKind.NEWS, row("a", mapOf("moderationStatus" to "pendingReview")))
        }
        failure(ReadFailure.MISSING) { repo(emptyList()).detail(ContentKind.NEWS, "missing") }
    }

    @Test
    fun cursorKeepsNanosecondsAndTies() = runTest {
        val rows = (1..18).map { row("item-${it.toString().padStart(2, '0')}") }
        val repository = repo(rows)
        val query = ContentQuery(ContentKind.NEWS, now = now)
        val found = mutableListOf<String>()
        var cursor: ContentCursor? = null
        do {
            val page = repository.page(query, cursor).value
            found += page.items.map { it.id }
            cursor = page.next
            assertEquals(123456789, cursor!!.time.nano)
        } while (page.hasMore)
        assertEquals(rows.map { it.id }.sortedDescending(), found)
        assertEquals(found.size, found.distinct().size)
    }

    @Test
    fun searchFindsMatchBeyondFirstBackendPage() = runTest {
        val rows =
            (1..30).map {
                row(
                    it.toString().padStart(2, '0'),
                    mapOf("body" to if (it == 1) "Unique Café" else "Other"),
                )
            }
        val page =
            repo(rows).page(ContentQuery(ContentKind.NEWS, search = "unique cafe", now = now)).value
        assertEquals(listOf("01"), page.items.map { it.id })
        assertFalse(page.hasMore)
    }

    @Test
    fun scanBudgetExposesContinuation() = runTest {
        val repository = repo((1..100).map { row(it.toString().padStart(3, '0')) })
        val q = ContentQuery(ContentKind.NEWS, search = "not-present", now = now)
        val first = repository.page(q, size = 2).value
        assertTrue(first.hasMore)
        assertTrue(first.items.isEmpty())
        assertNotNull(first.next)
        assertFalse(repository.page(q, first.next, 2).value.hasMore)
    }

    @Test
    fun categorySearchAndRegionIncludeNationalOnlyPlusSelected() = runTest {
        val rows =
            listOf(
                row("national"),
                row("wien", mapOf("regionScope" to "city", "federalState" to "wien")),
                row("tirol", mapOf("regionScope" to "federalState", "federalState" to "tirol")),
            )
        assertEquals(
            setOf("national", "wien"),
            repo(rows)
                .page(
                    ContentQuery(
                        ContentKind.NEWS,
                        region = "wien",
                        category = "education",
                        now = now,
                    )
                )
                .value
                .items
                .map { it.id }
                .toSet(),
        )
        assertEquals(3, repo(rows).page(ContentQuery(ContentKind.NEWS, now = now)).value.items.size)
    }

    @Test
    fun invalidRowsAdvanceCursorAndAreReported() = runTest {
        val page =
            repo(listOf(row("z", mapOf("body" to 1)), row("a")))
                .page(ContentQuery(ContentKind.NEWS, now = now))
                .value
        assertEquals(1, page.invalidCount)
        assertEquals(listOf("a"), page.items.map { it.id })
        assertFalse(page.hasMore)
    }

    @Test
    fun eventOrderUsesEndNotStartAndPastHasOppositeOrder() = runTest {
        val rows =
            listOf(
                row(
                    "a",
                    mapOf(
                        "details" to "a",
                        "startDate" to now.minusSeconds(300),
                        "endDate" to now.plusSeconds(100),
                    ),
                ),
                row(
                    "b",
                    mapOf(
                        "details" to "b",
                        "startDate" to now.minusSeconds(100),
                        "endDate" to now.plusSeconds(50),
                    ),
                ),
                row(
                    "past",
                    mapOf(
                        "details" to "p",
                        "startDate" to now.minusSeconds(100),
                        "endDate" to now.minusSeconds(10),
                    ),
                ),
            )
        val repository =
            ContentRepository(source(rows, ContentKind.EVENTS), MemoryContentCache()) { now }
        assertEquals(
            listOf("b", "a"),
            repository.page(ContentQuery(ContentKind.EVENTS, now = now)).value.items.map { it.id },
        )
        assertEquals(
            listOf("past"),
            repository
                .page(ContentQuery(ContentKind.EVENTS, past = true, now = now))
                .value
                .items
                .map { it.id },
        )
    }

    @Test
    fun eventAudienceAndInvalidDates() = runTest {
        val event =
            row(
                "a",
                mapOf(
                    "details" to "a",
                    "startDate" to now,
                    "endDate" to now.plusSeconds(1),
                    "audience" to "families",
                ),
            )
        val content = decodeContent(ContentKind.EVENTS, event)
        assertTrue(
            content.matches(ContentQuery(ContentKind.EVENTS, audience = "families", now = now))
        )
        assertFalse(
            content.matches(ContentQuery(ContentKind.EVENTS, audience = "children", now = now))
        )
        failure(ReadFailure.INVALID) {
            decodeContent(
                ContentKind.EVENTS,
                row("b", event.fields + ("endDate" to now.minusSeconds(1))),
            )
        }
    }

    @Test
    fun recommendationsUseCategoryAndCreatedAtForEventsWithoutUpcomingConstraint() {
        val query =
            ContentQuery(
                ContentKind.EVENTS,
                category = "education",
                recommendations = true,
                now = now,
            )
        assertEquals("createdAt", query.orderField)
        assertFalse(query.ascending)
        assertTrue(query.acceptsRaw(row("past", mapOf("endDate" to now.minusSeconds(10)))))
    }

    @Test
    fun unsafeLinksAreRejected() {
        for (url in
            listOf(
                "http://example.com",
                "javascript:alert(1)",
                "https://user:pass@example.com",
                "https://example.com\\evil",
                "https://example.com/a b",
                "file:///tmp/a",
                "https://example.com:1234",
            )) assertNull(url, safeHttps(url))
        assertEquals("https://example.com/a", safeHttps(" https://example.com/a "))
        assertEquals("https://example.com", safeHttps("example.com", true))
    }

    @Test
    fun mediaCannotReachCloudOrRedirectHost() {
        assertTrue(
            localMediaUrl("http://10.0.2.2:9198/v0/b/demo-uac-android.appspot.com/o/test?alt=media")
        )
        assertFalse(localMediaUrl("https://storage.googleapis.com/production/file"))
        assertFalse(
            localMediaUrl("http://10.0.2.2.evil:9198/v0/b/demo-uac-android.appspot.com/o/test")
        )
        assertFalse(localMediaUrl("http://10.0.2.2:9198/v0/b/production/o/test"))
    }

    @Test
    fun donationOnlyWhenEnabledAndDomainValid() {
        assertNull(
            Donation(mapOf("isEnabled" to false, "donationURL" to "https://example.com")).url
        )
        assertNull(Donation(mapOf("isEnabled" to true, "donationURL" to "localhost")).url)
        assertEquals(
            "https://example.com",
            Donation(mapOf("isEnabled" to true, "donationURL" to "example.com")).url,
        )
    }

    private fun banner(id: String, extra: Fields = emptyMap()) =
        RawDocument(
            id,
            mapOf(
                "id" to id,
                "createdBy" to "synthetic-owner",
                "isActive" to true,
                "actionType" to "none",
                "title" to "Demo",
                "createdAt" to now,
                "updatedAt" to now,
                "priority" to 1,
                "displayDurationSeconds" to 6,
                "imageURL" to "https://example.invalid/test",
                "regionScope" to "allAustria",
                "visibleSections" to listOf("home"),
            ) + extra,
        )

    @Test
    fun bannerWindowsAreInclusiveRegionAndUnsupportedAreFiltered() {
        val rows =
            listOf(
                banner("a", mapOf("startsAt" to now, "endsAt" to now.plusSeconds(1))),
                banner("b", mapOf("endsAt" to now)),
                banner("expired", mapOf("endsAt" to now.minusNanos(1))),
                banner("future", mapOf("startsAt" to now.plusNanos(1))),
                banner("legacy", mapOf("actionType" to "guide")),
                banner("tirol", mapOf("regionScope" to "federalState", "federalState" to "tirol")),
            )
        assertEquals(listOf("a", "b"), visibleBanners(rows, "home", "wien", now).map { it.id })
        assertTrue(visibleBanners(rows, "news", "", now).isEmpty())
    }

    @Test
    fun bannerOrderUsesUpdatedAtThenIdAndFailClosedConfiguration() {
        val rows =
            listOf(
                banner("z"),
                banner("b", mapOf("updatedAt" to now.plusSeconds(1))),
                banner("a", mapOf("priority" to 2)),
            )
        assertEquals(listOf("a", "b", "z"), visibleBanners(rows, "home", "", now).map { it.id })
        assertFalse(Banner("a", banner("a", mapOf("extraUnknown" to true)).fields).valid())
        assertFalse(Banner("a", banner("a", mapOf("displayDurationSeconds" to 99)).fields).valid())
    }

    @Test
    fun datesRespectDeviceZoneAndViennaDst() {
        val before = Instant.parse("2030-10-27T00:30:00Z")
        val after = Instant.parse("2030-10-27T01:30:00Z")
        val zone = ZoneId.of("Europe/Vienna")
        assertTrue(displayTime(before, "de", zone = zone).contains("02:30"))
        assertTrue(displayTime(after, "de", zone = zone).contains("02:30"))
        assertNotEquals(
            displayTime(before, "de", zone = zone),
            displayTime(after, "de", zone = zone),
        )
        assertFalse(displayTime(before, "uk", allDay = true, zone = zone).contains(":"))
        assertNotEquals(
            displayTime(before, "de", zone = zone),
            displayTime(before, "de", zone = ZoneId.of("UTC")),
        )
    }

    private class SwitchSource(val delegate: ContentSource) : ContentSource by delegate {
        var error: ReadFailure? = null
        var wait = false

        override suspend fun page(
            query: ContentQuery,
            after: ContentCursor?,
            limit: Int,
        ): List<RawDocument> {
            if (wait) delay(10_000)
            error?.let { throw ReadException(it) }
            return delegate.page(query, after, limit)
        }

        override suspend fun document(path: String): RawDocument {
            error?.let { throw ReadException(it) }
            return delegate.document(path)
        }
    }

    @Test
    fun cacheOnlyForOfflineAndPermissionRevocationPurgesIt() = runTest {
        val source = SwitchSource(source(listOf(row("a"))))
        val repository = ContentRepository(source, MemoryContentCache()) { now }
        assertNull(repository.detail(ContentKind.NEWS, "a").cachedAt)
        source.error = ReadFailure.OFFLINE
        assertEquals(now, repository.detail(ContentKind.NEWS, "a").cachedAt)
        source.error = ReadFailure.DENIED
        failure(ReadFailure.DENIED) { repository.detail(ContentKind.NEWS, "a") }
        source.error = ReadFailure.OFFLINE
        failure(ReadFailure.OFFLINE) { repository.detail(ContentKind.NEWS, "a") }
    }

    @Test
    fun timeoutFallsBackButUnknownDoesNot() = runTest {
        val source = SwitchSource(source(listOf(row("a"))))
        val repository = ContentRepository(source, MemoryContentCache()) { now }
        val query = ContentQuery(ContentKind.NEWS, now = now)
        repository.page(query)
        source.wait = true
        assertEquals(now, repository.page(query).cachedAt)
        source.wait = false
        source.error = ReadFailure.UNKNOWN
        failure(ReadFailure.UNKNOWN) { repository.page(query) }
    }

    @Test
    fun cacheExpiresAfterOneDay() = runTest {
        var clock = now
        val source = SwitchSource(source(listOf(row("a"))))
        val repository = ContentRepository(source, MemoryContentCache()) { clock }
        repository.detail(ContentKind.NEWS, "a")
        source.error = ReadFailure.OFFLINE
        clock = now.plusSeconds(86_401)
        failure(ReadFailure.OFFLINE) { repository.detail(ContentKind.NEWS, "a") }
    }

    @Test
    fun cancellationIsNeverReportedAsOffline() = runTest {
        val delegate = source(emptyList())
        val source =
            object : ContentSource by delegate {
                override suspend fun document(path: String): RawDocument =
                    throw CancellationException()
            }
        try {
            ContentRepository(source, MemoryContentCache()).detail(ContentKind.NEWS, "a")
            fail()
        } catch (_: CancellationException) {
            /* expected */
        }
    }
}
