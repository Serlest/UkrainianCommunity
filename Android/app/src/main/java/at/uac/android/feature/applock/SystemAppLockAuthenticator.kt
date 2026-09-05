package at.uac.android.feature.applock

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import at.uac.android.feature.auth.AuthLocalUnlockToken
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.browse.tr
import java.lang.ref.WeakReference
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Stable AndroidX adapter, retained with AppLockViewModel and reattached on Activity recreation.
 */
class SystemAppLockAuthenticator(private val auth: AuthStore? = null) : AppLockAuthenticating {
    private enum class Phase {
        BIOMETRIC,
        CREDENTIAL,
    }

    private class Pending(
        val attempt: AppLockAttempt,
        val language: String,
        val continuation: CancellableContinuation<AppLockResult>,
    ) {
        var phase = Phase.BIOMETRIC
        var cancelled = false
        var credentialBackgroundAvailable = false
        var deferred: AppLockResult? = null
        var foregroundToken: AuthLocalUnlockToken? = null
    }

    private var host = WeakReference<FragmentActivity>(null)
    private var prompt: BiometricPrompt? = null
    private var credentialLauncher: ActivityResultLauncher<android.content.Intent>? = null
    private var pending: Pending? = null
    private var resumed = false
    private var legacyBiometricLockedOut = false
    private val main = Handler(Looper.getMainLooper())

    /** Call during every onCreate, before STARTED, including after rotation. */
    fun attach(activity: FragmentActivity) {
        if (host.get() === activity) return
        host = WeakReference(activity)
        resumed = false
        credentialLauncher =
            activity.activityResultRegistry.register(
                "uac-app-lock-credential",
                activity,
                ActivityResultContracts.StartActivityForResult(),
            ) { result ->
                val request = pending ?: return@register
                if (request.phase != Phase.CREDENTIAL) return@register
                finish(
                    request,
                    if (result.resultCode == Activity.RESULT_OK) AppLockResult.ACCEPTED
                    else AppLockResult.CANCELLED,
                )
            }
        pending
            ?.takeIf { it.phase == Phase.BIOMETRIC }
            ?.let { request ->
                // Reconnect only. Calling authenticate again would start a second system request.
                prompt = biometricPrompt(activity, request)
                if (request.cancelled) prompt?.cancelAuthentication()
            }
    }

    fun detach(activity: FragmentActivity) {
        if (host.get() !== activity) return
        if (!activity.isChangingConfigurations) {
            pending?.let { request ->
                cancel(request.attempt)
                finish(request, AppLockResult.CANCELLED)
            }
        }
        resumed = false
        host.clear()
        credentialLauncher = null
        prompt = null
    }

    fun onHostPaused() {
        resumed = false
    }

    /** Root calls AppLockViewModel.enterForeground first, and AuthStore.onForeground afterwards. */
    fun onHostResumed() {
        resumed = true
        val request = pending ?: return
        request.deferred?.let { result ->
            request.deferred = null
            finish(request, result)
        }
    }

    fun consumeExpectedCredentialBackground(): AppLockAttempt? {
        val request = pending ?: return null
        if (
            request.cancelled ||
                request.phase != Phase.CREDENTIAL ||
                !request.credentialBackgroundAvailable
        )
            return null
        request.credentialBackgroundAvailable = false
        return request.attempt
    }

    override fun availability(): AppLockAvailability {
        val context = host.get() ?: return AppLockAvailability()
        val strong =
            !legacyBiometricLockedOut &&
                BiometricManager.from(context)
                    .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) ==
                    BiometricManager.BIOMETRIC_SUCCESS
        val credential =
            (context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager)
                ?.isDeviceSecure == true
        return AppLockAvailability(strong, credential)
    }

    override suspend fun authenticate(attempt: AppLockAttempt, language: String): AppLockResult {
        if (pending != null) throw AppLockException(AppLockProblem.BUSY)
        val activity =
            host.get()?.takeIf { resumed && !it.isFinishing && !it.isDestroyed }
                ?: throw AppLockException(AppLockProblem.UNAVAILABLE)
        val available = availability()
        val policy = appLockPromptPolicy(Build.VERSION.SDK_INT, available)
        if (policy == AppLockPromptPolicy.UNAVAILABLE) return AppLockResult.UNAVAILABLE
        return suspendCancellableCoroutine { continuation ->
            val request = Pending(attempt, language, continuation)
            pending = request
            continuation.invokeOnCancellation { onMain { cancel(attempt) } }
            try {
                if (policy == AppLockPromptPolicy.LEGACY_CREDENTIAL) launchCredential(request)
                else {
                    val info =
                        BiometricPrompt.PromptInfo.Builder()
                            .setTitle(tr(language, "App-Sperre", "Блокування застосунку"))
                            .setSubtitle(
                                tr(
                                    language,
                                    "Bestätige den Zugriff auf dein Konto.",
                                    "Підтвердьте доступ до свого облікового запису.",
                                )
                            )
                            .setConfirmationRequired(true)
                    if (policy == AppLockPromptPolicy.STRONG_OR_CREDENTIAL) {
                        info.setAllowedAuthenticators(
                            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                                BiometricManager.Authenticators.DEVICE_CREDENTIAL
                        )
                    } else {
                        info
                            .setAllowedAuthenticators(
                                BiometricManager.Authenticators.BIOMETRIC_STRONG
                            )
                            .setNegativeButtonText(
                                if (available.deviceCredential)
                                    tr(language, "Gerätecode verwenden", "Використати код пристрою")
                                else tr(language, "Abbrechen", "Скасувати")
                            )
                    }
                    prompt =
                        biometricPrompt(activity, request).also { it.authenticate(info.build()) }
                }
            } catch (_: Exception) {
                finish(request, AppLockResult.ERROR)
            }
        }
    }

    override fun cancel(attempt: AppLockAttempt) {
        val request = pending?.takeIf { it.attempt === attempt } ?: return
        request.cancelled = true
        request.foregroundToken?.let { auth?.cancelLocalUnlock(it) }
        request.foregroundToken = null
        request.credentialBackgroundAvailable = false
        if (request.deferred != null) {
            request.deferred = null
            finish(request, AppLockResult.CANCELLED)
            return
        }
        if (request.phase == Phase.BIOMETRIC) runCatching { prompt?.cancelAuthentication() }
        // Keep the native request quarantined until its terminal callback. A new
        // identity must never reuse an old prompt/Keyguard result as a fresh success.
    }

    private fun biometricPrompt(activity: FragmentActivity, request: Pending) =
        BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    result: BiometricPrompt.AuthenticationResult
                ) {
                    if (pending === request && request.phase == Phase.BIOMETRIC)
                        finish(request, AppLockResult.ACCEPTED)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    if (pending !== request || request.phase != Phase.BIOMETRIC) return
                    if (
                        !request.cancelled &&
                            Build.VERSION.SDK_INT < 30 &&
                            errorCode == BiometricPrompt.ERROR_NEGATIVE_BUTTON &&
                            availability().deviceCredential
                    ) {
                        launchCredential(request)
                        return
                    }
                    if (
                        Build.VERSION.SDK_INT < 30 &&
                            errorCode in
                                setOf(
                                    BiometricPrompt.ERROR_LOCKOUT,
                                    BiometricPrompt.ERROR_LOCKOUT_PERMANENT,
                                )
                    )
                        legacyBiometricLockedOut = true
                    finish(
                        request,
                        when (errorCode) {
                            BiometricPrompt.ERROR_USER_CANCELED,
                            BiometricPrompt.ERROR_CANCELED,
                            BiometricPrompt.ERROR_NEGATIVE_BUTTON -> AppLockResult.CANCELLED
                            BiometricPrompt.ERROR_LOCKOUT,
                            BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> AppLockResult.LOCKED_OUT
                            BiometricPrompt.ERROR_NO_BIOMETRICS,
                            BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
                            BiometricPrompt.ERROR_HW_NOT_PRESENT,
                            BiometricPrompt.ERROR_HW_UNAVAILABLE,
                            BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED ->
                                AppLockResult.UNAVAILABLE
                            else -> AppLockResult.ERROR
                        },
                    )
                }
                // onAuthenticationFailed is non-terminal; the system UI owns retry feedback.
            },
        )

    @Suppress("DEPRECATION") // Required only for the explicitly supported API 26–29 fallback.
    private fun launchCredential(request: Pending) {
        if (pending !== request || request.cancelled) return
        val context = host.get()
        val manager = context?.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
        val intent =
            manager
                ?.takeIf { it.isDeviceSecure }
                ?.createConfirmDeviceCredentialIntent(
                    tr(request.language, "App-Sperre", "Блокування застосунку"),
                    tr(
                        request.language,
                        "Bestätige den Zugriff auf dein Konto.",
                        "Підтвердьте доступ до свого облікового запису.",
                    ),
                )
        if (intent == null || credentialLauncher == null) {
            finish(request, AppLockResult.UNAVAILABLE)
            return
        }
        val token =
            auth?.beginLocalUnlock(request.attempt.session.uid, request.attempt.session.revision)
        if (auth != null && token == null) {
            finish(request, AppLockResult.CANCELLED)
            return
        }
        request.foregroundToken = token
        request.phase = Phase.CREDENTIAL
        request.credentialBackgroundAvailable = true
        prompt = null
        try {
            credentialLauncher!!.launch(intent)
        } catch (_: Exception) {
            request.foregroundToken?.let { auth?.cancelLocalUnlock(it) }
            request.foregroundToken = null
            request.credentialBackgroundAvailable = false
            finish(request, AppLockResult.ERROR)
        }
    }

    private fun finish(request: Pending, result: AppLockResult) {
        if (pending !== request) return
        if (!resumed && !request.cancelled) {
            request.deferred = result
            return
        }
        request.foregroundToken?.let { auth?.finishLocalUnlock(it) }
        request.foregroundToken = null
        if (
            !request.cancelled &&
                result == AppLockResult.ACCEPTED &&
                request.phase == Phase.CREDENTIAL
        )
            legacyBiometricLockedOut = false
        pending = null
        prompt = null
        if (request.continuation.isActive)
            request.continuation.resume(if (request.cancelled) AppLockResult.CANCELLED else result)
    }

    private fun onMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else main.post { action() }
    }
}
