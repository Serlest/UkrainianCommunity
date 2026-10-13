package at.uac.android.feature.bannermeasurement

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/** One-account queue. A lost acknowledgement retries the same UUID, which the server deduplicates. */
class BannerMeasurementQueue(context: Context, private val clock: () -> Long = System::currentTimeMillis) {
    private val preferences: SharedPreferences = context.applicationContext
        .getSharedPreferences("banner-measurement-v1", Context.MODE_PRIVATE)
    private var owner: String? = null
    private val events = mutableListOf<BannerMeasurement>()

    fun switchPrincipal(principal: String?) {
        if (principal == owner) return
        owner = principal
        events.clear()
        val storedOwner = preferences.getString("queue-owner", null)
        if (principal != null && principal == storedOwner) {
            runCatching {
                val rows = JSONArray(preferences.getString("queue", "[]"))
                for (index in 0 until rows.length()) {
                    val row = rows.getJSONObject(index)
                    events += BannerMeasurement(
                        row.getString("id"), row.getString("bannerID"),
                        row.getString("section"), row.getString("kind"),
                        row.getLong("occurredAtMilliseconds"), row.getString("consentID"),
                    )
                }
            }.onFailure { events.clear() }
        }
        prune()
    }

    fun append(event: BannerMeasurement) {
        prune()
        if (owner == null || events.size >= 100) return
        events += event
        persist()
    }

    fun first(): BannerMeasurement? = events.firstOrNull()

    fun removeFirst() {
        if (events.isNotEmpty()) { events.removeAt(0); persist() }
    }

    fun clear() { events.clear(); persist() }

    fun prune() {
        val cutoff = clock() - 48 * 60 * 60 * 1_000L
        events.removeAll { it.occurredAtMilliseconds < cutoff || it.occurredAtMilliseconds > clock() + 60_000 }
        if (events.size > 100) events.subList(0, events.size - 100).clear()
        persist()
    }

    fun pendingWithdrawal(principal: String): String? = preferences.getString("withdrawal:$principal", null)

    fun setPendingWithdrawal(principal: String, consentId: String?) {
        val edit = preferences.edit()
        if (consentId == null) edit.remove("withdrawal:$principal")
        else edit.putString("withdrawal:$principal", consentId)
        edit.commit()
    }

    private fun persist() {
        val edit = preferences.edit()
        if (owner == null || events.isEmpty()) {
            edit.remove("queue-owner").remove("queue")
        } else {
            val array = JSONArray()
            events.forEach { event ->
                array.put(JSONObject().apply {
                    put("id", event.id)
                    put("bannerID", event.bannerId)
                    put("section", event.section)
                    put("kind", event.kind)
                    put("occurredAtMilliseconds", event.occurredAtMilliseconds)
                    put("consentID", event.consentId)
                })
            }
            edit.putString("queue-owner", owner).putString("queue", array.toString())
        }
        edit.commit()
    }
}
