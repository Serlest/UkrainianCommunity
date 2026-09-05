package at.uac.android.feature.startup

import android.content.Context
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.view.Surface
import android.view.TextureView
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import at.uac.android.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Decorative, local-only media. TextureView stays in the app window (not a separate SurfaceView
 * window), under the host's existing privacy/input cover. No video frame is extracted into a
 * full-resolution Java/Kotlin Bitmap.
 */
@Composable
internal fun StartupVideoBackground(modifier: Modifier = Modifier) {
    // The static brand remains visible while probing. Cancellation/disposal cannot create
    // a late player, and codec discovery never blocks the real Auth restoration observer.
    val selected by
        produceState<StartupVideoAsset?>(null) {
            value = withContext(Dispatchers.Default) { supportedStartupVideo() }
        }
    val asset = selected ?: return
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val holder = remember(asset) { StartupVideoHolder() }
    DisposableEffect(lifecycle, holder) {
        // Stop synchronously in the lifecycle callback, not after a background
        // recomposition which the Activity may no longer be able to render.
        val observer = LifecycleEventObserver { _, _ ->
            holder.view?.allowPlayback(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED))
        }
        lifecycle.addObserver(observer)
        onDispose {
            lifecycle.removeObserver(observer)
            holder.view?.allowPlayback(false)
        }
    }
    AndroidView(
        factory = { StartupTextureView(it, asset).also { view -> holder.view = view } },
        modifier = modifier,
        onReset = null,
        onRelease = {
            it.close()
            if (holder.view === it) holder.view = null
        },
        update = { it.allowPlayback(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) },
    )
}

private class StartupVideoHolder {
    var view: StartupTextureView? = null
}

internal class StartupTextureView(context: Context, internal val asset: StartupVideoAsset) :
    TextureView(context), TextureView.SurfaceTextureListener {
    private val policy = StartupPlaybackPolicy()
    private var permitted = false
    private var player: MediaPlayer? = null
    private var output: Surface? = null
    private var videoWidth = 0
    private var videoHeight = 0
    internal var playbackGeneration = 0L
        private set

    internal var renderedUpdates = 0L
        private set

    internal val decodedSize: Pair<Int, Int>
        get() = videoWidth to videoHeight

    internal val hasActivePlayer: Boolean
        get() = player != null

    init {
        isOpaque = false
        alpha = 0f // Original static background remains visible until a real rendered frame.
        isClickable = false
        isFocusable = false
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        surfaceTextureListener = this
    }

    fun allowPlayback(value: Boolean) {
        permitted = value
        reconcile()
    }

    private fun reconcile() {
        val change =
            policy.update(permitted && isAttachedToWindow && isHardwareAccelerated, isAvailable)
        if (change.release) releasePlayer()
        change.startToken?.let(::prepare)
    }

    private fun prepare(token: Long) {
        val texture = surfaceTexture ?: return fail(token)
        try {
            playbackGeneration = token
            renderedUpdates = 0
            val candidate = MediaPlayer()
            player = candidate
            output = Surface(texture)
            candidate.setSurface(output)
            candidate.setVolume(0f, 0f)
            candidate.setScreenOnWhilePlaying(false)
            candidate.setOnPreparedListener { prepared ->
                if (player === prepared && policy.current(token)) {
                    try {
                        prepared.setVolume(0f, 0f)
                        prepared.isLooping = true
                        resize(prepared.videoWidth, prepared.videoHeight)
                        prepared.start()
                    } catch (_: Exception) {
                        fail(token)
                    }
                }
            }
            candidate.setOnVideoSizeChangedListener { source, width, height ->
                if (player === source && policy.current(token)) resize(width, height)
            }
            candidate.setOnInfoListener { source, what, _ ->
                if (
                    what == MediaPlayer.MEDIA_INFO_VIDEO_RENDERING_START &&
                        player === source &&
                        policy.current(token)
                )
                    alpha = 1f
                false
            }
            candidate.setOnErrorListener { source, _, _ ->
                if (player === source) fail(token)
                true // The unchanged static fallback is sufficient; never block Auth readiness.
            }
            val resource =
                when (asset) {
                    StartupVideoAsset.ORIGINAL -> R.raw.uac_start_animation
                    StartupVideoAsset.COMPATIBILITY -> R.raw.uac_start_animation_compat
                }
            context.resources.openRawResourceFd(resource).use { descriptor ->
                check(descriptor != null && descriptor.length > 0)
                candidate.setDataSource(
                    descriptor.fileDescriptor,
                    descriptor.startOffset,
                    descriptor.length,
                )
            }
            candidate.prepareAsync()
        } catch (_: Exception) {
            fail(token)
        }
    }

    private fun resize(width: Int, height: Int) {
        videoWidth = width
        videoHeight = height
        val fit = startupAspectFit(this.width, this.height, width, height) ?: return
        setTransform(
            Matrix().apply {
                setScale(
                    fit.scaleX,
                    fit.scaleY,
                    this@StartupTextureView.width / 2f,
                    this@StartupTextureView.height / 2f,
                )
            }
        )
    }

    private fun fail(token: Long) {
        if (policy.fail(token)) releasePlayer()
    }

    private fun releasePlayer() {
        alpha = 0f
        val previous = player
        player = null // Invalidate before release: queued native callbacks cannot revive it.
        if (previous != null) {
            runCatching { previous.setOnPreparedListener(null) }
            runCatching { previous.setOnInfoListener(null) }
            runCatching { previous.setOnErrorListener(null) }
            runCatching { previous.setOnVideoSizeChangedListener(null) }
            runCatching { previous.release() }
        }
        runCatching { output?.release() }
        output = null
    }

    fun close() {
        permitted = false
        policy.close()
        releasePlayer()
        surfaceTextureListener = null
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        reconcile()
    }

    override fun onDetachedFromWindow() {
        policy.update(allowed = false, surface = false)
        releasePlayer()
        super.onDetachedFromWindow()
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
        reconcile()
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) {
        resize(videoWidth, videoHeight)
    }

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        policy.update(allowed = false, surface = false)
        releasePlayer()
        return true // TextureView owns and releases its SurfaceTexture; we own only Surface.
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) {
        if (player != null && alpha == 1f && policy.current(playbackGeneration)) renderedUpdates++
    }
}
