package at.uac.android.feature.push

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import at.uac.android.BuildConfig
import at.uac.android.core.backend.AppBackend
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.inbox.InboxPreferences
import at.uac.android.feature.inbox.InboxSource
import at.uac.android.feature.inbox.localInboxSource
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/** Application-scoped owner shared by Activity recreation and FirebaseMessagingService. */
class MainPushRuntime
private constructor(
    context: Context,
    private val auth: AuthStore,
    private val source: InboxSource,
    private val scope: CoroutineScope,
) {
    private val appContext = context.applicationContext
    private val nativeAuth = AppBackend.auth(appContext)
    private val current = AtomicReference<PushSession?>()
    private val consent = AtomicBoolean(false)
    private val inboxRefresh = AtomicReference<(() -> Unit)?>(null)
    private val announcementOpen = AtomicReference<((String) -> Unit)?>(null)
    private val announcementChallenge = AtomicReference<((String) -> Unit)?>(null)
    private val tokenSource = FirebasePushTokenSource(AppBackend.app(appContext))
    private val coordinator =
        PushCoordinator(
            FirebasePushRegistrationBackend(
                AppBackend.firestore(appContext),
                nativeAuth,
                AppBackend.callables(appContext),
            ),
            PrivatePushOwnershipStore(appContext),
            tokenSource,
            current::get,
            ::deviceName,
            { BuildConfig.VERSION_NAME },
        )
    private val controller =
        PushController(
            coordinator,
            current::get,
            { PushGate(consent.get(), notificationsGranted()) },
            deliver = {},
            syncInbox = { inboxRefresh.get()?.invoke() },
            openAnnouncement = { id -> announcementOpen.get()?.invoke(id) },
            confirmAnnouncementChallenge = { value ->
                announcementChallenge.get()?.invoke(value)
            },
            scope = scope,
        )

    init {
        PushNotificationChannel.ensure(appContext)
        controller.start()
        auth.setBeforeExplicitSignOut { captured -> prepareSignOut(captured) }
        scope.launch {
            auth.state.collectLatest { state ->
                val session = state.pushSession()
                current.set(session)
                if (session?.verifiedActive != true) {
                    if (session == null) consent.set(false)
                    return@collectLatest
                }
                val enabled = runCatching {
                    withTimeout(15_000) { source.preferences(session.uid) }
                }
                    .getOrElse {
                        if (current.get() == session) {
                            consent.set(false)
                            controller.refresh()?.join()
                        }
                        return@collectLatest
                    }
                    .notificationsEnabled
                if (current.get() == session) {
                    consent.set(enabled)
                    controller.refresh()?.join()
                }
            }
        }
    }

    fun preferencesChanged(sessionUid: String, preferences: InboxPreferences) {
        val session = current.get() ?: return
        if (session.uid != sessionUid || !session.verifiedActive) return
        consent.set(preferences.notificationsEnabled)
        controller.refresh()
    }

    fun permissionChanged() {
        controller.refresh()
    }

    fun bindInboxRefresh(callback: () -> Unit): AutoCloseable {
        inboxRefresh.set(callback)
        return AutoCloseable { inboxRefresh.compareAndSet(callback, null) }
    }

    fun bindAnnouncements(
        open: (String) -> Unit,
        challenge: (String) -> Unit,
    ): AutoCloseable {
        announcementOpen.set(open)
        announcementChallenge.set(challenge)
        return AutoCloseable {
            announcementOpen.compareAndSet(open, null)
            announcementChallenge.compareAndSet(challenge, null)
        }
    }

    private suspend fun prepareSignOut(captured: AuthSession) {
        val uid = captured.identity?.takeUnless { it.anonymous }?.uid ?: return
        val result = coordinator.beforeExplicitSignOut(uid) { nativeAuth.currentUser?.uid == uid }
        if (result.failure != null) {
            throw AuthException(
                when (result.failure) {
                    PushFailure.OFFLINE -> AuthProblem.NETWORK
                    PushFailure.CROSS_ACCOUNT,
                    PushFailure.STALE_SESSION,
                    PushFailure.SIGN_IN -> AuthProblem.SESSION_CHANGED
                    else -> AuthProblem.UNKNOWN
                }
            )
        }
        consent.set(false)
    }

    private fun notificationsGranted(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(appContext, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED

    private fun deviceName(): String =
        listOf(Build.MANUFACTURER, Build.MODEL)
            .joinToString(" ")
            .filterNot(Char::isISOControl)
            .trim()
            .take(160)

    companion object {
        @Volatile private var instance: MainPushRuntime? = null

        @Synchronized
        fun get(context: Context, auth: AuthStore): MainPushRuntime {
            check(!BuildConfig.USE_LOCAL_BACKEND) { "PUSH_UNAVAILABLE_IN_LOCAL_BUILD" }
            return instance
                ?: MainPushRuntime(
                        context.applicationContext,
                        auth,
                        localInboxSource(context.applicationContext),
                        CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate),
                    )
                    .also { instance = it }
        }
    }
}

private fun AuthSession.pushSession(): PushSession? {
    val identity = identity?.takeUnless { it.anonymous } ?: return null
    return PushSession(
        identity.uid,
        revision,
        readyForActions && profile?.active == true && profile.uid == identity.uid,
    )
}
