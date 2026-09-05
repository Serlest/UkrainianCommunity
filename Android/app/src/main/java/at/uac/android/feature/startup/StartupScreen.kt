package at.uac.android.feature.startup

import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import at.uac.android.R
import at.uac.android.design.LocalUacDark
import at.uac.android.design.UacDesign

/**
 * Presentation only. The host owns the one-shot gate and must hide underlying input/semantics and
 * defer navigation while covered. No authentication or media result is manufactured here.
 * videoContent is injectable only for UI tests.
 */
@Composable
fun StartupScreen(
    language: String,
    reduceMotion: Boolean,
    playbackAllowed: Boolean,
    modifier: Modifier = Modifier,
    videoContent: @Composable (Modifier) -> Unit = { StartupVideoBackground(it) },
) {
    val overlay =
        if (LocalUacDark.current)
            listOf(
                Color(0xFF04060A).copy(alpha = .52f),
                Color(0xFF05080E).copy(alpha = .58f),
                Color(0xFF030408).copy(alpha = .66f),
            )
        else
            listOf(
                Color.White.copy(alpha = .12f),
                Color.White.copy(alpha = .08f),
                UacDesign.yellow.copy(alpha = .06f),
            )
    val loading = if (language == "de") "UAC wird geladen …" else "Завантаження UAC…"
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { appeared = true }
    val reveal by
        animateFloatAsState(
            if (appeared || reduceMotion) 1f else 0f,
            animationSpec = tween(if (reduceMotion) 0 else 350, easing = LinearOutSlowInEasing),
            label = "startup-brand-reveal",
        )
    BoxWithConstraints(
        modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
            .testTag("startup.splash")
    ) {
        Image(
            painterResource(R.drawable.uac_background),
            contentDescription = null,
            modifier = Modifier.fillMaxSize().testTag("startup.static"),
            contentScale = ContentScale.Crop,
        )
        if (!reduceMotion && playbackAllowed)
            videoContent(Modifier.fillMaxSize().testTag("startup.video"))
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(overlay)))
        val symbolSize = if (maxHeight < 320.dp) 80.dp else 132.dp
        Column(
            Modifier.fillMaxSize()
                .safeDrawingPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Column(
                Modifier.widthIn(max = 360.dp)
                    .fillMaxWidth()
                    .graphicsLayer {
                        alpha = if (reduceMotion) 1f else reveal
                        val scale = if (reduceMotion) 1f else .92f + .08f * reveal
                        scaleX = scale
                        scaleY = scale
                    }
                    .testTag("startup.logo")
                    .clearAndSetSemantics { contentDescription = "Ukrainian Community" },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                val original = ImageBitmap.imageResource(R.drawable.uac_logo_lockup)
                Canvas(Modifier.size(symbolSize)) {
                    // Same exact leading-symbol crop as iOS AdaptiveBrandLockupView.
                    drawImage(
                        original,
                        srcSize = IntSize((original.height * .82f).toInt(), original.height),
                        dstOffset = IntOffset((size.width * .09f).toInt(), 0),
                        dstSize = IntSize((size.width * .82f).toInt(), size.height.toInt()),
                    )
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        "Ukrainian",
                        style = MaterialTheme.typography.headlineLarge,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.onBackground,
                        textAlign = TextAlign.Center,
                    )
                    Text(
                        "Community",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            val progress =
                Modifier.padding(top = 20.dp)
                    .size(20.dp)
                    .testTag("startup.progress")
                    .clearAndSetSemantics {
                        contentDescription = loading
                        progressBarRangeInfo = ProgressBarRangeInfo.Indeterminate
                    }
            if (reduceMotion)
                CircularProgressIndicator(
                    progress = { .75f },
                    modifier = progress,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    strokeWidth = 2.dp,
                )
            else
                CircularProgressIndicator(
                    modifier = progress,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    strokeWidth = 2.dp,
                )
        }
    }
}
