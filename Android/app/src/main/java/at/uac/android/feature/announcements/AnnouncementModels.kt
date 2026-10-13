package at.uac.android.feature.announcements

import at.uac.android.feature.auth.AuthSession

data class AnnouncementText(val uk: String = "", val de: String = "") {
    fun localized(language: String) = if (language == "uk") uk else de
}

data class UserAnnouncement(
    val id: String,
    val schemaVersion: Int,
    val revision: Int,
    val title: AnnouncementText,
    val body: AnnouncementText,
    val groups: List<String>,
    val userIds: List<String>,
    val regions: List<String>,
    val targetPlatforms: List<String>,
    val mode: String,
    val feedback: Boolean,
    val push: Boolean,
    val startsAt: Long,
    val expiresAt: Long,
    val status: String,
    val presentedAt: Long?,
    val acknowledgedAt: Long?,
) {
    fun active(now: Long) =
        schemaVersion == AnnouncementContract.CAPABILITY &&
            mode in AnnouncementContract.MODES &&
            status == "published" &&
            startsAt <= now &&
            expiresAt > now

    fun valid(): Boolean =
        AnnouncementContract.id(id) &&
            revision >= 0 &&
            title.uk.length <= 160 &&
            title.de.length <= 160 &&
            body.uk.length <= 6_000 &&
            body.de.length <= 6_000 &&
            startsAt >= 0 &&
            expiresAt > startsAt &&
            targetPlatforms.isNotEmpty() &&
            targetPlatforms.all { it in setOf("ios", "android") } &&
            groups.all { it in AnnouncementContract.GROUPS } &&
            regions.all { it in AnnouncementContract.REGIONS } &&
            userIds.all(AnnouncementContract::id) &&
            mode in AnnouncementContract.MODES &&
            status in setOf("draft", "published", "cancelled") &&
            (presentedAt == null || presentedAt >= 0) &&
            (acknowledgedAt == null || acknowledgedAt >= 0)
}

data class AnnouncementPage(
    val items: List<UserAnnouncement>,
    val serverNow: Long,
    val cursor: String?,
)

data class AnnouncementSession(
    val uid: String?,
    val revision: Long,
    val available: Boolean,
    val ready: Boolean,
    val owner: Boolean,
) {
    override fun toString() = "AnnouncementSession(uid=[redacted], ready=$ready, owner=$owner)"
}

fun AuthSession.announcementSession(): AnnouncementSession {
    val identity = identity?.takeUnless { it.anonymous }
    val accountAvailable = identity == null || profile?.active == true
    return AnnouncementSession(
        uid = identity?.uid,
        revision = revision,
        available = accountAvailable,
        ready = identity == null || readyForActions,
        owner =
            identity != null &&
                readyForActions &&
                profile?.active == true &&
                profile.globalRole == "owner" &&
                profile.requiresMultiFactorAuth &&
                (totpAuthenticated || passkeyAuthenticated),
    )
}

enum class AnnouncementFailure {
    SIGN_IN,
    NOT_READY,
    DENIED,
    OFFLINE,
    INVALID,
    STALE,
    LIMIT,
    UNKNOWN,
}

class AnnouncementException(val failure: AnnouncementFailure, cause: Throwable? = null) :
    Exception(failure.name, cause)

object AnnouncementContract {
    const val CAPABILITY = 1
    const val PAGE_LIMIT = 100
    val MODES = setOf("once", "acknowledge")
    val GROUPS =
        setOf(
            "registered",
            "guests",
            "organizationOwners",
            "appAdmins",
            "organizationAdmins",
            "organizationModerators",
        )
    val REGIONS =
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

    fun id(value: String) = Regex("[A-Za-z0-9_-]{1,128}").matches(value)

    fun parsePage(value: Any?): AnnouncementPage {
        val map = value as? Map<*, *> ?: fail(AnnouncementFailure.INVALID)
        val raw = map["items"] as? List<*> ?: fail(AnnouncementFailure.INVALID)
        if (raw.size > PAGE_LIMIT) fail(AnnouncementFailure.INVALID)
        val items = raw.map { parse(it, platformScoped = true) }
        val now = (map["serverNow"] as? Number)?.toLong()?.takeIf { it >= 0 }
            ?: fail(AnnouncementFailure.INVALID)
        val cursor = map["cursor"]?.let { it as? String ?: fail(AnnouncementFailure.INVALID) }
        if (cursor != null && !id(cursor)) fail(AnnouncementFailure.INVALID)
        return AnnouncementPage(items, now, cursor)
    }

    fun parse(value: Any?, platformScoped: Boolean = false): UserAnnouncement {
        val map = value as? Map<*, *> ?: fail(AnnouncementFailure.INVALID)
        fun textPair(key: String): AnnouncementText {
            val pair = map[key] as? Map<*, *> ?: fail(AnnouncementFailure.INVALID)
            return AnnouncementText(
                pair["uk"] as? String ?: fail(AnnouncementFailure.INVALID),
                pair["de"] as? String ?: fail(AnnouncementFailure.INVALID),
            )
        }
        fun strings(key: String, maximum: Int): List<String> {
            val values = (map[key] as? List<*>)?.map {
                it as? String ?: fail(AnnouncementFailure.INVALID)
            } ?: emptyList()
            if (values.size > maximum || values.distinct().size != values.size)
                fail(AnnouncementFailure.INVALID)
            return values
        }
        fun number(key: String): Long =
            (map[key] as? Number)?.toLong()?.takeIf { it >= 0 }
                ?: fail(AnnouncementFailure.INVALID)
        val item =
            UserAnnouncement(
                id = map["id"] as? String ?: fail(AnnouncementFailure.INVALID),
                schemaVersion = (map["schemaVersion"] as? Number)?.toInt()
                    ?: fail(AnnouncementFailure.INVALID),
                revision = (map["revision"] as? Number)?.toInt()
                    ?: fail(AnnouncementFailure.INVALID),
                title = textPair("title"),
                body = textPair("body"),
                groups = strings("groups", GROUPS.size),
                userIds = strings("userIds", 100),
                regions = strings("regions", REGIONS.size),
                targetPlatforms =
                    if (platformScoped && !map.containsKey("targetPlatforms")) listOf("android")
                    else strings("targetPlatforms", 2),
                mode = map["mode"] as? String ?: fail(AnnouncementFailure.INVALID),
                feedback = map["feedback"] as? Boolean ?: false,
                push = map["push"] as? Boolean ?: false,
                startsAt = number("startsAt"),
                expiresAt = number("expiresAt"),
                status = map["status"] as? String ?: fail(AnnouncementFailure.INVALID),
                presentedAt = (map["presentedAt"] as? Number)?.toLong(),
                acknowledgedAt = (map["acknowledgedAt"] as? Number)?.toLong(),
            )
        if (!item.valid()) fail(AnnouncementFailure.INVALID)
        return item
    }

    fun fail(failure: AnnouncementFailure): Nothing = throw AnnouncementException(failure)
}

data class AnnouncementState(
    val session: AnnouncementSession? = null,
    val items: List<UserAnnouncement> = emptyList(),
    val active: UserAnnouncement? = null,
    val serverNow: Long = 0,
    val loading: Boolean = false,
    val error: AnnouncementFailure? = null,
    val guestPushEnabled: Boolean = false,
    val pendingPushId: String? = null,
) {
    fun forSession(current: AnnouncementSession) =
        if (session == current) this else AnnouncementState(session = current)
}
