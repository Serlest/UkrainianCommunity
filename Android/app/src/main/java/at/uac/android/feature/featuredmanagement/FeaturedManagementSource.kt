package at.uac.android.feature.featuredmanagement

import at.uac.android.feature.moderation.ModerationSession

interface FeaturedManagementSource {
    suspend fun list(session: ModerationSession): List<FeaturedBanner>
    suspend fun find(session: ModerationSession, id: String): FeaturedBanner?
    suspend fun save(session: ModerationSession, draft: FeaturedDraft, create: Boolean): FeaturedReceipt
    suspend fun setActive(session: ModerationSession, id: String, active: Boolean): FeaturedReceipt
    suspend fun delete(session: ModerationSession, id: String): FeaturedReceipt
    suspend fun upload(session: ModerationSession, bannerId: String, jpeg: ByteArray): String
}

fun interface FeaturedImagePreparation { suspend fun prepare(contentUri: String): ByteArray }
