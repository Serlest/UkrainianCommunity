package at.uac.android.feature.subscribers

import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.RawDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow

interface SubscribersSource {
    suspend fun organization(id: String, session: SubscriberSession): RawDocument?

    suspend fun page(
        id: String,
        after: SubscriberCursor?,
        session: SubscriberSession,
    ): List<RawDocument>

    suspend fun profiles(ids: List<String>, session: SubscriberSession): List<RawDocument>

    /**
     * Bounded invalidations, not data/authority: success requires hiding retained rows and fresh
     * SERVER verification. Includes uncertain cache/pending-write metadata. Actual terminal
     * listener errors remain failures.
     */
    fun changes(id: String, session: SubscriberSession): Flow<Result<Unit>>
}

class SubscribersRepository(
    private val source: SubscribersSource,
    private val authority: () -> SubscriberSession?,
    private val visibleOrganization: (Content) -> Boolean,
    private val visibleAuthor: (String?) -> Boolean,
) {
    private fun current(session: SubscriberSession) {
        if (authority() != session) throw CancellationException("Subscriber session changed")
    }

    private suspend fun organization(
        id: String,
        session: SubscriberSession,
    ): SubscribersOrganization {
        current(session)
        val raw =
            source.organization(id, session).also { current(session) }
                ?: SubscribersContract.fail(SubscribersFailure.MISSING)
        if (raw.id != id) SubscribersContract.fail(SubscribersFailure.INVALID)
        val value = SubscribersContract.organization(raw, session)
        if (!visibleOrganization(value.content)) SubscribersContract.fail(SubscribersFailure.POLICY)
        return value
    }

    suspend fun load(id: String, previous: SubscribersSnapshot? = null): SubscribersSnapshot {
        val session = authority() ?: SubscribersContract.fail(SubscribersFailure.SIGN_IN)
        if (!session.ready) SubscribersContract.fail(SubscribersFailure.NOT_READY)
        if (
            !SubscribersContract.organizationId(id) ||
                previous?.let {
                    it.session != session ||
                        it.organization.id != id ||
                        it.next == null ||
                        it.capped ||
                        it.references.size != it.next.consumed ||
                        it.references.size >= SubscribersContract.MAX_SUBSCRIBERS ||
                        it.references.lastOrNull()?.documentId != it.next.documentId ||
                        it.references.lastOrNull()?.createdAt != it.next.createdAt
                } == true ||
                !SubscribersContract.validCursor(id, previous?.next)
        )
            SubscribersContract.fail(SubscribersFailure.INVALID)
        val before = organization(id, session)
        if (previous != null && previous.organization != before)
            SubscribersContract.fail(SubscribersFailure.STALE)
        val rows = source.page(id, previous?.next, session).also { current(session) }
        val parsed = SubscribersContract.page(rows, id, previous?.next)
        val page = parsed.take(SubscribersContract.PAGE_SIZE)
        val references = previous?.references.orEmpty() + page
        if (
            references.size > SubscribersContract.MAX_SUBSCRIBERS ||
                references.distinctBy { it.userId }.size != references.size
        )
            SubscribersContract.fail(SubscribersFailure.INVALID)
        val requested =
            (before.roles.keys + references.map { it.userId }).distinct().filter(visibleAuthor)
        val profiles = linkedMapOf<String, SubscriberProfile>()
        for (ids in requested.chunked(10)) {
            current(session)
            val joined = source.profiles(ids, session).also { current(session) }
            if (joined.any { it.id !in ids } || joined.distinctBy { it.id }.size != joined.size)
                SubscribersContract.fail(SubscribersFailure.INVALID)
            for (raw in joined) SubscribersContract.profile(raw.id, raw)?.let {
                profiles[raw.id] = it
            }
        }
        val after = organization(id, session)
        if (before != after) SubscribersContract.fail(SubscribersFailure.STALE)
        // Public profile and organization reads do not prove the viewer is still a verified active
        // subscriber-list reader. Repeat the bounded protected query after the join under unchanged
        // Rules.
        val confirmed =
            SubscribersContract.page(
                source.page(id, previous?.next, session).also { current(session) },
                id,
                previous?.next,
            )
        if (confirmed != parsed) SubscribersContract.fail(SubscribersFailure.STALE)
        if (!visibleOrganization(after.content)) SubscribersContract.fail(SubscribersFailure.POLICY)
        current(session)
        val extra = parsed.size > SubscribersContract.PAGE_SIZE
        val next =
            page
                .lastOrNull()
                ?.takeIf { extra && references.size < SubscribersContract.MAX_SUBSCRIBERS }
                ?.let {
                    SubscriberCursor(id, it.createdAt, it.documentId, references.size)
                }
        return SubscribersSnapshot(
            session,
            after,
            references,
            SubscribersContract.members(after, references, profiles, visibleAuthor),
            next,
            extra && references.size == SubscribersContract.MAX_SUBSCRIBERS,
            references.count { visibleAuthor(it.userId) && it.userId !in profiles },
        )
    }
}
