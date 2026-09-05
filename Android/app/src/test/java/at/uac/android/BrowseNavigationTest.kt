package at.uac.android

import at.uac.android.feature.browse.BrowseNavigation
import at.uac.android.feature.browse.PrimaryTab
import org.junit.Assert.*
import org.junit.Test

class BrowseNavigationTest {
    @Test
    fun statementRouteRestoresOnlyPathAndBackKeepsInboxOrigin() {
        val route = "profile/dsa-statement/report-1"
        val nav =
            BrowseNavigation.restore()
                .select(PrimaryTab.PROFILE)
                .navigate("profile/inbox")
                .navigate(route)
        assertEquals(route, nav.route)
        assertEquals("profile/inbox", nav.back().route)
        assertEquals(route, BrowseNavigation.restore(nav.selected.route, nav.stacks).route)
    }

    @Test
    fun statementRouteCannotNormalizeOrEscapeSelectedId() {
        for (route in
            listOf(
                "profile/dsa-statement",
                "profile/dsa-statement/",
                "profile/dsa-statement/../x",
                "profile/dsa-statement/a b",
                "profile/dsa-statement/" + "a".repeat(201),
            )) {
            assertTrue(runCatching { BrowseNavigation.restore().navigate(route) }.isFailure)
        }
    }

    @Test
    fun fourTabsHaveIndependentRootsAndNewsBelongsToHome() {
        val navigation = BrowseNavigation.restore()
        assertEquals(4, navigation.stacks.size)
        assertEquals(PrimaryTab.HOME, PrimaryTab.forRoute("news/example"))
        assertEquals(PrimaryTab.ORGANIZATIONS, PrimaryTab.forRoute("organizations/example"))
        assertFalse(navigation.canBack)
    }

    @Test
    fun switchingTabsRestoresIndependentDetailAndBackReturnsWithinItsTab() {
        val home = BrowseNavigation.restore().navigate("news").navigate("news/example")
        val events = home.select(PrimaryTab.EVENTS).navigate("events/concert")
        val returned = events.select(PrimaryTab.HOME)
        assertEquals("news/example", returned.route)
        assertEquals("news", returned.back().route)
        assertEquals("events/concert", returned.select(PrimaryTab.EVENTS).route)
    }

    @Test
    fun repeatedTabTapResetsOnlyItsOwnStack() {
        val navigation =
            BrowseNavigation.restore()
                .navigate("news/example")
                .select(PrimaryTab.PROFILE)
                .navigate("profile/saved")
        val reset = navigation.select(PrimaryTab.PROFILE)
        assertEquals("profile", reset.route)
        assertFalse(reset.canBack)
        assertEquals("news/example", reset.select(PrimaryTab.HOME).route)
    }

    @Test
    fun crossSectionPersonalTargetKeepsItsOrigin() {
        val navigation =
            BrowseNavigation.restore()
                .select(PrimaryTab.PROFILE)
                .navigate("profile/saved")
                .navigate("events/concert")
        assertEquals(PrimaryTab.PROFILE, navigation.selected)
        assertEquals("profile/saved", navigation.back().route)
    }

    @Test
    fun explicitReplacementMaintainsLegacyRouteContractWithoutClearingOtherTabs() {
        val navigation =
            BrowseNavigation.restore()
                .select(PrimaryTab.EVENTS)
                .navigate("events/concert")
                .navigate("news", replace = true)
        assertEquals("news", navigation.route)
        assertFalse(navigation.canBack)
        assertEquals("events/concert", navigation.select(PrimaryTab.EVENTS).route)
    }

    @Test
    fun legacyAndNewSnapshotsRestoreWithoutRestoringContentData() {
        val legacy = BrowseNavigation.restore(legacy = listOf("news", "news/example"))
        assertEquals(PrimaryTab.HOME, legacy.selected)
        assertEquals("news", legacy.back().route)
        val state = legacy.select(PrimaryTab.PROFILE).navigate("profile/edit")
        assertEquals(state, BrowseNavigation.restore(state.selected.route, state.stacks))
    }

    @Test
    fun invalidEmptyOrOversizedRestoredStateIsBoundedAndSafe() {
        val navigation =
            BrowseNavigation.restore(
                "unknown",
                mapOf(
                    PrimaryTab.HOME to
                        listOf("", "outside", "news/\nexample", "news/" + "x".repeat(2_100)),
                    PrimaryTab.EVENTS to (1..100).map { "events/$it" },
                ),
            )
        assertEquals("home", navigation.route)
        assertEquals(16, navigation.stacks.getValue(PrimaryTab.EVENTS).size)
        assertEquals("events/100", navigation.select(PrimaryTab.EVENTS).route)
    }

    @Test
    fun duplicatePushDoesNotGrowHistory() {
        val navigation = BrowseNavigation.restore().navigate("news/example")
        assertEquals(navigation, navigation.navigate("news/example"))
        assertEquals(navigation.back(), navigation.back().back())
    }

    @Test
    fun currentPublicAndPrivateDestinationsRetainTheirCanonicalRoutes() {
        val routes =
            listOf(
                "home",
                "news",
                "events",
                "organizations",
                "settings",
                "profile",
                "profile/edit",
                "profile/saved",
                "profile/subscriptions",
                "profile/feedback",
                "profile/support",
                "profile/inbox",
                "profile/inbox-settings",
                "profile/legal",
                "profile/blocked",
                "profile/organizations",
                "profile/registrations",
                "profile/recent",
                "profile/history",
                "profile/delete",
                "profile/deleted",
                "news:org-1",
                "events:org-1",
                "news/article_1",
                "events/event-1",
                "organizations/org-1",
                "profile/feedback/request-1",
                "profile/support/request-1",
                "profile/organizations/request-1",
                "profile/organizations/manage/org-1",
                "profile/organizations/author/org-1/news",
                "profile/organizations/author/org_1/events",
            )
        routes.forEach { route ->
            assertEquals(route, BrowseNavigation.restore().navigate(route).route)
        }
    }

    @Test
    fun contentAndFeedbackIdsUseExistingDocumentContractsNotAnAsciiOnlyGuess() {
        listOf(
                "news/новина 1:допис",
                "events/подія.1",
                "profile/feedback/Запит 1",
                "profile/support/request:1",
                "news/" + "я".repeat(750),
            )
            .forEach { route ->
                assertEquals(route, BrowseNavigation.restore().navigate(route).route)
            }
    }

    @Test
    fun privateHistoryRoutesRestoreWithinProfileAndAreScrubbedOnIdentityChange() {
        val navigation =
            BrowseNavigation.restore()
                .select(PrimaryTab.PROFILE)
                .navigate("profile/recent")
                .navigate("news/from-recent")
                .navigate("profile/history")
        val restored = BrowseNavigation.restore(navigation.selected.route, navigation.stacks)
        assertEquals("profile/history", restored.route)
        assertEquals("news/from-recent", restored.back().route)
        assertEquals(listOf("profile"), restored.scrubPrivateDestinations().stack)
    }

    @Test
    fun lifecycleRoutesUseOnlyExactOrganizationNewsAndEventContracts() {
        listOf("news", "events").forEach { kind ->
            val route = "profile/organizations/lifecycle/org-1/$kind/item-1"
            assertEquals(route, BrowseNavigation.restore().navigate(route).route)
        }
        listOf(
                "profile/organizations/lifecycle/org-1/organizations/item-1",
                "profile/organizations/lifecycle/org-1/news",
                "profile/organizations/lifecycle/org-1/news/a/b",
                "profile/organizations/lifecycle/org-1/events/" + "x".repeat(129),
            )
            .forEach { route ->
                assertThrows(IllegalArgumentException::class.java) {
                    BrowseNavigation.restore().navigate(route)
                }
            }
    }

    @Test
    fun galleryManagementUsesAnExactOrganizationRouteAndReturnsToItsPublicOrigin() {
        val navigation =
            BrowseNavigation.restore()
                .select(PrimaryTab.ORGANIZATIONS)
                .navigate("organizations/org-1")
                .navigate("profile/organizations/gallery/org-1")
        assertEquals("profile/organizations/gallery/org-1", navigation.route)
        assertEquals("organizations/org-1", navigation.back().route)
        assertEquals(
            navigation,
            BrowseNavigation.restore(navigation.selected.route, navigation.stacks),
        )
        assertEquals("organizations/org-1", navigation.scrubPrivateDestinations().route)
    }

    @Test
    fun malformedGalleryManagementPathsCannotEnterOrSurviveRestoredHistory() {
        for (route in
            listOf(
                "profile/organizations/gallery/",
                "profile/organizations/gallery/org-1/photo-1",
                "profile/organizations/gallery/..",
                "profile/organizations/gallery/org:1",
                "profile/organizations/gallery/" + "x".repeat(129),
            )) {
            assertThrows(IllegalArgumentException::class.java) {
                BrowseNavigation.restore().navigate(route)
            }
            assertEquals(
                "profile",
                BrowseNavigation.restore(
                        "profile",
                        mapOf(PrimaryTab.PROFILE to listOf("profile", route)),
                    )
                    .route,
            )
        }
    }

    @Test
    fun moderationRoutesArePrivateAndNeverTurnTheRouteIntoAccessAuthority() {
        for (route in
            listOf(
                "profile/moderation",
                "profile/users",
                "profile/organization-review",
                "profile/organization-review/org-1",
            )) {
            val navigation = BrowseNavigation.restore().navigate("news/origin").navigate(route)
            assertEquals(route, navigation.route)
            assertEquals("news/origin", navigation.scrubPrivateDestinations().route)
            assertEquals(
                navigation,
                BrowseNavigation.restore(navigation.selected.route, navigation.stacks),
            )
        }
    }

    @Test
    fun malformedOrganizationReviewRequestsCannotEnterOrRestore() {
        for (route in
            listOf(
                "profile/moderation/item",
                "profile/users/",
                "profile/users/private-target",
                "profile/organization-review/",
                "profile/organization-review/..",
                "profile/organization-review/org:1",
                "profile/organization-review/org-1/extra",
                "profile/organization-review/" + "x".repeat(129),
            )) {
            assertThrows(IllegalArgumentException::class.java) {
                BrowseNavigation.restore().navigate(route)
            }
            assertEquals(
                "profile",
                BrowseNavigation.restore(
                        "profile",
                        mapOf(PrimaryTab.PROFILE to listOf("profile", route)),
                    )
                    .route,
            )
        }
    }

    @Test
    fun malformedRoutesCannotBePushedOrRestoredAsPartialDestinations() {
        val invalid =
            listOf(
                "",
                "outside",
                "home/x",
                "home:org-1",
                "settings/x",
                "settings:profile",
                "profile/x",
                "profile/edit/id",
                "news/",
                "news:",
                "news:org:other",
                "events/a/b",
                "events:org-1/event-1",
                "organizations:org-1",
                "organizations/",
                "organizations/org:1",
                "profile/feedback/",
                "profile/feedback/a/b",
                "profile/support/..",
                "profile/organizations/a/b",
                "profile/organizations/manage/",
                "profile/organizations/manage/org/extra",
                "news/.",
                "events/..",
                "profile/organizations/author/org-1",
                "profile/organizations/author/org-1/organizations",
                "profile/organizations/author/org-1/news/item",
                "profile/organizations/author//news",
                "profile/organizations/author/org:1/events",
                "profile/organizations/author/org-1/NEWS",
                "news/line\nbreak",
                "organizations/" + "x".repeat(129),
                "news/" + "я".repeat(751),
                "profile/feedback/" + "x".repeat(513),
            )
        invalid.forEach { route ->
            assertThrows(
                "Invalid route must not navigate: $route",
                IllegalArgumentException::class.java,
            ) {
                BrowseNavigation.restore().navigate(route)
            }
            val restored =
                BrowseNavigation.restore(
                    "events",
                    mapOf(PrimaryTab.EVENTS to listOf("events", route)),
                )
            assertEquals("events", restored.route)
            assertFalse(restored.canBack)
        }
    }

    @Test
    fun oneMalformedEntryResetsOnlyItsOwnStoredStack() {
        val restored =
            BrowseNavigation.restore(
                "events",
                mapOf(
                    PrimaryTab.HOME to listOf("home", "news/article"),
                    PrimaryTab.EVENTS to listOf("events", "events/a/b", "events/otherwise-valid"),
                    PrimaryTab.PROFILE to listOf("profile", "profile/saved"),
                ),
            )
        assertEquals("events", restored.route)
        assertEquals("news/article", restored.select(PrimaryTab.HOME).route)
        assertEquals("profile/saved", restored.select(PrimaryTab.PROFILE).route)
    }

    @Test
    fun malformedLegacyHistoryResetsToItsKnownTabRoot() {
        val restored =
            BrowseNavigation.restore(legacy = listOf("events", "events/a/b", "events/valid"))
        assertEquals(PrimaryTab.EVENTS, restored.selected)
        assertEquals(listOf("events"), restored.stack)
        val account = BrowseNavigation.restore(legacy = listOf("profile", "profile/unknown"))
        assertEquals(PrimaryTab.PROFILE, account.selected)
        assertEquals(listOf("profile"), account.stack)
        val explicit = BrowseNavigation.restore("organizations", legacy = listOf("outside"))
        assertEquals(listOf("organizations"), explicit.stack)
    }

    @Test
    fun deletionReceiptIsNeverRestoredAsProofInAnyStackOrLegacySnapshot() {
        val live = BrowseNavigation.restore().navigate("profile/deleted", replace = true)
        assertEquals("profile/deleted", live.route)
        val restored = BrowseNavigation.restore(live.selected.route, live.stacks)
        assertEquals("profile", restored.route)
        assertFalse(restored.canBack)
        val crossTab =
            BrowseNavigation.restore(
                "home",
                mapOf(
                    PrimaryTab.HOME to listOf("home", "profile/deleted"),
                    PrimaryTab.EVENTS to listOf("events", "profile/deleted"),
                ),
            )
        assertEquals("profile", crossTab.route)
        assertEquals("profile", crossTab.select(PrimaryTab.EVENTS).route)
        assertTrue(crossTab.stacks.values.flatten().none { it == "profile/deleted" })
        assertEquals("profile", BrowseNavigation.restore(legacy = listOf("profile/deleted")).route)
    }

    @Test
    fun accountScrubCutsPrivateOriginAndEveryFollowingTargetAcrossAllTabs() {
        val initial =
            BrowseNavigation.restore(
                "events",
                mapOf(
                    PrimaryTab.HOME to
                        listOf(
                            "home",
                            "news/article",
                            "profile/feedback/account-a-request",
                            "events/from-private",
                        ),
                    PrimaryTab.EVENTS to
                        listOf(
                            "events",
                            "events/concert",
                            "settings",
                            "organizations/from-settings",
                        ),
                    PrimaryTab.ORGANIZATIONS to
                        listOf("profile/organizations/manage/org-a", "organizations/org-a"),
                    PrimaryTab.PROFILE to listOf("profile", "profile/saved", "news/saved-by-a"),
                ),
            )
        val cleaned = initial.scrubPrivateDestinations()
        assertEquals(PrimaryTab.EVENTS, cleaned.selected)
        assertEquals(listOf("home", "news/article"), cleaned.stacks.getValue(PrimaryTab.HOME))
        assertEquals(listOf("events", "events/concert"), cleaned.stack)
        assertEquals(listOf("organizations"), cleaned.stacks.getValue(PrimaryTab.ORGANIZATIONS))
        assertEquals(listOf("profile"), cleaned.stacks.getValue(PrimaryTab.PROFILE))
    }

    @Test
    fun accountScrubPreservesUnrelatedPublicStacksAndIsIdempotent() {
        val initial =
            BrowseNavigation.restore()
                .navigate("news/article")
                .select(PrimaryTab.EVENTS)
                .navigate("events/concert")
                .select(PrimaryTab.PROFILE)
                .navigate("profile/delete")
        val cleaned = initial.scrubPrivateDestinations()
        assertEquals("profile", cleaned.route)
        assertFalse(cleaned.canBack)
        assertEquals(
            initial.stacks.getValue(PrimaryTab.HOME),
            cleaned.stacks.getValue(PrimaryTab.HOME),
        )
        assertEquals(
            initial.stacks.getValue(PrimaryTab.EVENTS),
            cleaned.stacks.getValue(PrimaryTab.EVENTS),
        )
        assertEquals(cleaned, cleaned.scrubPrivateDestinations())
    }

    @Test
    fun legacyPrivateHistoryIsScrubbedEvenWhenItBelongsToTheHomeTab() {
        val restored =
            BrowseNavigation.restore(
                legacy =
                    listOf(
                        "news",
                        "news/article",
                        "profile",
                        "profile/support/request-a",
                        "events/private-target",
                    )
            )
        val cleaned = restored.scrubPrivateDestinations()
        assertEquals(PrimaryTab.HOME, cleaned.selected)
        assertEquals(listOf("news", "news/article"), cleaned.stack)
        assertTrue(
            cleaned.stacks.values.flatten().none { it.startsWith("profile/") || it == "settings" }
        )
    }

    @Test
    fun liveNavigationAndLegacyRestorationShareTheSixteenRouteCap() {
        val routes = (1..100).map { "events/$it" }
        val live =
            routes.fold(BrowseNavigation.restore().select(PrimaryTab.EVENTS)) { state, route ->
                state.navigate(route)
            }
        assertEquals(16, live.stack.size)
        assertEquals(routes.takeLast(16), live.stack)
        assertEquals(routes.takeLast(16), BrowseNavigation.restore(legacy = routes).stack)
    }

    @Test
    fun authoringDestinationAndItsPublicResultAreRemovedAtAccountChange() {
        val navigation =
            BrowseNavigation.restore()
                .select(PrimaryTab.ORGANIZATIONS)
                .navigate("organizations/org-1")
                .navigate("profile/organizations/author/org-1/events")
                .navigate("events/new-from-private-editor")
        assertEquals(
            listOf("organizations", "organizations/org-1"),
            navigation.scrubPrivateDestinations().stack,
        )
    }

    @Test
    fun attendeeAndCoverDestinationsAreCanonicalPrivateRoutesWithTheirOwnIds() {
        val valid =
            listOf(
                "profile/attendees/event-1",
                "profile/organizations/cover/org-1/news/article-1",
                "profile/organizations/cover/org-1/events/event-1",
            )
        valid.forEach { route ->
            val navigation =
                BrowseNavigation.restore().navigate("events/public-event").navigate(route)
            assertEquals(route, navigation.route)
            assertEquals("events/public-event", navigation.scrubPrivateDestinations().route)
        }
        val invalid =
            listOf(
                "profile/attendees/",
                "profile/attendees/a/b",
                "profile/attendees/..",
                "profile/attendees/" + "x".repeat(513),
                "profile/organizations/cover/org-1/news",
                "profile/organizations/cover/org-1/organizations/article",
                "profile/organizations/cover/org:1/news/article",
                "profile/organizations/cover/org-1/events/..",
                "profile/organizations/cover/org-1/news/a/b",
                "profile/organizations/cover/org-1/news/" + "x".repeat(129),
                "profile/organizations/cover/org-1/news/space id",
            )
        invalid.forEach { route ->
            assertThrows(IllegalArgumentException::class.java) {
                BrowseNavigation.restore().navigate(route)
            }
        }
    }

    @Test
    fun subscriberRouteKeepsItsOrganizationIdentityAndIsScrubbedOnAccountChange() {
        val route = "profile/subscribers/org-1"
        val navigation = BrowseNavigation.restore().navigate("organizations/org-1").navigate(route)
        assertEquals(route, navigation.route)
        assertEquals("organizations/org-1", navigation.scrubPrivateDestinations().route)
        listOf(
                "profile/subscribers/",
                "profile/subscribers/..",
                "profile/subscribers/org-1/extra",
                "profile/subscribers/org:1",
                "profile/subscribers/space id",
                "profile/subscribers/" + "x".repeat(129),
            )
            .forEach { invalid ->
                assertThrows(IllegalArgumentException::class.java) {
                    BrowseNavigation.restore().navigate(invalid)
                }
            }
    }

    @Test
    fun guestAuthenticationDestinationsAreBoundedAndPrivate() {
        for (page in listOf("login", "register", "reset")) {
            val state =
                BrowseNavigation.restore().select(PrimaryTab.PROFILE).navigate("profile/$page")
            assertEquals("profile/$page", state.route)
            assertEquals("profile", state.scrubPrivateDestinations().route)
            assertEquals("profile", state.back().route)
        }
        assertThrows(IllegalArgumentException::class.java) {
            BrowseNavigation.restore().navigate("profile/login/arbitrary")
        }
    }
}
