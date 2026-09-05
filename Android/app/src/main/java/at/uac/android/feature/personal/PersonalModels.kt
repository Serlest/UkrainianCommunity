package at.uac.android.feature.personal

import at.uac.android.core.LocalStorage
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.regions
import at.uac.android.feature.browse.safeHttps
import at.uac.android.feature.browse.string
import at.uac.android.feature.browse.time
import java.time.Instant

/** Supplied by the authoritative auth gate, never inferred from an editable profile form. */
data class PersonalSession(
    val uid: String,
    val emailVerified: Boolean,
    val active: Boolean,
    val revision: Long,
) {
    val ready: Boolean
        get() = uid.isNotBlank() && emailVerified && active
}

enum class PersonalFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    OFFLINE,
    MISSING,
    INVALID,
    UNKNOWN,
}

class PersonalException(val reason: PersonalFailure, cause: Throwable? = null) :
    Exception(reason.name, cause)

data class ProfileDraft(
    val fullName: String = "",
    val displayName: String = "",
    val city: String = "",
    val bio: String = "",
    val telegramUsername: String = "",
    val federalState: String = "",
    val avatarUrl: String = "",
) {
    fun normalized(): ProfileDraft =
        copy(
            fullName = fullName.trim(),
            displayName = displayName.trim(),
            city = city.trim(),
            bio = bio.trim(),
            telegramUsername = telegramUsername.trim(),
            federalState = federalState.trim(),
            avatarUrl = avatarUrl.trim(),
        )

    fun valid(): Boolean = validFor(null)

    /** HTTP is accepted only for this named demo bucket's exact own canonical avatar object. */
    fun validFor(uid: String?): Boolean =
        normalized().let {
            it.fullName.length in 1..160 &&
                it.displayName.length in 1..160 &&
                it.city.length <= 160 &&
                it.bio.length <= 2_000 &&
                it.telegramUsername.length <= 80 &&
                regions.any { region -> region.first == it.federalState } &&
                it.avatarUrl.length <= 2_048 &&
                validProfileAvatar(it.avatarUrl, uid) &&
                listOf(it.fullName, it.displayName, it.city, it.telegramUsername).none { field ->
                    field.any(Char::isISOControl)
                }
        }
}

fun validProfileAvatar(value: String, uid: String?): Boolean =
    value.isEmpty() ||
        safeHttps(value) != null ||
        uid != null &&
            validDocumentId(uid) &&
            LocalStorage.urlMatches(value, "profileImages/$uid/avatar.jpg")

data class PersonalProfile(
    val uid: String,
    val email: String,
    val draft: ProfileDraft,
    val updatedAt: Instant?,
)

fun decodePersonalProfile(uid: String, fields: Fields): PersonalProfile {
    if (
        fields.string("id") != uid ||
            fields["email"] !is String ||
            fields["fullName"] !is String ||
            fields["city"] !is String ||
            fields["bio"] !is String
    )
        throw PersonalException(PersonalFailure.INVALID)
    return PersonalProfile(
        uid,
        fields.string("email"),
        ProfileDraft(
            fullName = fields.string("fullName"),
            displayName = fields.string("displayName").ifEmpty { fields.string("fullName") },
            city = fields.string("city"),
            bio = fields.string("bio"),
            telegramUsername = fields.string("telegramUsername"),
            federalState = fields.string("selectedFederalState"),
            avatarUrl = fields.string("avatarURL"),
        ),
        fields.time("updatedAt"),
    )
}

data class PersonalTarget(val kind: ContentKind, val id: String) {
    init {
        require(validDocumentId(id))
    }

    val key: String
        get() = "${kind.collection}/$id"

    val referenceField: String
        get() =
            when (kind) {
                ContentKind.NEWS -> "newsId"
                ContentKind.EVENTS -> "eventId"
                ContentKind.ORGANIZATIONS -> "organizationId"
            }

    val bookmarkCollection: String
        get() =
            when (kind) {
                ContentKind.NEWS -> "newsBookmarks"
                ContentKind.EVENTS -> "eventBookmarks"
                ContentKind.ORGANIZATIONS -> "organizationBookmarks"
            }
}

enum class PersonalAction {
    LIKE,
    BOOKMARK,
    SUBSCRIBE,
}

/** Canonical IDs and fields mirror the live iOS repository and unchanged Firestore Rules. */
data class PersonalMarker(val target: PersonalTarget, val uid: String, val action: PersonalAction) {
    init {
        require(validDocumentId(uid))
        require(action != PersonalAction.SUBSCRIBE || target.kind == ContentKind.ORGANIZATIONS)
        if (action == PersonalAction.LIKE) {
            require(
                target.kind != ContentKind.NEWS ||
                    !target.id.startsWith("event_") && !target.id.startsWith("organization_")
            )
            require(target.kind != ContentKind.ORGANIZATIONS || !target.id.startsWith("follow_"))
        }
    }

    val id: String
        get() =
            when (action) {
                PersonalAction.BOOKMARK -> target.id
                PersonalAction.SUBSCRIBE -> "organization_follow_${target.id}_$uid"
                PersonalAction.LIKE ->
                    when (target.kind) {
                        ContentKind.NEWS -> "${target.id}_$uid"
                        ContentKind.EVENTS -> "event_${target.id}_$uid"
                        ContentKind.ORGANIZATIONS -> "organization_${target.id}_$uid"
                    }
            }

    val path: String
        get() =
            if (action == PersonalAction.BOOKMARK) "users/$uid/${target.bookmarkCollection}/$id"
            else "likes/$id"

    val referenceField: String
        get() =
            if (action == PersonalAction.SUBSCRIBE) "subscribedOrganizationId"
            else target.referenceField

    fun identityFields(): Map<String, String> =
        mapOf("id" to id, "userId" to uid, referenceField to target.id)

    fun matches(row: RawDocument): Boolean =
        row.id == id && identityFields().all { (key, value) -> row.fields[key] == value }
}

fun validDocumentId(value: String): Boolean =
    value.isNotBlank() &&
        '/' !in value &&
        value != "." &&
        value != ".." &&
        value.toByteArray(Charsets.UTF_8).size <= 1_500 &&
        !value.any(Char::isISOControl)

data class PersonalActions(
    val liked: Boolean = false,
    val bookmarked: Boolean = false,
    val subscribed: Boolean = false,
) {
    fun selected(action: PersonalAction): Boolean =
        when (action) {
            PersonalAction.LIKE -> liked
            PersonalAction.BOOKMARK -> bookmarked
            PersonalAction.SUBSCRIBE -> subscribed
        }

    fun with(action: PersonalAction, value: Boolean): PersonalActions =
        when (action) {
            PersonalAction.LIKE -> copy(liked = value)
            PersonalAction.BOOKMARK -> copy(bookmarked = value)
            PersonalAction.SUBSCRIBE -> copy(subscribed = value)
        }
}

data class PersonalListPage(
    val items: List<Content>,
    val next: String?,
    val hasMore: Boolean,
    val unavailable: Int,
)

data class MarkerPage(val rows: List<RawDocument>, val next: String?, val hasMore: Boolean)

/** Private data stays in memory and is dropped on every auth revision/account change. */
data class PersonalState(
    val session: PersonalSession? = null,
    val profile: PersonalProfile? = null,
    val profileLoading: Boolean = false,
    val profileSaving: Boolean = false,
    val profileSaved: Boolean = false,
    val profileError: PersonalFailure? = null,
    val actions: Map<PersonalTarget, PersonalActions> = emptyMap(),
    val actionsLoading: Set<PersonalTarget> = emptySet(),
    val actionsPending: Set<PersonalTarget> = emptySet(),
    val actionErrors: Map<PersonalTarget, PersonalFailure> = emptyMap(),
    val saved: Map<ContentKind, PersonalListPage> = emptyMap(),
    val savedLoading: Boolean = false,
    val savedError: PersonalFailure? = null,
    val subscriptions: PersonalListPage? = null,
    val subscriptionsLoading: Boolean = false,
    val subscriptionsError: PersonalFailure? = null,
)
