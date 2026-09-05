package at.uac.android.feature.browse

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import java.security.MessageDigest
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
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
            ContentKind.entries.find {
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
) : ViewModel() {
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
                    savedString("mode")?.takeIf { it in setOf("synthetic", "emulator") }
                        ?: "synthetic",
                canBack = navigation.canBack,
                selectedTab = navigation.selected,
                retainedRoutes = navigation.stacks.values.flatten().toSet(),
            )
        )
    val state = mutable.asStateFlow()
    private var job: Job? = null
    private var generation = 0
    private var accountObserver: Job? = null
    private var accountBound = false
    private var accountHash: String? =
        savedString("navigation-account")?.takeIf { it.matches(Regex("[a-f0-9]{64}")) }
    private var deletionAccountHash: String? = null
    private var hostPaused = false

    private fun repository() = if (mutable.value.mode == "synthetic") synthetic else emulator

    private fun key(s: BrowseState = mutable.value) =
        "${s.mode}|${s.language}|${s.region}|${s.route}|${s.search}|${s.category}|${s.audience}|${s.past}"

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
        if (accountBound && nextHash == accountHash) return
        val changed = nextHash != accountHash || !accountBound && accountHash == null
        val restoringGuest = !accountBound && nextHash == null && accountHash == null
        accountBound = true
        if (changed) {
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
                )
        }
        accountHash = nextHash
        saved["navigation-account"] = nextHash
        if (changed) move()
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
        val prefixes = listOf("search:", "category:", "audience:", "past:")
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
                                ContentKind.entries.firstOrNull {
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
                    }
            }
        }
        val queries =
            (savedRoutes("query-keys").takeIf { it.isNotEmpty() }
                    ?: saved
                        .keys()
                        .filter { it.startsWith("now:") || it.startsWith("pages:") }
                        .map { it.substringAfter(':') }
                        .distinct())
                .filter { it.length <= 2_300 && it.none(Char::isISOControl) }
                .takeLast(24)
        saved
            .keys()
            .filter { it.startsWith("now:") || it.startsWith("pages:") }
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
            .filter { it.startsWith("now:") || it.startsWith("pages:") }
            .forEach { savedKey ->
                if (savedKey.substringAfter(':') !in queries) saved.remove<Any?>(savedKey)
            }
    }

    fun preference(name: String, value: String) {
        require(
            when (name) {
                "language" -> value in listOf("de", "uk")
                "theme" -> value in listOf("system", "light", "dark")
                "mode" -> value in listOf("synthetic", "emulator")
                "region" -> value.isEmpty() || regions.any { it.first == value }
                else -> false
            }
        )
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
    ) {
        val s = mutable.value
        val boundedSearch = search.take(160)
        saved["search:${s.route}"] = boundedSearch
        saved["category:${s.route}"] = category
        saved["audience:${s.route}"] = audience
        saved["past:${s.route}"] = past
        mutable.value =
            s.copy(search = boundedSearch, category = category, audience = audience, past = past)
        load(reset = true, debounce = boundedSearch != s.search)
    }

    fun refresh() = load(reset = true)

    fun more() {
        if (!mutable.value.data.loading && mutable.value.data.hasMore) load(append = true)
    }

    /** A background detail is not a fresh permission/content receipt when the user returns. */
    fun onHostPause() {
        if (hostPaused) return
        hostPaused = true
        val current = mutable.value
        if (!current.isAccountRoute && current.route != "settings") {
            job?.cancel()
            generation++
            mutable.value = current.copy(data = BrowseData())
        }
    }

    /** Keep each private editor's lifecycle and unsent draft with its own ViewModel. */
    fun onHostResume() {
        if (!hostPaused) return
        hostPaused = false
        if (!mutable.value.isAccountRoute && mutable.value.route != "settings") load()
    }

    private fun load(append: Boolean = false, reset: Boolean = false, debounce: Boolean = false) {
        job?.cancel()
        val ticket = ++generation
        val s = mutable.value
        if (s.route == "settings" || s.isAccountRoute) {
            mutable.value = s.copy(data = BrowseData(loading = false))
            return
        }
        val currentKey = key(s)
        retainQuery(currentKey)
        if (reset) {
            saved["pages:$currentKey"] = 1
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
            var result = BrowseData(loading = false)
            suspend fun <T> optional(label: String, request: suspend () -> ReadResult<T>): T? =
                try {
                    val read = request()
                    result =
                        result.copy(
                            cachedAt = listOfNotNull(result.cachedAt, read.cachedAt).minOrNull()
                        )
                    read.value
                } catch (e: ReadException) {
                    result = result.copy(warnings = result.warnings + (label to e.reason))
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
                } else {
                    val items = coroutineScope {
                        ContentKind.entries
                            .map { kind ->
                                async {
                                    optional(kind.collection) {
                                            repository.page(
                                                ContentQuery(
                                                    kind,
                                                    s.region,
                                                    language = s.language,
                                                    now = now,
                                                ),
                                                size = 3,
                                            )
                                        }
                                        ?.items
                                        .orEmpty()
                                }
                            }
                            .awaitAll()
                            .flatten()
                    }
                    result =
                        result.copy(
                            items =
                                items
                                    .distinctBy { "${it.kind}/${it.id}" }
                                    .sortedWith(
                                        compareByDescending<Content> { it.publishedAt }
                                            .thenBy { it.id }
                                    )
                        )
                    val donation = optional("donation") { repository.donation() }
                    result = result.copy(donation = donation)
                }
                if (
                    s.detailId.isEmpty() &&
                        s.route.substringBefore(':') in listOf("home", "events", "organizations")
                ) {
                    val banners =
                        optional("banners") {
                            repository.banners(s.route.substringBefore(':'), s.region)
                        }
                    result = result.copy(banners = banners.orEmpty())
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
            if (ticket == generation) {
                mutable.value = mutable.value.copy(data = result)
            }
        }
    }
}
