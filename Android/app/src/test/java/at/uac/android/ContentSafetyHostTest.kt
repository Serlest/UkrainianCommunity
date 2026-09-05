package at.uac.android

import at.uac.android.feature.browse.Banner
import at.uac.android.feature.browse.BrowseData
import at.uac.android.feature.browse.BrowseState
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentCursor
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.personal.PersonalListPage
import at.uac.android.feature.personal.PersonalState
import at.uac.android.feature.safety.SafetyAccess
import at.uac.android.feature.safety.SafetyVisibility
import java.time.Instant
import org.junit.Assert.*
import org.junit.Test

class ContentSafetyHostTest {
    private val time = Instant.parse("2026-09-03T00:00:00Z")
    private val hidden = Content(ContentKind.NEWS, "hidden", mapOf("authorId" to "blocked-author"))
    private val visible = Content(ContentKind.NEWS, "visible", mapOf("authorId" to "other"))
    private val policy = SafetyVisibility(blockedUserIds = setOf("blocked-author"))

    @Test
    fun everyContentSurfaceUsesTheSamePolicyWithoutDestroyingSourceOrCursor() {
        val cursor = ContentCursor(time, hidden.id)
        val source =
            BrowseState(
                data =
                    BrowseData(
                        items = listOf(hidden, visible),
                        detail = hidden,
                        related = listOf(hidden, visible),
                        next = cursor,
                        hasMore = true,
                        profiles =
                            listOf(
                                RawDocument("blocked-author", emptyMap()),
                                RawDocument("other", emptyMap()),
                            ),
                    )
            )
        val rendered = source.visibleTo(policy)
        assertEquals(listOf(visible), rendered.data.items)
        assertNull(rendered.data.detail)
        assertEquals(listOf(visible), rendered.data.related)
        assertEquals(listOf("other"), rendered.data.profiles.map { it.id })
        assertEquals(cursor, rendered.data.next)
        assertTrue(rendered.data.hasMore)
        assertEquals(2, source.data.items.size)
        assertEquals(hidden, source.data.detail)
        assertEquals(source, source.visibleTo(SafetyVisibility()))
    }

    @Test
    fun unknownAuthenticatedPolicyNeverRendersAnEmptyBlockListAsPermission() {
        val source =
            BrowseState(
                data =
                    BrowseData(items = listOf(visible), detail = visible, related = listOf(visible))
            )
        for (access in SafetyAccess.entries) {
            val rendered = source.visibleTo(SafetyVisibility(loaded = false, access = access))
            assertTrue(rendered.data.items.isEmpty())
            assertNull(rendered.data.detail)
            assertTrue(rendered.data.related.isEmpty())
        }
    }

    @Test
    fun blockedOrganizationDoesNotHideOtherOrganizationsOfItsOwner() {
        val a = Content(ContentKind.ORGANIZATIONS, "a", mapOf("ownerId" to "same-owner"))
        val b = a.copy(id = "b")
        val linked = visible.copy(fields = mapOf("organizationId" to "a"))
        val source = BrowseState(data = BrowseData(items = listOf(a, b, linked)))
        assertEquals(
            listOf(b),
            source.visibleTo(SafetyVisibility(blockedOrganizationIds = setOf("a"))).data.items,
        )
    }

    @Test
    fun personalProjectionPreservesMarkersAndPaginationForUnblockRestoration() {
        val page = PersonalListPage(listOf(hidden, visible), "cursor", true, 2)
        val source = PersonalState(saved = mapOf(ContentKind.NEWS to page), subscriptions = page)
        val rendered = source.visibleTo(policy)
        assertEquals(listOf(visible), rendered.saved.getValue(ContentKind.NEWS).items)
        assertEquals(3, rendered.subscriptions!!.unavailable)
        assertEquals("cursor", rendered.subscriptions.next)
        assertTrue(rendered.subscriptions.hasMore)
        assertEquals(2, source.subscriptions!!.items.size)
        assertEquals(source, source.visibleTo(SafetyVisibility()))
    }

    @Test
    fun bannerIsNotMistakenlyFilteredByItsEditorsIdentity() {
        // Build65 leaves banner copy in place and checks the resolved destination instead.
        val banner =
            Banner(
                "banner",
                mapOf("createdBy" to "blocked-author", "actionTargetID" to "unrelated-target"),
            )
        val source = BrowseState(data = BrowseData(banners = listOf(banner)))
        assertEquals(listOf(banner), source.visibleTo(policy).data.banners)
    }
}
