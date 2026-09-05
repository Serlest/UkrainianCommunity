package at.uac.android.feature.browse

import android.content.Context
import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import at.uac.android.design.LocalUacDark
import at.uac.android.design.UacDesign
import at.uac.android.design.UacIcon
import at.uac.android.design.UacSymbol
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
fun BannerCarousel(state: BrowseState, model: BrowseViewModel) {
    val banners = state.data.banners
    if (banners.isEmpty()) return
    var index by rememberSaveable { mutableIntStateOf(0) }
    val selected = index.coerceIn(0, banners.lastIndex)
    val banner = banners[selected]
    var auto by rememberSaveable { mutableStateOf(false) }
    var resumed by remember { mutableStateOf(false) }
    val accessibility =
        LocalContext.current.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
    var spoken by remember { mutableStateOf(accessibility.isTouchExplorationEnabled) }
    DisposableEffect(accessibility) {
        val listener = AccessibilityManager.TouchExplorationStateChangeListener { spoken = it }
        accessibility.addTouchExplorationStateChangeListener(listener)
        onDispose { accessibility.removeTouchExplorationStateChangeListener(listener) }
    }
    LifecycleResumeEffect(Unit) {
        resumed = true
        onPauseOrDispose { resumed = false }
    }
    LaunchedEffect(auto, resumed, spoken, banner.id) {
        if (auto && resumed && !spoken && banners.size > 1) {
            delay(banner.fields.count("displayDurationSeconds").coerceIn(3, 12) * 1_000)
            index = (selected + 1) % banners.size
        }
    }
    Column(
        Modifier.widthIn(max = UacDesign.readableWidth).fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        BannerHero(banner, state.language, { model.navigate(it) })
        if (banners.size > 1) {
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)
            ) {
                IconButton(
                    { index = (selected - 1 + banners.size) % banners.size },
                    Modifier.testTag("banner-previous"),
                ) {
                    UacSymbol(
                        UacIcon.BACK,
                        tr(state.language, "Vorherige Empfehlung", "Попередня добірка"),
                    )
                }
                Text(
                    "${selected + 1} / ${banners.size}",
                    Modifier.align(Alignment.CenterVertically),
                    style = MaterialTheme.typography.labelMedium,
                )
                IconButton(
                    { index = (selected + 1) % banners.size },
                    Modifier.testTag("banner-next"),
                ) {
                    UacSymbol(
                        UacIcon.BACK,
                        tr(state.language, "Nächste Empfehlung", "Наступна добірка"),
                        Modifier.rotate(180f),
                    )
                }
                if (!spoken)
                    IconToggleButton(
                        auto,
                        { auto = it },
                        Modifier.size(48.dp).testTag("banner-auto"),
                    ) {
                        UacSymbol(
                            if (auto) UacIcon.PAUSE else UacIcon.PLAY,
                            if (auto)
                                tr(
                                    state.language,
                                    "Automatik pausieren",
                                    "Призупинити автоперегляд",
                                )
                            else tr(state.language, "Automatik starten", "Увімкнути автоперегляд"),
                        )
                    }
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
        PublicImage(
            banner.fields.string("imageURL"),
            "",
            language,
            Modifier.matchParentSize(),
            compact = true,
        )
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
            Surface(
                color = UacDesign.bannerScrim,
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
                        if (route != null)
                            FilledIconButton(
                                { onNavigate(route) },
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
                    }
                    if (action == "externalURL")
                        SafeLink(
                            tr(language, "Ansehen", "Переглянути"),
                            banner.fields.string("externalURL"),
                            language,
                            buttonColor = Color.White,
                        )
                }
            }
        }
    }
}
