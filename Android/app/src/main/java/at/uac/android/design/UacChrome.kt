package at.uac.android.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.intl.LocaleList
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.Hyphens
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import at.uac.android.R
import at.uac.android.feature.browse.PrimaryTab
import at.uac.android.feature.browse.tr

/** Small code-native line icons; no platform font glyphs or third-party logo variants. */
enum class UacIcon {
    HOME,
    CALENDAR,
    ORGANIZATIONS,
    DIRECTORY,
    PROFILE,
    SETTINGS,
    BACK,
    NEWS,
    OPEN_ARROW,
    PLAY,
    PAUSE,
    LOGOUT,
    LIKE,
    BOOKMARK,
    NOTIFICATIONS,
    LOCATION,
    SECURITY,
    EDIT,
    HISTORY,
    SUPPORT,
    ANALYTICS,
    DELETE,
    SEARCH,
    FILTER,
    PHOTO,
}

private val icons =
    UacIcon.entries.associateWith { icon ->
        ImageVector.Builder(icon.name, 24.dp, 24.dp, 24f, 24f)
            .apply {
                path(
                    fill = null,
                    stroke = SolidColor(Color.Black),
                    strokeLineWidth = 1.8f,
                    strokeLineCap = StrokeCap.Round,
                    strokeLineJoin = StrokeJoin.Round,
                ) {
                    when (icon) {
                        UacIcon.PHOTO -> {
                            moveTo(3f, 7f)
                            lineTo(8f, 7f)
                            lineTo(10f, 4f)
                            lineTo(14f, 4f)
                            lineTo(16f, 7f)
                            lineTo(21f, 7f)
                            lineTo(21f, 20f)
                            lineTo(3f, 20f)
                            close()
                            moveTo(16f, 13f)
                            curveTo(16f, 18f, 8f, 18f, 8f, 13f)
                            curveTo(8f, 8f, 16f, 8f, 16f, 13f)
                            close()
                        }
                        UacIcon.SEARCH -> {
                            moveTo(17f, 10f)
                            curveTo(17f, 19f, 3f, 19f, 3f, 10f)
                            curveTo(3f, 1f, 17f, 1f, 17f, 10f)
                            close()
                            moveTo(15f, 15f)
                            lineTo(21f, 21f)
                        }
                        UacIcon.FILTER -> {
                            moveTo(3f, 5f)
                            lineTo(21f, 5f)
                            lineTo(14f, 13f)
                            lineTo(14f, 20f)
                            lineTo(10f, 18f)
                            lineTo(10f, 13f)
                            close()
                        }
                        UacIcon.LOGOUT -> {
                            moveTo(10f, 4f)
                            lineTo(4f, 4f)
                            lineTo(4f, 20f)
                            lineTo(10f, 20f)
                            moveTo(10f, 12f)
                            lineTo(21f, 12f)
                            moveTo(17f, 8f)
                            lineTo(21f, 12f)
                            lineTo(17f, 16f)
                        }
                        UacIcon.LIKE -> {
                            moveTo(12f, 20f)
                            curveTo(9f, 17f, 3f, 13f, 3f, 8f)
                            curveTo(3f, 3f, 9f, 2f, 12f, 7f)
                            curveTo(15f, 2f, 21f, 3f, 21f, 8f)
                            curveTo(21f, 13f, 15f, 17f, 12f, 20f)
                            close()
                        }
                        UacIcon.BOOKMARK -> {
                            moveTo(6f, 3f)
                            lineTo(18f, 3f)
                            lineTo(18f, 21f)
                            lineTo(12f, 17f)
                            lineTo(6f, 21f)
                            close()
                        }
                        UacIcon.NOTIFICATIONS -> {
                            moveTo(5f, 17f)
                            lineTo(7f, 14f)
                            lineTo(7f, 9f)
                            curveTo(7f, 2f, 17f, 2f, 17f, 9f)
                            lineTo(17f, 14f)
                            lineTo(19f, 17f)
                            close()
                            moveTo(10f, 20f)
                            quadTo(12f, 22f, 14f, 20f)
                        }
                        UacIcon.LOCATION -> {
                            moveTo(12f, 21f)
                            curveTo(8f, 17f, 5f, 12f, 5f, 9f)
                            curveTo(5f, 0f, 19f, 0f, 19f, 9f)
                            curveTo(19f, 12f, 16f, 17f, 12f, 21f)
                            close()
                            moveTo(14f, 9f)
                            curveTo(14f, 12f, 10f, 12f, 10f, 9f)
                            curveTo(10f, 6f, 14f, 6f, 14f, 9f)
                            close()
                        }
                        UacIcon.SECURITY -> {
                            moveTo(12f, 3f)
                            lineTo(20f, 6f)
                            lineTo(20f, 12f)
                            quadTo(20f, 18f, 12f, 22f)
                            quadTo(4f, 18f, 4f, 12f)
                            lineTo(4f, 6f)
                            close()
                            moveTo(8f, 12f)
                            lineTo(11f, 15f)
                            lineTo(16f, 9f)
                        }
                        UacIcon.EDIT -> {
                            moveTo(4f, 16f)
                            lineTo(16f, 4f)
                            lineTo(20f, 8f)
                            lineTo(8f, 20f)
                            lineTo(4f, 20f)
                            close()
                            moveTo(13f, 7f)
                            lineTo(17f, 11f)
                        }
                        UacIcon.HISTORY -> {
                            moveTo(4f, 7f)
                            curveTo(10f, -1f, 22f, 4f, 21f, 13f)
                            curveTo(20f, 23f, 6f, 24f, 3f, 15f)
                            moveTo(3f, 3f)
                            lineTo(3f, 8f)
                            lineTo(8f, 8f)
                            moveTo(12f, 7f)
                            lineTo(12f, 12f)
                            lineTo(16f, 14f)
                        }
                        UacIcon.SUPPORT -> {
                            moveTo(4f, 4f)
                            lineTo(20f, 4f)
                            lineTo(20f, 17f)
                            lineTo(9f, 17f)
                            lineTo(4f, 21f)
                            close()
                            moveTo(8f, 9f)
                            lineTo(16f, 9f)
                            moveTo(8f, 13f)
                            lineTo(13f, 13f)
                        }
                        UacIcon.ANALYTICS -> {
                            moveTo(4f, 3f)
                            lineTo(4f, 21f)
                            lineTo(21f, 21f)
                            moveTo(8f, 17f)
                            lineTo(8f, 12f)
                            moveTo(13f, 17f)
                            lineTo(13f, 6f)
                            moveTo(18f, 17f)
                            lineTo(18f, 9f)
                        }
                        UacIcon.DELETE -> {
                            moveTo(3f, 6f)
                            lineTo(21f, 6f)
                            moveTo(9f, 6f)
                            lineTo(9f, 3f)
                            lineTo(15f, 3f)
                            lineTo(15f, 6f)
                            moveTo(5f, 6f)
                            lineTo(6f, 21f)
                            lineTo(18f, 21f)
                            lineTo(19f, 6f)
                            moveTo(10f, 10f)
                            lineTo(10f, 17f)
                            moveTo(14f, 10f)
                            lineTo(14f, 17f)
                        }
                        UacIcon.PLAY -> {
                            moveTo(8f, 5f)
                            lineTo(19f, 12f)
                            lineTo(8f, 19f)
                            close()
                        }
                        UacIcon.PAUSE -> {
                            moveTo(8f, 5f)
                            lineTo(8f, 19f)
                            moveTo(16f, 5f)
                            lineTo(16f, 19f)
                        }
                        UacIcon.OPEN_ARROW -> {
                            moveTo(6f, 18f)
                            lineTo(18f, 6f)
                            moveTo(7f, 6f)
                            lineTo(18f, 6f)
                            lineTo(18f, 17f)
                        }
                        UacIcon.HOME -> {
                            moveTo(3f, 10f)
                            lineTo(12f, 3f)
                            lineTo(21f, 10f)
                            moveTo(5f, 9f)
                            lineTo(5f, 20f)
                            lineTo(9f, 20f)
                            lineTo(9f, 14f)
                            lineTo(15f, 14f)
                            lineTo(15f, 20f)
                            lineTo(19f, 20f)
                            lineTo(19f, 9f)
                        }
                        UacIcon.CALENDAR -> {
                            moveTo(5f, 5f)
                            lineTo(19f, 5f)
                            quadTo(21f, 5f, 21f, 7f)
                            lineTo(21f, 19f)
                            quadTo(21f, 21f, 19f, 21f)
                            lineTo(5f, 21f)
                            quadTo(3f, 21f, 3f, 19f)
                            lineTo(3f, 7f)
                            quadTo(3f, 5f, 5f, 5f)
                            close()
                            moveTo(7f, 3f)
                            lineTo(7f, 7f)
                            moveTo(17f, 3f)
                            lineTo(17f, 7f)
                            moveTo(3f, 10f)
                            lineTo(21f, 10f)
                            moveTo(7f, 14f)
                            lineTo(9f, 14f)
                            moveTo(14f, 14f)
                            lineTo(16f, 14f)
                            moveTo(7f, 17f)
                            lineTo(9f, 17f)
                        }
                        UacIcon.ORGANIZATIONS -> {
                            moveTo(8f, 21f)
                            lineTo(8f, 3f)
                            lineTo(18f, 3f)
                            lineTo(18f, 21f)
                            moveTo(3f, 21f)
                            lineTo(3f, 10f)
                            lineTo(8f, 10f)
                            moveTo(2f, 21f)
                            lineTo(22f, 21f)
                            moveTo(18f, 12f)
                            lineTo(21f, 12f)
                            lineTo(21f, 21f)
                            moveTo(11f, 7f)
                            lineTo(15f, 7f)
                            moveTo(11f, 11f)
                            lineTo(15f, 11f)
                            moveTo(11f, 15f)
                            lineTo(15f, 15f)
                            moveTo(13f, 18f)
                            lineTo(13f, 21f)
                        }
                        UacIcon.DIRECTORY -> {
                            moveTo(12f, 6f)
                            quadTo(8f, 3f, 3f, 5f)
                            lineTo(3f, 19f)
                            quadTo(8f, 17f, 12f, 20f)
                            quadTo(16f, 17f, 21f, 19f)
                            lineTo(21f, 5f)
                            quadTo(16f, 3f, 12f, 6f)
                            close()
                            moveTo(12f, 6f)
                            lineTo(12f, 20f)
                        }
                        UacIcon.PROFILE -> {
                            moveTo(16f, 7f)
                            curveTo(16f, 12.3f, 8f, 12.3f, 8f, 7f)
                            curveTo(8f, 1.7f, 16f, 1.7f, 16f, 7f)
                            close()
                            moveTo(4f, 21f)
                            lineTo(4f, 19f)
                            curveTo(4f, 12f, 20f, 12f, 20f, 19f)
                            lineTo(20f, 21f)
                        }
                        UacIcon.SETTINGS -> {
                            moveTo(4f, 6f)
                            lineTo(9f, 6f)
                            moveTo(13f, 6f)
                            lineTo(20f, 6f)
                            moveTo(4f, 12f)
                            lineTo(14f, 12f)
                            moveTo(18f, 12f)
                            lineTo(20f, 12f)
                            moveTo(4f, 18f)
                            lineTo(6f, 18f)
                            moveTo(10f, 18f)
                            lineTo(20f, 18f)
                            moveTo(9f, 3f)
                            lineTo(9f, 9f)
                            lineTo(13f, 9f)
                            lineTo(13f, 3f)
                            close()
                            moveTo(14f, 9f)
                            lineTo(14f, 15f)
                            lineTo(18f, 15f)
                            lineTo(18f, 9f)
                            close()
                            moveTo(6f, 15f)
                            lineTo(6f, 21f)
                            lineTo(10f, 21f)
                            lineTo(10f, 15f)
                            close()
                        }
                        UacIcon.BACK -> {
                            moveTo(15f, 5f)
                            lineTo(8f, 12f)
                            lineTo(15f, 19f)
                        }
                        UacIcon.NEWS -> {
                            moveTo(5f, 3f)
                            lineTo(19f, 3f)
                            lineTo(19f, 21f)
                            lineTo(5f, 21f)
                            close()
                            moveTo(8f, 7f)
                            lineTo(16f, 7f)
                            moveTo(8f, 11f)
                            lineTo(16f, 11f)
                            moveTo(8f, 15f)
                            lineTo(16f, 15f)
                            moveTo(8f, 18f)
                            lineTo(12f, 18f)
                        }
                    }
                }
            }
            .build()
    }

@Composable
fun UacSymbol(icon: UacIcon, description: String? = null, modifier: Modifier = Modifier) {
    Icon(icons.getValue(icon), description, modifier.size(24.dp))
}

@Composable
fun UacBrand(modifier: Modifier = Modifier) {
    val original = ImageBitmap.imageResource(R.drawable.uac_logo_lockup)
    Row(
        modifier.clearAndSetSemantics { contentDescription = "Ukrainian Community" },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Canvas(Modifier.size(56.dp)) {
            // The same leading-symbol crop as AdaptiveBrandLockupView in build 65.
            drawImage(
                original,
                srcSize = IntSize((original.height * .82f).toInt(), original.height),
                dstOffset = IntOffset((size.width * .09f).toInt(), 0),
                dstSize = IntSize((size.width * .82f).toInt(), size.height.toInt()),
            )
        }
        Column {
            Text(
                "Ukrainian",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "Community",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

@Composable
fun UacHeader(
    language: String,
    canBack: Boolean,
    onBack: () -> Unit,
    onSettings: () -> Unit,
    compact: Boolean = false,
) {
    val largeText = !compact && LocalDensity.current.fontScale > 1.3f
    Column(
        Modifier.widthIn(max = UacDesign.readableWidth)
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp)
    ) {
        if (largeText) UacBrand(Modifier.padding(horizontal = 4.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            if (canBack)
                IconButton(onBack, Modifier.size(48.dp).testTag("back")) {
                    UacSymbol(UacIcon.BACK, tr(language, "Zurück", "Назад"))
                }
            if (compact)
                Text(
                    "UAC",
                    Modifier.weight(1f).testTag("uac-compact-header-brand"),
                    style = MaterialTheme.typography.titleMedium,
                )
            else if (!largeText) UacBrand(Modifier.weight(1f)) else Spacer(Modifier.weight(1f))
            IconButton(onSettings, Modifier.size(48.dp).testTag("settings")) {
                UacSymbol(UacIcon.SETTINGS, tr(language, "Einstellungen", "Налаштування"))
            }
        }
    }
}

@Composable
fun UacBottomNavigation(selected: PrimaryTab, language: String, onSelect: (PrimaryTab) -> Unit) {
    val density = LocalDensity.current
    val measurer = rememberTextMeasurer()
    val labels = PrimaryTab.entries.map { navigationLabel(it, language) }
    val labelStyle =
        MaterialTheme.typography.labelMedium.copy(
            localeList = LocaleList(language),
            hyphens = Hyphens.Auto,
        )
    Box(
        Modifier.fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 12.dp, vertical = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Surface(
            shape = RoundedCornerShape(28.dp),
            color = MaterialTheme.colorScheme.surface,
            shadowElevation = 5.dp,
            modifier = Modifier.widthIn(max = 600.dp).fillMaxWidth(),
        ) {
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                // Use the actual tab count so the five labels have honest measured widths.
                val labelWidthPx =
                    with(density) {
                        ((maxWidth - 18.dp) / PrimaryTab.entries.size - 8.dp).roundToPx().coerceAtLeast(1)
                    }
                val grid =
                    density.fontScale > 1.3f &&
                        useLargeTextNavigationGrid(
                            density.fontScale,
                            labels.map {
                                measurer
                                    .measure(
                                        it,
                                        style = labelStyle,
                                        constraints = Constraints(maxWidth = labelWidthPx),
                                    )
                                    .lineCount
                            },
                        )
                if (grid) {
                    Column(
                        Modifier.selectableGroup()
                            .semantics { isTraversalGroup = true }
                            .testTag("uac-navigation-grid")
                            .padding(4.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        PrimaryTab.entries.chunked(3).forEach { tabs ->
                            Row(
                                Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                                horizontalArrangement = Arrangement.spacedBy(4.dp),
                            ) {
                                tabs.forEach { tab ->
                                    UacNavigationTab(
                                        tab,
                                        labels[tab.ordinal],
                                        labelStyle,
                                        selected == tab,
                                        false,
                                        onSelect,
                                        Modifier.weight(1f).fillMaxHeight(),
                                    )
                                }
                            }
                        }
                    }
                } else {
                    Row(
                        Modifier.selectableGroup()
                            .semantics { isTraversalGroup = true }
                            .testTag("uac-navigation-row")
                            .height(IntrinsicSize.Min)
                            .padding(4.dp),
                        horizontalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        PrimaryTab.entries.forEach { tab ->
                            UacNavigationTab(
                                tab,
                                labels[tab.ordinal],
                                labelStyle,
                                selected == tab,
                                false,
                                onSelect,
                                Modifier.weight(1f).fillMaxHeight(),
                            )
                        }
                    }
                }
            }
        }
    }
}

private fun navigationLabel(tab: PrimaryTab, language: String): String =
    when (tab) {
        PrimaryTab.HOME -> tr(language, "Start", "Головна")
        PrimaryTab.EVENTS -> tr(language, "Events", "Події")
        PrimaryTab.ORGANIZATIONS -> tr(language, "Organisationen", "Організації")
        PrimaryTab.DIRECTORY -> tr(language, "Ratgeber", "Довідник")
        PrimaryTab.PROFILE -> tr(language, "Profil", "Профіль")
    }

@Composable
private fun UacNavigationTab(
    tab: PrimaryTab,
    label: String,
    labelStyle: TextStyle,
    active: Boolean,
    horizontal: Boolean,
    onSelect: (PrimaryTab) -> Unit,
    modifier: Modifier,
) {
    val icon =
        when (tab) {
            PrimaryTab.HOME -> UacIcon.HOME
            PrimaryTab.EVENTS -> UacIcon.CALENDAR
            PrimaryTab.ORGANIZATIONS -> UacIcon.ORGANIZATIONS
            PrimaryTab.DIRECTORY -> UacIcon.DIRECTORY
            PrimaryTab.PROFILE -> UacIcon.PROFILE
        }
    val color =
        if (active) MaterialTheme.colorScheme.primary
        else MaterialTheme.colorScheme.onSurfaceVariant
    val touch =
        modifier
            .heightIn(min = if (horizontal) 48.dp else 56.dp)
            .clip(RoundedCornerShape(22.dp))
            .background(
                if (active) MaterialTheme.colorScheme.primaryContainer else Color.Transparent
            )
            .selectable(active, role = Role.Tab, onClick = { onSelect(tab) })
            .semantics { traversalIndex = tab.ordinal.toFloat() }
            .testTag("tab-${tab.route}")
    androidx.compose.runtime.CompositionLocalProvider(LocalContentColor provides color) {
        if (horizontal) {
            Row(
                touch.padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                UacSymbol(icon)
                Text(
                    label,
                    Modifier.weight(1f).testTag("tab-label-${tab.route}"),
                    style = labelStyle,
                    textAlign = TextAlign.Start,
                )
            }
        } else {
            Column(
                touch.padding(horizontal = 4.dp, vertical = 6.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(3.dp),
            ) {
                UacSymbol(icon)
                Text(
                    label,
                    Modifier.fillMaxWidth().testTag("tab-label-${tab.route}"),
                    style = labelStyle,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}
