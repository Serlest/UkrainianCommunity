package at.uac.android.feature.applock

import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import at.uac.android.core.WindowPrivacy
import at.uac.android.feature.auth.AuthStage
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.browse.BrowseViewModel
import kotlinx.coroutines.launch

/** Lifecycle/window wiring stays outside the product screens and never replaces their state. */
class ActivityAppLockHost(private val activity: FragmentActivity, private val auth: AuthStore) :
    AutoCloseable {
    val privacy = WindowPrivacy()
    val model =
        ViewModelProvider(
            activity,
            object : ViewModelProvider.Factory {
                @Suppress("UNCHECKED_CAST")
                override fun <T : ViewModel> create(modelClass: Class<T>): T {
                    check(modelClass == AppLockViewModel::class.java)
                    return AppLockViewModel(
                            DeviceAppLockPreferences(activity),
                            SystemAppLockAuthenticator(auth),
                        )
                        .also { it.observeAuth(auth.state) } as T
                }
            },
        )[AppLockViewModel::class.java]
    private val system
        get() = model.authentication as SystemAppLockAuthenticator

    private val preferences =
        activity.applicationContext.getSharedPreferences(
            "uac-local",
            android.content.Context.MODE_PRIVATE,
        )
    private val mainWindow = privacy.register(activity.window)
    private var paused = true
    private var signingOut = false
    private var renderedSession: AppLockSession? = null
    private var renderConfirmed = false
    private var closed = false
    private val shield =
        AppLockWindowShield(
            activity,
            onUnlock = { if (current()) model.unlock(language()) },
            onPasswordSignIn = ::passwordSignIn,
            onCancel = { if (current()) model.cancelAuthentication() },
        )
    private val protection: () -> Unit = ::synchronize

    init {
        system.attach(activity)
        model.protectionChanged = protection
        synchronize()
    }

    private fun language() = preferences.getString("language", "de").orEmpty()

    private fun current() =
        model.state.value.session != null &&
            model.state.value.session == auth.state.value.appLockSession()

    /** A removed identity must not uncover the previous frame before Compose has masked it. */
    fun rendered(session: AppLockSession?) {
        renderedSession = session
        renderConfirmed = true
        synchronize()
    }

    fun synchronize() {
        if (closed) return
        val state = model.state.value.forSession(auth.state.value.appLockSession())
        val pendingFrame =
            (!renderConfirmed || renderedSession != state.session) &&
                (renderedSession != null || state.session != null)
        val rendered = state.copy(foreground = state.foreground && !paused && !pendingFrame)
        val covered = rendered.blocksInteraction || pendingFrame
        privacy.update(secure = state.needsPrivacyShield || pendingFrame, blocked = covered)
        shield.update(
            rendered,
            language(),
            preferences.getString("theme", "system").orEmpty(),
            signingOut,
            covered,
        )
    }

    fun onResume() {
        paused = false
        model.enterForeground()
        system.onHostResumed()
        synchronize()
    }

    fun onPause() {
        paused = true
        system.onHostPaused()
        synchronize()
    }

    fun onStop() {
        if (!activity.isChangingConfigurations)
            model.enterBackground(system.consumeExpectedCredentialBackground())
        synchronize()
    }

    private fun passwordSignIn() {
        if (signingOut || !current() || !model.state.value.locked) return
        val captured = auth.state.value.appLockSession() ?: return
        signingOut = true
        model.cancelAuthentication()
        synchronize()
        activity.lifecycleScope.launch {
            try {
                if (auth.state.value.appLockSession() != captured) return@launch
                val operation = auth.signOut()
                val issued = auth.state.value.appLockSession()
                operation.join()
                if (
                    auth.state.value.stage == AuthStage.GUEST && auth.state.value.identity == null
                ) {
                    ViewModelProvider(activity)[BrowseViewModel::class.java].navigate(
                        "profile",
                        true,
                    )
                } else if (
                    issued?.uid == captured.uid && auth.state.value.appLockSession() == issued
                )
                    model.signOutFailed()
            } finally {
                signingOut = false
                synchronize()
            }
        }
    }

    override fun close() {
        if (closed) return
        closed = true
        if (model.protectionChanged === protection) model.protectionChanged = null
        system.detach(activity)
        shield.close()
        mainWindow.close()
        privacy.close()
    }
}
