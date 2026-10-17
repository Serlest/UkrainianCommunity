package at.uac.android.feature.featuredmanagement

import java.time.Instant

enum class FeaturedAction(val wire: String) {
    NONE("none"), NEWS("news"), EVENT("event"), ORGANIZATION("organization"), EXTERNAL_URL("externalURL");

    val needsTarget get() = this in setOf(NEWS, EVENT, ORGANIZATION)
}

enum class FeaturedRegion(val wire: String) { ALL_AUSTRIA("allAustria"), FEDERAL_STATE("federalState") }

enum class FeaturedSection(val wire: String) { HOME("home"), EVENTS("events"), ORGANIZATIONS("organizations"), DIRECTORY("directory") }

data class FeaturedLocalized(val title: String = "", val subtitle: String = "")

data class FeaturedDraft(
    val id: String,
    val internalName: String = "",
    val localizations: Map<String, FeaturedLocalized> = mapOf("uk" to FeaturedLocalized(), "de" to FeaturedLocalized()),
    val title: String = "",
    val subtitle: String = "",
    val imageUrl: String = "",
    val action: FeaturedAction = FeaturedAction.NONE,
    val actionTargetId: String = "",
    val externalUrl: String = "",
    val region: FeaturedRegion = FeaturedRegion.ALL_AUSTRIA,
    val federalState: String = "",
    val sections: Set<FeaturedSection> = setOf(FeaturedSection.HOME),
    val displayDurationSeconds: Int = 6,
    val priority: Int = 0,
    val active: Boolean = false,
    val startsAt: Instant? = null,
    val endsAt: Instant? = null,
)

data class FeaturedVersion(val id: String, val updatedAt: Instant, val fingerprint: String)

data class FeaturedBanner(
    val draft: FeaturedDraft,
    val version: FeaturedVersion,
    val createdAt: Instant,
    val createdBy: String,
    val updatedBy: String?,
    val repairRequired: Boolean = false,
) {
    val id get() = draft.id
}

enum class FeaturedFailure { ACCESS, INVALID, MISSING, CONFLICT, OFFLINE, UNCONFIRMED, IMAGE, BUSY }

class FeaturedException(val failure: FeaturedFailure, cause: Throwable? = null) : Exception(failure.name, cause)

data class FeaturedReceipt(val id: String, val updatedAt: Instant)

data class FeaturedState(
    val sessionOwner: String? = null,
    val loading: Boolean = false,
    val banners: List<FeaturedBanner> = emptyList(),
    val editing: FeaturedDraft? = null,
    val editingVersion: FeaturedVersion? = null,
    val saving: Boolean = false,
    val uploading: Boolean = false,
    val failure: FeaturedFailure? = null,
    val unconfirmed: Boolean = false,
)
