package at.uac.android.feature.featuredmanagement

import at.uac.android.feature.moderation.ModerationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext

class FeaturedManagementRepository(
    private val source: FeaturedManagementSource,
    private val authority: () -> ModerationSession?,
) {
    private val mutation = Mutex()

    private fun ensure(session: ModerationSession) {
        FeaturedManagementContract.requireOwner(session)
        if (authority() != session) throw CancellationException("Featured owner scope changed")
    }

    suspend fun list(session: ModerationSession): List<FeaturedBanner> {
        ensure(session)
        return source.list(session).also { ensure(session) }
    }

    suspend fun save(session: ModerationSession, draft: FeaturedDraft, expected: FeaturedVersion?): FeaturedBanner {
        if (!mutation.tryLock()) FeaturedManagementContract.fail(FeaturedFailure.BUSY)
        try {
            currentCoroutineContext().ensureActive()
            ensure(session)
            FeaturedManagementContract.validate(draft)
            val current = source.find(session, draft.id)
            if (expected == null && current != null) FeaturedManagementContract.fail(FeaturedFailure.CONFLICT)
            if (expected != null && current?.version != expected) FeaturedManagementContract.fail(if (current == null) FeaturedFailure.MISSING else FeaturedFailure.CONFLICT)
            ensure(session)
            currentCoroutineContext().ensureActive()
            val confirmed = withContext(NonCancellable) {
                val receipt = source.save(session, draft, expected == null)
                try {
                    source.find(session, draft.id)?.takeIf { it.version.updatedAt == receipt.updatedAt && it.version.fingerprint == FeaturedManagementContract.fingerprint(draft) }
                        ?: FeaturedManagementContract.fail(FeaturedFailure.UNCONFIRMED)
                } catch (error: FeaturedException) {
                    if (error.failure == FeaturedFailure.UNCONFIRMED) throw error
                    throw FeaturedException(FeaturedFailure.UNCONFIRMED, error)
                }
            }
            ensure(session)
            return confirmed
        } finally { mutation.unlock() }
    }

    suspend fun setActive(session: ModerationSession, banner: FeaturedBanner, active: Boolean): FeaturedBanner {
        if (!mutation.tryLock()) FeaturedManagementContract.fail(FeaturedFailure.BUSY)
        try {
            ensure(session)
            if (banner.repairRequired && active) FeaturedManagementContract.fail(FeaturedFailure.INVALID)
            val fresh = source.find(session, banner.id) ?: FeaturedManagementContract.fail(FeaturedFailure.MISSING)
            if (fresh.version != banner.version) FeaturedManagementContract.fail(FeaturedFailure.CONFLICT)
            val confirmed = withContext(NonCancellable) {
                val receipt = source.setActive(session, banner.id, active)
                try {
                    source.find(session, banner.id)?.takeIf { it.version.updatedAt == receipt.updatedAt && it.draft.active == active }
                        ?: FeaturedManagementContract.fail(FeaturedFailure.UNCONFIRMED)
                } catch (error: FeaturedException) {
                    if (error.failure == FeaturedFailure.UNCONFIRMED) throw error
                    throw FeaturedException(FeaturedFailure.UNCONFIRMED, error)
                }
            }
            ensure(session)
            return confirmed
        } finally { mutation.unlock() }
    }

    suspend fun delete(session: ModerationSession, banner: FeaturedBanner) {
        if (!mutation.tryLock()) FeaturedManagementContract.fail(FeaturedFailure.BUSY)
        try {
            ensure(session)
            val fresh = source.find(session, banner.id) ?: FeaturedManagementContract.fail(FeaturedFailure.MISSING)
            if (fresh.version != banner.version) FeaturedManagementContract.fail(FeaturedFailure.CONFLICT)
            withContext(NonCancellable) {
                source.delete(session, banner.id)
                try {
                    if (source.find(session, banner.id) != null) FeaturedManagementContract.fail(FeaturedFailure.UNCONFIRMED)
                } catch (error: FeaturedException) {
                    if (error.failure == FeaturedFailure.UNCONFIRMED) throw error
                    throw FeaturedException(FeaturedFailure.UNCONFIRMED, error)
                }
            }
            ensure(session)
        } finally { mutation.unlock() }
    }

    suspend fun upload(session: ModerationSession, id: String, jpeg: ByteArray): String {
        ensure(session)
        return source.upload(session, id, jpeg).also { ensure(session) }
    }
}
