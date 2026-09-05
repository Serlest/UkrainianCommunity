package at.uac.android.feature.browse

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import at.uac.android.core.ProtectedAlertDialog as AlertDialog
import at.uac.android.core.ProtectedDropdownMenu as DropdownMenu
import at.uac.android.design.UacBottomNavigation
import at.uac.android.design.UacDesign
import at.uac.android.design.UacHeader
import at.uac.android.design.UacIcon
import at.uac.android.design.UacPageBackground
import at.uac.android.design.UacSymbol
import at.uac.android.design.UacTheme
import at.uac.android.design.isCompactAuthHeaderRoute
import java.net.URI
import java.time.Instant

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
) {
    val l = state.language
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
    BackHandler(state.canBack, model::back)
    UacTheme(state.theme) {
        UacPageBackground(Modifier.fillMaxSize()) {
            val keyboardVisible =
                WindowInsets.ime.getBottom(androidx.compose.ui.platform.LocalDensity.current) > 0
            Scaffold(
                containerColor = Color.Transparent,
                modifier = Modifier.imePadding(),
                bottomBar = {
                    if (!keyboardVisible)
                        UacBottomNavigation(state.selectedTab, l, model::selectTab)
                },
            ) { insets ->
                Column(Modifier.fillMaxSize().padding(insets)) {
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        UacHeader(
                            l,
                            state.canBack,
                            model::back,
                            { model.navigate("settings") },
                            compact =
                                isCompactAuthHeaderRoute(state.route) ||
                                    keyboardVisible ||
                                    androidx.compose.ui.platform.LocalConfiguration.current
                                        .screenHeightDp < 480,
                        )
                    }
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
                            if (state.isAccountRoute) {
                                Column(Modifier.fillMaxSize()) {
                                    Box(
                                        Modifier.weight(1f)
                                            .fillMaxWidth()
                                            .padding(
                                                horizontal = UacDesign.pageInset,
                                                vertical = 12.dp,
                                            )
                                    ) {
                                        if (accountContent != null) accountContent(state.route, l)
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
                                LazyColumn(
                                    Modifier.fillMaxSize().testTag("browse-list"),
                                    state = list,
                                    contentPadding =
                                        PaddingValues(
                                            start = UacDesign.pageInset,
                                            end = UacDesign.pageInset,
                                            bottom = 24.dp,
                                        ),
                                    verticalArrangement = Arrangement.spacedBy(16.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally,
                                ) {
                                    if (state.route == "settings")
                                        item("preferences") {
                                            Settings(state, model, diagnostics)
                                        }
                                    else {
                                        if (visibilityNotice != null)
                                            item("visibility") { visibilityNotice() }
                                        if (
                                            state.route == "home" && state.data.banners.isNotEmpty()
                                        )
                                            item("home-banners") { BannerCarousel(state, model) }
                                        if (state.detailId.isEmpty())
                                            item("filters") {
                                                if (state.route == "home")
                                                    HomeFeedControls(state, model)
                                                else BrowseListControls(state, model)
                                            }
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
                                                Section(tr(l, "Nicht verfügbar", "Недоступно")) {
                                                    Text(
                                                        failureText(state.data.error, l),
                                                        Modifier.testTag("browse-error"),
                                                    )
                                                    Button(
                                                        if (state.data.items.isEmpty())
                                                            model::refresh
                                                        else model::more,
                                                        Modifier.testTag("browse-retry"),
                                                    ) {
                                                        Text(
                                                            tr(
                                                                l,
                                                                "Erneut versuchen",
                                                                "Спробувати ще раз",
                                                            )
                                                        )
                                                    }
                                                }
                                            }
                                        if (state.data.invalid > 0)
                                            item("invalid-warning") {
                                                Text(
                                                    tr(
                                                        l,
                                                        "Ungültige Einträge übersprungen: ",
                                                        "Пропущено некоректних записів: ",
                                                    ) + state.data.invalid,
                                                    Modifier.testTag("invalid-warning"),
                                                )
                                            }
                                        if (
                                            state.route != "home" && state.data.banners.isNotEmpty()
                                        )
                                            item("banners") { BannerCarousel(state, model) }
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
                                        if (state.route == "home")
                                            item("overview") {
                                                Text(
                                                    tr(
                                                        l,
                                                        "Aktuelle Auswahl · alle Einträge in den jeweiligen Bereichen",
                                                        "Свіжа добірка · усі матеріали у відповідних розділах",
                                                    ),
                                                    style = MaterialTheme.typography.bodySmall,
                                                    color =
                                                        MaterialTheme.colorScheme.onSurfaceVariant,
                                                )
                                            }
                                        items(state.data.items, key = { "${it.kind}/${it.id}" }) {
                                            item ->
                                            ContentCard(item, l) {
                                                model.navigate("${item.kind.collection}/${item.id}")
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
                                                        tr(
                                                            l,
                                                            "Keine passenden Inhalte gefunden.",
                                                            "Відповідних матеріалів не знайдено.",
                                                        ),
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
    Card(Modifier.widthIn(max = 760.dp).fillMaxWidth()) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Heading(title)
            content()
        }
    }
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
        HorizontalDivider()
        at.uac.android.feature.auth.ReferenceLegalLinks(l)
    }
}

@Composable
private fun BrowseListControls(state: BrowseState, model: BrowseViewModel) {
    val language = state.language
    Column(
        Modifier.widthIn(max = UacDesign.readableWidth).fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Heading(state.kind?.label(language) ?: tr(language, "Entdecken", "Відкривайте нове"))
        Choice(
            tr(language, "Region", "Регіон"),
            state.region,
            listOf("" to tr(language, "Ganz Österreich", "Уся Австрія")) + regions,
            "region",
            { model.preference("region", it) },
        )
        if (state.isList) {
            OutlinedTextField(
                state.search,
                { model.filters(search = it) },
                Modifier.fillMaxWidth().testTag("search"),
                label = {
                    Text(tr(language, "Suchen, auch nach Tags", "Пошук, зокрема за тегами"))
                },
                singleLine = true,
            )
            Choice(
                tr(language, "Kategorie", "Категорія"),
                state.category,
                listOf("" to tr(language, "Alle Kategorien", "Усі категорії")) +
                    categories(state.kind!!).map { it to label(it, language) },
                "category",
                { model.filters(category = it) },
            )
            if (state.kind == ContentKind.EVENTS) {
                Choice(
                    tr(language, "Zielgruppe", "Для кого"),
                    state.audience,
                    listOf("" to tr(language, "Alle Zielgruppen", "Усі аудиторії")) +
                        listOf("everyone", "families", "children", "teens", "adults", "seniors")
                            .map { it to label(it, language) },
                    "audience",
                    { model.filters(audience = it) },
                )
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        !state.past,
                        { model.filters(past = false) },
                        { Text(tr(language, "Kommend", "Майбутні")) },
                        modifier = Modifier.testTag("upcoming"),
                    )
                    FilterChip(
                        state.past,
                        { model.filters(past = true) },
                        { Text(tr(language, "Vergangen", "Минулі")) },
                        modifier = Modifier.testTag("past"),
                    )
                }
            }
            if (state.organizationId.isNotEmpty()) {
                Text(tr(language, "Inhalte dieser Organisation", "Матеріали цієї організації"))
            }
        }
        TextButton(model::refresh, Modifier.testTag("refresh")) {
            Text(tr(language, "Aktualisieren", "Оновити"))
        }
    }
}

@Composable
private fun HomeFeedControls(state: BrowseState, model: BrowseViewModel) {
    FlowRow(
        Modifier.widthIn(max = UacDesign.readableWidth).fillMaxWidth().testTag("home-controls"),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Choice(
            tr(state.language, "Region", "Регіон"),
            state.region,
            listOf("" to tr(state.language, "Ganz Österreich", "Уся Австрія")) + regions,
            "region",
            { model.preference("region", it) },
        )
        TextButton({ model.navigate("news") }, Modifier.testTag("tab-news")) {
            UacSymbol(UacIcon.NEWS)
            Spacer(Modifier.width(8.dp))
            Text(tr(state.language, "Alle Neuigkeiten", "Усі новини"))
        }
        TextButton(model::refresh, Modifier.testTag("refresh")) {
            Text(tr(state.language, "Aktualisieren", "Оновити"))
        }
    }
}

@Composable
fun SafeLink(
    title: String,
    value: String,
    language: String,
    buttonColor: Color = Color.Unspecified,
) {
    val url = safeHttps(value) ?: return
    var show by remember(url) { mutableStateOf(false) }
    var failed by remember(url) { mutableStateOf(false) }
    val context = LocalContext.current
    TextButton(
        { show = true },
        colors =
            ButtonDefaults.textButtonColors(
                contentColor =
                    if (buttonColor == Color.Unspecified) MaterialTheme.colorScheme.primary
                    else buttonColor
            ),
    ) {
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
                        if (!failed) show = false
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
