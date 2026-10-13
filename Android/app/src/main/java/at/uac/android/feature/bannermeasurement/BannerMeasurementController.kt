package at.uac.android.feature.bannermeasurement

import android.content.Context
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.feature.auth.AuthSession
import com.google.firebase.auth.FirebaseAuth
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await

data class BannerMeasurementAuthority(val uid: String, val ready: Boolean)

fun AuthSession.bannerMeasurementAuthority(): BannerMeasurementAuthority? =
    identity?.takeIf { !it.anonymous && it.emailVerified && profile?.uid == it.uid }
        ?.let { BannerMeasurementAuthority(it.uid, readyForActions) }

data class BannerMeasurementState(
    val available: Boolean = false,
    val enabled: Boolean = false,
    val busy: Boolean = false,
    val error: Boolean = false,
    val consentId: String? = null,
)

fun bannerMeasurementController(
    context: Context,
    scope: CoroutineScope,
    current: () -> BannerMeasurementAuthority?,
): BannerMeasurementController = BannerMeasurementController(
    AppBackend.callables(context), AppBackend.auth(context),
    BannerMeasurementQueue(context), scope, current,
)

/** Banner consent is separate from content analytics and has no locally cached grant. */
class BannerMeasurementController(
    private val callables: CallableGateway,
    private val auth: FirebaseAuth,
    private val queue: BannerMeasurementQueue,
    private val scope: CoroutineScope,
    private val current: () -> BannerMeasurementAuthority?,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    companion object {
        const val PRIVACY_VERSION = "2026.21"
        const val DISCLOSURE_VERSION = "2026-10-12.1"
    }

    private val mutable = MutableStateFlow(BannerMeasurementState())
    val state = mutable.asStateFlow()
    private var principal: String? = null
    private var generation = 0L
    private var retryAfter = 0L
    private val delivery = Mutex()

    init { callables.requireBoundTo(auth) }

    fun bind(authority: BannerMeasurementAuthority?) {
        val next = authority?.uid
        if (next != principal) {
            generation++
            principal = next
            queue.switchPrincipal(next)
            mutable.value = BannerMeasurementState()
        }
        if (authority?.ready != true) {
            generation++
            mutable.value = mutable.value.copy(enabled = false, consentId = null)
        } else if (next != null) {
            scope.launch { refresh() }
        }
    }

    suspend fun refresh() {
        val uid = principal ?: return
        if (!eligible(uid) || mutable.value.busy) return
        val ticket = ++generation
        val pending = queue.pendingWithdrawal(uid)
        if (pending != null) {
            if (!sendChoice(uid, false, pending, "de")) {
                if (ticket == generation) mutable.value = mutable.value.copy(
                    enabled = false, consentId = null, error = true,
                )
                return
            }
            queue.setPendingWithdrawal(uid, null)
        }
        try {
            val raw = call("getBannerMeasurementConsent") as? Map<*, *>
                ?: throw IllegalArgumentException("Invalid banner consent state")
            if (ticket != generation || !eligible(uid)) return
            val available = raw["available"] == true
            val consent = raw["consentID"] as? String
            val enabled = available && raw["enabled"] == true && consent != null
            mutable.value = BannerMeasurementState(available, enabled, consentId = if (enabled) consent else null)
            if (!enabled) queue.clear() else deliverPending()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            if (ticket == generation) mutable.value = mutable.value.copy(
                enabled = false, consentId = null, error = true,
            )
        }
    }

    suspend fun setEnabled(enabled: Boolean, locale: String) {
        val uid = principal ?: return
        if (!eligible(uid) || mutable.value.busy) return
        val ticket = ++generation
        if (enabled) {
            if (!mutable.value.available || mutable.value.enabled || queue.pendingWithdrawal(uid) != null) return
            val consentId = UUID.randomUUID().toString()
            mutable.value = mutable.value.copy(busy = true, error = false)
            val confirmed = sendChoice(uid, true, consentId, locale)
            if (ticket == generation && eligible(uid)) mutable.value = mutable.value.copy(
                enabled = confirmed, consentId = if (confirmed) consentId else null,
                busy = false, error = !confirmed,
            )
        } else {
            val consentId = mutable.value.consentId ?: return
            // Stop locally and persist withdrawal before any network operation.
            mutable.value = mutable.value.copy(enabled = false, consentId = null, busy = true)
            queue.clear()
            queue.setPendingWithdrawal(uid, consentId)
            val confirmed = sendChoice(uid, false, consentId, locale)
            if (confirmed) queue.setPendingWithdrawal(uid, null)
            if (ticket == generation) mutable.value = mutable.value.copy(
                busy = false, error = !confirmed,
            )
        }
    }

    fun record(measurement: BannerMeasurement) {
        val uid = principal ?: return
        val consentId = mutable.value.consentId ?: return
        if (!mutable.value.enabled || !eligible(uid) ||
            measurement.section !in setOf("home", "events", "organizations", "directory") ||
            measurement.kind !in setOf("impression", "click") ||
            !Regex("[A-Za-z0-9_-]{1,128}").matches(measurement.bannerId)) return
        queue.append(measurement.copy(consentId = consentId))
        scope.launch { deliverPending() }
    }

    private suspend fun sendChoice(uid: String, enabled: Boolean, consentId: String, locale: String): Boolean =
        try {
            val raw = call("updateBannerMeasurementConsent", mapOf(
                "enabled" to enabled,
                "consentID" to consentId,
                "locale" to if (locale == "uk") "uk" else "de",
                "privacyVersion" to PRIVACY_VERSION,
                "disclosureVersion" to DISCLOSURE_VERSION,
            )) as? Map<*, *>
            eligible(uid) && raw?.get("enabled") == enabled && raw["consentID"] == consentId
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) { false }

    private suspend fun deliverPending() = delivery.withLock {
        val uid = principal ?: return@withLock
        val consentId = mutable.value.consentId ?: return@withLock
        if (!mutable.value.enabled || !eligible(uid) || clock() < retryAfter) return@withLock
        queue.prune()
        while (principal == uid && mutable.value.enabled && mutable.value.consentId == consentId) {
            val event = queue.first() ?: break
            if (event.consentId != consentId) { queue.removeFirst(); continue }
            try {
                val raw = call("recordBannerMeasurement", event.payload()) as? Map<*, *>
                if (principal != uid || mutable.value.consentId != consentId) return@withLock
                if (raw?.get("counted") != true || raw["duplicate"] !is Boolean)
                    throw IllegalArgumentException("Invalid banner measurement receipt")
                queue.removeFirst()
            } catch (error: CancellationException) {
                throw error
            } catch (error: LocalCallableException) {
                when (error.code) {
                    LocalCallableFailure.INVALID_ARGUMENT, LocalCallableFailure.NOT_FOUND -> {
                        queue.removeFirst(); continue
                    }
                    LocalCallableFailure.FAILED_PRECONDITION, LocalCallableFailure.PERMISSION_DENIED,
                    LocalCallableFailure.UNAUTHENTICATED -> {
                        queue.clear()
                        mutable.value = mutable.value.copy(enabled = false, consentId = null, error = true)
                        scope.launch { refresh() }
                    }
                    else -> retryAfter = clock() + if (error.code == LocalCallableFailure.RESOURCE_EXHAUSTED) 300_000 else 60_000
                }
                return@withLock
            } catch (_: Exception) {
                retryAfter = clock() + 60_000
                return@withLock
            }
        }
    }

    private fun eligible(uid: String): Boolean =
        principal == uid && current()?.let { it.uid == uid && it.ready } == true &&
            auth.currentUser?.let { it.uid == uid && !it.isAnonymous && it.isEmailVerified } == true

    private suspend fun call(name: String, payload: Any? = null): Any? =
        callables.getHttpsCallable(name).withTimeout(60, TimeUnit.SECONDS).call(payload).await().data
}
