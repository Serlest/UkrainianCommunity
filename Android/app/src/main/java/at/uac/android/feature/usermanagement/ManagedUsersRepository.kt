package at.uac.android.feature.usermanagement

import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/**
 * No writes, role assignments, exports, presence or account status mutations exist on this port.
 */
interface ManagedUsersSource {
    suspend fun page(session: ModerationSession, cursor: ManagedUsersCursor?): ManagedUsersPage

    suspend fun search(session: ModerationSession, query: ManagedUsersQuery): ManagedUsersSearch

    suspend fun user(session: ModerationSession, targetId: String): ManagedUser?

    suspend fun security(session: ModerationSession, targetId: String): ManagedUserSecurity

    fun invalidations(session: ModerationSession, targetId: String?): Flow<Unit>
}

class ManagedUsersRepository(
    private val source: ManagedUsersSource,
    private val authority: () -> ModerationSession?,
    private val gate: ModerationDecisionGate,
) {
    fun currentSession() = authority()

    private fun current(session: ModerationSession) {
        ManagedUsersContract.requireSession(session)
        if (authority() != session) throw CancellationException("Managed users session changed")
    }

    private suspend fun <T> read(session: ModerationSession, action: suspend () -> T): T {
        current(session)
        val result =
            gate.withSession(session) {
                current(session)
                action().also { current(session) }
            }
        current(session)
        return result
    }

    suspend fun page(session: ModerationSession, cursor: ManagedUsersCursor?): ManagedUsersPage =
        read(session) {
            ManagedUsersContract.cursor(session, cursor)
            source.page(session, cursor).also { page ->
                val start = cursor?.consumed ?: 0
                if (
                    page.users.size > ManagedUsersContract.PAGE_SIZE ||
                        page.consumed != start + page.users.size ||
                        page.consumed > ManagedUsersContract.MAX_USERS ||
                        page.users.map { it.id }.distinct().size != page.users.size ||
                        page.capped != (page.consumed == ManagedUsersContract.MAX_USERS) ||
                        (page.next != null &&
                            (page.users.size != ManagedUsersContract.PAGE_SIZE ||
                                page.next.consumed != page.consumed)) ||
                        (page.users.size == ManagedUsersContract.PAGE_SIZE &&
                            !page.capped &&
                            page.next == null)
                )
                    ManagedUsersContract.fail(ManagedUsersFailure.INVALID)
                page.next?.let { ManagedUsersContract.cursor(session, it) }
                page.users.forEach { ManagedUsersContract.requireId(it.id) }
            }
        }

    suspend fun search(session: ModerationSession, query: ManagedUsersQuery): ManagedUsersSearch =
        read(session) {
            if (ManagedUsersQuery.from(query.value) != query)
                ManagedUsersContract.fail(ManagedUsersFailure.INVALID)
            source.search(session, query).also {
                if (
                    it.users.size + it.unavailable > ManagedUsersContract.SEARCH_LIMIT ||
                        it.unavailable < 0 ||
                        it.totalMatches < it.users.size + it.unavailable ||
                        it.users.map { user -> user.id }.distinct().size != it.users.size
                )
                    ManagedUsersContract.fail(ManagedUsersFailure.INVALID)
                it.users.forEach { user -> ManagedUsersContract.requireId(user.id) }
            }
        }

    suspend fun user(session: ModerationSession, targetId: String): ManagedUser? =
        read(session) {
            ManagedUsersContract.requireId(targetId)
            source.user(session, targetId).also {
                if (it != null && it.id != targetId)
                    ManagedUsersContract.fail(ManagedUsersFailure.INVALID)
            }
        }

    suspend fun security(session: ModerationSession, targetId: String): ManagedUserSecurity =
        read(session) {
            ManagedUsersContract.requireId(targetId)
            source.security(session, targetId).also {
                if (it.targetId != targetId) ManagedUsersContract.fail(ManagedUsersFailure.INVALID)
            }
        }

    fun invalidations(session: ModerationSession, targetId: String?): Flow<Unit> = flow {
        current(session)
        targetId?.let(ManagedUsersContract::requireId)
        source.invalidations(session, targetId).collect {
            current(session)
            emit(Unit)
        }
    }
}
