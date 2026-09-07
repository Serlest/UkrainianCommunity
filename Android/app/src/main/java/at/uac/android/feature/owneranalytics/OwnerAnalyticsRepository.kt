package at.uac.android.feature.owneranalytics

import android.content.Context
import at.uac.android.core.backend.AppBackend
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

fun ownerAnalyticsRepository(context: Context, current: () -> OwnerAnalyticsSession?) =
    FirestoreOwnerAnalyticsRepository(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        current,
    )

interface OwnerAnalyticsRepository {
    suspend fun overview(
        session: OwnerAnalyticsSession,
        period: AnalyticsPeriod,
    ): OwnerAnalyticsSnapshot

    suspend fun detail(
        session: OwnerAnalyticsSession,
        period: AnalyticsPeriod,
        type: String,
        id: String,
    ): AnalyticsDetail
}

class FirestoreOwnerAnalyticsRepository(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val current: () -> OwnerAnalyticsSession?,
    private val today: () -> LocalDate = { LocalDate.now(ZoneId.of("Europe/Vienna")) },
) : OwnerAnalyticsRepository {
    private fun authorize(session: OwnerAnalyticsSession) {
        if (
            !session.ready ||
                current() != session ||
                auth.currentUser?.uid != session.uid ||
                auth.currentUser?.isAnonymous != false ||
                auth.currentUser?.isEmailVerified != true
        )
            throw OwnerAnalyticsException(OwnerAnalyticsFailure.ACCESS)
    }

    override suspend fun overview(session: OwnerAnalyticsSession, period: AnalyticsPeriod) = read {
        authorize(session)
        val anchor = today()
        val currentDays = dates(anchor, period.days)
        val previousDays = dates(anchor.minusDays(period.days.toLong()), period.days)
        val periodId = if (period == AnalyticsPeriod.TODAY) anchor.toString() else period.documentId
        val documents = coroutineScope {
            (currentDays + previousDays)
                .distinct()
                .map { day ->
                    async { db.document("analyticsDailyStats/$day").get(Source.SERVER).await() }
                }
                .awaitAll()
        }
        val currentRows = currentDays.map { day ->
            day to metrics(documents.firstOrNull { it.id == day }?.data)
        }
        val previousRows = previousDays.map { day ->
            metrics(documents.firstOrNull { it.id == day }?.data)
        }
        val aggregate = aggregate(currentRows.map { it.second })
        val previous = aggregate(previousRows)
        val topDoc = server("analyticsTopContent/$periodId")
        val regionDoc = server("analyticsRegionStats/$periodId")
        val userDoc = server("analyticsUserStats/$periodId")
        authorize(session)
        val top = topItems(topDoc.data)
        val regions = regions(regionDoc.data)
        val userDataValid = validUsers(userDoc.data, periodId, currentDays.reversed())
        val users = if (userDataValid) users(userDoc.data) else AnalyticsUsers()
        val unavailable = buildSet {
            if (!topDoc.exists() || topDoc.getTimestamp("updatedAt") == null) add("top")
            if (!regionDoc.exists() || regionDoc.getTimestamp("updatedAt") == null) add("regions")
            if (!userDataValid) add("users")
        }
        OwnerAnalyticsSnapshot(
            period,
            listOfNotNull(
                    documents.mapNotNull { it.getTimestamp("updatedAt")?.instant() }.maxOrNull(),
                    topDoc.getTimestamp("updatedAt")?.instant(),
                    regionDoc.getTimestamp("updatedAt")?.instant(),
                    userDoc.getTimestamp("generatedAt")?.instant(),
                )
                .minOrNull(),
            aggregate,
            previous,
            currentRows.map { it.first to it.second },
            top,
            regions,
            users,
            unavailable,
        )
    }

    override suspend fun detail(
        session: OwnerAnalyticsSession,
        period: AnalyticsPeriod,
        type: String,
        id: String,
    ): AnalyticsDetail = read {
        authorize(session)
        require(type in setOf("news", "event", "organization") && safeId(id))
        val periodId =
            if (period == AnalyticsPeriod.TODAY) today().toString() else period.documentId
        val rootCollection =
            if (type == "organization") "analyticsOrganizationStats" else "analyticsContentStats"
        val child =
            if (type == "organization") "organizations/$id" else "items/${escapedKey(type, id)}"
        val root =
            if (period == AnalyticsPeriod.TODAY) null else server("$rootCollection/$periodId")
        if (
            root != null &&
                (!root.exists() ||
                    root.getString("periodId") != periodId ||
                    !root.getString("rollupInProgressGeneration").isNullOrBlank())
        ) {
            throw OwnerAnalyticsException(OwnerAnalyticsFailure.REFRESHING)
        }
        val generation = root?.getString("rollupGeneration")
        if (root != null && generation.isNullOrBlank())
            throw OwnerAnalyticsException(OwnerAnalyticsFailure.REFRESHING)
        val doc = server("$rootCollection/$periodId/$child")
        authorize(session)
        if (generation != null) {
            if (doc.exists() && doc.getString("rollupGeneration") != generation)
                throw OwnerAnalyticsException(OwnerAnalyticsFailure.REFRESHING)
            val confirmedRoot = server("$rootCollection/$periodId")
            authorize(session)
            if (
                confirmedRoot.getString("rollupGeneration") != generation ||
                    !confirmedRoot.getString("rollupInProgressGeneration").isNullOrBlank()
            )
                throw OwnerAnalyticsException(OwnerAnalyticsFailure.REFRESHING)
        }
        val data = doc.data.orEmpty()
        AnalyticsDetail(
            type,
            id,
            text(data, if (type == "organization") "organizationName" else "contentTitle"),
            period,
            intMap(data["metrics"]),
            detailRegions(data),
            if (type == "organization") detailTop(data["topNews"], "news") else emptyList(),
            if (type == "organization") detailTop(data["topEvents"], "event") else emptyList(),
            doc.getTimestamp("updatedAt")?.instant(),
            root?.getString("coverageStartDay").takeIf {
                root?.getBoolean("isPartialCoverage") == true
            },
        )
    }

    private suspend fun server(path: String) =
        withTimeout(20_000) {
            db.document(path).get(Source.SERVER).await().also {
                if (it.metadata.isFromCache || it.metadata.hasPendingWrites())
                    throw OwnerAnalyticsException(OwnerAnalyticsFailure.OFFLINE)
            }
        }

    private fun dates(end: LocalDate, count: Int) =
        (count - 1 downTo 0).map { end.minusDays(it.toLong()).toString() }

    private fun metrics(data: Map<String, Any?>?): Map<String, Int> {
        val source = (data?.get("metrics") as? Map<*, *>) ?: data.orEmpty()
        val result = intMap(source)
        val views = listOf("newsViews", "eventViews", "organizationViews").sumOf { result[it] ?: 0 }
        val activeRegionKeys = data?.get("activeRegionKeys") as? Map<*, *>
        val normalizedRegionKeys =
            activeRegionKeys
                ?.filterValues { it == true }
                ?.keys
                ?.mapNotNull { raw ->
                    val key = raw as? String ?: return@mapNotNull null
                    if (key.startsWith("city_") && key != "city_all")
                        "federalState_${key.removePrefix("city_")}"
                    else key
                }
                ?.toSet()
                .orEmpty()
        val activeRegions =
            normalizedRegionKeys.size.takeIf { activeRegionKeys != null }
                ?: (result["activeRegions"] ?: 0)
        return result +
            mapOf("totalViews" to views, "activeRegions" to activeRegions) +
            normalizedRegionKeys.associate { "__region:$it" to 1 }
    }

    private fun aggregate(rows: List<Map<String, Int>>): Map<String, Int> {
        val result = mutableMapOf<String, Int>()
        rows.forEach { row ->
            row.forEach { (key, value) ->
                if (key != "activeRegions" && !key.startsWith("__region:"))
                    result[key] = (result[key] ?: 0) + value
            }
        }
        val regionKeys =
            rows.flatMap { it.keys.filter { key -> key.startsWith("__region:") } }.toSet()
        result["activeRegions"] =
            if (regionKeys.isNotEmpty()) regionKeys.size
            else rows.maxOfOrNull { it["activeRegions"] ?: 0 } ?: 0
        return result
    }

    private fun topItems(data: Map<String, Any?>?): List<AnalyticsTopItem> {
        val keyed = data?.get("itemsByKey") as? Map<*, *>
        val values =
            keyed?.values?.takeIf { it.isNotEmpty() } ?: (data?.get("items") as? List<*>).orEmpty()
        return values
            .mapNotNull { topItem(it as? Map<*, *> ?: return@mapNotNull null) }
            .filter { it.views > 0 }
            .sortedWith(compareByDescending<AnalyticsTopItem> { it.views }.thenBy { it.rank })
    }

    private fun topItem(data: Map<*, *>): AnalyticsTopItem? {
        val id = text(data, "contentID").takeIf(::safeId) ?: return null
        val type =
            text(data, "contentType").takeIf { it in setOf("news", "event", "organization") }
                ?: return null
        return AnalyticsTopItem(
            id,
            type,
            text(data, "title").ifBlank { id },
            integer(data["viewCount"]),
            integer(data["rank"]),
            text(data, "organizationID").ifBlank { null },
        )
    }

    private fun regions(data: Map<String, Any?>?): List<AnalyticsRegion> {
        val keyed = data?.get("regionsByKey") as? Map<*, *>
        val values =
            keyed?.values?.takeIf { it.isNotEmpty() }
                ?: (data?.get("regions") as? List<*>).orEmpty()
        return values
            .mapNotNull { region(it as? Map<*, *> ?: return@mapNotNull null) }
            .filter { it.views > 0 || it.contentCount > 0 }
            .sortedByDescending { it.views }
    }

    private fun detailRegions(data: Map<String, Any?>): List<AnalyticsRegion> =
        ((data["regionsByKey"] as? Map<*, *>)?.values.orEmpty())
            .mapNotNull { region(it as? Map<*, *> ?: return@mapNotNull null) }
            .sortedByDescending { it.metrics.values.sum() }

    private fun region(data: Map<*, *>): AnalyticsRegion? {
        val rawScope = text(data, "regionScope")
        val state = text(data, "federalState").ifBlank { null }
        val scope = if (rawScope == "city" && state != null) "federalState" else rawScope
        if (
            scope !in setOf("austria", "federalState") ||
                scope != "austria" && state !in federalStates
        )
            return null
        val metrics = intMap(data["metrics"])
        val views =
            listOf("views", "profileViews", "newsViews", "eventViews", "organizationViews").sumOf {
                metrics[it] ?: 0
            }
        val contentCount =
            (data["contentKeys"] as? Map<*, *>)?.keys?.count { key ->
                key.toString().startsWith("news_") ||
                    key.toString().startsWith("event_") ||
                    key.toString().startsWith("organization_")
            } ?: integer(data["contentCount"])
        return AnalyticsRegion(
            "$scope:${state ?: "all"}",
            scope,
            state,
            views,
            contentCount,
            metrics,
        )
    }

    private fun users(data: Map<String, Any?>?): AnalyticsUsers {
        if (data == null || data["generatedAt"] !is Timestamp) return AnalyticsUsers()
        val source = (data["metrics"] as? Map<*, *>) ?: data
        val metrics = intMap(source)
        val required =
            setOf(
                "totalUsers",
                "newRegistrations",
                "deletedAccounts",
                "blockedUsers",
                "deactivatedUsers",
                "activeUsersToday",
                "activeUsersSevenDays",
                "activeUsersThirtyDays",
            )
        if (!required.all { validInteger(source[it]) }) return AnalyticsUsers()
        val states =
            intMap(data["usersByFederalState"])
                .filterKeys { it in federalStates }
                .filterValues { it > 0 }
        return AnalyticsUsers(
            metrics["totalUsers"] ?: 0,
            metrics["newRegistrations"] ?: 0,
            metrics["deletedAccounts"] ?: 0,
            metrics["blockedUsers"] ?: 0,
            metrics["deactivatedUsers"] ?: 0,
            metrics["activeUsersToday"] ?: 0,
            metrics["activeUsersSevenDays"] ?: 0,
            metrics["activeUsersThirtyDays"] ?: 0,
            states,
        )
    }

    private fun validUsers(
        data: Map<String, Any?>?,
        periodId: String,
        expectedSources: List<String>,
    ): Boolean {
        if (
            data == null ||
                data["generatedAt"] !is Timestamp ||
                data["period"] != periodId ||
                data["usersByFederalState"] !is Map<*, *>
        )
            return false
        val source = data["sourceDocumentIDs"] as? List<*> ?: return false
        val covered = data["coveredLifecycleSourceDocumentIDs"] as? List<*> ?: return false
        val coverageStart = data["lifecycleCoverageStartDay"] as? String ?: return false
        val partial = data["isLifecyclePartialCoverage"] as? Boolean ?: return false
        if (
            source != expectedSources ||
                source.any { it !is String } ||
                source.toSet().size != source.size ||
                covered.any { it !is String } ||
                covered != source.filter { (it as String) >= coverageStart } ||
                partial != (covered.size < source.size)
        )
            return false
        val metrics = (data["metrics"] as? Map<*, *>) ?: data
        return setOf(
                "totalUsers",
                "newRegistrations",
                "deletedAccounts",
                "blockedUsers",
                "deactivatedUsers",
                "activeUsersToday",
                "activeUsersSevenDays",
                "activeUsersThirtyDays",
            )
            .all { validInteger(metrics[it]) }
    }

    private fun detailTop(value: Any?, fallbackType: String): List<AnalyticsTopItem> {
        val values =
            when (value) {
                is Map<*, *> -> value.values
                is List<*> -> value
                else -> emptyList<Any?>()
            }
        return values
            .mapNotNull { raw ->
                val map = raw as? Map<*, *> ?: return@mapNotNull null
                val id = text(map, "contentID").takeIf(::safeId) ?: return@mapNotNull null
                val metrics = intMap(map["metrics"])
                AnalyticsTopItem(
                    id,
                    text(map, "contentType").ifBlank { fallbackType },
                    text(map, "contentTitle").ifBlank { id },
                    metrics["views"] ?: 0,
                    0,
                )
            }
            .sortedByDescending { it.views }
    }

    private fun intMap(value: Any?): Map<String, Int> =
        (value as? Map<*, *>)
            ?.entries
            ?.mapNotNull { (key, raw) ->
                val name = key as? String ?: return@mapNotNull null
                val number = integer(raw)
                name to number
            }
            ?.toMap()
            .orEmpty()

    private fun integer(value: Any?): Int {
        val number = value as? Number ?: return 0
        val double = number.toDouble()
        return if (
            double.isFinite() && double >= 0 && double % 1.0 == 0.0 && double <= Int.MAX_VALUE
        )
            double.toInt()
        else 0
    }

    private fun validInteger(value: Any?): Boolean {
        val number = value as? Number ?: return false
        val double = number.toDouble()
        return double.isFinite() && double >= 0 && double % 1.0 == 0.0 && double <= Int.MAX_VALUE
    }

    private fun text(data: Map<*, *>, key: String) = (data[key] as? String)?.trim().orEmpty()

    private fun safeId(value: String) = Regex("[A-Za-z0-9._:-]{1,128}").matches(value)

    private fun escapedKey(type: String, id: String) =
        listOf(type, id).joinToString("_") { segment ->
            segment.replace("_", "__").replace(".", "_d").replace(":", "_c").replace("-", "_h")
        }

    private fun Timestamp.instant(): Instant = toDate().toInstant()

    private suspend fun <T> read(block: suspend () -> T): T =
        try {
            block()
        } catch (error: CancellationException) {
            throw error
        } catch (error: OwnerAnalyticsException) {
            throw error
        } catch (error: TimeoutCancellationException) {
            throw OwnerAnalyticsException(OwnerAnalyticsFailure.OFFLINE, error)
        } catch (error: Exception) {
            val denied =
                error is FirebaseFirestoreException &&
                    error.code in
                        setOf(
                            FirebaseFirestoreException.Code.PERMISSION_DENIED,
                            FirebaseFirestoreException.Code.UNAUTHENTICATED,
                        )
            throw OwnerAnalyticsException(
                if (denied) OwnerAnalyticsFailure.ACCESS else OwnerAnalyticsFailure.OFFLINE,
                error,
            )
        }

    private companion object {
        val federalStates =
            setOf(
                "burgenland",
                "kaernten",
                "niederoesterreich",
                "oberoesterreich",
                "salzburg",
                "steiermark",
                "tirol",
                "vorarlberg",
                "wien",
            )
    }
}
