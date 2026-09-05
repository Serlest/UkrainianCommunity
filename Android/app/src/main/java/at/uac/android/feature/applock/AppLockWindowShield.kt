package at.uac.android.feature.applock

import android.app.Dialog
import android.graphics.drawable.ColorDrawable
import android.view.View
import android.view.Window
import android.view.WindowManager
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.core.view.WindowCompat
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.setViewTreeLifecycleOwner
import androidx.lifecycle.setViewTreeViewModelStoreOwner
import androidx.savedstate.setViewTreeSavedStateRegistryOwner
import at.uac.android.design.UacTheme

/** A distinct modal window covers existing editor/dialog windows without disposing their state. */
class AppLockWindowShield(
    private val activity: FragmentActivity,
    onUnlock: () -> Unit,
    onPasswordSignIn: () -> Unit,
    onCancel: () -> Unit,
) : AutoCloseable {
    private var state by mutableStateOf(AppLockState())
    private var language by mutableStateOf("de")
    private var theme by mutableStateOf("system")
    private var signingOut by mutableStateOf(false)
    private var requested = false
    private var closed = false
    private val dialog =
        Dialog(activity, android.R.style.Theme_Material_Light_NoActionBar).apply {
            requestWindowFeature(Window.FEATURE_NO_TITLE)
            setCancelable(false)
            setCanceledOnTouchOutside(false)
        }
    private val content =
        ComposeView(activity).apply {
            id = View.generateViewId()
            setViewCompositionStrategy(
                ViewCompositionStrategy.DisposeOnDetachedFromWindowOrReleasedFromPool
            )
            setContent {
                UacTheme(theme) {
                    Surface(Modifier.fillMaxSize()) {
                        androidx.compose.foundation.layout.Box(Modifier.safeDrawingPadding()) {
                            AppLockScreen(
                                state,
                                language,
                                onUnlock,
                                onPasswordSignIn,
                                onCancel,
                                signingOut,
                            )
                        }
                    }
                }
            }
        }
    private val attach =
        object : View.OnAttachStateChangeListener {
            override fun onViewAttachedToWindow(view: View) {
                showIfReady()
            }

            override fun onViewDetachedFromWindow(view: View) = Unit
        }

    init {
        val window = requireNotNull(dialog.window)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        window.setBackgroundDrawable(ColorDrawable(android.graphics.Color.WHITE))
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.decorView.setViewTreeLifecycleOwner(activity)
        window.decorView.setViewTreeViewModelStoreOwner(activity)
        window.decorView.setViewTreeSavedStateRegistryOwner(activity)
        dialog.setContentView(content)
        activity.window.decorView.addOnAttachStateChangeListener(attach)
    }

    fun update(
        value: AppLockState,
        selectedLanguage: String,
        selectedTheme: String,
        busySigningOut: Boolean,
        visible: Boolean,
    ) {
        if (closed) return
        state = value
        language = selectedLanguage
        theme = selectedTheme
        signingOut = busySigningOut
        val dark =
            selectedTheme == "dark" ||
                selectedTheme == "system" &&
                    activity.resources.configuration.uiMode and
                        android.content.res.Configuration.UI_MODE_NIGHT_MASK ==
                        android.content.res.Configuration.UI_MODE_NIGHT_YES
        dialog.window?.setBackgroundDrawable(
            ColorDrawable(
                if (dark) android.graphics.Color.rgb(18, 18, 18) else android.graphics.Color.WHITE
            )
        )
        requested = visible
        if (visible) showIfReady() else if (dialog.isShowing) dialog.dismiss()
    }

    private fun showIfReady() {
        if (
            !requested ||
                closed ||
                dialog.isShowing ||
                activity.isFinishing ||
                activity.isDestroyed ||
                !activity.window.decorView.isAttachedToWindow
        )
            return
        dialog.show()
        dialog.window?.setLayout(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
        )
    }

    override fun close() {
        if (closed) return
        closed = true
        activity.window.decorView.removeOnAttachStateChangeListener(attach)
        dialog.dismiss()
        content.disposeComposition()
    }
}
