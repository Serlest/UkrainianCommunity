package at.uac.pushprobe

import java.security.MessageDigest
import java.util.UUID

object ProbeContract {
    const val PROJECT = "uac-android-test-20260903"
    const val NUMBER = "966536981122"
    const val APP = "1:966536981122:android:2b617eb5d71f37b8dbe29b"
    const val PACKAGE = "at.serlest.ukrainiancommunity.staging"
    const val CHANNEL = "uac_push_probe"
    const val KIND = "uac-synthetic-push-v1"
    const val RUN_LIFETIME_MS = 60 * 60 * 1_000L
    const val MESSAGE_LIFETIME_MS = 5 * 60 * 1_000L
    const val CLOCK_SKEW_MS = 120 * 1_000L
    val fields =
        setOf("kind", "runId", "targetHash", "probeId", "sentAtEpochMs", "expiresAtEpochMs")

    fun configurationAllowed(
        project: String,
        number: String,
        app: String,
        packageName: String,
        debug: Boolean,
        apiKey: String,
    ): Boolean =
        debug &&
            project == PROJECT &&
            number == NUMBER &&
            app == APP &&
            packageName == PACKAGE &&
            apiKey.matches(Regex("AIza[A-Za-z0-9_-]{35}"))

    fun validId(value: String): Boolean = runCatching {
        UUID.fromString(value).toString() == value
    }
        .getOrDefault(false)

    fun validFid(value: String): Boolean = value.matches(Regex("[A-Za-z0-9_-]{22}"))

    fun hash(value: String): String =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8)).joinToString(
            ""
        ) {
            "%02x".format(it)
        }
}

enum class ProbeEvent {
    OPTED_IN,
    REGISTER_ACK,
    REGISTER_CALLBACK,
    CALLBACK_IGNORED,
    REGISTER_FAILED,
    OPTED_OUT,
    UNREGISTER_ACK,
    UNREGISTER_CALLBACK,
    UNREGISTER_FAILED,
    RECEIVED,
    NOTIFY_POSTED,
    TAPPED,
    REJECTED_CONSENT,
    REJECTED_PERMISSION,
    REJECTED_SCHEMA,
    REJECTED_SENDER,
    REJECTED_TARGET,
    REJECTED_EXPIRED,
    REJECTED_DUPLICATE,
    REJECTED_CAPACITY,
    DISPLAY_FAILED,
    DELETED_MESSAGES,
    STORAGE_FAILED,
    CONFIGURATION_BLOCKED,
}

data class ProbeReceipt(val event: ProbeEvent, val at: Long, val probeId: String? = null)

data class ProbeCleanupScope(val generation: Long, val runId: String) {
    fun matches(state: ProbeState): Boolean =
        (state.generation == generation && state.optedIn && state.runId == runId) ||
            (state.generation == generation + 1 && !state.optedIn && state.runId == null)
}

data class ProbeState(
    val generation: Long = 0,
    val everOptedIn: Boolean = false,
    val optedIn: Boolean = false,
    val runId: String? = null,
    val runExpiresAt: Long = 0,
    val registering: Boolean = false,
    val registrationHash: String? = null,
    val cleanupPending: Boolean = false,
    val receipts: List<ProbeReceipt> = emptyList(),
    val seen: List<String> = emptyList(),
) {
    fun event(event: ProbeEvent, now: Long, probeId: String? = null) =
        copy(
            receipts =
                (receipts + ProbeReceipt(event, now, probeId?.takeIf(ProbeContract::validId)))
                    .takeLast(48)
        )

    fun optIn(now: Long, newRun: String): ProbeState {
        require(!optedIn && !registering && !cleanupPending && ProbeContract.validId(newRun))
        return copy(
                generation = generation + 1,
                everOptedIn = true,
                optedIn = true,
                runId = newRun,
                runExpiresAt = now + ProbeContract.RUN_LIFETIME_MS,
                registering = true,
                registrationHash = null,
                seen = emptyList(),
            )
            .event(ProbeEvent.OPTED_IN, now)
    }

    fun optOut(now: Long): ProbeState =
        copy(
                generation = generation + 1,
                optedIn = false,
                registering = false,
                registrationHash = null,
                cleanupPending = everOptedIn,
                runId = null,
                runExpiresAt = 0,
                seen = emptyList(),
            )
            .event(ProbeEvent.OPTED_OUT, now)

    fun registrationAcknowledged(captured: Long, hash: String, now: Long): ProbeState =
        if (
            generation != captured ||
                !optedIn ||
                !registering ||
                cleanupPending ||
                now >= runExpiresAt
        )
            this
        else copy(registering = false, registrationHash = hash).event(ProbeEvent.REGISTER_ACK, now)

    fun unregistrationAcknowledged(captured: Long, now: Long): ProbeState =
        if (generation != captured || optedIn) this
        else copy(cleanupPending = false).event(ProbeEvent.UNREGISTER_ACK, now)
}

data class ProbeMessage(
    val probeId: String,
    val runId: String,
    val targetHash: String,
    val expiresAt: Long,
)

data class ProbeDecision(val message: ProbeMessage? = null, val refusal: ProbeEvent? = null)

/** Untrusted push text never becomes a notification title, body, URL, or route. */
fun decideProbeMessage(
    state: ProbeState,
    data: Map<String, String>,
    sender: String?,
    hasNotification: Boolean,
    notificationsAllowed: Boolean,
    now: Long,
): ProbeDecision {
    fun reject(event: ProbeEvent) = ProbeDecision(refusal = event)
    if (
        !state.optedIn ||
            state.registering ||
            state.cleanupPending ||
            state.registrationHash == null
    )
        return reject(ProbeEvent.REJECTED_CONSENT)
    if (!notificationsAllowed) return reject(ProbeEvent.REJECTED_PERMISSION)
    if (sender != ProbeContract.NUMBER) return reject(ProbeEvent.REJECTED_SENDER)
    if (hasNotification || data.keys != ProbeContract.fields || data["kind"] != ProbeContract.KIND)
        return reject(ProbeEvent.REJECTED_SCHEMA)
    val id = data["probeId"].orEmpty()
    val run = data["runId"].orEmpty()
    val target = data["targetHash"].orEmpty()
    val sent = data["sentAtEpochMs"]?.toLongOrNull() ?: return reject(ProbeEvent.REJECTED_SCHEMA)
    val expiry =
        data["expiresAtEpochMs"]?.toLongOrNull() ?: return reject(ProbeEvent.REJECTED_SCHEMA)
    if (
        !ProbeContract.validId(id) ||
            !ProbeContract.validId(run) ||
            !target.matches(Regex("[a-f0-9]{64}"))
    )
        return reject(ProbeEvent.REJECTED_SCHEMA)
    if (run != state.runId || target != state.registrationHash)
        return reject(ProbeEvent.REJECTED_TARGET)
    if (
        sent <= 0 ||
            expiry <= sent ||
            expiry - sent > ProbeContract.MESSAGE_LIFETIME_MS ||
            sent > now + ProbeContract.CLOCK_SKEW_MS ||
            expiry <= now ||
            now >= state.runExpiresAt
    )
        return reject(ProbeEvent.REJECTED_EXPIRED)
    if (id in state.seen) return reject(ProbeEvent.REJECTED_DUPLICATE)
    // This bounded probe never evicts a seen ID and accidentally replays it.
    // A fresh explicit run is required after 64 unique accepted messages.
    if (state.seen.size >= 64) return reject(ProbeEvent.REJECTED_CAPACITY)
    return ProbeDecision(message = ProbeMessage(id, run, target, expiry))
}
