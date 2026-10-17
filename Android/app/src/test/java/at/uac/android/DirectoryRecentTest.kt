package at.uac.android

import androidx.lifecycle.SavedStateHandle
import at.uac.android.core.LocalCallableProtocol
import at.uac.android.feature.applinks.*
import at.uac.android.feature.browse.BrowseNavigation
import at.uac.android.feature.directory.*
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*

@OptIn(ExperimentalCoroutinesApi::class)
class DirectoryRecentTest {
    @Before fun setup() = Dispatchers.setMain(StandardTestDispatcher())
    @After fun teardown() = Dispatchers.resetMain()
    private fun id(char: Char) = char.toString().repeat(64)
    private fun text(s: String) = mapOf("ukrainian" to s, "german" to s)
    private fun row(id: String = id('a'), section: String? = null, region: String? = null,
        date: String = "2026-10-17T12:00:00.123Z") = mapOf(
        "id" to id, "kind" to if (section == null) "topic" else "section", "categoryID" to "safety",
        "topicID" to "emergency", "sectionID" to section, "federalState" to region,
        "publishedAt" to date, "revision" to 2, "title" to text("Title"),
        "topicTitle" to text("Topic"), "categoryTitle" to text("Category"))
    private fun page(rows: List<Map<String, Any?>>, cursor: DirectoryRecentCursor? = null) =
        mapOf("items" to rows, "nextCursor" to cursor?.wire(), "hasMore" to (cursor != null))
    private fun fails(block: () -> Unit) { assertTrue(runCatching(block).isFailure) }

    @Test fun callableIsPublicReadContractAndCursorPreservesNanoseconds() {
        val cursor = DirectoryRecentCursor(1792238400, 123456789, id('a'))
        assertEquals(cursor, DirectoryRecentContract.cursor(cursor.wire()))
        assertTrue(LocalCallableProtocol.endpoint(DirectoryRecentContract.callable).contains("/europe-west3/"))
        assertFalse(LocalCallableProtocol.nonIdempotent(DirectoryRecentContract.callable))
        val request = LocalCallableProtocol.request(DirectoryRecentContract.callable,
            mapOf("limit" to 20, "cursor" to cursor.wire()))
        val body = request["data"] as Map<*, *>
        assertEquals(20, body["limit"])
        assertEquals(cursor.id, (body["cursor"] as Map<*, *>)["id"])
    }
    @Test fun topicsGlobalAndRegionalSectionsShareOneServerOrderedList() {
        val decoded = DirectoryRecentContract.decode(page(listOf(row(id('c')), row(id('b'), "choose"),
            row(id('a'), "regional-protection", "wien"))), null)
        assertEquals(listOf(id('c'), id('b'), id('a')), decoded.items.map { it.id })
        assertEquals("directory/safety/emergency", decoded.items[0].destination)
        assertEquals("directory/safety/emergency?section=choose", decoded.items[1].destination)
        assertEquals("directory/safety/emergency?section=regional-protection&region=wien", decoded.items[2].destination)
    }
    @Test fun millisecondsInItemsDoNotCorruptNanosecondCursorOrReorderServerTies() {
        val last = DirectoryRecentCursor(Instant.parse("2026-10-17T12:00:00Z").epochSecond, 123456789, id('b'))
        val decoded = DirectoryRecentContract.decode(page(listOf(row(id('a')), row(id('b'))), last), null)
        assertEquals(listOf(id('a'), id('b')), decoded.items.map { it.id })
        assertEquals(last, decoded.nextCursor)
        val older = last.copy(nanoseconds = 123400000, id = id('c'))
        assertTrue(DirectoryRecentContract.older(older, last))
        assertEquals(1, DirectoryRecentContract.decode(page(listOf(row(id('c')))), last).items.size)
    }
    @Test fun malformedPayloadAndCursorCannotBecomeNavigationOrInventDates() {
        listOf(mapOf("kind" to "private"), mapOf("publishedAt" to ""), mapOf("revision" to 1.5),
            mapOf("categoryID" to "../profile"), mapOf("categoryID" to "manage"), mapOf("title" to text("")), mapOf("id" to "profile/users"),
            mapOf("kind" to "topic", "sectionID" to "choose"), mapOf("federalState" to "all"))
            .forEach { bad -> fails { DirectoryRecentContract.decode(page(listOf(row() + bad)), null) } }
        fails { DirectoryRecentContract.decode(page(listOf(row(), row())), null) }
        fails { DirectoryRecentContract.decode(page(listOf(row(date = "2026-10-16T12:00:00Z"), row())), null) }
        fails { DirectoryRecentContract.decode(mapOf("items" to emptyList<Any>(), "hasMore" to true), null) }
        fails { DirectoryRecentContract.cursor(mapOf("seconds" to 1, "nanoseconds" to 1e9, "id" to id('a'))) }
        val cursor = DirectoryRecentCursor(1, 0, id('a'))
        fails { DirectoryRecentContract.decode(page(emptyList(), cursor), cursor) }
    }
    @Test fun linksArePublicCanonicalRestorableAndCannotReachEditorOrInjectQueries() {
        val path = "directory/safety/emergency?section=regional-protection&region=wien"
        listOf("directory/recent", path).forEach { route ->
            val link = "ukrainiancommunity://$route"
            assertEquals(route, AppLinkContract.parse(link)?.route)
            assertEquals(AppLinkAccess.PUBLIC, AppLinkContract.parse(link)?.access)
            assertEquals(route, BrowseNavigation.restore().navigate(route).route)
            val saved = SavedStateHandle()
            assertTrue(AppLinkNavigationViewModel(saved).offer(link))
            assertEquals(route, AppLinkNavigationViewModel(saved).pending.value?.destination?.route)
        }
        listOf("directory/manage", "directory/manage/custom-topic", "directory/recent?section=a",
            "directory/safety/emergency?route=profile/users", "directory/safety/emergency?section=a&section=b",
            "directory/safety/emergency?region=unknown", "directory/safety/emergency?section=%2e%2e",
            "directory/safety/emergency#private", "directory//safety/emergency", "directory/safety/emergency/extra")
            .forEach { assertNull(it, AppLinkContract.parse("ukrainiancommunity://$it")) }
        assertNull(AppLinkContract.parse("ukrainiancommunity://news/a?section=choose"))
    }
    @Test fun emptyLoadingErrorRetryAndPaginationDoNotDropTheFirstPage() = runTest {
        val first = DirectoryRecentContract.decode(page(listOf(row(id('c'))),
            DirectoryRecentCursor(Instant.parse("2026-10-17T12:00:00.123Z").epochSecond, 123000000, id('c'))), null)
        var calls = 0
        val received = mutableListOf<DirectoryRecentCursor?>()
        val model = DirectoryRecentViewModel { after ->
            received += after
            calls++
            if (calls == 2) error("offline")
            if (after == null) first else DirectoryRecentContract.decode(page(listOf(row(id('b')))), after)
        }
        model.ensureLoaded()
        model.ensureLoaded()
        assertTrue(model.state.value.loading)
        advanceUntilIdle()
        assertEquals(1, calls)
        model.more(); advanceUntilIdle()
        assertTrue(model.state.value.failed)
        assertEquals(listOf(id('c')), model.state.value.items.map { it.id })
        model.retry(); advanceUntilIdle()
        assertEquals(first.nextCursor, received.last())
        assertEquals(listOf(id('c'), id('b')), model.state.value.items.map { it.id })
        assertFalse(model.state.value.hasMore)
        model.refresh(); advanceUntilIdle()
        assertNull(received.last())
        assertEquals(1, model.state.value.items.size)
        val empty = DirectoryRecentViewModel { DirectoryRecentPage(emptyList(), null, false) }
        empty.ensureLoaded(); advanceUntilIdle()
        assertTrue(empty.state.value.loaded)
        assertFalse(empty.state.value.failed)
        assertTrue(empty.state.value.items.isEmpty())
    }
    @Test fun currentVisibilityRejectsHiddenDeletedAndMissingAnchors() {
        val text = DirectoryText("UK", "DE")
        val section = DirectorySection("block", 0, false, text, text, null, null, emptyList())
        val topic = DirectoryTopic("topic", "group", 0, false, text, text, listOf(section), emptyList(),
            mapOf("wien" to listOf(section.copy(id = "regional"))))
        val category = DirectoryCategory("custom-guide", "life", 0, false, text, text,
            listOf(DirectoryGroup("group", 0, false, text)), listOf(topic), "{}")
        val target = DirectoryRoute("custom-guide", "topic", "regional", "wien")
        assertTrue(directoryTargetAvailable(listOf(category), target))
        assertFalse(directoryTargetAvailable(emptyList(), target))
        assertFalse(directoryTargetAvailable(listOf(category.copy(hidden = true)), target))
        assertFalse(directoryTargetAvailable(listOf(category.copy(groups = category.groups.map { it.copy(hidden = true) })), target))
        assertFalse(directoryTargetAvailable(listOf(category.copy(topics = listOf(topic.copy(hidden = true)))), target))
        assertFalse(directoryTargetAvailable(listOf(category.copy(topics = listOf(topic.copy(regionalSections =
            mapOf("wien" to listOf(section.copy(id = "regional", hidden = true))))))), target))
        assertFalse(directoryTargetAvailable(listOf(category), target.copy(region = "tirol")))
        assertFalse(directoryTargetAvailable(listOf(category), target.copy(region = null)))
        assertTrue(directoryTargetAvailable(listOf(category), target.copy(section = "block", region = null)))
    }
    @Test fun scanPageWithOnlyHiddenEntriesCanContinueWithoutFalseEndOrLoop() = runTest {
        var calls = 0
        val cursor = DirectoryRecentCursor(1, 0, id('c'))
        val model = DirectoryRecentViewModel {
            calls++
            if (calls == 1) DirectoryRecentPage(emptyList(), cursor, true)
            else DirectoryRecentPage(emptyList(), null, false)
        }
        model.ensureLoaded(); advanceUntilIdle()
        assertTrue(model.state.value.hasMore)
        model.more(); advanceUntilIdle()
        assertEquals(2, calls)
        assertFalse(model.state.value.hasMore)
    }
}
