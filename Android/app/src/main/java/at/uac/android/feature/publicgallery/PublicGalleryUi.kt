package at.uac.android.feature.publicgallery

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.LocalSaveableStateRegistry
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogProperties
import at.uac.android.core.LocalWindowPrivacy
import at.uac.android.core.ProtectedDialog
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSymbol
import at.uac.android.feature.browse.*
import java.time.Instant
import kotlinx.coroutines.launch

/**
 * No source, identity permission or mutations: the host owns the current public target and policy.
 */
@Composable
fun PublicOrganizationGallery(
    organizationId: String,
    photos: List<RawDocument>,
    language: String,
    cachedAt: Instant?,
    failure: ReadFailure?,
    onRefresh: () -> Unit,
    displayable: () -> Boolean,
    scopeKey: Any,
) {
    var selectedId by remember(scopeKey, organizationId) { mutableStateOf<String?>(null) }
    val window = PublicGalleryProjection.window(photos, cachedAt, failure)
    val privacy = LocalWindowPrivacy.current
    fun current() = displayable() && privacy?.interactionBlocked != true
    val allowed = current()
    val selected = PublicGalleryProjection.selected(window, selectedId, allowed)
    // Render-time invalidation: neither a deferred effect nor a saved stale URL may keep the dialog
    // alive.
    if (selectedId != null && selected == null) selectedId = null
    if (!allowed) return

    Column(
        Modifier.fillMaxWidth().testTag("public-gallery"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                tr(language, "Fotos", "Фото"),
                Modifier.weight(1f).semantics { heading() },
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                "${window.photos.size} / ${PublicGalleryProjection.MAX_PHOTOS}",
                Modifier.testTag("public-gallery-count"),
                style = MaterialTheme.typography.labelMedium,
            )
        }
        GalleryReadNotice(window, language)
        if (window.photos.isEmpty() && window.failure == null)
            Text(
                tr(language, "Noch keine Fotos.", "Фотографій поки немає."),
                Modifier.testTag("public-gallery-empty"),
                style = MaterialTheme.typography.bodyMedium,
            )
        if (window.photos.isNotEmpty())
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val columns = PublicGalleryProjection.columns(maxWidth.value)
                // The host is already a LazyColumn; these at-most15 non-scroll rows cannot request
                // infinite height.
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    window.photos.chunked(columns).forEach { row ->
                        Row(
                            Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            row.forEach { photo ->
                                key(photo.id) {
                                    val label =
                                        photo.caption
                                            ?: tr(language, "Foto öffnen", "Відкрити фотографію")
                                    Box(
                                        Modifier.weight(1f)
                                            .aspectRatio(1f)
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(MaterialTheme.colorScheme.surfaceVariant)
                                            .clickable(
                                                role = Role.Button,
                                                onClickLabel =
                                                    tr(
                                                        language,
                                                        "Foto öffnen",
                                                        "Відкрити фотографію",
                                                    ),
                                            ) {
                                                if (current()) selectedId = photo.id
                                            }
                                            .semantics { contentDescription = label }
                                            .testTag("public-gallery-photo-${photo.id}")
                                    ) {
                                        PublicImage(
                                            photo.imageUrl,
                                            "",
                                            language,
                                            Modifier.fillMaxSize(),
                                            fallback = UacIcon.ORGANIZATIONS,
                                            presentation = PublicImagePresentation.VIEWPORT_CROP,
                                        )
                                    }
                                }
                            }
                            repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
            }
        TextButton(
            {
                if (current()) {
                    selectedId = null
                    onRefresh()
                }
            },
            Modifier.heightIn(min = 48.dp).testTag("public-gallery-refresh"),
        ) {
            Text(tr(language, "Fotos aktualisieren", "Оновити фотографії"))
        }
    }
    if (selected != null && current())
        key(scopeKey, organizationId) {
            // Pager/scroll helpers normally save their indices. This public overlay is deliberately
            // ephemeral.
            CompositionLocalProvider(LocalSaveableStateRegistry provides null) {
                PublicGalleryViewer(
                    window,
                    selected.id,
                    language,
                    onSelected = { id ->
                        if (current() && window.photos.any { it.id == id }) selectedId = id
                    },
                    onDismiss = { selectedId = null },
                    displayable = ::current,
                )
            }
        }
}

@Composable
private fun GalleryReadNotice(window: PublicGalleryWindow, language: String) {
    window.cachedAt?.let { at ->
        Text(
            tr(language, "Offline-Kopie vom ", "Збережена копія від ") +
                displayTime(at, language) +
                tr(language, ". Kann veraltet sein.", ". Може бути застарілою."),
            Modifier.testTag("public-gallery-cached"),
            style = MaterialTheme.typography.bodySmall,
        )
    }
    window.failure?.let {
        Text(
            failureText(it, language),
            Modifier.testTag("public-gallery-error"),
            style = MaterialTheme.typography.bodySmall,
        )
    }
    if (window.truncated)
        Text(
            tr(
                language,
                "Angezeigt werden die letzten 30 geladenen Fotos.",
                "Показано останні 30 завантажених фотографій.",
            ),
            Modifier.testTag("public-gallery-window"),
            style = MaterialTheme.typography.bodySmall,
        )
}

@Composable
private fun PublicGalleryViewer(
    window: PublicGalleryWindow,
    initialId: String,
    language: String,
    onSelected: (String) -> Unit,
    onDismiss: () -> Unit,
    displayable: () -> Boolean,
) {
    val pager =
        rememberPagerState(
            initialPage = window.photos.indexOfFirst { it.id == initialId }.coerceAtLeast(0),
            pageCount = { window.photos.size },
        )
    val scope = rememberCoroutineScope()
    LaunchedEffect(pager, window.photos) {
        snapshotFlow { pager.currentPage }
            .collect { index ->
                window.photos.getOrNull(index)?.let { if (displayable()) onSelected(it.id) }
            }
    }
    if (!displayable()) return
    ProtectedDialog(
        onDismissRequest = onDismiss,
        properties =
            DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        Surface(
            Modifier.fillMaxSize().testTag("public-gallery-viewer"),
            color = Color.Black,
            contentColor = Color.White,
        ) {
            Column(
                Modifier.fillMaxSize()
                    .windowInsetsPadding(WindowInsets.safeDrawing)
                    .padding(horizontal = 12.dp)
            ) {
                Row(
                    Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        tr(language, "Fotos", "Фото"),
                        Modifier.weight(1f),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    TextButton(
                        onDismiss,
                        Modifier.heightIn(min = 48.dp)
                            .widthIn(min = 48.dp)
                            .testTag("public-gallery-done"),
                        colors = ButtonDefaults.textButtonColors(contentColor = Color.White),
                    ) {
                        Text(tr(language, "Fertig", "Готово"))
                    }
                }
                if (window.cachedAt != null || window.failure != null || window.truncated) {
                    Box(
                        Modifier.fillMaxWidth()
                            .heightIn(max = 96.dp)
                            .verticalScroll(rememberScrollState())
                    ) {
                        GalleryReadNotice(window, language)
                    }
                }
                HorizontalPager(
                    pager,
                    Modifier.weight(1f).fillMaxWidth().testTag("public-gallery-pager"),
                    key = { window.photos[it].id },
                    beyondViewportPageCount = 0,
                ) { index ->
                    val photo = window.photos[index]
                    BoxWithConstraints(Modifier.fillMaxSize()) {
                        val captionHeight = maxHeight * .3f
                        Column(
                            Modifier.fillMaxSize(),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            PublicImage(
                                photo.imageUrl,
                                photo.caption ?: tr(language, "Foto", "Фотографія"),
                                language,
                                Modifier.weight(1f)
                                    .fillMaxWidth()
                                    .testTag("public-gallery-image-${photo.id}"),
                                fallback = UacIcon.ORGANIZATIONS,
                                presentation = PublicImagePresentation.VIEWPORT_FIT,
                            )
                            photo.caption?.let { caption ->
                                Box(
                                    Modifier.fillMaxWidth()
                                        .heightIn(max = captionHeight)
                                        .verticalScroll(rememberScrollState())
                                        .padding(vertical = 8.dp)
                                ) {
                                    Text(
                                        caption,
                                        Modifier.fillMaxWidth()
                                            .testTag("public-gallery-caption-${photo.id}"),
                                        textAlign = TextAlign.Center,
                                        style = MaterialTheme.typography.bodyMedium,
                                    )
                                }
                            }
                        }
                    }
                }
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(
                        {
                            if (displayable())
                                scope.launch {
                                    pager.animateScrollToPage(
                                        (pager.currentPage - 1).coerceAtLeast(0)
                                    )
                                }
                        },
                        Modifier.size(48.dp).testTag("public-gallery-previous"),
                        enabled = pager.currentPage > 0,
                    ) {
                        UacSymbol(
                            UacIcon.BACK,
                            tr(language, "Vorheriges Foto", "Попередня фотографія"),
                        )
                    }
                    Text(
                        "${pager.currentPage + 1} / ${window.photos.size}",
                        Modifier.weight(1f).testTag("public-gallery-page"),
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.labelMedium,
                    )
                    IconButton(
                        {
                            if (displayable())
                                scope.launch {
                                    pager.animateScrollToPage(
                                        (pager.currentPage + 1).coerceAtMost(
                                            window.photos.lastIndex
                                        )
                                    )
                                }
                        },
                        Modifier.size(48.dp).testTag("public-gallery-next"),
                        enabled = pager.currentPage < window.photos.lastIndex,
                    ) {
                        UacSymbol(
                            UacIcon.BACK,
                            tr(language, "Nächstes Foto", "Наступна фотографія"),
                            Modifier.rotate(180f),
                        )
                    }
                }
            }
        }
    }
}
