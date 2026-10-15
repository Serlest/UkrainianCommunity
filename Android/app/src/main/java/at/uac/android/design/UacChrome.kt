package at.uac.android.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
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
    CHEVRON_DOWN,
    GRID,
    ARRIVAL, CHECKLIST, ID_CARD, DOCUMENT, GLOBE, MEDICAL, BRAIN, INSURANCE,
    BRIEFCASE, GRADUATION, FAMILY, TRAIN, EURO, HEART_NOTE, COURT,
    WIFI, COMPUTER, GROUP, RUNNER, WHEELCHAIR, CARE, SENIOR,
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
                        UacIcon.ARRIVAL -> {
                            moveTo(4f, 21f); lineTo(20f, 21f); moveTo(12f, 3f); lineTo(12f, 16f)
                            moveTo(8f, 12f); lineTo(12f, 16f); lineTo(16f, 12f)
                            moveTo(5f, 7f); lineTo(8f, 7f)
                        }
                        UacIcon.CHECKLIST -> {
                            moveTo(8f, 5f); lineTo(21f, 5f); moveTo(8f, 12f); lineTo(21f, 12f)
                            moveTo(8f, 19f); lineTo(21f, 19f)
                            moveTo(2f, 5f); lineTo(4f, 7f); lineTo(6f, 3f)
                            moveTo(2f, 12f); lineTo(4f, 14f); lineTo(6f, 10f)
                            moveTo(2f, 19f); lineTo(4f, 21f); lineTo(6f, 17f)
                        }
                        UacIcon.ID_CARD -> {
                            moveTo(2f, 5f); lineTo(22f, 5f); lineTo(22f, 19f); lineTo(2f, 19f); close()
                            moveTo(9f, 10f); curveTo(9f, 13f, 5f, 13f, 5f, 10f)
                            curveTo(5f, 7f, 9f, 7f, 9f, 10f); close()
                            moveTo(4f, 16f); quadTo(7f, 13f, 10f, 16f)
                            moveTo(13f, 10f); lineTo(19f, 10f); moveTo(13f, 14f); lineTo(18f, 14f)
                        }
                        UacIcon.DOCUMENT -> {
                            moveTo(5f, 2f); lineTo(15f, 2f); lineTo(20f, 7f); lineTo(20f, 22f)
                            lineTo(5f, 22f); close(); moveTo(15f, 2f); lineTo(15f, 7f)
                            lineTo(20f, 7f); moveTo(8f, 12f); lineTo(17f, 12f)
                            moveTo(8f, 16f); lineTo(17f, 16f)
                        }
                        UacIcon.GLOBE -> {
                            moveTo(12f, 2f); curveTo(25f, 2f, 25f, 22f, 12f, 22f)
                            curveTo(-1f, 22f, -1f, 2f, 12f, 2f); close()
                            moveTo(2f, 12f); lineTo(22f, 12f)
                            moveTo(12f, 2f); curveTo(4f, 6f, 4f, 18f, 12f, 22f)
                            curveTo(20f, 18f, 20f, 6f, 12f, 2f)
                        }
                        UacIcon.MEDICAL -> {
                            moveTo(4f, 7f); lineTo(20f, 7f); lineTo(20f, 21f); lineTo(4f, 21f); close()
                            moveTo(9f, 7f); lineTo(9f, 4f); lineTo(15f, 4f); lineTo(15f, 7f)
                            moveTo(12f, 10f); lineTo(12f, 18f); moveTo(8f, 14f); lineTo(16f, 14f)
                        }
                        UacIcon.BRAIN -> {
                            moveTo(12f, 20f); lineTo(12f, 6f)
                            curveTo(9f, 1f, 3f, 4f, 4f, 9f); curveTo(1f, 12f, 4f, 17f, 7f, 17f)
                            curveTo(8f, 21f, 11f, 21f, 12f, 20f)
                            moveTo(12f, 6f); curveTo(15f, 1f, 21f, 4f, 20f, 9f)
                            curveTo(23f, 12f, 20f, 17f, 17f, 17f)
                            curveTo(16f, 21f, 13f, 21f, 12f, 20f)
                            moveTo(7f, 11f); lineTo(10f, 13f); moveTo(17f, 10f); lineTo(14f, 13f)
                        }
                        UacIcon.INSURANCE -> {
                            moveTo(12f, 2f); lineTo(21f, 6f); lineTo(21f, 12f)
                            quadTo(21f, 19f, 12f, 23f)
                            quadTo(3f, 19f, 3f, 12f); lineTo(3f, 6f); close()
                            moveTo(8f, 13f); lineTo(11f, 16f); lineTo(17f, 9f)
                        }
                        UacIcon.BRIEFCASE -> {
                            moveTo(3f, 8f); lineTo(21f, 8f); lineTo(21f, 20f); lineTo(3f, 20f); close()
                            moveTo(8f, 8f); lineTo(8f, 4f); lineTo(16f, 4f); lineTo(16f, 8f)
                            moveTo(3f, 13f); lineTo(10f, 15f); lineTo(14f, 15f); lineTo(21f, 13f)
                        }
                        UacIcon.GRADUATION -> {
                            moveTo(2f, 9f); lineTo(12f, 4f); lineTo(22f, 9f); lineTo(12f, 14f); close()
                            moveTo(6f, 12f); lineTo(6f, 18f); quadTo(12f, 22f, 18f, 18f)
                            lineTo(18f, 12f); moveTo(22f, 9f); lineTo(22f, 17f)
                        }
                        UacIcon.FAMILY -> {
                            moveTo(9f, 6f); curveTo(9f, 10f, 3f, 10f, 3f, 6f)
                            curveTo(3f, 2f, 9f, 2f, 9f, 6f); close()
                            moveTo(21f, 6f); curveTo(21f, 10f, 15f, 10f, 15f, 6f)
                            curveTo(15f, 2f, 21f, 2f, 21f, 6f); close()
                            moveTo(1f, 19f); curveTo(1f, 10f, 11f, 10f, 11f, 19f)
                            moveTo(13f, 19f); curveTo(13f, 10f, 23f, 10f, 23f, 19f)
                        }
                        UacIcon.TRAIN -> {
                            moveTo(5f, 3f); lineTo(19f, 3f); lineTo(19f, 18f); lineTo(5f, 18f); close()
                            moveTo(5f, 12f); lineTo(19f, 12f)
                            moveTo(8f, 21f); lineTo(10f, 18f); moveTo(16f, 21f); lineTo(14f, 18f)
                            moveTo(8f, 7f); lineTo(10f, 7f); moveTo(14f, 7f); lineTo(16f, 7f)
                        }
                        UacIcon.EURO -> {
                            moveTo(20f, 5f); curveTo(8f, -1f, 3f, 8f, 6f, 16f)
                            curveTo(8f, 22f, 15f, 23f, 20f, 19f)
                            moveTo(3f, 10f); lineTo(16f, 10f); moveTo(3f, 14f); lineTo(15f, 14f)
                        }
                        UacIcon.HEART_NOTE -> {
                            moveTo(12f, 21f); curveTo(7f, 17f, 2f, 13f, 2f, 8f)
                            curveTo(2f, 2f, 9f, 2f, 12f, 7f)
                            curveTo(15f, 2f, 22f, 2f, 22f, 8f)
                            curveTo(22f, 13f, 17f, 17f, 12f, 21f); close()
                            moveTo(7f, 12f); lineTo(17f, 12f)
                        }
                        UacIcon.COURT -> {
                            moveTo(2f, 8f); lineTo(12f, 3f); lineTo(22f, 8f); close()
                            moveTo(4f, 9f); lineTo(20f, 9f)
                            for (x in listOf(6f, 12f, 18f)) { moveTo(x, 10f); lineTo(x, 18f) }
                            moveTo(3f, 19f); lineTo(21f, 19f); moveTo(2f, 22f); lineTo(22f, 22f)
                        }
                        UacIcon.WIFI -> {
                            moveTo(2f, 8f); quadTo(12f, -1f, 22f, 8f)
                            moveTo(5f, 12f); quadTo(12f, 5f, 19f, 12f)
                            moveTo(8f, 16f); quadTo(12f, 12f, 16f, 16f)
                            moveTo(12f, 20f); lineTo(12f, 21f)
                        }
                        UacIcon.COMPUTER -> {
                            moveTo(2f, 4f); lineTo(22f, 4f); lineTo(22f, 18f); lineTo(2f, 18f)
                            close(); moveTo(12f, 18f); lineTo(12f, 22f)
                            moveTo(7f, 22f); lineTo(17f, 22f)
                        }
                        UacIcon.GROUP -> {
                            moveTo(12f, 9f); curveTo(16f, 9f, 16f, 3f, 12f, 3f)
                            curveTo(8f, 3f, 8f, 9f, 12f, 9f); close()
                            moveTo(4f, 11f); curveTo(7f, 11f, 7f, 6f, 4f, 6f)
                            moveTo(20f, 11f); curveTo(17f, 11f, 17f, 6f, 20f, 6f)
                            moveTo(5f, 21f); curveTo(5f, 8f, 19f, 8f, 19f, 21f)
                            moveTo(1f, 20f); curveTo(0f, 15f, 2f, 13f, 5f, 13f)
                            moveTo(23f, 20f); curveTo(24f, 15f, 22f, 13f, 19f, 13f)
                        }
                        UacIcon.RUNNER -> {
                            moveTo(14f, 5f); curveTo(17f, 5f, 17f, 1f, 14f, 1f)
                            curveTo(11f, 1f, 11f, 5f, 14f, 5f)
                            moveTo(9f, 8f); lineTo(15f, 10f); lineTo(19f, 8f)
                            moveTo(15f, 10f); lineTo(11f, 15f); lineTo(5f, 17f)
                            moveTo(11f, 15f); lineTo(17f, 21f)
                            moveTo(8f, 8f); lineTo(4f, 12f)
                        }
                        UacIcon.WHEELCHAIR -> {
                            moveTo(12f, 3f); curveTo(15f, 3f, 15f, 7f, 12f, 7f)
                            curveTo(9f, 7f, 9f, 3f, 12f, 3f)
                            moveTo(11f, 8f); lineTo(11f, 14f); lineTo(17f, 14f)
                            lineTo(20f, 20f); moveTo(8f, 12f)
                            curveTo(0f, 12f, 2f, 23f, 9f, 22f)
                            quadTo(15f, 22f, 15f, 18f)
                        }
                        UacIcon.CARE -> {
                            moveTo(3f, 13f); lineTo(9f, 13f); lineTo(12f, 17f)
                            lineTo(15f, 13f); lineTo(21f, 13f)
                            moveTo(12f, 3f); lineTo(12f, 9f)
                            moveTo(9f, 6f); lineTo(15f, 6f)
                            moveTo(4f, 17f); quadTo(12f, 24f, 20f, 17f)
                        }
                        UacIcon.SENIOR -> {
                            moveTo(10f, 4f); curveTo(13f, 4f, 13f, 1f, 10f, 1f)
                            curveTo(7f, 1f, 7f, 4f, 10f, 4f)
                            moveTo(10f, 5f); lineTo(13f, 11f); lineTo(8f, 15f)
                            moveTo(13f, 11f); lineTo(18f, 10f); lineTo(18f, 21f)
                            moveTo(8f, 15f); lineTo(5f, 22f)
                            moveTo(13f, 11f); lineTo(15f, 21f)
                        }
                        UacIcon.CHEVRON_DOWN -> {
                            moveTo(5f, 9f)
                            lineTo(12f, 16f)
                            lineTo(19f, 9f)
                        }
                        UacIcon.GRID -> {
                            for (x in listOf(4f, 13f)) for (y in listOf(4f, 13f)) {
                                moveTo(x, y)
                                lineTo(x + 7f, y)
                                lineTo(x + 7f, y + 7f)
                                lineTo(x, y + 7f)
                                close()
                            }
                        }
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
    actionIcon: UacIcon = UacIcon.SETTINGS,
    actionTag: String = "settings",
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
            IconButton(onSettings, Modifier.size(48.dp)
                .then(if (actionIcon == UacIcon.SEARCH) Modifier
                    .clip(RoundedCornerShape(17.dp))
                    .background(MaterialTheme.colorScheme.surface.copy(alpha = .56f))
                    .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(17.dp))
                else Modifier)
                .testTag(actionTag)) {
                UacSymbol(actionIcon, when (actionIcon) {
                    UacIcon.SEARCH -> tr(language, "Suchen", "Пошук")
                    UacIcon.SETTINGS -> tr(language, "Einstellungen", "Налаштування")
                    else -> null
                })
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
            fontSize = 10.sp,
            lineHeight = 12.sp,
            letterSpacing = 0.sp,
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
        PrimaryTab.HOME -> tr(language, "Nachrichten", "Новини")
        PrimaryTab.EVENTS -> tr(language, "Termine", "Події")
        PrimaryTab.ORGANIZATIONS -> tr(language, "Organisation", "Організації")
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
            PrimaryTab.HOME -> UacIcon.NEWS
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
                    Modifier.fillMaxWidth().testTag("tab-label-${tab.route}")
                        .semantics { contentDescription = label },
                    style = labelStyle,
                    textAlign = TextAlign.Center,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
