package at.uac.android.feature.inbox

import at.uac.android.feature.personal.validDocumentId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withTimeout

interface InboxSource {
    suspend fun page(uid: String, after: InboxCursor?, size: Int): InboxRawPage

    suspend fun unreadCount(uid: String): Long

    suspend fun preferences(uid: String): InboxPreferences

    suspend fun mutate(
        uid: String,
        ids: List<String>,
        mutation: InboxMutation,
        stillCurrent: () -> Boolean,
    )

    suspend fun savePreferences(
        uid: String,
        preferences: InboxPreferences,
        stillCurrent: () -> Boolean,
    )

    fun changes(uid: String): Flow<Unit>
}

interface InboxMutationGate {
    suspend fun <T> withSession(
        session: InboxSession,
        preferences: Boolean,
        operation: suspend () -> T,
    ): T
}

/**
 * No persistent private cache, detached writes, recipient arguments from UI, or client-created
 * notices.
 */
class InboxRepository(
    private val source: InboxSource,
    private val session: () -> InboxSession?,
    private val mutations: InboxMutationGate,
) {
    private fun capture(): InboxSession =
        session()?.also {
            if (!validDocumentId(it.uid)) throw InboxException(InboxFailure.INVALID)
        } ?: throw InboxException(InboxFailure.SIGN_IN)

    private fun current(captured: InboxSession) {
        if (session() != captured) throw CancellationException("Account scope changed")
    }

    private suspend fun <T> read(captured: InboxSession, operation: suspend () -> T): T {
        current(captured)
        return try {
            withTimeout(15_000) { operation() }.also { current(captured) }
        } catch (error: TimeoutCancellationException) {
            current(captured)
            throw InboxException(InboxFailure.OFFLINE, error)
        } catch (error: Exception) {
            current(captured)
            throw error
        }
    }

    private suspend fun <T> write(
        captured: InboxSession,
        preferences: Boolean = false,
        operation: suspend () -> T,
    ): T {
        current(captured)
        if (preferences && !captured.canEditPreferences)
            throw InboxException(InboxFailure.NOT_READY)
        return mutations.withSession(captured, preferences, operation).also { current(captured) }
    }

    suspend fun page(after: InboxCursor? = null): InboxPage {
        val captured = capture()
        return read(captured) { pageFor(captured, after) }
    }

    private suspend fun pageFor(captured: InboxSession, after: InboxCursor?): InboxPage {
        val raw = source.page(captured.uid, after, 50)
        if (raw.hasMore && (raw.next == null || raw.next == after))
            throw InboxException(InboxFailure.INVALID)
        val decoded = raw.rows.mapNotNull { decodeInboxNotice(captured.uid, it) }
        return InboxPage(
            decoded.filter { it.visible },
            raw.next,
            raw.hasMore,
            raw.rows.size - decoded.size,
        )
    }

    suspend fun unreadCount(): Long {
        val captured = capture()
        return read(captured) { source.unreadCount(captured.uid).coerceAtLeast(0) }
    }

    suspend fun preferences(): InboxPreferences {
        val captured = capture()
        return read(captured) { source.preferences(captured.uid) }
    }

    suspend fun savePreferences(preferences: InboxPreferences): InboxPreferences {
        val captured = capture()
        if (!preferences.valid()) throw InboxException(InboxFailure.INVALID)
        return write(captured, preferences = true) {
            source.savePreferences(captured.uid, preferences) { session() == captured }
            read(captured) { source.preferences(captured.uid) }
                .also {
                    if (it != preferences) throw InboxException(InboxFailure.UNKNOWN)
                }
        }
    }

    suspend fun mutate(notice: InboxNotice, mutation: InboxMutation) {
        val captured = capture()
        if (notice.uid != captured.uid || !validDocumentId(notice.id))
            throw InboxException(InboxFailure.DENIED)
        write(captured) {
            source.mutate(captured.uid, listOf(notice.id), mutation) { session() == captured }
        }
    }

    /**
     * Bounded, restartable sweep; never reports all cleared after only clearing the loaded page.
     */
    suspend fun mutateAll(mutation: InboxMutation): InboxBulkResult {
        require(mutation == InboxMutation.READ || mutation == InboxMutation.DELETE)
        val captured = capture()
        var cursor: InboxCursor? = null
        var changed = 0
        var invalid = 0
        repeat(100) {
            val page = read(captured) { pageFor(captured, cursor) }
            invalid += page.invalid
            val ids =
                page.items.filter { mutation == InboxMutation.DELETE || it.unread }.map { it.id }
            if (ids.isNotEmpty()) {
                write(captured) {
                    source.mutate(captured.uid, ids, mutation) { session() == captured }
                }
                changed += ids.size
            }
            if (!page.hasMore) return InboxBulkResult(changed, complete = invalid == 0)
            cursor = page.next
        }
        return InboxBulkResult(changed, complete = false)
    }

    fun changes(): Flow<Unit> = source.changes(capture().uid)
}
