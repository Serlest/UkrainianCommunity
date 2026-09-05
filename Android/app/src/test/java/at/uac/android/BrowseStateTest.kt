package at.uac.android

import androidx.lifecycle.SavedStateHandle
import at.uac.android.feature.browse.*
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class BrowseStateTest {
    @Before
    fun setup() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @After
    fun finish() {
        Dispatchers.resetMain()
    }

    private val now = Instant.parse("2026-09-02T10:00:00Z")

    private fun data() =
        (1..18).associate { index ->
            val id = "synthetic-${index.toString().padStart(2, '0')}"
            "news/$id" to
                RawDocument(
                    id,
                    mapOf(
                        "title" to id,
                        "body" to "body",
                        "summary" to "Summary",
                        "createdAt" to now,
                        "updatedAt" to now,
                        "publishedAt" to now,
                        "moderationStatus" to "approved",
                        "sourceType" to "organization",
                        "regionScope" to "austria",
                        "category" to "education",
                    ),
                )
        }

    private fun model(
        saved: SavedStateHandle = SavedStateHandle(),
        source: ContentSource = SyntheticContentSource(data()),
        save: (String, String) -> Unit = { _, _ -> },
    ): BrowseViewModel {
        val repo = ContentRepository(source, MemoryContentCache())
        return BrowseViewModel(repo, repo, saved, "de", "", "system", save)
    }

    @Test
    fun backRestoresFiltersAndLoadedPages() = runTest {
        val vm = model()
        vm.navigate("news", true)
        advanceUntilIdle()
        vm.more()
        advanceUntilIdle()
        assertEquals(12, vm.state.value.data.items.size)
        vm.navigate("news/synthetic-07")
        advanceUntilIdle()
        assertNotNull(vm.state.value.data.detail)
        vm.back()
        advanceUntilIdle()
        assertEquals(12, vm.state.value.data.items.size)
        vm.filters(search = "synthetic-01")
        advanceUntilIdle()
        vm.navigate("news/synthetic-01")
        advanceUntilIdle()
        vm.back()
        advanceUntilIdle()
        assertEquals("synthetic-01", vm.state.value.search)
        assertEquals(1, vm.state.value.data.items.size)
    }

    @Test
    fun savedHandleRestoresRouteAndParentPaginationInNewModel() = runTest {
        val saved = SavedStateHandle()
        val first = model(saved)
        first.navigate("news", true)
        advanceUntilIdle()
        first.more()
        advanceUntilIdle()
        first.navigate("news/synthetic-07")
        advanceUntilIdle()
        val copied = SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) })
        val recreated = model(copied)
        advanceUntilIdle()
        assertEquals("news/synthetic-07", recreated.state.value.route)
        recreated.back()
        advanceUntilIdle()
        assertEquals(12, recreated.state.value.data.items.size)
    }

    @Test
    fun localeAndThemePersistWithoutLosingDestination() = runTest {
        val values = mutableMapOf<String, String>()
        val vm = model(save = { key, value -> values[key] = value })
        vm.navigate("news", true)
        advanceUntilIdle()
        vm.navigate("settings")
        vm.preference("language", "uk")
        vm.preference("theme", "dark")
        vm.back()
        advanceUntilIdle()
        assertEquals("news", vm.state.value.route)
        assertEquals("uk", vm.state.value.language)
        assertEquals(mapOf("language" to "uk", "theme" to "dark"), values)
    }

    @Test
    fun rapidSearchCancelsStaleResponse() = runTest {
        val delegate = SyntheticContentSource(data())
        val source =
            object : ContentSource by delegate {
                override suspend fun page(
                    query: ContentQuery,
                    after: ContentCursor?,
                    limit: Int,
                ): List<RawDocument> {
                    delay(if (query.search == "old") 4000 else 100)
                    return delegate.page(query, after, limit)
                }
            }
        val vm = model(source = source)
        vm.navigate("news", true)
        advanceUntilIdle()
        vm.filters(search = "old")
        advanceTimeBy(300)
        runCurrent()
        vm.filters(search = "synthetic-01")
        advanceUntilIdle()
        assertEquals(listOf("synthetic-01"), vm.state.value.data.items.map { it.id })
        assertNull(vm.state.value.data.error)
    }

    @Test
    fun backRevalidatesRevokedDetailInsteadOfUiCache() = runTest {
        val delegate = SyntheticContentSource(data())
        var denied = false
        val source =
            object : ContentSource by delegate {
                override suspend fun document(path: String): RawDocument {
                    if (denied) throw ReadException(ReadFailure.DENIED)
                    return delegate.document(path)
                }
            }
        val vm = model(source = source)
        vm.navigate("news/synthetic-01")
        advanceUntilIdle()
        vm.navigate("settings")
        denied = true
        vm.back()
        advanceUntilIdle()
        assertEquals(ReadFailure.DENIED, vm.state.value.data.error)
        assertNull(vm.state.value.data.detail)
    }

    @Test
    fun doubleMoreDoesNotDuplicatePages() = runTest {
        val vm = model()
        vm.navigate("news", true)
        advanceUntilIdle()
        vm.more()
        vm.more()
        advanceUntilIdle()
        assertEquals(12, vm.state.value.data.items.size)
        assertEquals(12, vm.state.value.data.items.map { it.id }.distinct().size)
    }

    @Test
    fun visitIdentityChangesOnDestinationEntryButNotOnRefreshOrReconstruction() = runTest {
        val saved = SavedStateHandle()
        val vm = model(saved)
        vm.navigate("news/synthetic-01")
        advanceUntilIdle()
        val firstVisit = vm.state.value.entryRevision
        assertTrue(firstVisit > 0)
        vm.navigate("news/synthetic-01")
        vm.onHostPause()
        vm.onHostResume()
        advanceUntilIdle()
        vm.preference("theme", "dark")
        advanceUntilIdle()
        assertEquals(firstVisit, vm.state.value.entryRevision)
        vm.navigate("profile/recent")
        advanceUntilIdle()
        vm.back()
        advanceUntilIdle()
        assertEquals("news/synthetic-01", vm.state.value.route)
        assertTrue(vm.state.value.entryRevision > firstVisit)
        val recreated = model(SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) }))
        advanceUntilIdle()
        assertEquals("news/synthetic-01", recreated.state.value.route)
        assertEquals(0L, recreated.state.value.entryRevision)
    }

    @Test
    fun foregroundReturnRevalidatesAndNeverShowsARevokedOldDetail() = runTest {
        val delegate = SyntheticContentSource(data())
        var denied = false
        var reads = 0
        val source =
            object : ContentSource by delegate {
                override suspend fun document(path: String): RawDocument {
                    if (path.startsWith("news/")) {
                        reads++
                        if (denied) throw ReadException(ReadFailure.DENIED)
                    }
                    return delegate.document(path)
                }
            }
        val vm = model(source = source)
        vm.navigate("news/synthetic-01")
        advanceUntilIdle()
        assertNotNull(vm.state.value.data.detail)
        val initialReads = reads
        vm.onHostResume()
        advanceUntilIdle()
        assertEquals(initialReads, reads)
        vm.onHostPause()
        assertNull(vm.state.value.data.detail)
        denied = true
        vm.onHostResume()
        advanceUntilIdle()
        assertEquals(initialReads + 1, reads)
        assertEquals(ReadFailure.DENIED, vm.state.value.data.error)
        assertNull(vm.state.value.data.detail)
        vm.onHostResume()
        advanceUntilIdle()
        assertEquals(initialReads + 1, reads)
    }

    @Test
    fun foregroundRevalidationPreservesListFiltersAndLoadedPageDepth() = runTest {
        val vm = model()
        vm.navigate("news")
        advanceUntilIdle()
        vm.filters(search = "synthetic")
        advanceUntilIdle()
        vm.more()
        advanceUntilIdle()
        assertEquals(12, vm.state.value.data.items.size)
        vm.onHostPause()
        vm.onHostPause()
        assertTrue(vm.state.value.data.items.isEmpty())
        vm.onHostResume()
        advanceUntilIdle()
        assertEquals("news", vm.state.value.route)
        assertEquals("synthetic", vm.state.value.search)
        assertEquals(12, vm.state.value.data.items.size)
    }

    @Test
    fun foregroundOfPrivateEditorDoesNotReloadPublicDataOrChangeNavigation() = runTest {
        var reads = 0
        val delegate = SyntheticContentSource(data())
        val source =
            object : ContentSource by delegate {
                override suspend fun page(
                    query: ContentQuery,
                    after: ContentCursor?,
                    limit: Int,
                ): List<RawDocument> {
                    reads++
                    return delegate.page(query, after, limit)
                }
            }
        val vm = model(source = source)
        vm.navigate("profile/edit")
        advanceUntilIdle()
        val before = vm.state.value
        val readCount = reads
        vm.onHostPause()
        vm.onHostResume()
        advanceUntilIdle()
        assertEquals(before, vm.state.value)
        assertEquals(readCount, reads)
    }

    @Test
    fun nonCancellableOldDetailCannotReappearAfterBackgroundInvalidation() = runTest {
        val delegate = SyntheticContentSource(data())
        val source =
            object : ContentSource by delegate {
                override suspend fun document(path: String): RawDocument =
                    kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) {
                        delay(2_000)
                        delegate.document(path)
                    }
            }
        val vm = model(source = source)
        vm.navigate("news/synthetic-01")
        runCurrent()
        vm.onHostPause()
        advanceUntilIdle()
        assertNull(vm.state.value.data.detail)
        assertTrue(vm.state.value.data.loading)
        vm.onHostResume()
        advanceUntilIdle()
        assertEquals("synthetic-01", vm.state.value.data.detail?.id)
    }

    @Test
    fun accountDestinationsHaveNoPublicFeedAndRestoreBackStack() = runTest {
        val vm = model()
        vm.navigate("news", true)
        advanceUntilIdle()
        vm.filters(search = "synthetic-01")
        advanceUntilIdle()
        vm.navigate("profile")
        vm.navigate("profile/saved")
        advanceUntilIdle()
        assertTrue(vm.state.value.isAccountRoute)
        assertTrue(vm.state.value.data.items.isEmpty())
        assertFalse(vm.state.value.data.loading)
        vm.back()
        assertEquals("profile", vm.state.value.route)
        vm.back()
        advanceUntilIdle()
        assertEquals("news", vm.state.value.route)
        assertEquals("synthetic-01", vm.state.value.search)
    }

    @Test
    fun personalTargetsAlwaysOpenOnTheirActualFirestoreSource() = runTest {
        val vm = model()
        vm.navigate("profile/saved")
        advanceUntilIdle()
        val item = decodeContent(ContentKind.NEWS, data().getValue("news/synthetic-01"))
        vm.openPersonalContent(item)
        advanceUntilIdle()
        assertEquals("emulator", vm.state.value.mode)
        assertEquals("news/synthetic-01", vm.state.value.route)
        vm.back()
        advanceUntilIdle()
        assertEquals("profile/saved", vm.state.value.route)
        assertFalse(vm.state.value.data.loading)
    }

    @Test
    fun tabSwitchRestoresFiltersPagesAndPerTabDestinationAfterProcessReconstruction() = runTest {
        val saved = SavedStateHandle()
        val first = model(saved)
        first.navigate("news")
        advanceUntilIdle()
        first.more()
        advanceUntilIdle()
        first.navigate("news/synthetic-07")
        advanceUntilIdle()
        first.selectTab(PrimaryTab.PROFILE)
        first.navigate("profile/saved")
        advanceUntilIdle()
        val copied = SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) })
        val restored = model(copied)
        advanceUntilIdle()
        assertEquals("profile/saved", restored.state.value.route)
        assertEquals(PrimaryTab.PROFILE, restored.state.value.selectedTab)
        restored.selectTab(PrimaryTab.HOME)
        advanceUntilIdle()
        assertEquals("news/synthetic-07", restored.state.value.route)
        restored.back()
        advanceUntilIdle()
        assertEquals(12, restored.state.value.data.items.size)
        restored.selectTab(PrimaryTab.PROFILE)
        advanceUntilIdle()
        assertEquals("profile/saved", restored.state.value.route)
        restored.selectTab(PrimaryTab.PROFILE)
        advanceUntilIdle()
        assertEquals("profile", restored.state.value.route)
        assertFalse(restored.state.value.canBack)
    }

    @Test
    fun returningToTabRevalidatesRevokedDetailInsteadOfShowingOldContent() = runTest {
        val delegate = SyntheticContentSource(data())
        var denied = false
        val source =
            object : ContentSource by delegate {
                override suspend fun document(path: String): RawDocument {
                    if (denied) throw ReadException(ReadFailure.DENIED)
                    return delegate.document(path)
                }
            }
        val vm = model(source = source)
        vm.navigate("news/synthetic-01")
        advanceUntilIdle()
        vm.selectTab(PrimaryTab.PROFILE)
        advanceUntilIdle()
        denied = true
        vm.selectTab(PrimaryTab.HOME)
        assertNull(vm.state.value.data.detail)
        advanceUntilIdle()
        assertEquals(ReadFailure.DENIED, vm.state.value.data.error)
        assertNull(vm.state.value.data.detail)
    }

    @Test
    fun trueAccountChangeScrubsPrivateHistoryInEveryTabButSameUidRefreshKeepsIt() = runTest {
        val saved = SavedStateHandle()
        val vm = model(saved)
        vm.bindAccount(NavigationAccount("account-a"))
        vm.navigate("news")
        vm.navigate("profile/feedback/request-a")
        vm.selectTab(PrimaryTab.EVENTS)
        vm.navigate("profile/delete")
        vm.selectTab(PrimaryTab.PROFILE)
        vm.navigate("profile/edit")
        advanceUntilIdle()
        val epoch = vm.state.value.navigationEpoch
        vm.bindAccount(NavigationAccount("account-a", resolving = true))
        assertEquals("profile/edit", vm.state.value.route)
        assertEquals(epoch, vm.state.value.navigationEpoch)
        vm.bindAccount(NavigationAccount("account-b"))
        advanceUntilIdle()
        assertEquals("profile", vm.state.value.route)
        assertTrue(vm.state.value.navigationEpoch > epoch)
        vm.selectTab(PrimaryTab.HOME)
        advanceUntilIdle()
        assertEquals("news", vm.state.value.route)
        vm.selectTab(PrimaryTab.EVENTS)
        advanceUntilIdle()
        assertEquals("events", vm.state.value.route)
        assertFalse(
            saved
                .keys()
                .filter { it.startsWith("tab-routes:") }
                .flatMap {
                    saved.get<ArrayList<String>>(it).orEmpty()
                }
                .any { it.startsWith("profile/") }
        )
        assertFalse(saved.get<String>("navigation-account").orEmpty().contains("account-b"))
    }

    @Test
    fun coldSameAccountRetainsPrivateDestinationButGuestAndForeignAccountDoNot() = runTest {
        val saved = SavedStateHandle()
        val first = model(saved)
        first.bindAccount(NavigationAccount("account-a"))
        first.selectTab(PrimaryTab.PROFILE)
        first.navigate("profile/feedback/request-a")
        advanceUntilIdle()
        fun restored() = model(SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) }))
        val same = restored()
        same.bindAccount(NavigationAccount(null, resolving = true))
        same.bindAccount(NavigationAccount("account-a"))
        advanceUntilIdle()
        assertEquals("profile/feedback/request-a", same.state.value.route)
        val guest = restored()
        guest.bindAccount(NavigationAccount(null))
        advanceUntilIdle()
        assertEquals("profile", guest.state.value.route)
        val different = restored()
        different.bindAccount(NavigationAccount("account-b"))
        advanceUntilIdle()
        assertEquals("profile", different.state.value.route)
    }

    @Test
    fun restoredGuestKeepsOnlyItsAuthenticationDestination() = runTest {
        for (page in listOf("login", "register", "reset")) {
            val saved = SavedStateHandle()
            val first = model(saved)
            first.bindAccount(NavigationAccount(null))
            first.selectTab(PrimaryTab.PROFILE)
            first.navigate("profile/$page")
            advanceUntilIdle()
            val restored =
                model(SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) }))
            restored.bindAccount(NavigationAccount(null))
            advanceUntilIdle()
            assertEquals("profile/$page", restored.state.value.route)
            restored.back()
            advanceUntilIdle()
            assertEquals("profile", restored.state.value.route)
        }
    }

    @Test
    fun guestAuthenticationCannotRestoreAFormerPrivateHistorySuffix() = runTest {
        val saved =
            SavedStateHandle(
                mapOf(
                    "selected-tab" to "profile",
                    "tab-routes:profile" to arrayListOf("profile", "profile/edit", "profile/login"),
                )
            )
        val restored = model(saved)
        restored.bindAccount(NavigationAccount(null))
        advanceUntilIdle()
        assertEquals("profile", restored.state.value.route)
        assertFalse(restored.state.value.retainedRoutes.any { it.startsWith("profile/") })
    }

    @Test
    fun realIdentityChangeAlwaysClosesGuestAuthentication() = runTest {
        val vm = model()
        vm.bindAccount(NavigationAccount(null))
        vm.selectTab(PrimaryTab.PROFILE)
        vm.navigate("profile/login")
        advanceUntilIdle()
        vm.bindAccount(NavigationAccount("account-a"))
        advanceUntilIdle()
        assertEquals("profile", vm.state.value.route)
        vm.navigate("profile/register")
        vm.bindAccount(NavigationAccount(null))
        advanceUntilIdle()
        assertEquals("profile", vm.state.value.route)
    }

    @Test
    fun deletionCompletionRequiresLiveReceiptAndCannotSurviveNewAccountOrProcess() = runTest {
        val saved = SavedStateHandle()
        val vm = model(saved)
        vm.bindAccount(NavigationAccount("account-a"))
        vm.navigate("profile/deleted", true)
        advanceUntilIdle()
        assertFalse(vm.deletionCompletionVisible("account-a"))
        vm.showDeletionCompletion("account-a")
        assertTrue(vm.deletionCompletionVisible("account-a"))
        assertFalse(vm.deletionCompletionVisible("account-b"))
        vm.bindAccount(NavigationAccount(null))
        advanceUntilIdle()
        assertTrue(vm.deletionCompletionVisible(null))
        assertEquals("profile/deleted", vm.state.value.route)
        val cold = model(SavedStateHandle(saved.keys().associateWith { saved.get<Any?>(it) }))
        advanceUntilIdle()
        assertEquals("profile", cold.state.value.route)
        assertFalse(cold.deletionCompletionVisible(null))
        vm.bindAccount(NavigationAccount("account-b"))
        advanceUntilIdle()
        assertFalse(vm.deletionCompletionVisible("account-b"))
        assertEquals("profile", vm.state.value.route)
    }

    @Test
    fun receiptAlsoWorksWhenConfirmedSignOutCompletesBeforeHostCallback() = runTest {
        val vm = model()
        vm.bindAccount(NavigationAccount("account-a"))
        vm.bindAccount(NavigationAccount(null))
        vm.showDeletionCompletion("account-a")
        advanceUntilIdle()
        assertTrue(vm.deletionCompletionVisible(null))
        vm.navigate("profile", true)
        advanceUntilIdle()
        assertFalse(vm.deletionCompletionVisible(null))
    }

    @Test
    fun corruptedPreferencesAndTimestampRestoreSafelyWithoutSelectingEmulator() = runTest {
        val key = "synthetic|de||news||||false"
        val saved =
            SavedStateHandle(
                mapOf(
                    "routes" to arrayListOf("news"),
                    "mode" to "unexpected",
                    "language" to 42,
                    "region" to "unknown",
                    "theme" to "broken",
                    "now:$key" to "not-an-instant",
                    "pages:$key" to "wrong-type",
                    "search:news" to 12,
                    "past:news" to "true",
                )
            )
        val vm = model(saved)
        advanceUntilIdle()
        assertEquals("synthetic", vm.state.value.mode)
        assertEquals("de", vm.state.value.language)
        assertEquals("", vm.state.value.region)
        assertEquals("system", vm.state.value.theme)
        assertEquals("", vm.state.value.search)
        assertFalse(vm.state.value.past)
        assertNull(vm.state.value.data.error)
        assertEquals(6, vm.state.value.data.items.size)
        assertNotNull(Instant.parse(saved.get<String>("now:$key")))
    }

    @Test
    fun searchHistoryAndRemovedRouteStateStayBounded() = runTest {
        val saved = SavedStateHandle()
        val vm = model(saved)
        vm.navigate("news")
        advanceUntilIdle()
        repeat(100) {
            vm.filters(search = "query-$it")
            advanceUntilIdle()
        }
        assertTrue(saved.keys().count { it.startsWith("now:") } <= 24)
        assertTrue(saved.keys().count { it.startsWith("pages:") } <= 24)
        assertTrue(saved.get<ArrayList<String>>("query-keys")!!.size <= 24)
        vm.filters(search = "x".repeat(10_000))
        advanceUntilIdle()
        assertEquals(160, vm.state.value.search.length)
        vm.selectTab(PrimaryTab.HOME)
        advanceUntilIdle()
        assertFalse(saved.keys().contains("search:news"))
    }

    @Test
    fun mixedRouteListAndOversizedInactiveFiltersCannotBypassRestoreBounds() = runTest {
        val oversized = "x".repeat(10_000)
        val saved =
            SavedStateHandle(
                mapOf(
                    "selected-tab" to "profile",
                    "routes" to arrayListOf("news", "news/synthetic-01"),
                    "tab-routes:profile" to arrayListOf("profile"),
                    "tab-routes:events" to arrayListOf("events", 42, "events/example"),
                    "search:events" to oversized,
                    "category:events" to oversized,
                    "query-keys" to arrayListOf(oversized),
                    "now:$oversized" to "invalid",
                    "pages:$oversized" to 1,
                )
            )
        val vm = model(saved)
        advanceUntilIdle()
        assertEquals("profile", vm.state.value.route)
        assertEquals(160, saved.get<String>("search:events")!!.length)
        assertEquals("", saved.get<String>("category:events"))
        assertFalse(saved.keys().any { it.length > 2_310 })
        assertTrue(saved.get<ArrayList<String>>("query-keys")!!.isEmpty())
        vm.selectTab(PrimaryTab.EVENTS)
        advanceUntilIdle()
        assertEquals("events", vm.state.value.route)
        assertFalse(vm.state.value.canBack)
    }
}
