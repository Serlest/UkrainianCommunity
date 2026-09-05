package at.uac.android.feature.startup

import android.animation.ValueAnimator
import android.database.ContentObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner

/** Read-only system preference; failures select the motion-free presentation. */
@Composable
fun rememberStartupReducedMotion(): Boolean {
    val context = LocalContext.current.applicationContext
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    fun reduced() = runCatching { !ValueAnimator.areAnimatorsEnabled() }.getOrDefault(true)
    var value by remember { mutableStateOf(reduced()) }
    DisposableEffect(context, lifecycle) {
        val observer =
            object : ContentObserver(Handler(Looper.getMainLooper())) {
                override fun onChange(selfChange: Boolean) {
                    value = reduced()
                }
            }
        val registered = runCatching {
            context.contentResolver.registerContentObserver(
                Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
                false,
                observer,
            )
        }
            .isSuccess
        if (!registered) value = true
        val lifecycleObserver = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) value = if (registered) reduced() else true
        }
        lifecycle.addObserver(lifecycleObserver)
        onDispose {
            lifecycle.removeObserver(lifecycleObserver)
            if (registered)
                runCatching { context.contentResolver.unregisterContentObserver(observer) }
        }
    }
    return value
}
