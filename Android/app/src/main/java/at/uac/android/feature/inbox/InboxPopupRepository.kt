package at.uac.android.feature.inbox

import at.uac.android.feature.personal.validDocumentId
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout

/** The existing inbox gate holds the SDK identity through actual writes and receipts. */
internal class InboxPopupRepository(
    private val source: InboxPopupSource,
    private val authority: () -> InboxPopupAccount,
    private val gate: InboxMutationGate,
    private val clock: () -> Instant,
) {
    private fun current(session: InboxSession) {
        if (authority().session != session || authority().uid != session.uid)
            throw CancellationException("Account scope changed")
    }

    private suspend fun read(session: InboxSession, id: String): InboxNotice {
        current(session)
        val row =
            try {
                withTimeout(15_000) { source.popupNotice(session.uid, id) }
            } catch (error: TimeoutCancellationException) {
                current(session)
                throw InboxException(InboxFailure.OFFLINE, error)
            }
        current(session)
        return row?.let { decodeInboxNotice(session.uid, it) }?.takeIf { it.id == id }
            ?: throw InboxException(if (row == null) InboxFailure.MISSING else InboxFailure.INVALID)
    }

    suspend fun acknowledge(
        session: InboxSession,
        notice: InboxNotice,
        markRead: Boolean,
    ): InboxNotice {
        current(session)
        if (
            !validDocumentId(session.uid) ||
                !validDocumentId(notice.id) ||
                notice.uid != session.uid
        )
            throw InboxException(InboxFailure.DENIED)
        return gate.withSession(session, preferences = false) {
            current(session)
            var fresh = read(session, notice.id)
            // Never acknowledge an item that disappeared or was retired while the dialog was open.
            if (
                !fresh.visible ||
                    fresh.archivedAt != null ||
                    fresh.expiresAt?.let { it <= clock() } == true ||
                    !fresh.requiresPopup ||
                    fresh.severity != "critical" ||
                    fresh.kind in setOf(InboxKind.ACCOUNT_STATUS, InboxKind.LEGAL)
            ) {
                throw InboxException(InboxFailure.MISSING)
            }
            if (fresh.popupPresentedAt == null) {
                source.mutate(session.uid, listOf(notice.id), InboxMutation.POPUP_PRESENTED) {
                    authority().session == session
                }
                fresh = read(session, notice.id)
            }
            if (fresh.popupPresentedAt == null) throw InboxException(InboxFailure.UNKNOWN)
            if (markRead && !fresh.isRead && fresh.visible) {
                source.mutate(session.uid, listOf(notice.id), InboxMutation.READ) {
                    authority().session == session
                }
                fresh = read(session, notice.id)
            }
            if (fresh.popupPresentedAt == null || markRead && !fresh.isRead)
                throw InboxException(InboxFailure.UNKNOWN)
            current(session)
            fresh
        }
    }
}
