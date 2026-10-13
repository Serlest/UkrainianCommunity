package at.uac.android

import androidx.lifecycle.SavedStateHandle
import at.uac.android.feature.applinks.AppLinkAccess
import at.uac.android.feature.applinks.AppLinkAction
import at.uac.android.feature.applinks.AppLinkContract
import at.uac.android.feature.applinks.AppLinkNavigationViewModel
import org.junit.Assert.*
import org.junit.Test

class AppLinkContractTest {
    @Test
    fun acceptsOnlyKnownProductionRoutesAndMarksInboxPrivate() {
        assertEquals(
            "news/article-1",
            AppLinkContract.parse("ukrainiancommunity://news/article-1")?.route,
        )
        assertEquals(
            "events/event_1",
            AppLinkContract.parse("ukrainiancommunity://events/event_1")?.route,
        )
        assertEquals(
            AppLinkAccess.SIGNED_IN,
            AppLinkContract.parse("ukrainiancommunity://inbox")?.access,
        )
    }

    @Test
    fun rejectsUnknownAuthorityTraversalParametersAndInternalRoutes() {
        listOf(
                "https://example.com/news/a",
                "ukrainiancommunity://news:443/a",
                "ukrainiancommunity://user@news/a",
                "ukrainiancommunity://news/a?route=profile/users",
                "ukrainiancommunity://news/a#profile",
                "ukrainiancommunity://news/%2e%2e",
                "ukrainiancommunity://news/a%2Fb",
                "ukrainiancommunity://profile/users",
                "javascript://news/a",
            )
            .forEach { assertNull(it, AppLinkContract.parse(it)) }
    }

    @Test
    fun coldStartRestoresValidatedPendingDestination() {
        val state = SavedStateHandle()
        val first = AppLinkNavigationViewModel(state)
        assertTrue(first.offer("ukrainiancommunity://organizations/org-1"))
        val restored = AppLinkNavigationViewModel(state).pending.value
        assertEquals("organizations/org-1", restored?.destination?.route)
        assertEquals(AppLinkAccess.PUBLIC, restored?.destination?.access)
    }

    @Test
    fun warmStartReplacesPendingAndOldConsumerCannotClearNewIntent() {
        val model = AppLinkNavigationViewModel(SavedStateHandle())
        model.offer("ukrainiancommunity://news/one")
        val old = model.pending.value!!.revision
        model.offer("ukrainiancommunity://events/two")
        model.consume(old)
        assertEquals("events/two", model.pending.value?.destination?.route)
        model.consume(model.pending.value!!.revision)
        assertNull(model.pending.value)
    }

    @Test
    fun duplicateWarmDeliveryIsIdempotent() {
        val model = AppLinkNavigationViewModel(SavedStateHandle())
        val link = "ukrainiancommunity://inbox"
        model.offer(link)
        val first = model.pending.value
        model.offer(link)
        assertEquals(first, model.pending.value)
    }

    @Test
    fun inboxNeverOpensBeforeAuthenticationAndPrivateSurfaceAuthority() {
        val inbox = AppLinkContract.parse("ukrainiancommunity://inbox")!!
        assertEquals(
            AppLinkAction.PROMPT_LOGIN,
            AppLinkContract.resolve(
                    inbox,
                    signedInReady = false,
                    guest = true,
                    privateSurfaceReady = false,
                )
                .action,
        )
        assertEquals(
            AppLinkAction.WAIT,
            AppLinkContract.resolve(
                    inbox,
                    signedInReady = true,
                    guest = false,
                    privateSurfaceReady = false,
                )
                .action,
        )
        assertEquals(
            AppLinkAction.OPEN,
            AppLinkContract.resolve(
                    inbox,
                    signedInReady = true,
                    guest = false,
                    privateSurfaceReady = true,
                )
                .action,
        )
    }
}
