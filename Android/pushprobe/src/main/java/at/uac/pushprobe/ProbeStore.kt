package at.uac.pushprobe

import android.content.Context
import android.util.AtomicFile
import java.io.File
import org.json.JSONArray
import org.json.JSONObject

/** App-private, no-backup records; only the separate target file contains a FID. */
class ProbeStore(context: Context) {
    private val directory = File(context.noBackupFilesDir, "push-probe")
    private val file = AtomicFile(File(directory, "state.json"))
    private val target = AtomicFile(File(directory, "target.json"))
    private var state = ProbeState()
    @Volatile
    var healthy = true
        private set

    init {
        try {
            check(directory.isDirectory || directory.mkdirs())
            if (file.baseFile.exists()) state = decode(file.readFully().toString(Charsets.UTF_8))
        } catch (_: Exception) {
            healthy = false
        }
    }

    @Synchronized fun snapshot() = state

    @Synchronized
    fun update(transform: (ProbeState) -> ProbeState): ProbeState {
        check(healthy) { "Probe local storage is unavailable" }
        val next = transform(state)
        if (next != state) {
            try {
                write(file, encode(next))
                state = next
            } catch (_: Exception) {
                healthy = false
                error("Probe local storage is unavailable")
            }
        }
        return state
    }

    @Synchronized
    fun clearTarget() {
        try {
            target.delete()
            check(!target.baseFile.exists())
        } catch (_: Exception) {
            healthy = false
            error("Probe target cleanup is unconfirmed")
        }
    }

    /** Scope check, consent mask, target removal and local notification cleanup share one lock. */
    @Synchronized
    fun stop(expected: ProbeCleanupScope?, now: Long, cancelNotifications: () -> Unit): Boolean {
        if (!healthy || (expected != null && !expected.matches(state))) return false
        try {
            update { if (it.optedIn || it.registering) it.optOut(now) else it }
            clearTarget()
        } finally {
            cancelNotifications()
        }
        return true
    }

    @Synchronized
    fun acknowledgeRegistration(generation: Long, fid: String, now: Long) {
        require(ProbeContract.validFid(fid))
        val hash = ProbeContract.hash(fid)
        val next = update { it.registrationAcknowledged(generation, hash, now) }
        if (
            next.generation != generation ||
                !next.optedIn ||
                next.registrationHash != hash ||
                next.registering
        )
            return
        try {
            // Root may read this exact sandbox file into a private work/ file for
            // one synthetic send. Never print/share/copy the FID or a raw token.
            write(
                target,
                JSONObject()
                    .put("projectId", ProbeContract.PROJECT)
                    .put("projectNumber", ProbeContract.NUMBER)
                    .put("appId", ProbeContract.APP)
                    .put("packageName", ProbeContract.PACKAGE)
                    .put("installationId", fid)
                    .put("installationHash", hash)
                    .put("runId", next.runId)
                    .put("generation", next.generation)
                    .put("registeredAtEpochMs", now)
                    .put("runExpiresAtEpochMs", next.runExpiresAt)
                    .toString(),
            )
        } catch (_: Exception) {
            healthy = false
            error("Probe target receipt could not be saved")
        }
    }

    /** The entire small local display operation is serialized with opt-out. */
    @Synchronized
    fun receive(
        data: Map<String, String>,
        sender: String?,
        hasNotification: Boolean,
        allowed: () -> Boolean,
        now: Long,
        display: (ProbeMessage) -> Unit,
    ) {
        if (!healthy) return
        val decision = decideProbeMessage(state, data, sender, hasNotification, allowed(), now)
        val message = decision.message
        if (message == null) {
            update { it.event(decision.refusal ?: ProbeEvent.REJECTED_SCHEMA, now) }
            return
        }
        update {
            it.copy(seen = it.seen + message.probeId)
                .event(ProbeEvent.RECEIVED, now, message.probeId)
        }
        try {
            display(message)
            update { it.event(ProbeEvent.NOTIFY_POSTED, now, message.probeId) }
        } catch (_: Exception) {
            update { it.event(ProbeEvent.DISPLAY_FAILED, now, message.probeId) }
        }
    }

    private fun write(destination: AtomicFile, value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        val stream = destination.startWrite()
        try {
            stream.write(bytes)
            destination.finishWrite(stream)
        } catch (error: Exception) {
            destination.failWrite(stream)
            throw error
        }
        check(destination.readFully().contentEquals(bytes))
    }

    private fun encode(value: ProbeState) =
        JSONObject()
            .put("version", 1)
            .put("generation", value.generation)
            .put("everOptedIn", value.everOptedIn)
            .put("optedIn", value.optedIn)
            .put("runId", value.runId ?: JSONObject.NULL)
            .put("runExpiresAt", value.runExpiresAt)
            .put("registering", value.registering)
            .put("registrationHash", value.registrationHash ?: JSONObject.NULL)
            .put("cleanupPending", value.cleanupPending)
            .put("seen", JSONArray(value.seen))
            .put(
                "receipts",
                JSONArray(
                    value.receipts.map {
                        JSONObject()
                            .put("event", it.event.name)
                            .put("at", it.at)
                            .put("probeId", it.probeId ?: JSONObject.NULL)
                    }
                ),
            )
            .toString()

    private fun decode(raw: String): ProbeState {
        val json = JSONObject(raw)
        check(json.getInt("version") == 1)
        fun optional(key: String) = if (json.isNull(key)) null else json.getString(key)
        val seen =
            json.getJSONArray("seen").let { array ->
                (0 until array.length()).map { array.getString(it) }
            }
        val receipts =
            json.getJSONArray("receipts").let { array ->
                (0 until array.length()).map {
                    val entry = array.getJSONObject(it)
                    ProbeReceipt(
                        ProbeEvent.valueOf(entry.getString("event")),
                        entry.getLong("at"),
                        if (entry.isNull("probeId")) null else entry.getString("probeId"),
                    )
                }
            }
        val decoded =
            ProbeState(
                json.getLong("generation"),
                json.getBoolean("everOptedIn"),
                json.getBoolean("optedIn"),
                optional("runId"),
                json.getLong("runExpiresAt"),
                json.getBoolean("registering"),
                optional("registrationHash"),
                json.getBoolean("cleanupPending"),
                receipts,
                seen,
            )
        check(
            decoded.generation >= 0 &&
                seen.size <= 64 &&
                seen.all(ProbeContract::validId) &&
                receipts.size <= 48 &&
                receipts.all {
                    it.at > 0 && (it.probeId == null || ProbeContract.validId(it.probeId))
                }
        )
        check(decoded.runId == null || ProbeContract.validId(decoded.runId))
        check(
            decoded.registrationHash == null ||
                decoded.registrationHash.matches(Regex("[a-f0-9]{64}"))
        )
        check(
            !decoded.optedIn ||
                (decoded.everOptedIn &&
                    decoded.runId != null &&
                    decoded.runExpiresAt > 0 &&
                    !decoded.cleanupPending)
        )
        check(
            decoded.optedIn ||
                (!decoded.registering && decoded.registrationHash == null && decoded.runId == null)
        )
        return decoded
    }
}
