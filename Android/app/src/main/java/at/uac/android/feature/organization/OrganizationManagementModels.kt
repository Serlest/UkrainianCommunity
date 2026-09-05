package at.uac.android.feature.organization

import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import java.time.Instant
import java.time.Year
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit

enum class OrganizationManagementFailure {
    SIGN_IN,
    NOT_READY,
    INVALID,
    DENIED,
    MISSING,
    STALE,
    OFFLINE,
    TARGET_UNAVAILABLE,
    UNCONFIRMED,
    UNKNOWN,
}

class OrganizationManagementException(
    val failure: OrganizationManagementFailure,
    cause: Throwable? = null,
) : Exception(failure.name, cause)

enum class OrganizationTeamRole(val wire: String) {
    MEMBER("none"),
    OWNER("communityOwner"),
    ADMIN("communityAdmin"),
    MODERATOR("communityModerator"),
}

enum class OrganizationTeamAction {
    ADMIN,
    MODERATOR,
    REMOVE,
    TRANSFER,
}

data class OrganizationRoleIntent(
    val targetId: String,
    val action: OrganizationTeamAction,
    val previousRole: OrganizationTeamRole,
)

data class OrganizationRoleReceipt(
    val previousRole: OrganizationTeamRole?,
    val previousOwnerId: String?,
    val updatedAt: Instant,
)

data class OrganizationPublicMember(val id: String, val displayName: String?, val city: String?)

data class OrganizationSubscriber(
    val userId: String,
    val followedAt: Instant,
    val documentId: String,
)

data class OrganizationSubscriberCursor(val followedAt: Instant, val documentId: String)

data class OrganizationSubscriberPage(
    val items: List<OrganizationSubscriber>,
    val next: OrganizationSubscriberCursor?,
)

data class OrganizationTeamMember(
    val profile: OrganizationPublicMember,
    val role: OrganizationTeamRole,
)

data class OrganizationManagementSnapshot(
    val organization: OrganizationRecord,
    val members: List<OrganizationTeamMember>,
    val subscriberIds: List<String>,
    val next: OrganizationSubscriberCursor?,
    val teamTruncated: Boolean = false,
)

data class OrganizationInformationResult(
    val organization: OrganizationRecord,
    val logoIncomplete: Boolean = false,
)

/** Material's selected date is UTC midnight; the offer is valid through its local calendar date. */
object OrganizationOfferCalendar {
    fun pickerMillis(value: Instant, zone: ZoneId): Long =
        value.atZone(zone).toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

    fun inclusiveEnd(pickerMillis: Long, zone: ZoneId): Instant =
        Instant.ofEpochMilli(pickerMillis)
            .atZone(ZoneOffset.UTC)
            .toLocalDate()
            .plusDays(1)
            .atStartOfDay(zone)
            .toInstant()
            .minusNanos(1_000)
            .truncatedTo(ChronoUnit.MICROS)
}

data class OrganizationDirectoryDraft(
    val secondaryCategories: String = "",
    val serviceModes: Set<String> = emptySet(),
    val serviceArea: String = "",
    val regularHours: Map<String, String> = emptyMap(),
    val specialHoursNote: String = "",
    val services: String = "",
    val orderUrl: String = "",
    val bookingUrl: String = "",
    val offerTitle: String = "",
    val offerDetails: String = "",
    val offerUrl: String = "",
    val offerUntil: String = "",
)

data class OrganizationDirectoryTranslation(
    val mission: String = "",
    val serviceArea: String = "",
    val hoursNote: String = "",
    val services: String = "",
    val offerTitle: String = "",
    val offerDetails: String = "",
)

data class OrganizationInformationDraft(
    val basics: OrganizationDraft,
    val category: String = "",
    val foundedYear: String = "",
    val foundedMonth: String = "",
    val languages: String = "",
    val mission: String = "",
    val contactPerson: String = "",
    val links: Map<String, String> = emptyMap(),
    val directory: OrganizationDirectoryDraft = OrganizationDirectoryDraft(),
    val german: OrganizationDirectoryTranslation = OrganizationDirectoryTranslation(),
)

/**
 * Canonical organization fields decide authority; neither UI flags nor membership mirrors grant
 * rights.
 */
object OrganizationManagementContract {
    const val PAGE_SIZE = 50
    const val MAX_TEAM_PROFILES = 200
    val weekdays =
        listOf("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")
    val serviceModes = listOf("inStore", "pickup", "delivery", "online", "onSite")
    val categories =
        listOf(
            "ukrainianProducts",
            "foodAndDrink",
            "retail",
            "beautyAndHealth",
            "legalAndFinance",
            "workAndBusiness",
            "education",
            "childrenAndFamily",
            "culture",
            "support",
            "integration",
            "homeAndTransport",
            "media",
            "publicInstitution",
            "other",
        )
    val linkFields =
        listOf(
            "telegramURL",
            "donationURL",
            "facebookURL",
            "instagramURL",
            "whatsappURL",
            "youtubeURL",
            "linkedinURL",
        )
    val safeFields =
        setOf(
            "name",
            "localizations",
            "description",
            "shortDescription",
            "fullDescription",
            "imageURL",
            "logoURL",
            "coverURL",
            "contactEmail",
            "website",
            "email",
            "phone",
            "address",
            "latitude",
            "longitude",
            "regionScope",
            "city",
            "federalState",
            "organizationType",
            "directoryProfile",
            "foundedYear",
            "foundedMonth",
            "languages",
            "socialLinks",
            "telegramURL",
            "donationURL",
            "facebookURL",
            "instagramURL",
            "whatsappURL",
            "youtubeURL",
            "linkedinURL",
            "missionStatement",
            "contactPerson",
            "updatedAt",
        )

    fun userId(value: String): Boolean =
        value.length in 1..128 &&
            value == value.trim() &&
            value !in setOf(".", "..") &&
            '/' !in value &&
            value.none { it.isISOControl() || it.isWhitespace() }

    fun documentId(value: String): Boolean =
        value.length in 1..512 &&
            value !in setOf(".", "..") &&
            '/' !in value &&
            value.none(Char::isISOControl)

    fun canonical(record: OrganizationRecord, session: OrganizationSession): OrganizationRecord =
        try {
            OrganizationContract.record(RawDocument(record.id, record.fields), session)
        } catch (error: OrganizationException) {
            throw OrganizationManagementException(OrganizationManagementFailure.INVALID, error)
        }

    fun requireApproved(
        record: OrganizationRecord,
        session: OrganizationSession,
    ): OrganizationRecord {
        if (!session.ready) fail(OrganizationManagementFailure.NOT_READY)
        val actual = canonical(record, session)
        if (actual.status != "approved" || actual.id == "ukrainian-community")
            fail(OrganizationManagementFailure.DENIED)
        return actual
    }

    fun canEdit(record: OrganizationRecord, session: OrganizationSession): Boolean =
        runCatching { requireApproved(record, session) }.getOrNull()?.authority in
            setOf(
                OrganizationAuthority.PLATFORM_OWNER,
                OrganizationAuthority.OWNER,
                OrganizationAuthority.ADMIN,
            )

    fun canManage(record: OrganizationRecord, session: OrganizationSession): Boolean =
        runCatching { requireApproved(record, session) }.getOrNull()?.authority in
            setOf(OrganizationAuthority.PLATFORM_OWNER, OrganizationAuthority.OWNER)

    fun canTransfer(record: OrganizationRecord, session: OrganizationSession): Boolean =
        runCatching { requireApproved(record, session) }.getOrNull()?.authority ==
            OrganizationAuthority.PLATFORM_OWNER

    fun role(record: OrganizationRecord, id: String): OrganizationTeamRole =
        when {
            record.fields["ownerId"] == id -> OrganizationTeamRole.OWNER
            id in (record.fields["adminIds"] as? List<*>).orEmpty() -> OrganizationTeamRole.ADMIN
            id in (record.fields["moderatorIds"] as? List<*>).orEmpty() ->
                OrganizationTeamRole.MODERATOR
            else -> OrganizationTeamRole.MEMBER
        }

    fun teamIds(record: OrganizationRecord): List<String> {
        val ids =
            listOfNotNull((record.fields["ownerId"] as? String)?.takeIf(String::isNotEmpty)) +
                (record.fields["adminIds"] as? List<*>)
                    ?.map { it as? String ?: fail(OrganizationManagementFailure.INVALID) }
                    .orEmpty() +
                (record.fields["moderatorIds"] as? List<*>)
                    ?.map { it as? String ?: fail(OrganizationManagementFailure.INVALID) }
                    .orEmpty()
        if (ids.any { !userId(it) }) fail(OrganizationManagementFailure.INVALID)
        return ids.distinct()
    }

    fun callable(intent: OrganizationRoleIntent): String =
        when (intent.action) {
            OrganizationTeamAction.ADMIN -> "assignOrganizationAdmin"
            OrganizationTeamAction.MODERATOR -> "assignOrganizationModerator"
            OrganizationTeamAction.REMOVE ->
                if (intent.previousRole == OrganizationTeamRole.MODERATOR)
                    "removeOrganizationModerator"
                else "removeOrganizationAdmin"
            OrganizationTeamAction.TRANSFER -> "transferOrganizationOwnership"
        }

    fun desired(intent: OrganizationRoleIntent): OrganizationTeamRole =
        when (intent.action) {
            OrganizationTeamAction.ADMIN -> OrganizationTeamRole.ADMIN
            OrganizationTeamAction.MODERATOR -> OrganizationTeamRole.MODERATOR
            OrganizationTeamAction.REMOVE -> OrganizationTeamRole.MEMBER
            OrganizationTeamAction.TRANSFER -> OrganizationTeamRole.OWNER
        }

    fun requireIntent(
        record: OrganizationRecord,
        intent: OrganizationRoleIntent,
        session: OrganizationSession,
    ) {
        requireApproved(record, session)
        if (!userId(intent.targetId)) fail(OrganizationManagementFailure.INVALID)
        if (
            !canManage(record, session) ||
                (intent.action == OrganizationTeamAction.TRANSFER && !canTransfer(record, session))
        )
            fail(OrganizationManagementFailure.DENIED)
        if (
            role(record, intent.targetId) == OrganizationTeamRole.OWNER &&
                intent.action != OrganizationTeamAction.TRANSFER
        )
            fail(OrganizationManagementFailure.DENIED)
    }

    fun payload(record: OrganizationRecord, intent: OrganizationRoleIntent): Fields =
        mapOf(
            "organizationId" to record.id,
            "targetUserId" to intent.targetId,
            "reason" to "Organization management hub",
        )

    fun receipt(
        data: Any?,
        record: OrganizationRecord,
        intent: OrganizationRoleIntent,
    ): OrganizationRoleReceipt {
        val value = data as? Map<*, *> ?: fail(OrganizationManagementFailure.UNCONFIRMED)
        val time =
            (value["updatedAt"] as? String)?.let { runCatching { Instant.parse(it) }.getOrNull() }
                ?: fail(OrganizationManagementFailure.UNCONFIRMED)
        if (value["organizationId"] != record.id) fail(OrganizationManagementFailure.UNCONFIRMED)
        if (intent.action == OrganizationTeamAction.TRANSFER) {
            if (
                value["newOwnerId"] != intent.targetId ||
                    !value.containsKey("previousOwnerId") ||
                    (value["previousOwnerId"] != null &&
                        (value["previousOwnerId"] as? String)?.let(::userId) != true)
            )
                fail(OrganizationManagementFailure.UNCONFIRMED)
            return OrganizationRoleReceipt(null, value["previousOwnerId"] as? String, time)
        }
        val previous =
            OrganizationTeamRole.entries.firstOrNull { it.wire == value["previousRole"] }
                ?: fail(OrganizationManagementFailure.UNCONFIRMED)
        if (
            previous == OrganizationTeamRole.OWNER ||
                value["targetUserId"] != intent.targetId ||
                value["newRole"] != desired(intent).wire
        )
            fail(OrganizationManagementFailure.UNCONFIRMED)
        return OrganizationRoleReceipt(previous, null, time)
    }

    fun verifyRole(
        record: OrganizationRecord,
        intent: OrganizationRoleIntent,
        receipt: OrganizationRoleReceipt,
    ) {
        val admins = (record.fields["adminIds"] as? List<*>).orEmpty()
        val moderators = (record.fields["moderatorIds"] as? List<*>).orEmpty()
        if (role(record, intent.targetId) != desired(intent))
            fail(OrganizationManagementFailure.UNCONFIRMED)
        if (
            intent.action == OrganizationTeamAction.ADMIN &&
                admins.count { it == intent.targetId } != 1
        )
            fail(OrganizationManagementFailure.UNCONFIRMED)
        if (
            intent.action == OrganizationTeamAction.MODERATOR &&
                moderators.count { it == intent.targetId } != 1
        )
            fail(OrganizationManagementFailure.UNCONFIRMED)
        if (intent.action != OrganizationTeamAction.ADMIN && intent.targetId in admins)
            fail(OrganizationManagementFailure.UNCONFIRMED)
        if (intent.action != OrganizationTeamAction.MODERATOR && intent.targetId in moderators)
            fail(OrganizationManagementFailure.UNCONFIRMED)
        if (
            intent.action == OrganizationTeamAction.TRANSFER &&
                receipt.previousOwnerId?.let { it in admins || it in moderators } == true
        )
            fail(OrganizationManagementFailure.UNCONFIRMED)
    }

    fun profile(id: String, fields: Fields?): OrganizationPublicMember {
        if (!userId(id)) fail(OrganizationManagementFailure.INVALID)
        if (fields == null || (fields["id"] != null && fields["id"] != id))
            return OrganizationPublicMember(id, null, null)
        fun clean(key: String, max: Int) =
            (fields[key] as? String)
                ?.filterNot(Char::isISOControl)
                ?.trim()
                ?.take(max)
                ?.takeIf(String::isNotEmpty)
        return OrganizationPublicMember(id, clean("displayName", 160), clean("city", 160))
    }

    fun members(
        record: OrganizationRecord,
        subscriberIds: List<String>,
        profiles: List<OrganizationPublicMember>,
    ): List<OrganizationTeamMember> {
        val byId = profiles.associateBy { it.id }
        val ids = (teamIds(record).take(MAX_TEAM_PROFILES) + subscriberIds).distinct()
        if (ids.any { !userId(it) }) fail(OrganizationManagementFailure.INVALID)
        return ids.map { OrganizationTeamMember(byId[it] ?: profile(it, null), role(record, it)) }
    }

    fun page(
        rows: List<RawDocument>,
        organizationId: String,
        after: OrganizationSubscriberCursor?,
    ): OrganizationSubscriberPage {
        if (rows.size > PAGE_SIZE + 1) fail(OrganizationManagementFailure.INVALID)
        val values = rows.map { row ->
            val uid = row.fields["userId"] as? String ?: fail(OrganizationManagementFailure.INVALID)
            val time =
                row.fields["createdAt"] as? Instant ?: fail(OrganizationManagementFailure.INVALID)
            if (
                !userId(uid) ||
                    !documentId(row.id) ||
                    row.fields["subscribedOrganizationId"] != organizationId
            )
                fail(OrganizationManagementFailure.INVALID)
            OrganizationSubscriber(uid, time, row.id)
        }
        fun before(a: OrganizationSubscriberCursor, b: OrganizationSubscriberCursor) =
            a.followedAt > b.followedAt ||
                (a.followedAt == b.followedAt && a.documentId > b.documentId)
        val cursors = values.map { OrganizationSubscriberCursor(it.followedAt, it.documentId) }
        if (
            (after != null && cursors.firstOrNull()?.let { !before(after, it) } == true) ||
                cursors.zipWithNext().any { !before(it.first, it.second) }
        )
            fail(OrganizationManagementFailure.INVALID)
        return OrganizationSubscriberPage(
            values.take(PAGE_SIZE),
            if (values.size > PAGE_SIZE) cursors[PAGE_SIZE - 1] else null,
        )
    }

    private fun text(fields: Map<*, *>, key: String) = fields[key] as? String ?: ""

    private fun strings(fields: Map<*, *>, key: String) =
        (fields[key] as? List<*>)?.filterIsInstance<String>().orEmpty()

    fun draft(record: OrganizationRecord): OrganizationInformationDraft {
        val f = record.fields
        val p = f["directoryProfile"] as? Map<*, *> ?: emptyMap<Any, Any>()
        val de = (f["localizations"] as? Map<*, *>)?.get("de") as? Map<*, *> ?: emptyMap<Any, Any>()
        val hours =
            (p["regularHours"] as? Map<*, *>)
                ?.entries
                ?.associate { it.key.toString() to (it.value as? String ?: "") }
                .orEmpty()
        return OrganizationInformationDraft(
            OrganizationContract.draft(record),
            text(f, "organizationType"),
            f["foundedYear"]?.toString().orEmpty(),
            f["foundedMonth"]?.toString().orEmpty(),
            strings(f, "languages").joinToString(", "),
            text(f, "missionStatement"),
            text(f, "contactPerson"),
            linkFields.associateWith { text(f, it) },
            OrganizationDirectoryDraft(
                strings(p, "secondaryCategories").joinToString(", "),
                strings(p, "serviceModes").toSet(),
                text(p, "serviceArea"),
                hours,
                text(p, "specialHoursNote"),
                strings(p, "services").joinToString("\n"),
                text(p, "orderURL"),
                text(p, "bookingURL"),
                text(p, "currentOfferTitle"),
                text(p, "currentOfferDetails"),
                text(p, "currentOfferURL"),
                (p["currentOfferValidUntil"] as? Instant)?.toString().orEmpty(),
            ),
            OrganizationDirectoryTranslation(
                text(de, "missionStatement"),
                text(de, "serviceArea"),
                text(de, "specialHoursNote"),
                strings(de, "services").joinToString("\n"),
                text(de, "currentOfferTitle"),
                text(de, "currentOfferDetails"),
            ),
        )
    }

    private fun bounded(value: String, maximum: Int) =
        value.trim().also {
            if (
                it.codePointCount(0, it.length) > maximum ||
                    it.any { c -> c.isISOControl() && c !in "\n\t" }
            )
                fail(OrganizationManagementFailure.INVALID)
        }

    private fun split(value: String, maximum: Int, length: Int, delimiter: String = ",") =
        value
            .split(delimiter)
            .map { bounded(it, length) }
            .filter(String::isNotEmpty)
            .distinct()
            .also { if (it.size > maximum) fail(OrganizationManagementFailure.INVALID) }

    private fun url(value: String): String =
        try {
            OrganizationContract.website(value)
        } catch (error: OrganizationException) {
            throw OrganizationManagementException(OrganizationManagementFailure.INVALID, error)
        }

    /**
     * Only actual safe-information fields are emitted. Unexposed fields, roles and counters are
     * untouched.
     */
    fun informationFields(
        draft: OrganizationInformationDraft,
        original: OrganizationRecord,
        year: Int = Year.now().value,
    ): Fields {
        if (draft.basics.id != original.id) fail(OrganizationManagementFailure.INVALID)
        val basic =
            try {
                OrganizationContract.editableFields(draft.basics, original.fields)
            } catch (error: OrganizationException) {
                throw OrganizationManagementException(OrganizationManagementFailure.INVALID, error)
            }
        val category = draft.category.trim()
        if (category.isNotEmpty() && category !in categories)
            fail(OrganizationManagementFailure.INVALID)
        val founded =
            draft.foundedYear.trim().takeIf(String::isNotEmpty)?.let {
                it.toIntOrNull()?.takeIf { value -> value in 1000..year }
                    ?: fail(OrganizationManagementFailure.INVALID)
            }
        val month =
            draft.foundedMonth.trim().takeIf(String::isNotEmpty)?.let {
                it.toIntOrNull()?.takeIf { value -> founded != null && value in 1..12 }
                    ?: fail(OrganizationManagementFailure.INVALID)
            }
        if (draft.links.keys.any { it !in linkFields }) fail(OrganizationManagementFailure.INVALID)
        val d = draft.directory
        val secondary = split(d.secondaryCategories, 2, 80)
        if (
            secondary.any { it !in categories || it == category } ||
                d.serviceModes.any { it !in serviceModes } ||
                d.regularHours.keys.any { it !in weekdays }
        )
            fail(OrganizationManagementFailure.INVALID)
        val hours =
            d.regularHours.mapValues { bounded(it.value, 32) }.filterValues(String::isNotEmpty)
        val interval = Regex("(?:[01][0-9]|2[0-3]):[0-5][0-9]-(?:[01][0-9]|2[0-3]):[0-5][0-9]")
        if (hours.values.any { it != "closed" && !interval.matches(it) })
            fail(OrganizationManagementFailure.INVALID)
        val directory =
            mutableMapOf<String, Any?>(
                "profileKind" to draft.basics.profileKind,
                "secondaryCategories" to secondary,
                "serviceModes" to serviceModes.filter { it in d.serviceModes },
                "regularHours" to hours,
                "services" to split(d.services, 8, 180, "\n"),
            )
        fun optional(map: MutableMap<String, Any?>, key: String, value: String) {
            value.takeIf(String::isNotEmpty)?.let { map[key] = it }
        }
        optional(directory, "serviceArea", bounded(d.serviceArea, 500))
        optional(directory, "specialHoursNote", bounded(d.specialHoursNote, 1000))
        optional(directory, "orderURL", url(d.orderUrl))
        optional(directory, "bookingURL", url(d.bookingUrl))
        optional(directory, "currentOfferURL", url(d.offerUrl))
        optional(directory, "currentOfferTitle", bounded(d.offerTitle, 180))
        optional(directory, "currentOfferDetails", bounded(d.offerDetails, 1200))
        d.offerUntil.trim().takeIf(String::isNotEmpty)?.let {
            // Firestore stores timestamps at microsecond precision; normalize before exact
            // read-back comparison.
            directory["currentOfferValidUntil"] =
                runCatching { Instant.parse(it).truncatedTo(ChronoUnit.MICROS) }.getOrNull()
                    ?: fail(OrganizationManagementFailure.INVALID)
        }
        val localized =
            (basic["localizations"] as Map<*, *>)
                .entries
                .associate { it.key.toString() to it.value }
                .toMutableMap()
        val mission = bounded(draft.mission, 1200)
        fun localization(key: String, translation: OrganizationDirectoryTranslation?) {
            val values =
                ((localized[key] ?: localized["uk"]) as? Map<*, *>)
                    ?.entries
                    ?.associate { it.key.toString() to it.value }
                    .orEmpty()
                    .toMutableMap()
            values["missionStatement"] =
                bounded(translation?.mission.orEmpty(), 1200).ifEmpty { mission }
            values["serviceArea"] =
                bounded(translation?.serviceArea.orEmpty(), 500).ifEmpty {
                    bounded(d.serviceArea, 500)
                }
            values["specialHoursNote"] =
                bounded(translation?.hoursNote.orEmpty(), 1000).ifEmpty {
                    bounded(d.specialHoursNote, 1000)
                }
            values["services"] =
                split(translation?.services.orEmpty().ifBlank { d.services }, 8, 180, "\n")
            values["currentOfferTitle"] =
                bounded(translation?.offerTitle.orEmpty(), 180).ifEmpty {
                    bounded(d.offerTitle, 180)
                }
            values["currentOfferDetails"] =
                bounded(translation?.offerDetails.orEmpty(), 1200).ifEmpty {
                    bounded(d.offerDetails, 1200)
                }
            localized[key] = values
        }
        localization("uk", null)
        if (localized.containsKey("de") || draft.german != OrganizationDirectoryTranslation())
            localization("de", draft.german)
        val fields =
            basic +
                mapOf(
                    "organizationType" to category.ifEmpty { null },
                    "foundedYear" to founded?.toLong(),
                    "foundedMonth" to month?.toLong(),
                    "languages" to split(draft.languages, 12, 60),
                    "missionStatement" to mission.ifEmpty { null },
                    "contactPerson" to bounded(draft.contactPerson, 180).ifEmpty { null },
                    "directoryProfile" to directory,
                    "localizations" to localized,
                ) +
                linkFields.associateWith { url(draft.links[it].orEmpty()).ifEmpty { null } }
        if (!safeFields.containsAll(fields.keys)) fail(OrganizationManagementFailure.INVALID)
        return fields
    }

    fun fail(failure: OrganizationManagementFailure): Nothing =
        throw OrganizationManagementException(failure)
}
