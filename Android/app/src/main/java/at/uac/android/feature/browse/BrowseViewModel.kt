package at.uac.android.feature.browse

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import at.uac.android.BuildConfig
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class NavigationAccount(val uid: String?, val resolving: Boolean = false)

data class BrowseData(
    val loading: Boolean = true,
    val error: ReadFailure? = null,
    val items: List<Content> = emptyList(),
    val detail: Content? = null,
    val next: ContentCursor? = null,
    val hasMore: Boolean = false,
    val pastItems: List<Content> = emptyList(),
    val pastNext: ContentCursor? = null,
    val pastHasMore: Boolean = false,
    val pastLoading: Boolean = false,
    val pastError: ReadFailure? = null,
    val invalid: Int = 0,
    val cachedAt: Instant? = null,
    val banners: List<Banner> = emptyList(),
    val donation: Donation? = null,
    val photos: List<RawDocument> = emptyList(),
    val profiles: List<RawDocument> = emptyList(),
    val related: List<Content> = emptyList(),
    val warnings: List<Pair<String, ReadFailure>> = emptyList(),
)

data class BrowseState(
    val route: String = "home",
    val language: String = "de",
    val region: String = "",
    val mode: String = "synthetic",
    val theme: String = "system",
    val search: String = "",
    val category: String = "",
    val audience: String = "",
    val past: Boolean = false,
    val eventPeriod: EventPeriod = EventPeriod.ALL,
    val eventAge: EventAge = EventAge.ANY,
    val eventScope: EventScope = EventScope.ALL,
    val organizationScope: OrganizationScope = OrganizationScope.ALL,
    val newsPeriod: NewsPeriod = NewsPeriod.ALL,
    val newsOrder: NewsOrder = NewsOrder.NEWEST,
    val newsSource: NewsSource = NewsSource.ALL,
    val accountAvailable: Boolean = false,
    val customStart: LocalDate? = null,
    val customEnd: LocalDate? = null,
    val data: BrowseData = BrowseData(),
    val canBack: Boolean = false,
    val selectedTab: PrimaryTab = PrimaryTab.HOME,
    val navigationEpoch: Long = 0,
    /** Memory-only destination visit, independent of route text and refresh/recomposition. */
    val entryRevision: Long = 0,
    val retainedRoutes: Set<String> = setOf("home"),
    val deletionCompleted: Boolean = false,
) {
    val kind
        get() =
            if (route == "home") ContentKind.NEWS else ContentKind.entries.find {
                it.collection == route.substringBefore('/').substringBefore(':')
            }

    val detailId
        get() = route.substringAfter('/', "")

    val organizationId
        get() = if ('/' !in route) route.substringAfter(':', "") else ""

    val isList
        get() = kind != null && detailId.isEmpty()

    // Navigation validates the complete grammar; every accepted profile destination is private.
    val isAccountRoute
        get() = route == "profile" || route.startsWith("profile/")
}

class BrowseViewModel(
    private val synthetic: ContentRepository,
    private val emulator: ContentRepository,
    private val saved: SavedStateHandle,
    initialLanguage: String,
    initialRegion: String,
    initialTheme: String,
    private val savePreference: (String, String) -> Unit,
    private val newsPersonalScope: NewsPersonalScopeSource = NewsPersonalScopeSource { source ->
        if (source == NewsSource.ALL) NewsPersonalScope()
        else throw ReadException(ReadFailure.DENIED)
    },
    private val organizationPersonalScope: OrganizationPersonalScopeSource = OrganizationPersonalScopeSource { scope ->
        if (scope == OrganizationScope.ALL) emptySet()
        else throw ReadException(ReadFailure.DENIED)
    },
    private val eventPersonalScope: EventPersonalScopeSource = EventPersonalScopeSource { scope ->
        if (scope == EventScope.ALL) emptySet()
        else throw ReadException(ReadFailure.DENIED)
    },
) : ViewModel() {
    private val availableModes =
        if (BuildConfig.USE_LOCAL_BACKEND) setOf("synthetic", "emulator") else setOf("emulator")

    private fun savedString(key: String): String? = saved.get<Any?>(key) as? String

    private fun savedRoutes(key: String): List<String> {
        val value = saved.get<Any?>(key) ?: return emptyList()
        val list = value as? List<*> ?: return listOf("\u0000")
        return if (list.all { it is String }) list.filterIsInstance<String>() else listOf("\u0000")
    }

    private fun language(value: String?) = value?.takeIf { it in setOf("de", "uk") } ?: "de"

    private fun theme(value: String?) =
        value?.takeIf { it in setOf("system", "light", "dark") } ?: "system"

    private fun region(value: String?) =
        value?.takeIf { selected -> selected.isEmpty() || regions.any { it.first == selected } }
            ?: ""

    private var navigation =
        BrowseNavigation.restore(
            savedString("selected-tab"),
            PrimaryTab.entries
                .filter { "tab-routes:${it.route}" in saved.keys() }
                .associateWith { savedRoutes("tab-routes:${it.route}") },
            savedRoutes("routes"),
        )
    private val mutable =
        MutableStateFlow(
            BrowseState(
                route = navigation.route,
                language = language(savedString("language") ?: initialLanguage),
                region = region(savedString("region") ?: initialRegion),
                theme = theme(savedString("theme") ?: initialTheme),
                mode =
                    savedString("mode")?.takeIf { it in availableModes }
                        ?: if (BuildConfig.USE_LOCAL_BACKEND) "synthetic" else "emulator",
                canBack = navigation.canBack,
                selectedTab = navigation.selected,
                retainedRoutes = navigation.stacks.values.flatten().toSet(),
            )
        )
    val state = mutable.asStateFlow()
    private var job: Job? = null
    private var pastJob: Job? = null
    private var generation = 0
    private var accountObserver: Job? = null
    private var accountBound = false
    private var accountHash: String? =
        savedString("navigation-account")?.takeIf { it.matches(Regex("[a-f0-9]{64}")) }
    private var deletionAccountHash: String? = null
    private var hostPaused = false
    private var profileRegionAccount: String? = null
    private var profileRegionBound = false
    private var manuallySelectedPublicRegion = false
    private var pendingProfileRegion: Pair<String, String?>? = null

    /** The profile seeds public browsing until the user explicitly chooses a public filter. */
    fun synchronizeProfileRegion(uid: String?, profileRegion: String?) {
        // Guests keep their own durable public preference; no unresolved profile can clear it.
        if (uid == null) return
        val hash = identityHash(uid)
        pendingProfileRegion = uid to profileRegion
        if (!accountBound || hash != accountHash) return
        pendingProfileRegion = null
        if (!profileRegionBound || profileRegionAccount != hash) {
            profileRegionBound = true
            profileRegionAccount = hash
            manuallySelectedPublicRegion = false
        }
        if (uid != null && profileRegion == null || manuallySelectedPublicRegion) return
        val selected = region(profileRegion)
        if (selected == mutable.value.region) return
        saved["region"] = selected
        savePreference("region", selected)
        mutable.value = mutable.value.copy(region = selected)
        load(reset = true)
    }

    private fun repository() = if (mutable.value.mode == "synthetic") synthetic else emulator

    private fun key(s: BrowseState = mutable.value): String {
        val legacy =
            "${s.mode}|${s.language}|${s.region}|${s.route}|${s.search}|${s.category}|${s.audience}|${s.past}"
        return if (
            s.eventPeriod == EventPeriod.ALL && s.eventAge == EventAge.ANY &&
                s.eventScope == EventScope.ALL &&
                s.organizationScope == OrganizationScope.ALL &&
                s.newsPeriod == NewsPeriod.ALL &&
                s.newsOrder == NewsOrder.NEWEST &&
                s.newsSource == NewsSource.ALL &&
                s.customStart == null &&
                s.customEnd == null
        )
            legacy
        else {
            val newsKey = "$legacy|${s.newsPeriod}|${s.newsOrder}|${s.newsSource}|${s.customStart}|${s.customEnd}"
            if (s.eventPeriod == EventPeriod.ALL && s.eventAge == EventAge.ANY &&
                s.eventScope == EventScope.ALL &&
                s.organizationScope == OrganizationScope.ALL) newsKey
            else "$newsKey|${s.eventPeriod}|${s.eventAge}|${s.eventScope}|${s.organizationScope}"
        }
    }

    init {
        saved["language"] = mutable.value.language
        saved["region"] = mutable.value.region
        saved["theme"] = mutable.value.theme
        saved["mode"] = mutable.value.mode
        restoreFilters()
        trimRouteState()
        load()
    }

    fun observeAccounts(accounts: Flow<NavigationAccount>) {
        accountObserver?.cancel()
        accountObserver =
            viewModelScope.launch(Dispatchers.Main.immediate, start = CoroutineStart.UNDISPATCHED) {
                accounts.collect(::bindAccount)
            }
    }

    /**
     * A same-UID token refresh keeps navigation. A true identity change cannot inherit private
     * routes.
     */
    fun bindAccount(account: NavigationAccount) {
        if (account.resolving && account.uid == null) return
        val nextHash = account.uid?.let(::identityHash)
        if (accountBound && nextHash == accountHash) {
            mutable.value = mutable.value.copy(accountAvailable = nextHash != null)
            pendingProfileRegion?.takeIf { identityHash(it.first) == nextHash }?.let {
                synchronizeProfileRegion(it.first, it.second)
            }
            return
        }
        if (nextHash != accountHash) {
            profileRegionBound = false
            profileRegionAccount = null
            manuallySelectedPublicRegion = false
        }
        val changed = nextHash != accountHash || !accountBound && accountHash == null
        val restoringGuest = !accountBound && nextHash == null && accountHash == null
        accountBound = true
        if (changed) {
            saved
                .keys()
                .filter { it.startsWith("news-source:") || it.startsWith("organization-scope:") || it.startsWith("event-scope:") }
                .forEach { key ->
                    saved[key] = when {
                        key.startsWith("news-source:") -> NewsSource.ALL.name
                        key.startsWith("event-scope:") -> EventScope.ALL.name
                        else -> OrganizationScope.ALL.name
                    }
                }
            val keepReceipt =
                nextHash == null &&
                    deletionAccountHash != null &&
                    deletionAccountHash == accountHash
            val showingReceipt = navigation.route == "profile/deleted"
            if (!keepReceipt) deletionAccountHash = null
            navigation =
                navigation.scrubPrivateDestinations(restoreGuestAuthentication = restoringGuest)
            if (keepReceipt && showingReceipt)
                navigation = navigation.navigate("profile/deleted", replace = true)
            mutable.value =
                mutable.value.copy(
                    navigationEpoch = mutable.value.navigationEpoch + 1,
                    deletionCompleted = deletionAccountHash != null,
                    newsSource = NewsSource.ALL,
                    eventScope = EventScope.ALL,
                    organizationScope = OrganizationScope.ALL,
                    accountAvailable = nextHash != null,
                )
        } else {
            mutable.value = mutable.value.copy(accountAvailable = nextHash != null)
        }
        accountHash = nextHash
        saved["navigation-account"] = nextHash
        if (changed) move()
        pendingProfileRegion?.takeIf { identityHash(it.first) == nextHash }?.let {
            synchronizeProfileRegion(it.first, it.second)
        }
    }

    /**
     * Called only by the real deletion receipt callback, never reconstructed from a route string.
     */
    fun showDeletionCompletion(uid: String) {
        val hash = identityHash(uid)
        if (!accountBound || accountHash != null && accountHash != hash) return
        deletionAccountHash = hash
        mutable.value = mutable.value.copy(deletionCompleted = true)
        navigate("profile/deleted", true)
    }

    fun deletionCompletionVisible(uid: String?): Boolean =
        mutable.value.deletionCompleted &&
            deletionAccountHash?.let { uid == null || it == identityHash(uid) } == true

    private fun identityHash(uid: String) =
        MessageDigest.getInstance("SHA-256")
            .digest(("uac-navigation:" + uid).toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    private fun restoreFilters() {
        val s = mutable.value
        mutable.value =
            s.copy(
                search = savedString("search:${s.route}").orEmpty().take(160),
                category =
                    savedString("category:${s.route}")
                        .orEmpty()
                        .takeIf { value ->
                            value.isEmpty() || s.kind?.let { value in categories(it) } == true
                        }
                        .orEmpty(),
                audience =
                    savedString("audience:${s.route}")
                        .orEmpty()
                        .takeIf {
                            it in
                                setOf(
                                    "",
                                    "everyone",
                                    "families",
                                    "children",
                                    "teens",
                                    "adults",
                                    "seniors",
                                )
                        }
                        .orEmpty(),
                past = saved.get<Any?>("past:${s.route}") as? Boolean ?: false,
                eventPeriod = savedString("event-period:${s.route}")?.let {
                    runCatching { EventPeriod.valueOf(it) }.getOrNull()
                } ?: EventPeriod.ALL,
                eventAge = savedString("event-age:${s.route}")?.let {
                    runCatching { EventAge.valueOf(it) }.getOrNull()
                } ?: EventAge.ANY,
                eventScope = savedString("event-scope:${s.route}")?.let {
                    runCatching { EventScope.valueOf(it) }.getOrNull()
                } ?: EventScope.ALL,
                organizationScope = savedString("organization-scope:${s.route}")?.let {
                    runCatching { OrganizationScope.valueOf(it) }.getOrNull()
                } ?: OrganizationScope.ALL,
                newsPeriod =
                    savedString("news-period:${s.route}")?.let {
                        runCatching { NewsPeriod.valueOf(it) }.getOrNull()
                    } ?: NewsPeriod.ALL,
                newsOrder =
                    savedString("news-order:${s.route}")?.let {
                        runCatching { NewsOrder.valueOf(it) }.getOrNull()
                    } ?: NewsOrder.NEWEST,
                newsSource =
                    savedString("news-source:${s.route}")?.let {
                        runCatching { NewsSource.valueOf(it) }.getOrNull()
                    } ?: NewsSource.ALL,
                customStart = savedString("news-start:${s.route}")?.let(::safeLocalDate),
                customEnd = savedString("news-end:${s.route}")?.let(::safeLocalDate),
            )
    }

    fun navigate(route: String, tab: Boolean = false) {
        val next = navigation.navigate(route, replace = tab)
        if (next == navigation) return
        if (route != "profile/deleted") {
            deletionAccountHash = null
            mutable.value = mutable.value.copy(deletionCompleted = false)
        }
        navigation = next
        move()
    }

    fun selectTab(tab: PrimaryTab) {
        val next = navigation.select(tab)
        if (next == navigation) return
        navigation = next
        move()
    }

    fun back() {
        if (!navigation.canBack) return
        navigation = navigation.back()
        move()
    }

    /**
     * Personal lists were read from Firestore; never reopen a same-ID embedded example as their
     * target.
     */
    fun openPersonalContent(content: Content) {
        preference("mode", "emulator")
        navigate("${content.kind.collection}/${content.id}")
    }

    private fun move() {
        job?.cancel()
        pastJob?.cancel()
        generation++
        saved["selected-tab"] = navigation.selected.route
        navigation.stacks.forEach { (tab, stack) ->
            saved["tab-routes:${tab.route}"] = ArrayList(stack)
        }
        saved["routes"] = ArrayList(navigation.stack)
        mutable.value =
            mutable.value.copy(
                route = navigation.route,
                canBack = navigation.canBack,
                selectedTab = navigation.selected,
                retainedRoutes = navigation.stacks.values.flatten().toSet(),
                entryRevision = mutable.value.entryRevision + 1,
            )
        trimRouteState()
        restoreFilters()
        // Revalidate on every destination entry; never resurrect a denied/deleted detail from UI
        // memory.
        load()
    }

    private fun trimRouteState() {
        val live = navigation.stacks.values.flatten().toSet()
        val prefixes =
            listOf(
                "search:",
                "category:",
                "audience:",
                "past:",
                "event-period:",
                "event-age:",
                "event-scope:",
                "organization-scope:",
                "news-period:",
                "news-order:",
                "news-source:",
                "news-start:",
                "news-end:",
            )
        saved.keys().toList().forEach { key ->
            val prefix = prefixes.firstOrNull(key::startsWith)
            if (prefix != null) {
                val route = key.removePrefix(prefix)
                if (route !in live) saved.remove<Any?>(key)
                else
                    when (prefix) {
                        "search:" -> saved[key] = savedString(key).orEmpty().take(160)
                        "category:" -> {
                            val kind =
                                if (route == "home") ContentKind.NEWS else ContentKind.entries.firstOrNull {
                                    it.collection == route.substringBefore('/').substringBefore(':')
                                }
                            saved[key] =
                                savedString(key)
                                    .orEmpty()
                                    .takeIf { value ->
                                        value.isEmpty() ||
                                            kind?.let { value in categories(it) } == true
                                    }
                                    .orEmpty()
                        }
                        "audience:" ->
                            saved[key] =
                                savedString(key)
                                    .orEmpty()
                                    .takeIf {
                                        it in
                                            setOf(
                                                "",
                                                "everyone",
                                                "families",
                                                "children",
                                                "teens",
                                                "adults",
                                                "seniors",
                                            )
                                    }
                                    .orEmpty()
                        "past:" -> saved[key] = saved.get<Any?>(key) as? Boolean ?: false
                        "event-period:" -> saved[key] = savedString(key)?.takeIf {
                            runCatching { EventPeriod.valueOf(it) }.isSuccess
                        } ?: EventPeriod.ALL.name
                        "event-age:" -> saved[key] = savedString(key)?.takeIf {
                            runCatching { EventAge.valueOf(it) }.isSuccess
                        } ?: EventAge.ANY.name
                        "event-scope:" -> saved[key] = savedString(key)?.takeIf {
                            runCatching { EventScope.valueOf(it) }.isSuccess
                        } ?: EventScope.ALL.name
                        "organization-scope:" -> saved[key] = savedString(key)?.takeIf {
                            runCatching { OrganizationScope.valueOf(it) }.isSuccess
                        } ?: OrganizationScope.ALL.name
                        "news-period:" ->
                            saved[key] =
                                savedString(key)?.takeIf {
                                    runCatching { NewsPeriod.valueOf(it) }.isSuccess
                                } ?: NewsPeriod.ALL.name
                        "news-order:" ->
                            saved[key] =
                                savedString(key)?.takeIf {
                                    runCatching { NewsOrder.valueOf(it) }.isSuccess
                                } ?: NewsOrder.NEWEST.name
                        "news-source:" ->
                            saved[key] =
                                savedString(key)?.takeIf {
                                    runCatching { NewsSource.valueOf(it) }.isSuccess
                                } ?: NewsSource.ALL.name
                        "news-start:",
                        "news-end:" ->
                            saved[key] = savedString(key)?.let(::safeLocalDate)?.toString()
                    }
            }
        }
        val queries =
            (savedRoutes("query-keys").takeIf { it.isNotEmpty() }
                    ?: saved
                        .keys()
                .filter { it.startsWith("now:") || it.startsWith("pages:") || it.startsWith("past-pages:") }
                        .map { it.substringAfter(':') }
                        .distinct())
                .filter { it.length <= 2_300 && it.none(Char::isISOControl) }
                .takeLast(24)
        saved
            .keys()
            .filter { it.startsWith("now:") || it.startsWith("pages:") || it.startsWith("past-pages:") }
            .forEach { key ->
                if (key.substringAfter(':') !in queries) saved.remove<Any?>(key)
            }
        saved["query-keys"] = ArrayList(queries)
    }

    private fun retainQuery(key: String) {
        val queries = (savedRoutes("query-keys").filterNot { it == key } + key).takeLast(24)
        saved["query-keys"] = ArrayList(queries)
        saved
            .keys()
            .filter { it.startsWith("now:") || it.startsWith("pages:") || it.startsWith("past-pages:") }
            .forEach { savedKey ->
                if (savedKey.substringAfter(':') !in queries) saved.remove<Any?>(savedKey)
            }
    }

    fun preference(name: String, value: String) {
        require(
            when (name) {
                "language" -> value in listOf("de", "uk")
                "theme" -> value in listOf("system", "light", "dark")
                "mode" -> value in availableModes
                "region" -> value.isEmpty() || regions.any { it.first == value }
                else -> false
            }
        )
        if (name == "region") manuallySelectedPublicRegion = true
        saved[name] = value
        if (name != "mode") savePreference(name, value)
        mutable.value =
            when (name) {
                "language" -> mutable.value.copy(language = value)
                "theme" -> mutable.value.copy(theme = value)
                "region" -> mutable.value.copy(region = value)
                else -> mutable.value.copy(mode = value)
            }
        if (name != "theme") load(reset = true)
    }

    fun filters(
        search: String = mutable.value.search,
        category: String = mutable.value.category,
        audience: String = mutable.value.audience,
        past: Boolean = mutable.value.past,
        eventPeriod: EventPeriod = mutable.value.eventPeriod,
        eventAge: EventAge = mutable.value.eventAge,
        eventScope: EventScope = mutable.value.eventScope,
        organizationScope: OrganizationScope = mutable.value.organizationScope,
        newsPeriod: NewsPeriod = mutable.value.newsPeriod,
        newsOrder: NewsOrder = mutable.value.newsOrder,
        newsSource: NewsSource = mutable.value.newsSource,
        customStart: LocalDate? = mutable.value.customStart,
        customEnd: LocalDate? = mutable.value.customEnd,
    ) {
        val s = mutable.value
        val boundedSearch = search.take(160)
        val privateFeed = newsSource != NewsSource.ALL ||
            eventScope != EventScope.ALL || organizationScope != OrganizationScope.ALL
        if (privateFeed) saved["mode"] = "emulator"
        saved["search:${s.route}"] = boundedSearch
        saved["category:${s.route}"] = category
        saved["audience:${s.route}"] = audience
        saved["past:${s.route}"] = past
        saved["event-period:${s.route}"] = eventPeriod.name
        saved["event-age:${s.route}"] = eventAge.name
        saved["event-scope:${s.route}"] = eventScope.name
        saved["organization-scope:${s.route}"] = organizationScope.name
        saved["news-period:${s.route}"] = newsPeriod.name
        saved["news-order:${s.route}"] = newsOrder.name
        saved["news-source:${s.route}"] = newsSource.name
        saved["news-start:${s.route}"] = customStart?.toString()
        saved["news-end:${s.route}"] = customEnd?.toString()
        mutable.value =
            s.copy(
                mode = if (privateFeed) "emulator" else s.mode,
                search = boundedSearch,
                category = category,
                audience = audience,
                past = past,
                eventPeriod = eventPeriod,
                eventAge = eventAge,
                eventScope = eventScope,
                organizationScope = organizationScope,
                newsPeriod = newsPeriod,
                newsOrder = newsOrder,
                newsSource = newsSource,
                customStart = customStart,
                customEnd = customEnd,
            )
        load(reset = true, debounce = boundedSearch != s.search)
    }

    fun refresh() = load(reset = true)

    fun more() {
        if (!mutable.value.data.loading && mutable.value.data.hasMore) load(append = true)
    }

    fun morePast() {
        val s = mutable.value
        if (s.kind != ContentKind.EVENTS || s.past || !s.data.pastHasMore ||
            s.data.pastLoading || s.data.pastNext == null) return
        pastJob?.cancel()
        val ticket = generation
        val currentKey = key(s)
        val now = savedString("now:$currentKey")?.let {
            runCatching { Instant.parse(it) }.getOrNull()
        } ?: Instant.now()
        mutable.value = s.copy(data = s.data.copy(pastLoading = true, pastError = null))
        pastJob = viewModelScope.launch {
            try {
                val ids = eventPersonalScope.load(s.eventScope)
                val page = repository().page(
                    ContentQuery(
                        ContentKind.EVENTS, s.region, s.search, s.category, s.language,
                        past = true, now = now, audience = s.audience,
                        eventAge = s.eventAge, eventScope = s.eventScope,
                        allowedEventIds = ids,
                    ),
                    s.data.pastNext,
                )
                if (ticket != generation || key() != currentKey) return@launch
                val current = mutable.value
                mutable.value = current.copy(data = current.data.copy(
                    pastItems = (current.data.pastItems + page.value.items).distinctBy(Content::id),
                    pastNext = page.value.next,
                    pastHasMore = page.value.hasMore,
                    pastLoading = false,
                    pastError = null,
                    cachedAt = listOfNotNull(current.data.cachedAt, page.cachedAt).minOrNull(),
                ))
                saved["past-pages:$currentKey"] =
                    (saved.get<Any?>("past-pages:$currentKey") as? Int ?: 1).coerceIn(1, 100) + 1
            } catch (error: CancellationException) {
                throw error
            } catch (error: ReadException) {
                if (ticket == generation && key() == currentKey) {
                    val current = mutable.value
                    mutable.value = current.copy(data = current.data.copy(
                        pastLoading = false, pastError = error.reason,
                    ))
                }
            }
        }
    }

    /** A background detail is not a fresh permission/content receipt when the user returns. */
    fun onHostPause() {
        if (hostPaused) return
        hostPaused = true
        val current = mutable.value
        if (!current.isAccountRoute && current.route != "settings" &&
            !current.route.startsWith("directory/")) {
            job?.cancel()
            pastJob?.cancel()
            generation++
            mutable.value = current.copy(data = BrowseData())
        }
    }

    /** Keep each private editor's lifecycle and unsent draft with its own ViewModel. */
    fun onHostResume() {
        if (!hostPaused) return
        hostPaused = false
        if (!mutable.value.isAccountRoute && mutable.value.route != "settings" &&
            !mutable.value.route.startsWith("directory/")) load()
    }

    private fun load(append: Boolean = false, reset: Boolean = false, debounce: Boolean = false) {
        job?.cancel()
        pastJob?.cancel()
        val ticket = ++generation
        val s = mutable.value
        if (s.route == "settings" || s.isAccountRoute || s.route.startsWith("directory/")) {
            mutable.value = s.copy(data = BrowseData(loading = false))
            return
        }
        val currentKey = key(s)
        retainQuery(currentKey)
        if (reset) {
            saved["pages:$currentKey"] = 1
            saved["past-pages:$currentKey"] = 1
            saved["now:$currentKey"] = Instant.now().toString()
        }
        val now =
            savedString("now:$currentKey")?.let { runCatching { Instant.parse(it) }.getOrNull() }
                ?: Instant.now().also {
                    saved["now:$currentKey"] = it.toString()
                }
        val repository = repository()
        mutable.value =
            s.copy(data = if (append) s.data.copy(loading = true, error = null) else BrowseData())
        job = viewModelScope.launch {
            if (debounce) delay(250)
            var result = if (append) s.data.copy(loading = false, error = null) else BrowseData(loading = false)
            suspend fun <T> optional(
                label: String,
                missingIsEmpty: Boolean = false,
                request: suspend () -> ReadResult<T>,
            ): T? =
                try {
                    val read = request()
                    result =
                        result.copy(
                            cachedAt = listOfNotNull(result.cachedAt, read.cachedAt).minOrNull()
                        )
                    read.value
                } catch (e: ReadException) {
                    if (!(missingIsEmpty && e.reason == ReadFailure.MISSING))
                        result = result.copy(warnings = result.warnings + (label to e.reason))
                    null
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    result = result.copy(warnings = result.warnings + (label to ReadFailure.UNKNOWN))
                    null
                }
            try {
                if (s.detailId.isNotEmpty() && s.kind != null) {
                    val detail = repository.detail(s.kind!!, s.detailId)
                    val content = detail.value
                    result = result.copy(detail = content, cachedAt = detail.cachedAt)
                    if (content.kind == ContentKind.ORGANIZATIONS) {
                        val photos = optional("photos") { repository.photos(content.id) }.orEmpty()
                        result = result.copy(photos = photos)
                        val ids =
                            (listOf(content.fields.string("ownerId")) +
                                    content.fields.strings("adminIds") +
                                    content.fields.strings("moderatorIds"))
                                .filter(String::isNotBlank)
                                .distinct()
                        val profiles = ids.mapNotNull { id ->
                            optional("team") { repository.profile(id) }?.firstOrNull()
                        }
                        result = result.copy(profiles = profiles)
                    } else {
                        val related =
                            optional("recommendations") {
                                repository.page(
                                    ContentQuery(
                                        content.kind,
                                        category = content.category,
                                        language = s.language,
                                        now = now,
                                        recommendations = true,
                                    ),
                                    size = 6,
                                )
                            }
                        result =
                            result.copy(
                                related =
                                    related?.items.orEmpty().filter { it.id != content.id }.take(3)
                            )
                    }
                } else if (s.kind != null) {
                    val personalScope =
                        if (s.kind == ContentKind.NEWS) newsPersonalScope.load(s.newsSource)
                        else NewsPersonalScope()
                    val organizationIds =
                        if (s.kind == ContentKind.ORGANIZATIONS)
                            organizationPersonalScope.load(s.organizationScope)
                        else personalScope.organizationIds
                    val eventIds =
                        if (s.kind == ContentKind.EVENTS) eventPersonalScope.load(s.eventScope)
                        else emptySet()
                    val query =
                        ContentQuery(
                            s.kind!!,
                            s.region,
                            s.search,
                            s.category,
                            s.language,
                            s.past,
                            s.organizationId,
                            now,
                            s.audience,
                            eventPeriod = s.eventPeriod,
                            eventAge = s.eventAge,
                            eventScope = s.eventScope,
                            organizationScope = s.organizationScope,
                            newsPeriod = s.newsPeriod,
                            newsOrder = s.newsOrder,
                            newsSource = s.newsSource,
                            customStart = s.customStart,
                            customEnd = s.customEnd,
                            allowedNewsIds = personalScope.newsIds,
                            allowedEventIds = eventIds,
                            allowedOrganizationIds = organizationIds,
                        )
                    var page = repository.page(query, if (append) s.data.next else null)
                    var items = if (append) s.data.items + page.value.items else page.value.items
                    var invalid = (if (append) s.data.invalid else 0) + page.value.invalidCount
                    var cachedAt =
                        listOfNotNull(if (append) s.data.cachedAt else null, page.cachedAt)
                            .minOrNull()
                    val pageCount =
                        (saved.get<Any?>("pages:$currentKey") as? Int ?: 1).coerceIn(1, 100)
                    if (!append)
                        repeat((pageCount - 1).coerceIn(0, 99)) {
                            if (page.value.hasMore) {
                                page = repository.page(query, page.value.next)
                                items = items + page.value.items
                                invalid += page.value.invalidCount
                                cachedAt = listOfNotNull(cachedAt, page.cachedAt).minOrNull()
                            }
                        }
                    result =
                        result.copy(
                            items = items.distinctBy { it.id },
                            next = page.value.next,
                            hasMore = page.value.hasMore,
                            invalid = invalid,
                            cachedAt = cachedAt,
                        )
                    if (append) saved["pages:$currentKey"] = pageCount + 1
                    if (s.kind == ContentKind.EVENTS && !s.past &&
                        s.organizationId.isEmpty() && !append) {
                        try {
                            val pastQuery = query.copy(past = true, eventPeriod = EventPeriod.ALL)
                            var pastPage = repository.page(pastQuery)
                            var pastItems = pastPage.value.items
                            val pastPageCount =
                                (saved.get<Any?>("past-pages:$currentKey") as? Int ?: 1)
                                    .coerceIn(1, 100)
                            repeat((pastPageCount - 1).coerceIn(0, 99)) {
                                if (pastPage.value.hasMore) {
                                    pastPage = repository.page(pastQuery, pastPage.value.next)
                                    pastItems = pastItems + pastPage.value.items
                                }
                            }
                            result = result.copy(
                                pastItems = pastItems.distinctBy(Content::id),
                                pastNext = pastPage.value.next,
                                pastHasMore = pastPage.value.hasMore,
                                cachedAt = listOfNotNull(result.cachedAt, pastPage.cachedAt).minOrNull(),
                            )
                        } catch (error: ReadException) {
                            result = result.copy(pastError = error.reason)
                        }
                    }
                    if (s.route == "home") {
                        // The first tab is the full news feed; retain its optional support card.
                        val donation = optional("donation", missingIsEmpty = true) {
                            repository.donation()
                        }
                        result = result.copy(donation = donation)
                    }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: ReadException) {
                result =
                    if (append && e.reason == ReadFailure.OFFLINE)
                        s.data.copy(loading = false, error = e.reason)
                    else BrowseData(loading = false, error = e.reason)
            } catch (_: Exception) {
                result = BrowseData(loading = false, error = ReadFailure.UNKNOWN)
            }
            // A feed failure must not suppress the independently readable banner carousel.
            if (s.detailId.isEmpty() && s.route.substringBefore(':') in bannerSections) {
                val banners = optional("banners") {
                    repository.banners(s.route.substringBefore(':'), s.region, includeScheduled = true)
                }
                result = result.copy(banners = banners.orEmpty())
            }
            if (ticket == generation) {
                mutable.value = mutable.value.copy(data = result)
            }
        }
    }

    private fun safeLocalDate(value: String): LocalDate? = runCatching {
        LocalDate.parse(value)
    }
        .getOrNull()
}
