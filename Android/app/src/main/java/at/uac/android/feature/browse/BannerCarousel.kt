package at.uac.android.feature.browse

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import at.uac.android.design.LocalUacDark
import at.uac.android.design.UacDesign
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSymbol
import at.uac.android.feature.bannermeasurement.BannerExposureTracker
import at.uac.android.feature.bannermeasurement.BannerMeasurement
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.delay

/**
 * Use the same complete route grammar as restored navigation; a malformed remote action is never
 * clickable.
 */
fun bannerRoute(action: String, target: String): String? {
    val collection =
        when (action) {
            "news" -> "news"
            "event" -> "events"
            "organization" -> "organizations"
            else -> return null
        }
    return runCatching { BrowseNavigation.restore().navigate("$collection/$target").route }
        .getOrNull()
}

@Composable
fun BannerCarousel(
    state: BrowseState,
    model: BrowseViewModel,
    measurementActive: Boolean = false,
    onMeasurement: (BannerMeasurement) -> Unit = {},
    viewport: Rect? = null,
) {
    val candidates = state.data.banners
    if (candidates.isEmpty()) return
    var now by remember(candidates) { mutableStateOf(Instant.now()) }
    var resumed by remember { mutableStateOf(false) }
    LifecycleResumeEffect(Unit) {
        resumed = true
        now = Instant.now()
        onPauseOrDispose { resumed = false }
    }
    LaunchedEffect(candidates, resumed) {
        if (!resumed) return@LaunchedEffect
        while (true) {
            now = Instant.now()
            val boundary =
                candidates
                    .flatMap {
                        listOfNotNull(
                            it.fields.time("startsAt"),
                            it.fields.time("endsAt")?.plusNanos(1),
                        )
                    }
                    .filter { it > now }
                    .minOrNull() ?: break
            delay(Duration.between(now, boundary).toMillis().coerceAtLeast(1))
        }
    }
    val banners =
        visibleBanners(
            candidates.map { RawDocument(it.id, it.fields) },
            state.route.substringBefore(':'),
            state.region,
            now,
        )
    if (banners.isEmpty()) return
    var index by rememberSaveable { mutableIntStateOf(0) }
    val selected = index.coerceIn(0, banners.lastIndex)
    val banner = banners[selected]
    val section = state.route.substringBefore(':')
    val view = LocalView.current
    val tracker = remember { BannerExposureTracker() }
    var visibleFraction by remember(banner.id) { mutableFloatStateOf(0f) }
    var artworkReady by remember(banner.id, banner.fields.string("imageURL")) {
        mutableStateOf(false)
    }
    var externalDialogVisible by remember(banner.id) { mutableStateOf(false) }
    val eligible = measurementActive && resumed && artworkReady && !externalDialogVisible
    LaunchedEffect(banner.id, section, eligible, visibleFraction) {
        tracker.observe(banner.id, section, visibleFraction, eligible, System.currentTimeMillis())
            ?.let(onMeasurement)
        if (eligible && visibleFraction >= .5f) {
            delay(1_000)
            tracker.observe(banner.id, section, visibleFraction, eligible, System.currentTimeMillis())
                ?.let(onMeasurement)
        }
    }
    fun recordClick() {
        tracker.click(banner.id, section, visibleFraction, eligible, System.currentTimeMillis())
            .forEach(onMeasurement)
    }
    val accessibility =
        LocalContext.current.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    var spoken by remember { mutableStateOf(accessibility.isTouchExplorationEnabled) }
    DisposableEffect(accessibility) {
        val listener = AccessibilityManager.TouchExplorationStateChangeListener { spoken = it }
        accessibility.addTouchExplorationStateChangeListener(listener)
        onDispose { accessibility.removeTouchExplorationStateChangeListener(listener) }
    }
    LaunchedEffect(resumed, spoken, banner.id, banners.size) {
        if (resumed && !spoken && banners.size > 1) {
            delay(banner.fields.count("displayDurationSeconds").coerceIn(3, 12) * 1_000)
            index = (selected + 1) % banners.size
        }
    }
    var horizontalDrag by remember { mutableFloatStateOf(0f) }
    fun previous(): Boolean {
        index = (selected - 1 + banners.size) % banners.size
        return true
    }
    fun next(): Boolean {
        index = (selected + 1) % banners.size
        return true
    }
    Column(
        Modifier.widthIn(max = UacDesign.readableWidth)
            .fillMaxWidth()
            .testTag("banner-carousel")
            .pointerInput(banners.size, selected) {
                val threshold = 48.dp.toPx()
                detectHorizontalDragGestures(
                    onDragStart = { horizontalDrag = 0f },
                    onHorizontalDrag = { _, amount -> horizontalDrag += amount },
                    onDragEnd = {
                        when {
                            horizontalDrag < -threshold -> next()
                            horizontalDrag > threshold -> previous()
                        }
                        horizontalDrag = 0f
                    },
                    onDragCancel = { horizontalDrag = 0f },
                )
            }
            .semantics {
                if (banners.size > 1) {
                    stateDescription = "${selected + 1} / ${banners.size}"
                    customActions =
                        listOf(
                            CustomAccessibilityAction(
                                tr(state.language, "Vorherige Empfehlung", "Попередня добірка"),
                                ::previous,
                            ),
                            CustomAccessibilityAction(
                                tr(state.language, "Nächste Empfehlung", "Наступна добірка"),
                                ::next,
                            ),
                        )
                }
            },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box {
            BannerHero(
                banner, state.language, { model.navigate(it) },
                modifier = Modifier.onGloballyPositioned { coordinates ->
                    val frame = coordinates.boundsInWindow()
                    val visible = viewport ?: Rect(0f, 0f, view.width.toFloat(), view.height.toFloat())
                    val width = frame.width
                    val height = frame.height
                    val overlapWidth = (minOf(frame.right, visible.right) - maxOf(frame.left, visible.left))
                        .coerceAtLeast(0f)
                    val overlapHeight = (minOf(frame.bottom, visible.bottom) - maxOf(frame.top, visible.top))
                        .coerceAtLeast(0f)
                    visibleFraction = if (width > 0f && height > 0f)
                        (overlapWidth * overlapHeight / (width * height)).coerceIn(0f, 1f)
                    else 0f
                },
                onArtworkReady = { artworkReady = it },
                onTap = ::recordClick,
                onDialogVisibilityChanged = { externalDialogVisible = it },
            )
        }
        if (banners.size > 1)
            Row(
                Modifier.padding(top = 8.dp).testTag("banner-indicator"),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                banners.indices.forEach { dot ->
                    Box(
                        Modifier.size(width = if (dot == selected) 18.dp else 6.dp, height = 6.dp)
                            .clip(RoundedCornerShape(50))
                            .background(
                                if (dot == selected) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = .35f)
                            )
                    )
                }
            }
    }
}

/**
 * iPhone-style image hero with a readable scrim. Large text grows the card instead of clipping it.
 */
@Composable
fun BannerHero(
    banner: Banner,
    language: String,
    onNavigate: (String) -> Unit,
    modifier: Modifier = Modifier,
    onArtworkReady: (Boolean) -> Unit = {},
    onTap: () -> Unit = {},
    onDialogVisibilityChanged: (Boolean) -> Unit = {},
) {
    val largeText = LocalDensity.current.fontScale > 1.3f
    val title = banner.text("title", language)
    val subtitle = banner.text("subtitle", language)
    val action = banner.fields.string("actionType")
    val route =
        remember(action, banner.fields.string("actionTargetID")) {
            bannerRoute(action, banner.fields.string("actionTargetID"))
        }
    val dark = LocalUacDark.current
    val fallback =
        if (dark) listOf(Color(0xFF213858), Color(0xFF283343), Color(0xFF51482D))
        else listOf(Color(0xFFDCE6F6), Color(0xFFE9EAF0), Color(0xFFF4ECD4))
    Box(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(22.dp))
            .background(Brush.linearGradient(fallback))
            .testTag("banner-hero")
    ) {
        if (banner.fields.string("imageURL").isNotBlank())
            PublicImage(
                banner.fields.string("imageURL"),
                "",
                language,
                Modifier.matchParentSize(),
                presentation = PublicImagePresentation.VIEWPORT_FIT,
                adaptiveBackdrop = true,
                externalBanner = true,
                fallback = UacIcon.PHOTO,
                showUnavailableText = false,
                onLoadStateChanged = onArtworkReady,
            )
        else LaunchedEffect(banner.id) { onArtworkReady(true) }
        Box(
            Modifier.matchParentSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Color.Transparent, Color.Black.copy(alpha = .35f))
                    )
                )
        )
        Column(
            Modifier.fillMaxWidth().heightIn(min = 210.dp).padding(16.dp),
            verticalArrangement = Arrangement.Bottom,
        ) {
            Spacer(Modifier.height(if (largeText) 36.dp else 52.dp))
            if (
                title.isNotBlank() ||
                    subtitle.isNotBlank() ||
                    route != null ||
                    action == "externalURL"
            )
                Surface(
                    color = UacDesign.bannerScrim.copy(alpha = .88f),
                    contentColor = Color.White,
                    shape = RoundedCornerShape(14.dp),
                ) {
                    Column(
                        Modifier.fillMaxWidth().padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Row(
                            verticalAlignment = Alignment.Bottom,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Column(
                                Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                if (title.isNotBlank())
                                    Text(
                                        title,
                                        Modifier.testTag("banner-title").semantics { heading() },
                                        style = MaterialTheme.typography.titleSmall,
                                        maxLines = if (largeText) Int.MAX_VALUE else 2,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                                if (subtitle.isNotBlank())
                                    Text(
                                        subtitle,
                                        Modifier.testTag("banner-text"),
                                        color = UacDesign.bannerSubtitle,
                                        style = MaterialTheme.typography.bodySmall,
                                        maxLines = if (largeText) Int.MAX_VALUE else 2,
                                        overflow = TextOverflow.Ellipsis,
                                    )
                            }
                            if (route != null) {
                                FilledIconButton(
                                    { onTap(); onNavigate(route) },
                                    Modifier.size(48.dp).testTag("banner-open"),
                                    colors =
                                        IconButtonDefaults.filledIconButtonColors(
                                            containerColor = UacDesign.blue,
                                            contentColor = Color.White,
                                        ),
                                ) {
                                    UacSymbol(
                                        UacIcon.OPEN_ARROW,
                                        tr(language, "Ansehen", "Переглянути"),
                                    )
                                }
                            } else if (action == "externalURL") {
                                SafeLink(
                                    tr(language, "Ansehen", "Переглянути"),
                                    banner.fields.string("externalURL"),
                                    language,
                                    onOpen = onTap,
                                    onDialogVisibilityChanged = onDialogVisibilityChanged,
                                    iconOnly = true,
                                )
                            }
                        }
                    }
                }
        }
    }
}
