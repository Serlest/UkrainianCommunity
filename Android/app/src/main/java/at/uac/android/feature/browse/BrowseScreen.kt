package at.uac.android.feature.browse

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import at.uac.android.BuildConfig
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.core.ProtectedDropdownMenu as DropdownMenu
import at.uac.android.design.UacBottomNavigation
import at.uac.android.design.UacDesign
import at.uac.android.design.UacHeader
import at.uac.android.design.UacIcon
import at.uac.android.design.UacPageBackground
import at.uac.android.design.UacSymbol
import at.uac.android.design.UacTheme
import at.uac.android.design.isCompactHeaderRoute
import at.uac.android.feature.bannermeasurement.BannerMeasurement
import at.uac.android.feature.directory.DirectoryDestination
import at.uac.android.feature.directory.DirectoryEditorAccess
import java.net.URI
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

internal fun shouldRevealNewBanner(
    bannersAvailable: Boolean,
    bannersWereAvailable: Boolean,
    hasDetail: Boolean,
    firstVisibleItemIndex: Int,
): Boolean = bannersAvailable && !bannersWereAvailable && !hasDetail && firstVisibleItemIndex <= 1

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BrowseScreen(
    state: BrowseState,
    model: BrowseViewModel,
    diagnostics: () -> Unit,
    accountContent: (@Composable (route: String, language: String) -> Unit)? = null,
    personalActions: (@Composable (Content, BrowseState) -> Unit)? = null,
    visibilityNotice: (@Composable () -> Unit)? = null,
    overlay: (@Composable () -> Unit)? = null,
    publicGallery: (@Composable (Content, BrowseState) -> Unit)? = null,
    navigationRequest: (((() -> Unit)) -> Unit)? = null,
    directoryFeedback: ((String?, String?, String) -> Unit)? = null,
    directoryEditor: DirectoryEditorAccess? = null,
    bannerMeasurementActive: Boolean = false,
    onBannerMeasurement: (BannerMeasurement) -> Unit = {},
) {
    val l = state.language
    val discoveryRoot = state.route in setOf("home", "events", "organizations")
    val directoryRoot = state.route == "directory"
    val cardColumns = if (androidx.compose.ui.platform.LocalConfiguration.current.screenWidthDp >= 700 &&
        androidx.compose.ui.platform.LocalDensity.current.fontScale <= 1.3f) 2 else 1
    var searchVisible by rememberSaveable(state.route) { mutableStateOf(state.search.isNotEmpty()) }
    var directorySearchVisible by rememberSaveable(state.route) { mutableStateOf(false) }
    val backDispatcher =
        androidx.activity.compose.LocalOnBackPressedDispatcherOwner.current?.onBackPressedDispatcher
    LifecycleResumeEffect(model) {
        model.onHostResume()
        onPauseOrDispose { model.onHostPause() }
    }
    val dark = state.theme == "dark" || (state.theme == "system" && isSystemInDarkTheme())
    val window = LocalActivity.current?.window
    SideEffect {
        window?.let {
            WindowCompat.getInsetsController(it, it.decorView).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
    }
    fun requestNavigation(action: () -> Unit) {
        if (navigationRequest != null) navigationRequest(action) else action()
    }
    BackHandler(state.canBack) { requestNavigation(model::back) }
    UacTheme(state.theme) {
        UacPageBackground(
            Modifier.fillMaxSize(),
            plain = state.isAccountRoute || state.route == "settings",
        ) {
            val keyboardVisible =
                WindowInsets.ime.getBottom(androidx.compose.ui.platform.LocalDensity.current) > 0
            Scaffold(
                containerColor = Color.Transparent,
                modifier = Modifier.imePadding(),
                bottomBar = {
                    if (!keyboardVisible)
                        UacBottomNavigation(state.selectedTab, l) { tab ->
                            requestNavigation { model.selectTab(tab) }
                        }
                },
            ) { insets ->
                Column(Modifier.fillMaxSize().padding(insets)) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        UacHeader(
                            l,
                            state.canBack,
                            {
                                if (backDispatcher != null) backDispatcher.onBackPressed()
                                else requestNavigation(model::back)
                            },
                            {
                                if (discoveryRoot) {
                                    if (searchVisible || state.search.isNotEmpty()) {
                                        searchVisible = false
                                        model.filters(search = "")
                                    } else searchVisible = true
                                } else if (directoryRoot) directorySearchVisible = !directorySearchVisible
                                else requestNavigation { model.navigate("settings") }
                            },
                            compact =
                                isCompactHeaderRoute(state.route) ||
                                    keyboardVisible ||
                                    androidx.compose.ui.platform.LocalConfiguration.current
                                        .screenHeightDp < 480,
                            actionIcon = if (discoveryRoot || directoryRoot) UacIcon.SEARCH else UacIcon.SETTINGS,
                            actionTag = if (discoveryRoot || directoryRoot) "header-search-toggle" else "settings",
                        )
                    }
                    if (discoveryRoot && searchVisible)
                        OutlinedTextField(
                            state.search,
                            { model.filters(search = it) },
                            Modifier.widthIn(max = UacDesign.readableWidth)
                                .fillMaxWidth()
                                .padding(horizontal = UacDesign.pageInset, vertical = 4.dp)
                                .testTag("header-search-field"),
                            label = { Text(tr(l, "Suchen, auch nach Tags", "Пошук, зокрема за тегами")) },
                            trailingIcon = {
                                if (state.search.isNotEmpty()) TextButton({ model.filters(search = "") }) {
                                    Text(tr(l, "Löschen", "Очистити"))
                                }
                            },
                            singleLine = true,
                        )
                    if (state.data.loading)
                        LinearProgressIndicator(Modifier.fillMaxWidth().testTag("browse-loading"))
                    key(state.navigationEpoch) {
                        val holder = rememberSaveableStateHolder()
                        var knownRoutes by remember { mutableStateOf(state.retainedRoutes) }
                        LaunchedEffect(state.retainedRoutes) {
                            (knownRoutes - state.retainedRoutes).forEach(holder::removeState)
                            knownRoutes = state.retainedRoutes
                        }
                        holder.SaveableStateProvider(state.route) {
                            if (state.route == "directory" || state.route.startsWith("directory/")) {
                                DirectoryDestination(
                                    state.route,
                                    l,
                                    state.region,
                                    { model.preference("region", it) },
                                    { destination -> requestNavigation { model.navigate(destination) } },
                                    { category, topic, title ->
                                        directoryFeedback?.invoke(category, topic, title)
                                    },
                                    directoryEditor,
                                    searchVisible = directorySearchVisible,
                                )
                            } else if (state.isAccountRoute) {
                                Column(Modifier.fillMaxSize()) {
                                    Box(
                                        Modifier.weight(1f)
                                            .fillMaxWidth()
                                            .padding(
                                                horizontal = UacDesign.pageInset,
                                                vertical = 12.dp,
                                            )
                                    ) {
                                        if (accountContent != null)
                                            CompositionLocalProvider(
                                                at.uac.android.design
                                                    .LocalEmbeddedNavigation provides true
                                            ) {
                                                accountContent(state.route, l)
                                            }
                                        else
                                            Text(
                                                tr(
                                                    l,
                                                    "Kontobereich nicht verfügbar.",
                                                    "Розділ облікового запису недоступний.",
                                                )
                                            )
                                    }
                                }
                            } else {
                                val list = rememberLazyListState()
                                var listViewport by remember { mutableStateOf<Rect?>(null) }
                                var filterSheetVisible by remember(state.route) { mutableStateOf(false) }
                                var bannersWereAvailable by
                                    remember(state.route) {
                                        mutableStateOf(false)
                                    }
                                val bannersAvailable =
                                    state.route.substringBefore(':') in
                                        setOf("home", "events", "organizations") &&
                                        state.detailId.isEmpty() &&
                                        state.data.banners.isNotEmpty()
                                LaunchedEffect(bannersAvailable, state.detailId) {
                                    // On a cold/cloud load the filters are initially item 0. When
                                    // banners arrive they are inserted above the filters and
                                    // LazyColumn
                                    // deliberately keeps the filter key in place, hiding the hero
                                    // just
                                    // above the viewport. Correct only that near-top insertion;
                                    // never
                                    // pull a reader back from a position they intentionally
                                    // scrolled to.
                                    if (
                                        shouldRevealNewBanner(
                                            bannersAvailable,
                                            bannersWereAvailable,
                                            state.detailId.isNotEmpty(),
                                            list.firstVisibleItemIndex,
                                        )
                                    ) {
                                        list.scrollToItem(0)
                                    }
                                    bannersWereAvailable = bannersAvailable
                                }
                                PullToRefreshBox(
                                    isRefreshing = state.data.loading && state.route != "settings",
                                    onRefresh = {
                                        if (state.route != "settings") model.refresh()
                                    },
                                    modifier =
                                        Modifier.fillMaxSize().testTag("browse-pull-refresh"),
                                ) {
                                    LazyColumn(
                                        Modifier.fillMaxSize().testTag("browse-list")
                                            .onGloballyPositioned { listViewport = it.boundsInWindow() },
                                        state = list,
                                        contentPadding =
                                            PaddingValues(
                                                start = UacDesign.pageInset,
                                                end = UacDesign.pageInset,
                                                bottom = 36.dp,
                                            ),
                                        verticalArrangement = Arrangement.spacedBy(16.dp),
                                        horizontalAlignment = Alignment.CenterHorizontally,
                                    ) {
                                        if (state.route == "settings")
                                            item("preferences") {
                                                Settings(state, model, diagnostics)
                                            }
                                        else {
                                            if (bannersAvailable)
                                                item("banners") {
                                                    BannerCarousel(state, model,
                                                        bannerMeasurementActive && !filterSheetVisible,
                                                        onBannerMeasurement, listViewport)
                                                }
                                            if (state.detailId.isEmpty())
                                                item("filters") {
                                                    BrowseListControls(state, model,
                                                        searchVisible,
                                                        { searchVisible = it },
                                                        { filterSheetVisible = it })
                                                }
                                            if (visibilityNotice != null)
                                                item("visibility") { visibilityNotice() }
                                            if (state.data.loading)
                                                item("loading") {
                                                    Text(tr(l, "Wird geladen…", "Завантаження…"))
                                                }
                                            if (state.data.cachedAt != null)
                                                item("offline") {
                                                    Text(
                                                        tr(
                                                            l,
                                                            "Offline-Kopie vom ",
                                                            "Збережена копія від ",
                                                        ) +
                                                            displayTime(state.data.cachedAt, l) +
                                                            tr(
                                                                l,
                                                                ". Kann veraltet sein.",
                                                                ". Може бути застарілою.",
                                                            ),
                                                        Modifier.testTag("cached"),
                                                        color = MaterialTheme.colorScheme.primary,
                                                    )
                                                }
                                            if (state.data.error != null)
                                                item("error") {
                                                    val signInRequired = !state.accountAvailable &&
                                                        state.data.error == ReadFailure.DENIED &&
                                                        (state.kind == ContentKind.NEWS && state.newsSource != NewsSource.ALL ||
                                                            state.kind == ContentKind.EVENTS && state.eventScope != EventScope.ALL ||
                                                            state.kind == ContentKind.ORGANIZATIONS && state.organizationScope != OrganizationScope.ALL)
                                                    Section(
                                                        if (signInRequired) tr(l, "Anmeldung erforderlich", "Потрібен вхід")
                                                        else tr(l, "Nicht verfügbar", "Недоступно")
                                                    ) {
                                                        Text(
                                                            if (signInRequired)
                                                                tr(l, "Melde dich an, um deine persönlichen Inhalte zu sehen.", "Увійдіть, щоб побачити особисті матеріали.")
                                                            else failureText(state.data.error, l),
                                                            Modifier.testTag("browse-error"),
                                                        )
                                                        if (signInRequired) {
                                                            Button(
                                                                { model.navigate("profile/login") },
                                                                Modifier.testTag("browse-sign-in"),
                                                            ) { Text(tr(l, "Anmelden", "Увійти")) }
                                                        } else {
                                                            Button(
                                                                if (state.data.items.isEmpty()) model::refresh else model::more,
                                                                Modifier.testTag("browse-retry"),
                                                            ) { Text(tr(l, "Erneut versuchen", "Спробувати ще раз")) }
                                                        }
                                                    }
                                                }
                                            if (state.data.detail != null)
                                                item("detail") {
                                                    ContentDetail(
                                                        state.data.detail,
                                                        state,
                                                        model,
                                                        personalActions,
                                                        publicGallery,
                                                    )
                                                }
                                            if (state.isList && state.kind == ContentKind.EVENTS) {
                                                val sorted = state.data.items.sortedWith(
                                                    compareBy<Content> { it.fields.displayEventOccurrence(Instant.now())?.start }
                                                        .thenBy { it.id }
                                                ).let { if (state.past) it.reversed() else it }
                                                sorted.groupBy {
                                                    it.fields.displayEventOccurrence(Instant.now())!!.start
                                                        .atZone(ZoneId.systemDefault())
                                                        .toLocalDate()
                                                        .withDayOfMonth(1)
                                                }.forEach { (month, events) ->
                                                    item("month:$month") {
                                                        Text(
                                                            month.format(
                                                                DateTimeFormatter.ofPattern(
                                                                    "LLLL yyyy",
                                                                    Locale.forLanguageTag(if (l == "uk") "uk" else "de"),
                                                                )
                                                            ).replaceFirstChar(Char::titlecase),
                                                            Modifier.fillMaxWidth().semantics { heading() }
                                                                .testTag("event-month-$month"),
                                                            style = MaterialTheme.typography.titleMedium,
                                                        )
                                                    }
                                                    items(events.chunked(cardColumns), key = { "events/${it.first().id}" }) { row ->
                                                        BrowseCardRow(row, l, cardColumns) { item ->
                                                            model.navigate("events/${item.id}")
                                                        }
                                                    }
                                                }
                                            } else {
                                                items(
                                                    state.data.items.chunked(cardColumns),
                                                    key = { row -> "${row.first().kind}/${row.first().id}" },
                                                ) { row ->
                                                    BrowseCardRow(row, l, cardColumns) { item ->
                                                        model.navigate(
                                                            "${item.kind.collection}/${item.id}"
                                                        )
                                                    }
                                                }
                                            }
                                            if (
                                                !state.data.loading &&
                                                    state.data.error == null &&
                                                    state.detailId.isEmpty() &&
                                                    state.data.items.isEmpty()
                                            )
                                                item("empty") {
                                                    Text(
                                                        if (state.data.hasMore)
                                                            tr(
                                                                l,
                                                                "Bisher keine Treffer. Weitere Seiten durchsuchen.",
                                                                "Поки немає збігів. Перегляньте наступні сторінки.",
                                                            )
                                                        else
                                                            when {
                                                                state.kind == ContentKind.EVENTS && state.past ->
                                                                    tr(l, "Keine vergangenen Termine gefunden.", "Минулих подій не знайдено.")
                                                                state.kind == ContentKind.EVENTS && state.eventScope == EventScope.SAVED ->
                                                                    tr(l, "Keine gespeicherten Termine gefunden.", "Збережених подій не знайдено.")
                                                                state.kind == ContentKind.EVENTS && state.eventScope == EventScope.REGISTERED ->
                                                                    tr(l, "Keine Anmeldungen gefunden.", "Реєстрацій не знайдено.")
                                                                state.kind == ContentKind.EVENTS ->
                                                                    tr(l, "Keine kommenden Termine gefunden.", "Майбутніх подій не знайдено.")
                                                                state.kind == ContentKind.ORGANIZATIONS && state.organizationScope == OrganizationScope.SUBSCRIBED ->
                                                                    tr(l, "Keine abonnierten Organisationen gefunden.", "Підписок на організації не знайдено.")
                                                                state.kind == ContentKind.ORGANIZATIONS && state.organizationScope == OrganizationScope.BOOKMARKED ->
                                                                    tr(l, "Keine gespeicherten Organisationen gefunden.", "Збережених організацій не знайдено.")
                                                                else -> tr(l, "Keine passenden Inhalte gefunden.", "Відповідних матеріалів не знайдено.")
                                                            },
                                                        Modifier.testTag("empty"),
                                                    )
                                                }
                                            if (state.data.hasMore)
                                                item("more") {
                                                    Button(
                                                        model::more,
                                                        Modifier.testTag("load-more"),
                                                        enabled = !state.data.loading,
                                                    ) {
                                                        Text(tr(l, "Mehr laden", "Завантажити ще"))
                                                    }
                                                }
                                            if (state.isList && state.kind == ContentKind.EVENTS &&
                                                !state.past && state.organizationId.isEmpty() &&
                                                (state.data.pastItems.isNotEmpty() ||
                                                    state.data.pastError != null || state.data.pastHasMore)) {
                                                item("past-heading") {
                                                    Text(
                                                        tr(l, "Vergangene Termine", "Минулі події"),
                                                        Modifier.fillMaxWidth().semantics { heading() }
                                                            .testTag("past-events-heading"),
                                                        style = MaterialTheme.typography.titleMedium,
                                                    )
                                                }
                                                items(
                                                    state.data.pastItems.sortedWith(
                                                        compareByDescending<Content> { it.fields.displayEventOccurrence(Instant.now())?.start }
                                                            .thenBy { it.id }
                                                    ).chunked(cardColumns),
                                                    key = { "past-events/${it.first().id}" },
                                                ) { row ->
                                                    BrowseCardRow(row, l, cardColumns) { item ->
                                                        model.navigate("events/${item.id}")
                                                    }
                                                }
                                                if (state.data.pastError != null)
                                                    item("past-error") {
                                                        Section(tr(l, "Vergangene Termine", "Минулі події")) {
                                                            Text(failureText(state.data.pastError, l))
                                                            Button(model::refresh, Modifier.testTag("past-events-retry")) {
                                                                Text(tr(l, "Erneut versuchen", "Спробувати ще раз"))
                                                            }
                                                        }
                                                    }
                                                if (state.data.pastHasMore)
                                                    item("past-more") {
                                                        Button(
                                                            model::morePast,
                                                            Modifier.testTag("load-more-past"),
                                                            enabled = !state.data.pastLoading,
                                                        ) { Text(tr(l, "Mehr vergangene Termine", "Більше минулих подій")) }
                                                    }
                                            }
                                            if (state.data.donation?.url != null)
                                                item("donation") {
                                                    val donation = state.data.donation
                                                    Section(donation.text("title", l)) {
                                                        Text(donation.text("message", l))
                                                        SafeLink(
                                                            donation.text("buttonTitle", l),
                                                            donation.url!!,
                                                            l,
                                                        )
                                                    }
                                                }
                                            items(
                                                state.data.warnings.distinct(),
                                                key = { "warning:${it.first}:${it.second}" },
                                            ) { (section, reason) ->
                                                Text(
                                                    sectionLabel(section, l) +
                                                        ": " +
                                                        failureText(reason, l)
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            overlay?.invoke()
        }
    }
}

private fun sectionLabel(key: String, l: String) =
    when (key) {
        "photos" -> tr(l, "Fotos", "Фото")
        "team" -> tr(l, "Team", "Команда")
        "banners" -> tr(l, "Highlights", "Добірки")
        "donation" -> tr(l, "Unterstützung", "Підтримка")
        "recommendations" -> tr(l, "Ähnliche Inhalte", "Схожі матеріали")
        else -> ContentKind.entries.find { it.collection == key }?.label(l) ?: key
    }

@Composable
fun Heading(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.headlineSmall,
        modifier = Modifier.semantics { heading() },
    )
}

@Composable
fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    at.uac.android.design.UacSectionCard(title = title, content = content)
}

@Composable
fun Choice(
    title: String,
    selected: String,
    options: List<Pair<String, String>>,
    tag: String,
    onSelect: (String) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(
            { expanded = true },
            Modifier.heightIn(min = UacDesign.minimumTouch).testTag(tag),
        ) {
            Text("$title: ${options.find { it.first == selected }?.second.orEmpty()}")
        }
        DropdownMenu(expanded, { expanded = false }, Modifier.heightIn(max = 420.dp)) {
            options.forEach { (value, text) ->
                DropdownMenuItem(
                    { Text(text) },
                    {
                        expanded = false
                        onSelect(value)
                    },
                    Modifier.testTag("$tag-$value"),
                )
            }
        }
    }
}

@Composable
private fun Settings(s: BrowseState, model: BrowseViewModel, diagnostics: () -> Unit) {
    val l = s.language
    Section(tr(l, "Einstellungen", "Налаштування")) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("de" to "Deutsch", "uk" to "Українська").forEach { (key, title) ->
                FilterChip(
                    s.language == key,
                    { model.preference("language", key) },
                    { Text(title) },
                    modifier = Modifier.testTag("browse-language-$key"),
                )
            }
        }
        Choice(
            tr(l, "Darstellung", "Тема"),
            s.theme,
            listOf(
                "system" to tr(l, "System", "Системна"),
                "light" to tr(l, "Hell", "Світла"),
                "dark" to tr(l, "Dunkel", "Темна"),
            ),
            "theme",
            { model.preference("theme", it) },
        )
        if (BuildConfig.USE_LOCAL_BACKEND) {
            Text(tr(l, "Datenquelle · ausschließlich lokal", "Джерело даних · лише локально"))
            listOf(
                    "synthetic" to tr(l, "Eingebaute Beispiele", "Вбудовані приклади"),
                    "emulator" to "Firebase Emulator · demo-uac-android",
                )
                .forEach { (key, title) ->
                    FilterChip(
                        s.mode == key,
                        { model.preference("mode", key) },
                        { Text(title) },
                        modifier = Modifier.testTag("browse-mode-$key"),
                    )
                }
            Text(
                tr(
                    l,
                    "Externe Demo-Links öffnen keine echten Angebote. Persönliche Aktionen verwenden ausschließlich den lokalen Firebase Emulator, nicht die eingebauten Beispiele.",
                    "Демо-посилання не відкривають справжніх пропозицій. Особисті дії працюють лише з локальним Firebase Emulator, а не з вбудованими прикладами.",
                )
            )
            TextButton(diagnostics, Modifier.testTag("diagnostics")) {
                Text(tr(l, "Technische lokale Prüfung", "Технічна локальна перевірка"))
            }
        }
        HorizontalDivider()
        at.uac.android.feature.auth.ReferenceLegalLinks(l)
    }
}

@Composable
private fun BrowseCardRow(
    row: List<Content>,
    language: String,
    columns: Int,
    onOpen: (Content) -> Unit,
) {
    Row(
        Modifier.widthIn(max = if (columns == 1) UacDesign.readableWidth else 1040.dp)
            .fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        row.forEach { item ->
            ContentCard(item, language, Modifier.weight(1f)) { onOpen(item) }
        }
        if (columns > row.size) Spacer(Modifier.weight(1f))
    }
}

@Composable
private fun BrowseFilterChip(
    selected: Boolean,
    onClick: () -> Unit,
    label: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    leadingIcon: (@Composable () -> Unit)? = null,
    trailingIcon: (@Composable () -> Unit)? = null,
) {
    val colors = MaterialTheme.colorScheme
    Box(modifier.selectable(selected = selected, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center) {
        Surface(
            shape = RoundedCornerShape(UacDesign.chipRadius),
            color = if (selected) colors.primary else colors.surface.copy(alpha = .64f),
            contentColor = if (selected) colors.onPrimary else colors.onSurfaceVariant,
            border = BorderStroke(1.dp, if (selected) colors.primary else colors.outlineVariant),
        ) {
            Row(Modifier.heightIn(min = 34.dp).padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                verticalAlignment = Alignment.CenterVertically) {
                leadingIcon?.invoke()
                ProvideTextStyle(MaterialTheme.typography.labelLarge) { label() }
                trailingIcon?.invoke()
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BrowseListControls(
    state: BrowseState, model: BrowseViewModel,
    searchVisible: Boolean,
    onSearchVisible: (Boolean) -> Unit,
    onSheetVisible: (Boolean) -> Unit = {},
) {
    val language = state.language
    var sheet by rememberSaveable(state.route) { mutableStateOf<String?>(null) }
    var eventPeriodMenu by remember { mutableStateOf(false) }
    LaunchedEffect(sheet) { onSheetVisible(sheet != null) }
    val regionLabel = localizedRegionName(state.region, language)
        ?: tr(language, "Ganz Österreich", "Уся Австрія")
    Column(
        Modifier.widthIn(max = UacDesign.readableWidth).fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (state.route !in setOf("home", "events", "organizations"))
            Heading(state.kind?.label(language) ?: tr(language, "Entdecken", "Відкривайте нове"))
        if (state.isList) {
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                    .testTag("primary-filter-row"),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (state.kind == ContentKind.NEWS)
                    BrowseFilterChip(
                        selected = state.category.isNotEmpty(),
                        onClick = { sheet = "news" },
                        label = { Text(state.category.takeIf(String::isNotEmpty)?.let { label(it, language) }
                            ?: tr(language, "Thema", "Тема")) },
                        leadingIcon = { UacSymbol(UacIcon.FILTER, modifier = Modifier.size(18.dp)) },
                        trailingIcon = { UacSymbol(UacIcon.CHEVRON_DOWN, modifier = Modifier.size(15.dp)) },
                        modifier = Modifier.heightIn(min = 48.dp).testTag("news-topic"),
                    )
                if (state.kind == ContentKind.EVENTS)
                    Box {
                        BrowseFilterChip(
                            selected = state.eventPeriod != EventPeriod.ALL,
                            onClick = { eventPeriodMenu = true },
                            label = { Text(when (state.eventPeriod) {
                                EventPeriod.ALL -> tr(language, "Alle", "Усі")
                                EventPeriod.TODAY -> tr(language, "Heute", "Сьогодні")
                                EventPeriod.THIS_WEEK -> tr(language, "Diese Woche", "Цього тижня")
                            }) },
                            leadingIcon = { UacSymbol(UacIcon.GRID, modifier = Modifier.size(18.dp)) },
                            trailingIcon = { UacSymbol(UacIcon.CHEVRON_DOWN, modifier = Modifier.size(15.dp)) },
                            modifier = Modifier.heightIn(min = 48.dp).testTag("event-period-menu"),
                        )
                        DropdownMenu(eventPeriodMenu, onDismissRequest = { eventPeriodMenu = false }) {
                            listOf(
                                EventPeriod.ALL to tr(language, "Alle", "Усі"),
                                EventPeriod.TODAY to tr(language, "Heute", "Сьогодні"),
                                EventPeriod.THIS_WEEK to tr(language, "Diese Woche", "Цього тижня"),
                            ).forEach { (period, title) ->
                                DropdownMenuItem(text = { Text(title) }, onClick = {
                                    model.filters(eventPeriod = period)
                                    eventPeriodMenu = false
                                }, modifier = Modifier.testTag("event-quick-period-${period.name}"))
                            }
                        }
                    }
                if (state.kind == ContentKind.ORGANIZATIONS)
                    BrowseFilterChip(
                        selected = false,
                        onClick = { model.filters(organizationScope = OrganizationScope.ALL) },
                        label = { Text(tr(language, "Alle", "Усі")) },
                        leadingIcon = { UacSymbol(UacIcon.GRID, modifier = Modifier.size(18.dp)) },
                        trailingIcon = { UacSymbol(UacIcon.CHEVRON_DOWN, modifier = Modifier.size(15.dp)) },
                        modifier = Modifier.heightIn(min = 48.dp).testTag("organization-all"),
                    )
                BrowseFilterChip(
                    selected = state.region.isNotEmpty(),
                    onClick = { sheet = "region" },
                    label = { Text(regionLabel) },
                    leadingIcon = { UacSymbol(UacIcon.LOCATION, modifier = Modifier.size(18.dp)) },
                    trailingIcon = { UacSymbol(UacIcon.CHEVRON_DOWN, modifier = Modifier.size(15.dp)) },
                    modifier = Modifier.heightIn(min = 48.dp).testTag("region"),
                )
                if (state.kind == ContentKind.EVENTS) {
                    BrowseFilterChip(
                        selected = state.category.isNotEmpty(),
                        onClick = { sheet = "filters" },
                        label = { Text(state.category.takeIf(String::isNotEmpty)?.let { label(it, language) }
                            ?: tr(language, "Alle Kategorien", "Усі категорії")) },
                        leadingIcon = { UacSymbol(UacIcon.FILTER, modifier = Modifier.size(18.dp)) },
                        trailingIcon = { UacSymbol(UacIcon.CHEVRON_DOWN, modifier = Modifier.size(15.dp)) },
                        modifier = Modifier.heightIn(min = 48.dp).testTag("event-category"),
                    )
                }
                if (state.kind == ContentKind.NEWS)
                    listOf(
                        NewsSource.SUBSCRIBED to tr(language, "Gefolgt", "Підписані"),
                        NewsSource.SAVED to tr(language, "Gespeichert", "Збережені"),
                    ).forEach { (source, title) ->
                        BrowseFilterChip(
                            selected = state.newsSource == source,
                            onClick = { model.filters(newsSource = if (state.newsSource == source) NewsSource.ALL else source) },
                            label = { Text(title) },
                            modifier = Modifier.heightIn(min = 48.dp).testTag("news-quick-source-${source.name}"),
                        )
                    }
                if (state.kind == ContentKind.EVENTS)
                    listOf(
                        EventScope.REGISTERED to tr(language, "Angemeldet", "Зареєстровані"),
                        EventScope.SAVED to tr(language, "Gespeichert", "Збережені"),
                    ).forEach { (scope, title) ->
                        BrowseFilterChip(
                            selected = state.eventScope == scope,
                            onClick = { model.filters(eventScope = if (state.eventScope == scope) EventScope.ALL else scope) },
                            label = { Text(title) },
                            modifier = Modifier.heightIn(min = 48.dp).testTag("event-quick-scope-${scope.name}"),
                        )
                    }
                if (state.kind == ContentKind.ORGANIZATIONS)
                    listOf(
                        OrganizationScope.SUBSCRIBED to tr(language, "Gefolgt", "Підписані"),
                        OrganizationScope.BOOKMARKED to tr(language, "Gespeichert", "Збережені"),
                    ).forEach { (scope, title) ->
                        BrowseFilterChip(
                            selected = state.organizationScope == scope,
                            onClick = { model.filters(organizationScope = if (state.organizationScope == scope) OrganizationScope.ALL else scope) },
                            label = { Text(title) },
                            modifier = Modifier.heightIn(min = 48.dp).testTag("organization-quick-scope-${scope.name}"),
                        )
                    }
                BrowseFilterChip(
                    selected = searchVisible || state.search.isNotEmpty(),
                    onClick = { onSearchVisible(!searchVisible) },
                    label = { Text(tr(language, "Suchen", "Пошук")) },
                    leadingIcon = { UacSymbol(UacIcon.SEARCH, modifier = Modifier.size(18.dp)) },
                    modifier = Modifier.heightIn(min = 48.dp).testTag("search-toggle"),
                )
                val activeFilters =
                    listOf(
                            state.category.isNotEmpty(),
                            state.kind == ContentKind.EVENTS && state.past,
                            state.kind == ContentKind.EVENTS && state.audience.isNotEmpty(),
                            state.kind == ContentKind.EVENTS && state.eventPeriod != EventPeriod.ALL,
                            state.kind == ContentKind.EVENTS && state.eventAge != EventAge.ANY,
                            state.kind == ContentKind.EVENTS && state.eventScope != EventScope.ALL,
                            state.kind == ContentKind.ORGANIZATIONS && state.organizationScope != OrganizationScope.ALL,
                            state.kind == ContentKind.NEWS && state.newsPeriod != NewsPeriod.ALL,
                            state.kind == ContentKind.NEWS && state.newsOrder != NewsOrder.NEWEST,
                            state.kind == ContentKind.NEWS && state.newsSource != NewsSource.ALL,
                        )
                        .count { it }
                BrowseFilterChip(
                    selected = activeFilters > 0,
                    onClick = { sheet = if (state.kind == ContentKind.NEWS) "news" else "filters" },
                    leadingIcon = { UacSymbol(UacIcon.FILTER, modifier = Modifier.size(18.dp)) },
                    label = {
                        Text(
                            tr(language, "Filter", "Фільтри") +
                                if (activeFilters > 0) " · $activeFilters" else ""
                        )
                    },
                    modifier = Modifier.heightIn(min = 48.dp).testTag("news-filters"),
                )
            }
            if (state.route == "organizations")
                Heading(tr(language, "Organisationen", "Організації"))
            if (state.kind == ContentKind.NEWS)
                Text(
                    newsFilterSummary(state, language),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.fillMaxWidth().testTag("news-filter-summary"),
                )
            if (state.route !in setOf("home", "events", "organizations") &&
                (searchVisible || state.search.isNotEmpty()))
                OutlinedTextField(
                    state.search,
                    { model.filters(search = it) },
                    Modifier.fillMaxWidth().testTag("search"),
                    label = {
                        Text(tr(language, "Suchen, auch nach Tags", "Пошук, зокрема за тегами"))
                    },
                    trailingIcon = {
                        if (state.search.isNotEmpty())
                            TextButton({ model.filters(search = "") }) {
                                Text(tr(language, "Löschen", "Очистити"))
                            }
                    },
                    singleLine = true,
                )
            val categorySummary =
                state.category.takeIf(String::isNotEmpty)?.let { label(it, language) }
            if (categorySummary != null && state.route !in setOf("home", "events", "organizations"))
                Text(
                    tr(language, "Kategorie", "Категорія") + ": " + categorySummary,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.testTag("category-filter-row"),
                )
            val quickDestination =
                when (state.kind) {
                    ContentKind.NEWS -> "profile/saved"
                    ContentKind.EVENTS -> "profile/registrations"
                    ContentKind.ORGANIZATIONS -> "profile/subscriptions"
                    else -> null
                }
            quickDestination?.takeIf { state.route !in setOf("home", "events", "organizations") }
                ?.let { destination ->
                TextButton(
                    onClick = { model.navigate(destination) },
                    modifier =
                        Modifier.testTag(
                            when (state.kind) {
                                ContentKind.NEWS -> "quick-saved"
                                ContentKind.EVENTS -> "quick-registrations"
                                else -> "quick-subscriptions"
                            }
                        ),
                ) {
                    UacSymbol(
                        when (state.kind) {
                            ContentKind.EVENTS -> UacIcon.CALENDAR
                            ContentKind.ORGANIZATIONS -> UacIcon.NOTIFICATIONS
                            else -> UacIcon.BOOKMARK
                        },
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        when (state.kind) {
                            ContentKind.NEWS ->
                                tr(language, "Gespeicherte Inhalte", "Збережені матеріали")
                            ContentKind.EVENTS ->
                                tr(language, "Meine Anmeldungen", "Мої реєстрації")
                            else -> tr(language, "Meine Abonnements", "Мої підписки")
                        }
                    )
                }
            }
            if (state.organizationId.isNotEmpty()) {
                Text(tr(language, "Inhalte dieser Organisation", "Матеріали цієї організації"))
            }
        }
    }
    if (sheet == "news")
        NewsFilterSheet(
            state = state,
            onDismiss = { sheet = null },
            onApply = { period, order, source, start, end, category ->
                model.filters(
                    category = category,
                    newsPeriod = period,
                    newsOrder = order,
                    newsSource = source,
                    customStart = start,
                    customEnd = end,
                )
                sheet = null
            },
        )
    else if (sheet == "filters")
        ContentFilterSheet(
            state = state,
            onDismiss = { sheet = null },
            onCategory = { model.filters(category = it) },
            onPast = { model.filters(past = it) },
            onAudience = { model.filters(audience = it) },
            onEventPeriod = { model.filters(eventPeriod = it) },
            onEventAge = { model.filters(eventAge = it) },
            onEventScope = { model.filters(eventScope = it) },
            onOrganizationScope = { model.filters(organizationScope = it) },
        )
    else if (sheet != null)
        ModalBottomSheet(
            onDismissRequest = { sheet = null },
            modifier = Modifier.testTag("browse-filter-sheet"),
        ) {
            val title =
                if (sheet == "region") tr(language, "Region", "Регіон")
                else tr(language, "Zielgruppe", "Для кого")
            Column(
                Modifier.fillMaxWidth()
                    .navigationBarsPadding()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Heading(title)
                val options =
                    if (sheet == "region")
                        listOf("" to tr(language, "Ganz Österreich", "Уся Австрія")) + regions
                    else
                        listOf("" to tr(language, "Alle Zielgruppen", "Усі аудиторії")) +
                            listOf("everyone", "families", "children", "teens", "adults", "seniors")
                                .map { it to label(it, language) }
                options.forEach { (value, text) ->
                    FilterChip(
                        selected =
                            if (sheet == "region") state.region == value
                            else state.audience == value,
                        onClick = {
                            if (sheet == "region") model.preference("region", value)
                            else model.filters(audience = value)
                            sheet = null
                        },
                        label = { Text(text) },
                        modifier =
                            Modifier.fillMaxWidth()
                                .heightIn(min = UacDesign.minimumTouch)
                                .testTag("${sheet.orEmpty()}-$value"),
                    )
                }
                Spacer(Modifier.height(8.dp))
            }
        }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ContentFilterSheet(
    state: BrowseState,
    onDismiss: () -> Unit,
    onCategory: (String) -> Unit,
    onPast: (Boolean) -> Unit,
    onAudience: (String) -> Unit,
    onEventPeriod: (EventPeriod) -> Unit,
    onEventAge: (EventAge) -> Unit,
    onEventScope: (EventScope) -> Unit,
    onOrganizationScope: (OrganizationScope) -> Unit,
) {
    val language = state.language
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        modifier = Modifier.testTag("browse-filter-sheet"),
    ) {
        Column(
            Modifier.fillMaxWidth()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Heading(tr(language, "Inhalte filtern", "Фільтрувати матеріали"))
            if (state.kind == ContentKind.EVENTS) {
                Text(tr(language, "Wann", "Коли"), style = MaterialTheme.typography.titleMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    EventPeriod.entries.forEach { period ->
                        FilterChip(
                            selected = state.eventPeriod == period,
                            onClick = { onEventPeriod(period) },
                            label = { Text(when (period) {
                                EventPeriod.ALL -> tr(language, "Alle", "Усі")
                                EventPeriod.TODAY -> tr(language, "Heute", "Сьогодні")
                                EventPeriod.THIS_WEEK -> tr(language, "Diese Woche", "Цього тижня")
                            }) },
                            modifier = Modifier.testTag("event-period-${period.name}"),
                        )
                    }
                }
                Text(tr(language, "Zeitraum", "Час"), style = MaterialTheme.typography.titleMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        !state.past,
                        { onPast(false) },
                        { Text(tr(language, "Kommend", "Майбутні")) },
                        Modifier.testTag("upcoming"),
                    )
                    FilterChip(
                        state.past,
                        { onPast(true) },
                        { Text(tr(language, "Vergangen", "Минулі")) },
                        Modifier.testTag("past"),
                    )
                }
                Text(
                    tr(language, "Zielgruppe", "Для кого"),
                    style = MaterialTheme.typography.titleMedium,
                )
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    (listOf("") +
                            listOf(
                                "everyone",
                                "families",
                                "children",
                                "teens",
                                "adults",
                                "seniors",
                            ))
                        .forEach { value ->
                            FilterChip(
                                selected = state.audience == value,
                                onClick = { onAudience(value) },
                                label = {
                                    Text(
                                        if (value.isEmpty()) tr(language, "Alle", "Усі")
                                        else label(value, language)
                                    )
                                },
                                modifier = Modifier.testTag("audience-$value"),
                            )
                        }
                }
                Text(tr(language, "Alter", "Вік"), style = MaterialTheme.typography.titleMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    EventAge.entries.forEach { age ->
                        FilterChip(
                            selected = state.eventAge == age,
                            onClick = { onEventAge(age) },
                            label = { Text(when (age) {
                                EventAge.ANY -> tr(language, "Alle", "Усі")
                                EventAge.CHILD -> tr(language, "Kinder", "Діти")
                                EventAge.TEEN -> tr(language, "Jugendliche", "Підлітки")
                                EventAge.ADULT -> tr(language, "Erwachsene", "Дорослі")
                            }) },
                            modifier = Modifier.testTag("event-age-${age.name}"),
                        )
                    }
                }
                Text(tr(language, "Meine Termine", "Мої події"), style = MaterialTheme.typography.titleMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    EventScope.entries.forEach { scope ->
                        FilterChip(
                            selected = state.eventScope == scope,
                            onClick = { onEventScope(scope) },
                            label = { Text(when (scope) {
                                EventScope.ALL -> tr(language, "Alle", "Усі")
                                EventScope.SAVED -> tr(language, "Gespeichert", "Збережені")
                                EventScope.REGISTERED -> tr(language, "Angemeldet", "Зареєстровані")
                            }) },
                            modifier = Modifier.testTag("event-scope-${scope.name}"),
                        )
                    }
                }
            }
            if (state.kind == ContentKind.ORGANIZATIONS) {
                Text(tr(language, "Meine Organisationen", "Мої організації"), style = MaterialTheme.typography.titleMedium)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OrganizationScope.entries.forEach { scope ->
                        FilterChip(
                            selected = state.organizationScope == scope,
                            onClick = { onOrganizationScope(scope) },
                            label = { Text(when (scope) {
                                OrganizationScope.ALL -> tr(language, "Alle", "Усі")
                                OrganizationScope.SUBSCRIBED -> tr(language, "Abonniert", "Підписки")
                                OrganizationScope.BOOKMARKED -> tr(language, "Gespeichert", "Збережені")
                            }) },
                            modifier = Modifier.testTag("organization-scope-${scope.name}"),
                        )
                    }
                }
            }
            Text(
                tr(language, "Kategorie", "Категорія"),
                style = MaterialTheme.typography.titleMedium,
            )
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                (listOf("") + categories(state.kind!!)).forEach { value ->
                    FilterChip(
                        selected = state.category == value,
                        onClick = { onCategory(value) },
                        label = {
                            Text(
                                if (value.isEmpty()) tr(language, "Alle", "Усі")
                                else label(value, language)
                            )
                        },
                        modifier = Modifier.testTag("category-$value"),
                    )
                }
            }
            Button(onDismiss, Modifier.fillMaxWidth().testTag("content-filter-done")) {
                Text(tr(language, "Ergebnisse anzeigen", "Показати результати"))
            }
            Spacer(Modifier.height(8.dp))
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NewsFilterSheet(
    state: BrowseState,
    onDismiss: () -> Unit,
    onApply: (NewsPeriod, NewsOrder, NewsSource, LocalDate?, LocalDate?, String) -> Unit,
) {
    val language = state.language
    var period by rememberSaveable { mutableStateOf(state.newsPeriod) }
    var order by rememberSaveable { mutableStateOf(state.newsOrder) }
    var source by rememberSaveable { mutableStateOf(state.newsSource) }
    var category by rememberSaveable { mutableStateOf(state.category) }
    var start by rememberSaveable { mutableStateOf(state.customStart) }
    var end by rememberSaveable { mutableStateOf(state.customEnd) }
    var datesVisible by rememberSaveable { mutableStateOf(false) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        modifier = Modifier.testTag("news-filter-sheet"),
    ) {
        Column(
            Modifier.fillMaxWidth()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Heading(tr(language, "Nachrichten filtern", "Фільтри новин"))
            Text(tr(language, "Zeitraum", "Період"), style = MaterialTheme.typography.titleMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NewsPeriod.entries.forEach { value ->
                    FilterChip(
                        selected = period == value,
                        onClick = {
                            period = value
                            if (value == NewsPeriod.CUSTOM) datesVisible = true
                        },
                        label = { Text(newsPeriodLabel(value, language)) },
                        modifier = Modifier.testTag("news-period-${value.name}"),
                    )
                }
            }
            if (period == NewsPeriod.CUSTOM && start != null && end != null)
                Text("${start.toString()} – ${end.toString()}")
            Text(
                tr(language, "Reihenfolge", "Порядок"),
                style = MaterialTheme.typography.titleMedium,
            )
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NewsOrder.entries.forEach { value ->
                    FilterChip(
                        selected = order == value,
                        onClick = { order = value },
                        label = { Text(newsOrderLabel(value, language)) },
                        modifier = Modifier.testTag("news-order-${value.name}"),
                    )
                }
            }
            Text(tr(language, "Quelle", "Джерело"), style = MaterialTheme.typography.titleMedium)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                NewsSource.entries.forEach { value ->
                    FilterChip(
                        selected = source == value,
                        onClick = { source = value },
                        enabled = value == NewsSource.ALL || state.accountAvailable,
                        label = { Text(newsSourceLabel(value, language)) },
                        modifier = Modifier.testTag("news-source-${value.name}"),
                    )
                }
            }
            if (!state.accountAvailable)
                Text(
                    tr(
                        language,
                        "Gespeicherte Inhalte und Abos sind nach der Anmeldung verfügbar.",
                        "Збережене та підписки доступні після входу.",
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            Text(
                tr(language, "Kategorie", "Категорія"),
                style = MaterialTheme.typography.titleMedium,
            )
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                (listOf("") + categories(ContentKind.NEWS)).forEach { value ->
                    FilterChip(
                        selected = category == value,
                        onClick = { category = value },
                        label = {
                            Text(
                                if (value.isEmpty()) tr(language, "Alle", "Усі")
                                else label(value, language)
                            )
                        },
                        modifier = Modifier.testTag("category-$value"),
                    )
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onDismiss, Modifier.weight(1f)) {
                    Text(tr(language, "Abbrechen", "Скасувати"))
                }
                Button(
                    onClick = { onApply(period, order, source, start, end, category) },
                    enabled = period != NewsPeriod.CUSTOM || start != null && end != null,
                    modifier = Modifier.weight(1f).testTag("news-filter-apply"),
                ) {
                    Text(tr(language, "Anwenden", "Застосувати"))
                }
            }
            Spacer(Modifier.height(8.dp))
        }
    }
    if (datesVisible) {
        val picker =
            rememberDateRangePickerState(
                initialSelectedStartDateMillis =
                    start?.atStartOfDay()?.toInstant(ZoneOffset.UTC)?.toEpochMilli(),
                initialSelectedEndDateMillis =
                    end?.atStartOfDay()?.toInstant(ZoneOffset.UTC)?.toEpochMilli(),
            )
        DatePickerDialog(
            onDismissRequest = { datesVisible = false },
            confirmButton = {
                TextButton({
                    start =
                        picker.selectedStartDateMillis?.let {
                            Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                        }
                    end =
                        picker.selectedEndDateMillis?.let {
                            Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                        }
                    datesVisible = false
                }) {
                    Text(tr(language, "Übernehmen", "Готово"))
                }
            },
            dismissButton = {
                TextButton({ datesVisible = false }) {
                    Text(tr(language, "Abbrechen", "Скасувати"))
                }
            },
        ) {
            DateRangePicker(picker, modifier = Modifier.fillMaxWidth().heightIn(max = 560.dp))
        }
    }
}

private fun newsFilterSummary(state: BrowseState, language: String): String =
    listOf(
            newsPeriodLabel(state.newsPeriod, language),
            newsOrderLabel(state.newsOrder, language),
            newsSourceLabel(state.newsSource, language).takeIf { state.newsSource != NewsSource.ALL },
        )
        .filterNotNull()
        .joinToString(" · ")

private fun newsPeriodLabel(value: NewsPeriod, language: String) =
    when (value) {
        NewsPeriod.ALL -> tr(language, "Gesamter Zeitraum", "За весь час")
        NewsPeriod.TODAY -> tr(language, "Heute", "Сьогодні")
        NewsPeriod.SEVEN_DAYS -> tr(language, "7 Tage", "7 днів")
        NewsPeriod.THIRTY_DAYS -> tr(language, "30 Tage", "30 днів")
        NewsPeriod.CUSTOM -> tr(language, "Zeitraum", "Власний період")
    }

private fun newsOrderLabel(value: NewsOrder, language: String) =
    if (value == NewsOrder.NEWEST) tr(language, "Neueste zuerst", "Спочатку нові")
    else tr(language, "Älteste zuerst", "Спочатку старі")

private fun newsSourceLabel(value: NewsSource, language: String) =
    when (value) {
        NewsSource.ALL -> tr(language, "Alle Quellen", "Усі джерела")
        NewsSource.SAVED -> tr(language, "Gespeichert", "Збережені")
        NewsSource.SUBSCRIBED -> tr(language, "Meine Abos", "Мої підписки")
    }

@Composable
fun SafeLink(
    title: String,
    value: String,
    language: String,
    buttonColor: Color = Color.Unspecified,
    onOpen: () -> Unit = {},
    onDialogVisibilityChanged: (Boolean) -> Unit = {},
    iconOnly: Boolean = false,
) {
    val url = safeHttps(value) ?: return
    var show by remember(url) { mutableStateOf(false) }
    LaunchedEffect(show) { onDialogVisibilityChanged(show) }
    var failed by remember(url) { mutableStateOf(false) }
    val context = LocalContext.current
    if (iconOnly)
        FilledIconButton(
            { onOpen(); show = true },
            Modifier.size(48.dp).testTag("banner-open"),
            colors = IconButtonDefaults.filledIconButtonColors(
                containerColor = UacDesign.blue, contentColor = Color.White),
        ) { UacSymbol(UacIcon.OPEN_ARROW, title.ifBlank { url }) }
    else
        TextButton(
            { onOpen(); show = true },
            colors =
                ButtonDefaults.textButtonColors(
                    contentColor =
                        if (buttonColor == Color.Unspecified) MaterialTheme.colorScheme.primary
                        else buttonColor
                ),
        ) {
            UacSymbol(UacIcon.OPEN_ARROW, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(title.ifBlank { url })
        }
    if (show)
        AlertDialog(
            onDismissRequest = { show = false },
            title = { Text(title) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SelectionContainer { Text(url) }
                    if (URI(url).host.endsWith(".invalid"))
                        Text(
                            tr(
                                language,
                                "Erfundener Demo-Link; wird nicht geöffnet.",
                                "Вигадане демо-посилання; відкриття вимкнене.",
                            )
                        )
                    if (failed)
                        Text(
                            tr(
                                language,
                                "Keine passende App verfügbar.",
                                "Відповідного застосунку немає.",
                            )
                        )
                }
            },
            confirmButton = {
                TextButton(
                    {
                        failed =
                            runCatching {
                                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            }
                                .isFailure
                        if (!failed) {
                            show = false
                        }
                    },
                    enabled = !URI(url).host.endsWith(".invalid"),
                ) {
                    Text(tr(language, "Öffnen", "Відкрити"))
                }
            },
            dismissButton = {
                FlowRow {
                    TextButton({
                        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                            .setPrimaryClip(ClipData.newPlainText(title, url))
                    }) {
                        Text(tr(language, "Kopieren", "Копіювати"))
                    }
                    TextButton({ show = false }) { Text(tr(language, "Schließen", "Закрити")) }
                }
            },
        )
}
