package at.uac.android.feature.bannermeasurement

import java.util.UUID

data class BannerMeasurement(
    val id: String,
    val bannerId: String,
    val section: String,
    val kind: String,
    val occurredAtMilliseconds: Long,
    val consentId: String = "",
) {
    fun payload(): Map<String, Any> = mapOf(
        "id" to id,
        "bannerID" to bannerId,
        "section" to section,
        "kind" to kind,
        "occurredAtMilliseconds" to occurredAtMilliseconds,
        "consentID" to consentId,
    )
}

/** Mirrors the iOS exposure contract; consent and delivery are enforced separately. */
class BannerExposureTracker(private val id: () -> String = { UUID.randomUUID().toString() }) {
    private var currentId: String? = null
    private var visibleSince: Long? = null
    private var counted = false
    private val lastImpression = mutableMapOf<String, Long>()
    private val lastClick = mutableMapOf<String, Long>()

    fun observe(
        bannerId: String?, section: String, visibleFraction: Float,
        eligible: Boolean, now: Long,
    ): BannerMeasurement? {
        if (!eligible || visibleFraction < .5f || bannerId.isNullOrBlank()) {
            endExposure()
            return null
        }
        if (currentId != bannerId) {
            currentId = bannerId
            visibleSince = now
            counted = false
            return null
        }
        if (counted || now - (visibleSince ?: now) < 1_000) return null
        counted = true
        if (now - (lastImpression[bannerId] ?: Long.MIN_VALUE / 2) < 30_000) return null
        lastImpression[bannerId] = now
        return event(bannerId, section, "impression", now)
    }

    fun click(
        bannerId: String, section: String, visibleFraction: Float,
        eligible: Boolean, now: Long,
    ): List<BannerMeasurement> {
        if (!eligible || visibleFraction < .5f || currentId != bannerId ||
            now - (lastClick[bannerId] ?: Long.MIN_VALUE / 2) < 800) return emptyList()
        lastClick[bannerId] = now
        val result = mutableListOf<BannerMeasurement>()
        if (!counted) {
            counted = true
            if (now - (lastImpression[bannerId] ?: Long.MIN_VALUE / 2) >= 30_000) {
                lastImpression[bannerId] = now
                result += event(bannerId, section, "impression", now)
            }
        }
        result += event(bannerId, section, "click", now)
        return result
    }

    private fun event(bannerId: String, section: String, kind: String, now: Long) =
        BannerMeasurement(id(), bannerId, section, kind, now)

    private fun endExposure() {
        currentId = null
        visibleSince = null
        counted = false
    }
}
