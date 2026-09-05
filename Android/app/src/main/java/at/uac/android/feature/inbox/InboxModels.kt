package at.uac.android.feature.inbox

import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.safeHttps
import at.uac.android.feature.personal.validDocumentId
import java.time.Instant

data class InboxSession(val uid: String, val revision: Long, val canEditPreferences: Boolean)

enum class InboxFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    OFFLINE,
    MISSING,
    INVALID,
    UNKNOWN,
}

class InboxException(val reason: InboxFailure, cause: Throwable? = null) :
    Exception(reason.name, cause)

enum class InboxMutation {
    READ,
    UNREAD,
    ARCHIVE,
    DELETE,
    POPUP_PRESENTED,
}

data class InboxPreferences(
    val notificationsEnabled: Boolean = false,
    val eventRemindersEnabled: Boolean = true,
    val reminderLeadMinutes: Int = 60,
) {
    fun valid(): Boolean = reminderLeadMinutes in 0..10_080
}

enum class InboxKind(val wire: String, val de: String, val uk: String) {
    ORGANIZATION_REQUEST(
        "organizationRequestSubmitted",
        "Neue Organisationsanfrage",
        "Нова заявка організації",
    ),
    COMMENT("commentAdded", "Neuer Kommentar", "Новий коментар"),
    MODERATION("contentModerationChanged", "Moderation aktualisiert", "Модерацію оновлено"),
    PARTICIPATION("eventParticipationChanged", "Teilnahme aktualisiert", "Участь оновлено"),
    FEEDBACK_SUBMITTED("feedbackSubmitted", "Neue Rückmeldung", "Нове звернення"),
    FEEDBACK_REPLY("feedbackReply", "Antwort auf deine Rückmeldung", "Відповідь на ваше звернення"),
    ORGANIZATION_APPROVED(
        "organizationRequestApproved",
        "Organisation freigegeben",
        "Організацію схвалено",
    ),
    ORGANIZATION_REVISION(
        "organizationRequestNeedsRevision",
        "Anfrage überarbeiten",
        "Доопрацюйте заявку",
    ),
    ORGANIZATION_REJECTED("organizationRequestRejected", "Anfrage abgelehnt", "Заявку відхилено"),
    ORGANIZATION_CLEANUP(
        "organizationRequestCleanupWarning",
        "Anfrage läuft bald ab",
        "Термін заявки скоро спливе",
    ),
    ORGANIZATION_EXPIRED("organizationRequestExpired", "Anfrage abgelaufen", "Термін заявки сплив"),
    ACCOUNT_STATUS(
        "accountStatusChanged",
        "Kontostatus aktualisiert",
        "Статус облікового запису оновлено",
    ),
    LEGAL(
        "legalDocumentsUpdated",
        "Rechtliche Dokumente aktualisiert",
        "Правові документи оновлено",
    ),
    NEWS("organizationNewsPublished", "Neue Nachricht", "Нова новина"),
    EVENT("organizationEventPublished", "Neue Veranstaltung", "Нова подія"),
    ROLE("roleChanged", "Rolle aktualisiert", "Роль оновлено"),
    ORGANIZATION_ROLE_ASSIGNED(
        "organizationRoleAssigned",
        "Organisationsrolle zugewiesen",
        "Призначено роль в організації",
    ),
    ORGANIZATION_ROLE_REMOVED(
        "organizationRoleRemoved",
        "Organisationsrolle entfernt",
        "Роль в організації скасовано",
    ),
    REPORT("reportReviewed", "Meldung geprüft", "Скаргу розглянуто"),
    EVENT_UPDATED("eventUpdated", "Veranstaltung aktualisiert", "Подію оновлено"),
    EVENT_CANCELLED("eventCancelled", "Veranstaltung abgesagt", "Подію скасовано"),
    EVENT_REGISTERED(
        "eventRegistrationConfirmed",
        "Anmeldung bestätigt",
        "Реєстрацію підтверджено",
    ),
    SYSTEM("systemAnnouncement", "Mitteilung", "Повідомлення"),
    DRAFT("contentDraftReady", "Entwurf bereit", "Чернетка готова"),
    UNKNOWN("unknown", "Mitteilung", "Повідомлення");

    fun title(language: String): String = if (language == "uk") uk else de

    val defaultAction: String
        get() =
            when (this) {
                FEEDBACK_SUBMITTED,
                FEEDBACK_REPLY -> "openFeedback"
                ORGANIZATION_REQUEST,
                ORGANIZATION_APPROVED,
                ORGANIZATION_REVISION,
                ORGANIZATION_REJECTED,
                ORGANIZATION_CLEANUP -> "openOrganizationRequest"
                ORGANIZATION_ROLE_ASSIGNED,
                ORGANIZATION_ROLE_REMOVED -> "openOrganization"
                EVENT_UPDATED,
                EVENT_CANCELLED,
                EVENT_REGISTERED,
                EVENT -> "openEvent"
                NEWS -> "openNews"
                LEGAL -> "openLegalDocuments"
                ACCOUNT_STATUS,
                ROLE,
                ORGANIZATION_EXPIRED -> "openProfile"
                DRAFT -> "openContentPlanning"
                else -> "none"
            }

    val defaultSeverity: String
        get() =
            when (this) {
                ORGANIZATION_APPROVED -> "success"
                ORGANIZATION_REVISION,
                ORGANIZATION_REJECTED,
                ORGANIZATION_CLEANUP,
                ORGANIZATION_EXPIRED,
                ACCOUNT_STATUS,
                EVENT_CANCELLED -> "warning"
                LEGAL,
                SYSTEM -> "critical"
                else -> "info"
            }

    companion object {
        fun parse(value: String?): InboxKind = entries.firstOrNull { it.wire == value } ?: UNKNOWN
    }
}

enum class InboxDestinationKind {
    NEWS,
    EVENT,
    ORGANIZATION,
    ORGANIZATION_REQUEST,
    FEEDBACK,
    DSA_STATEMENT,
    LEGAL,
    PROFILE,
    CONTENT_PLANNING,
    URL,
    ANNOUNCEMENT,
}

data class InboxDestination(val kind: InboxDestinationKind, val target: String? = null)

/** A route is a request to re-fetch a destination, never authority to view private content. */
object InboxRoutes {
    private val sources =
        setOf(
            "feedback",
            "organization",
            "account",
            "legal",
            "profile",
            "event",
            "system",
            "contentDraft",
        )
    private val actions =
        setOf(
            "none",
            "openNews",
            "openFeedback",
            "openDsaStatement",
            "openOrganization",
            "openOrganizationRequest",
            "openEvent",
            "openLegalDocuments",
            "openProfile",
            "openContentPlanning",
            "openURL",
        )

    fun fromPush(data: Map<String, String>): InboxDestination? {
        if (InboxKind.parse(data["type"]) == InboxKind.UNKNOWN) return null
        val source = nonEmpty(data["sourceType"])
        if (source != null && source !in sources) return null
        val action = nonEmpty(data["actionType"]) ?: "none"
        if (action !in actions) return null
        val route =
            nonEmpty(data["route"])
                ?: if (action != "none") action
                else
                    when (source) {
                        "event" -> "openEvent"
                        "organization" -> "openOrganization"
                        "feedback" -> "openFeedback"
                        "contentDraft" -> "openContentPlanning"
                        "account",
                        "profile" -> "openProfile"
                        else -> "none"
                    }
        return destination(
            route,
            firstText(
                data["routeTargetId"],
                data["targetId"],
                data["targetID"],
                data["actionTargetId"],
                data["sourceId"],
            ),
        )
    }

    fun destination(route: String, target: String?): InboxDestination? {
        val kind =
            when (route) {
                "openNews",
                "news" -> InboxDestinationKind.NEWS
                "openEvent",
                "event" -> InboxDestinationKind.EVENT
                "openOrganization",
                "organization" -> InboxDestinationKind.ORGANIZATION
                "openOrganizationRequest",
                "organizationRequest" -> InboxDestinationKind.ORGANIZATION_REQUEST
                "openFeedback",
                "feedback" -> InboxDestinationKind.FEEDBACK
                "openDsaStatement",
                "dsaStatement" -> InboxDestinationKind.DSA_STATEMENT
                "openLegalDocuments",
                "legalDocuments",
                "legal" -> InboxDestinationKind.LEGAL
                "openProfile",
                "profile" -> InboxDestinationKind.PROFILE
                "openContentPlanning",
                "contentPlanning" -> InboxDestinationKind.CONTENT_PLANNING
                "openURL",
                "url" -> InboxDestinationKind.URL
                "systemAnnouncement",
                "announcement",
                "none" -> InboxDestinationKind.ANNOUNCEMENT
                else -> return null
            }
        if (kind == InboxDestinationKind.URL)
            return safeHttps(target.orEmpty())?.let { InboxDestination(kind, it) }
        if (
            kind in
                setOf(
                    InboxDestinationKind.LEGAL,
                    InboxDestinationKind.PROFILE,
                    InboxDestinationKind.ANNOUNCEMENT,
                )
        )
            return InboxDestination(kind)
        if (target != null && !validDocumentId(target)) return null
        if (
            target == null &&
                kind in
                    setOf(
                        InboxDestinationKind.NEWS,
                        InboxDestinationKind.EVENT,
                        InboxDestinationKind.ORGANIZATION,
                        InboxDestinationKind.DSA_STATEMENT,
                    )
        )
            return null
        return InboxDestination(kind, target)
    }
}

data class InboxNotice(
    val id: String,
    val uid: String,
    val kind: InboxKind,
    val createdAt: Instant,
    val isRead: Boolean,
    val actionType: String = "none",
    val sourceId: String? = null,
    val actionTargetId: String? = null,
    val title: String? = null,
    val message: String? = null,
    val actorName: String? = null,
    val severity: String = "info",
    val requiresPopup: Boolean = false,
    val popupPresentedAt: Instant? = null,
    val expiresAt: Instant? = null,
    val archivedAt: Instant? = null,
    val deletedAt: Instant? = null,
    val metadata: Map<String, String> = emptyMap(),
    val payload: Map<String, String> = emptyMap(),
) {
    val visible: Boolean
        get() = deletedAt == null

    // Build 65 keeps archived messages visible, but excludes them from the unread badge.
    val unread: Boolean
        get() = !isRead && archivedAt == null && deletedAt == null

    fun destination(now: Instant): InboxDestination? {
        if (
            !visible ||
                kind == InboxKind.UNKNOWN ||
                actionType == "none" ||
                expiresAt?.let { it <= now } == true
        )
            return null
        val target =
            if (actionType == "openURL") firstText(actionTargetId, metadata["url"], payload["url"])
            else
                firstText(
                    actionTargetId,
                    sourceId,
                    payload["routeTargetId"],
                    metadata["routeTargetId"],
                    metadata["targetId"],
                    metadata["targetID"],
                    metadata["url"],
                )
        return InboxRoutes.destination(actionType, target)
    }

    fun displayTitle(language: String): String =
        title?.takeUnless { it.startsWith("notifications.") } ?: kind.title(language)

    fun displayBody(language: String): String =
        firstText(
                message,
                metadata["message"],
                payload["message"],
                payload["reviewMessage"],
                payload["rejectionReason"],
                payload["messagePreview"],
                payload["contentTitle"],
                metadata["eventTitle"],
                metadata["reason"],
            )
            ?.takeUnless { it.startsWith("notifications.") }
            ?: if (language == "uk") "Відкрийте повідомлення, щоб переглянути подробиці."
            else "Öffne die Mitteilung, um weitere Informationen zu sehen."
}

internal fun nonEmpty(value: String?): String? = value?.trim()?.takeIf { it.isNotEmpty() }

internal fun firstText(vararg values: String?): String? = values.firstNotNullOfOrNull(::nonEmpty)

fun decodeInboxNotice(uid: String, row: RawDocument): InboxNotice? {
    if (!validDocumentId(uid) || !validDocumentId(row.id)) return null
    val f = row.fields
    val created = f["createdAt"] as? Instant ?: return null
    if (f["isRead"] !is Boolean) return null
    val dates = listOf("popupPresentedAt", "expiresAt", "archivedAt", "deletedAt")
    if (dates.any { f[it] != null && f[it] !is Instant }) return null
    fun text(key: String): String? =
        (f[key] as? String)?.takeIf { it.length <= 16_384 }?.let(::nonEmpty)
    fun strings(key: String): Map<String, String> =
        (f[key] as? Map<*, *>)
            ?.entries
            ?.take(64)
            ?.mapNotNull { (k, v) ->
                if (k is String && v is String && k.length <= 160 && v.length <= 16_384) k to v
                else null
            }
            ?.toMap()
            .orEmpty()
    val kind = InboxKind.parse(text("type"))
    return InboxNotice(
        row.id,
        uid,
        kind,
        created,
        f["isRead"] as Boolean,
        text("actionType") ?: kind.defaultAction,
        text("sourceId"),
        text("actionTargetId"),
        text("title"),
        text("message"),
        text("actorDisplayName"),
        text("severity")?.takeIf { it in setOf("info", "success", "warning", "critical") }
            ?: kind.defaultSeverity,
        f["requiresPopup"] == true,
        f["popupPresentedAt"] as? Instant,
        f["expiresAt"] as? Instant,
        f["archivedAt"] as? Instant,
        f["deletedAt"] as? Instant,
        strings("metadata"),
        strings("payload"),
    )
}

fun decodeInboxPreferences(fields: Fields?): InboxPreferences {
    if (fields == null) return InboxPreferences()
    val enabled =
        fields["notificationsEnabled"] as? Boolean ?: throw InboxException(InboxFailure.INVALID)
    val reminders =
        fields["eventRemindersEnabled"] as? Boolean ?: throw InboxException(InboxFailure.INVALID)
    val lead = fields["reminderLeadMinutes"]
    val minutes =
        when (lead) {
            is Long -> lead
            is Int -> lead.toLong()
            else -> throw InboxException(InboxFailure.INVALID)
        }
    if (minutes !in 0..10_080) throw InboxException(InboxFailure.INVALID)
    return InboxPreferences(enabled, reminders, minutes.toInt())
}

data class InboxCursor(val createdAt: Instant, val id: String)

data class InboxRawPage(val rows: List<RawDocument>, val next: InboxCursor?, val hasMore: Boolean)

data class InboxPage(
    val items: List<InboxNotice>,
    val next: InboxCursor?,
    val hasMore: Boolean,
    val invalid: Int,
)

data class InboxBulkResult(val changed: Int, val complete: Boolean)
