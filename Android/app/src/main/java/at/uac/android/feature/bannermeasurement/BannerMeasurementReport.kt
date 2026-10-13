package at.uac.android.feature.bannermeasurement

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.owneranalytics.AnalyticsPeriod
import at.uac.android.feature.owneranalytics.OwnerAnalyticsSession
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.time.LocalDate
import java.time.ZoneOffset
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

data class BannerDailyCount(
    val day: String, val bannerId: String, val section: String,
    val impressions: Long, val clicks: Long,
)

data class BannerTotals(val impressions: Long = 0, val clicks: Long = 0) {
    operator fun plus(row: BannerDailyCount) =
        BannerTotals(impressions + row.impressions, clicks + row.clicks)
    val clickRate: Double? get() = if (impressions > 0) clicks.toDouble() / impressions else null
}

data class BannerReport(
    val totals: BannerTotals,
    val sections: Map<String, BannerTotals>,
    val days: Map<String, BannerTotals>,
    val banners: Map<String, BannerTotals>,
    val bannerSections: Map<String, Map<String, BannerTotals>>,
    val names: Map<String, String> = emptyMap(),
    val namesUnavailable: Boolean = false,
)

fun bannerReport(rows: List<BannerDailyCount>, names: Map<String, String> = emptyMap(),
    namesUnavailable: Boolean = false): BannerReport {
    var all = BannerTotals()
    val sections = mutableMapOf<String, BannerTotals>()
    val days = mutableMapOf<String, BannerTotals>()
    val banners = mutableMapOf<String, BannerTotals>()
    val bannerSections = mutableMapOf<String, MutableMap<String, BannerTotals>>()
    rows.forEach { row ->
        all += row
        sections[row.section] = (sections[row.section] ?: BannerTotals()) + row
        days[row.day] = (days[row.day] ?: BannerTotals()) + row
        banners[row.bannerId] = (banners[row.bannerId] ?: BannerTotals()) + row
        val sectionsForBanner = bannerSections.getOrPut(row.bannerId) { mutableMapOf() }
        sectionsForBanner[row.section] = (sectionsForBanner[row.section] ?: BannerTotals()) + row
    }
    return BannerReport(all, sections, days, banners, bannerSections, names, namesUnavailable)
}

interface BannerReportSource {
    suspend fun load(session: OwnerAnalyticsSession, period: AnalyticsPeriod): BannerReport
}

fun bannerReportSource(context: Context): BannerReportSource = FirebaseBannerReportSource(
    AppBackend.firestore(context), AppBackend.auth(context),
)

/** Owner-only server reads; the Rules remain the final authority. */
class FirebaseBannerReportSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
) : BannerReportSource {
    init { FirebaseBackendGuard.requireSameApp(auth, db) }

    override suspend fun load(session: OwnerAnalyticsSession, period: AnalyticsPeriod): BannerReport {
        require(session.ready)
        requireCurrent(session)
        val last = LocalDate.now(ZoneOffset.UTC)
        val first = last.minusDays((period.days - 1).toLong())
        val base = db.collection("bannerMeasurementDailyShards")
            .whereGreaterThanOrEqualTo("day", first.toString())
            .whereLessThanOrEqualTo("day", last.toString())
            .orderBy("day", Query.Direction.ASCENDING)
            .limit(500)
        val rows = mutableListOf<BannerDailyCount>()
        var cursor: com.google.firebase.firestore.DocumentSnapshot? = null
        do {
            val page = (cursor?.let(base::startAfter) ?: base).get(Source.SERVER).await()
            requireCurrent(session)
            check(!page.metadata.isFromCache && !page.metadata.hasPendingWrites())
            page.documents.forEach { document ->
                val day = document.getString("day") ?: error("Invalid banner day")
                val bannerId = document.getString("bannerID") ?: error("Invalid banner ID")
                val section = document.getString("section") ?: error("Invalid banner section")
                val impressions = document.getLong("impressions") ?: error("Invalid impressions")
                val clicks = document.getLong("clicks") ?: error("Invalid clicks")
                check(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}").matches(day) &&
                    bannerId.isNotBlank() && section in setOf("home", "events", "organizations", "directory") &&
                    impressions >= 0 && clicks >= 0)
                rows += BannerDailyCount(day, bannerId, section, impressions, clicks)
            }
            cursor = if (page.size() == 500) page.documents.last() else null
        } while (cursor != null)
        var namesUnavailable = false
        val names = try {
            val banners = db.collection("featuredBanners").get(Source.SERVER).await()
            requireCurrent(session)
            check(!banners.metadata.isFromCache && !banners.metadata.hasPendingWrites())
            banners.documents.mapNotNull { document ->
                val name = document.getString("internalName")?.takeIf(String::isNotBlank)
                    ?: document.getString("title")?.takeIf(String::isNotBlank)
                name?.let { document.id to it }
            }.toMap()
        } catch (error: CancellationException) { throw error }
        catch (_: Exception) { namesUnavailable = true; emptyMap() }
        return bannerReport(rows, names, namesUnavailable)
    }

    private fun requireCurrent(session: OwnerAnalyticsSession) {
        if (auth.currentUser?.uid != session.uid || auth.currentUser?.isAnonymous != false ||
            auth.currentUser?.isEmailVerified != true)
            throw CancellationException("Banner report account changed")
    }
}
