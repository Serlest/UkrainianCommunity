package at.uac.android.feature.subscribers

import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.fold
import at.uac.android.feature.browse.regions
import at.uac.android.feature.community.communityId
import at.uac.android.feature.organization.OrganizationContract
import at.uac.android.feature.personal.validProfileAvatar
import java.text.Collator
import java.time.Instant
import java.util.Locale

data class SubscriberSession(val uid: String, val revision: Long, val ready: Boolean) {
    override fun toString() = "SubscriberSession([redacted], revision=$revision, ready=$ready)"
}

fun AuthSession.subscribersScope(): SubscriberSession? =
    identity
        ?.takeUnless { it.anonymous }
        ?.let {
            SubscriberSession(it.uid, revision, readyForActions && profile?.uid == it.uid)
        }

enum class SubscribersFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    MISSING,
    INVALID,
    STALE,
    POLICY,
    OFFLINE,
    INDEX,
    UNKNOWN,
}

class SubscribersException(val failure: SubscribersFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

enum class SubscriberRole {
    OWNER,
    ADMIN,
    MODERATOR,
    SUBSCRIBER,
}

data class SubscriberReference(val userId: String, val createdAt: Instant, val documentId: String) {
    override fun toString() = "SubscriberReference([redacted])"
}

data class SubscriberCursor(
    val organizationId: String,
    val createdAt: Instant,
    val documentId: String,
    val consumed: Int,
) {
    override fun toString() = "SubscriberCursor([redacted], consumed=$consumed)"
}

data class SubscriberProfile(
    val id: String,
    val displayName: String,
    val avatarUrl: String?,
    val city: String,
    val region: String?,
) {
    override fun toString() = "SubscriberProfile([redacted])"
}

data class SubscriberMember(
    val userId: String,
    val role: SubscriberRole,
    val profile: SubscriberProfile?,
    val followedAt: Instant?,
) {
    override fun toString() =
        "SubscriberMember([redacted], role=$role, unavailable=${profile == null})"
}

data class SubscribersOrganization(
    val content: Content,
    val roles: Map<String, SubscriberRole>,
    val teamTruncated: Boolean,
) {
    val id
        get() = content.id

    override fun toString() = "SubscribersOrganization([redacted], teamTruncated=$teamTruncated)"
}

data class SubscribersSnapshot(
    val session: SubscriberSession,
    val organization: SubscribersOrganization,
    val references: List<SubscriberReference>,
    val members: List<SubscriberMember>,
    val next: SubscriberCursor?,
    val capped: Boolean,
    val unavailable: Int,
) {
    override fun toString() =
        "SubscribersSnapshot([redacted], loaded=${references.size}, capped=$capped)"
}

object SubscribersContract {
    const val PAGE_SIZE = 50
    const val MAX_SUBSCRIBERS = 200
    const val MAX_TEAM = 200

    fun organizationId(value: String) = OrganizationContract.id(value)

    fun userId(value: String) = communityId(value, 128)

    fun documentId(value: String) = communityId(value)

    fun fail(reason: SubscribersFailure): Nothing = throw SubscribersException(reason)

    fun validCursor(id: String, cursor: SubscriberCursor?): Boolean =
        cursor == null ||
            cursor.organizationId == id &&
                documentId(cursor.documentId) &&
                cursor.documentId.startsWith("organization_follow_${id}_") &&
                userId(cursor.documentId.removePrefix("organization_follow_${id}_")) &&
                cursor.consumed in PAGE_SIZE until MAX_SUBSCRIBERS &&
                cursor.consumed % PAGE_SIZE == 0

    /**
     * Read permission is NOT organization-management authority. Approved system organizations are
     * valid.
     */
    fun organization(raw: RawDocument, session: SubscriberSession): SubscribersOrganization {
        if (!session.ready) fail(SubscribersFailure.NOT_READY)
        if (
            !userId(session.uid) ||
                !organizationId(raw.id) ||
                raw.fields["id"]?.let { it != raw.id } == true
        )
            fail(SubscribersFailure.INVALID)
        if (raw.fields["moderationStatus"] != "approved") fail(SubscribersFailure.DENIED)
        val all = linkedMapOf<String, SubscriberRole>()
        fun add(value: Any?, role: SubscriberRole) {
            if (value == null || value == "") return
            val id = value as? String ?: fail(SubscribersFailure.INVALID)
            if (!userId(id)) fail(SubscribersFailure.INVALID)
            all.putIfAbsent(id, role)
        }
        add(raw.fields["ownerId"], SubscriberRole.OWNER)
        for ((field, role) in
            listOf(
                "adminIds" to SubscriberRole.ADMIN,
                "moderatorIds" to SubscriberRole.MODERATOR,
            )) {
            val values =
                raw.fields[field]
                    ?.let { it as? List<*> ?: fail(SubscribersFailure.INVALID) }
                    .orEmpty()
            values.forEach { add(it, role) }
        }
        return SubscribersOrganization(
            Content(ContentKind.ORGANIZATIONS, raw.id, raw.fields),
            all.entries.take(MAX_TEAM).associate { it.toPair() },
            all.size > MAX_TEAM,
        )
    }

    /** Firestore's final tie is UTF-8 document order, not JVM UTF-16 order. */
    fun compareIds(left: String, right: String): Int {
        val a = left.toByteArray(Charsets.UTF_8)
        val b = right.toByteArray(Charsets.UTF_8)
        for (index in 0 until minOf(a.size, b.size)) {
            val comparison = (a[index].toInt() and 255).compareTo(b[index].toInt() and 255)
            if (comparison != 0) return comparison
        }
        return a.size.compareTo(b.size)
    }

    fun order(left: SubscriberReference, right: SubscriberReference): Int =
        right.createdAt.compareTo(left.createdAt).takeIf { it != 0 }
            ?: compareIds(right.documentId, left.documentId)

    fun page(
        rows: List<RawDocument>,
        id: String,
        after: SubscriberCursor?,
    ): List<SubscriberReference> {
        if (!organizationId(id) || rows.size > PAGE_SIZE + 1 || !validCursor(id, after))
            fail(SubscribersFailure.INVALID)
        val parsed = rows.map { row ->
            val uid = row.fields["userId"] as? String ?: fail(SubscribersFailure.INVALID)
            val time = row.fields["createdAt"] as? Instant ?: fail(SubscribersFailure.INVALID)
            if (
                !userId(uid) ||
                    !documentId(row.id) ||
                    row.id != "organization_follow_${id}_$uid" ||
                    row.fields["subscribedOrganizationId"] != id ||
                    row.fields["id"]?.let { it != row.id } == true ||
                    row.fields.keys.any {
                        it !in setOf("id", "userId", "subscribedOrganizationId", "createdAt")
                    }
            )
                fail(SubscribersFailure.INVALID)
            SubscriberReference(uid, time, row.id)
        }
        if (
            parsed.zipWithNext().any { order(it.first, it.second) >= 0 } ||
                after?.let { cursor ->
                    parsed.firstOrNull()?.let {
                        order(SubscriberReference("", cursor.createdAt, cursor.documentId), it) >= 0
                    }
                } == true
        )
            fail(SubscribersFailure.INVALID)
        return parsed
    }

    fun profile(id: String, raw: RawDocument?): SubscriberProfile? {
        if (
            !userId(id) || raw == null || raw.id != id || raw.fields["id"]?.let { it != id } == true
        )
            return null
        fun clean(field: String, max: Int) =
            (raw.fields[field] as? String).orEmpty().filterNot(Char::isISOControl).trim().take(max)
        val name = clean("displayName", 160).takeIf(String::isNotEmpty) ?: return null
        val avatar =
            (raw.fields["avatarURL"] as? String)?.takeIf {
                it.length <= 2_048 && validProfileAvatar(it, id) && it.isNotBlank()
            }
        val region =
            (raw.fields["federalState"] as? String)?.takeIf { value ->
                regions.any { it.first == value }
            }
        return SubscriberProfile(id, name, avatar, clean("city", 160), region)
    }

    fun members(
        organization: SubscribersOrganization,
        refs: List<SubscriberReference>,
        profiles: Map<String, SubscriberProfile>,
        visibleAuthor: (String?) -> Boolean,
    ): List<SubscriberMember> {
        val followed = refs.associateBy { it.userId }
        val ids = (organization.roles.keys + followed.keys).distinct()
        return ids.filter(visibleAuthor).mapNotNull { id ->
            val profile = profiles[id]
            val role = organization.roles[id]
            if (profile == null && role == null) null
            else
                SubscriberMember(
                    id,
                    role ?: SubscriberRole.SUBSCRIBER,
                    profile,
                    followed[id]?.createdAt,
                )
        }
    }

    fun visible(
        members: List<SubscriberMember>,
        search: String,
        language: String,
        author: (String?) -> Boolean,
    ): List<SubscriberMember> {
        val collator =
            Collator.getInstance(Locale.forLanguageTag(if (language == "uk") "uk" else "de"))
        val query = fold(search.trim())
        return members
            .filter { author(it.userId) && fold(it.profile?.displayName.orEmpty()).contains(query) }
            .sortedWith { a, b ->
                a.role.ordinal.compareTo(b.role.ordinal).takeIf { it != 0 }
                    ?: (if (a.role == SubscriberRole.SUBSCRIBER)
                        compareValues(b.followedAt, a.followedAt).takeIf { it != 0 }
                    else null)
                    ?: collator
                        .compare(a.profile?.displayName.orEmpty(), b.profile?.displayName.orEmpty())
                        .takeIf { it != 0 }
                    ?: compareIds(a.userId, b.userId)
            }
    }
}
