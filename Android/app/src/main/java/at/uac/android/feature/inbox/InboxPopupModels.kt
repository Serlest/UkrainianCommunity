package at.uac.android.feature.inbox

import at.uac.android.feature.auth.AuthSession
import at.uac.android.feature.browse.RawDocument
import java.time.Instant
import kotlinx.coroutines.flow.Flow

/** UID remains known during an auth refresh; a usable session does not. */
data class InboxPopupAccount(val uid: String?, val revision: Long, val session: InboxSession?)

fun AuthSession.inboxPopupAccount() =
    InboxPopupAccount(identity?.takeUnless { it.anonymous }?.uid, revision, inboxScope())

/** Only a live query head may feed the coordinator. A loaded/paginated inbox is not a head. */
data class InboxPopupHead(
    val rows: List<RawDocument>,
    val fromCache: Boolean = false,
    val pendingWrites: Boolean = false,
)

interface InboxPopupSource : InboxSource {
    fun popupHeads(uid: String): Flow<InboxPopupHead>

    suspend fun popupNotice(uid: String, id: String): RawDocument?
}

fun InboxNotice.eligibleForPopup(now: Instant): Boolean =
    requiresPopup &&
        severity == "critical" &&
        popupPresentedAt == null &&
        archivedAt == null &&
        deletedAt == null &&
        kind !in setOf(InboxKind.ACCOUNT_STATUS, InboxKind.LEGAL) &&
        expiresAt?.let { it <= now } != true

data class InboxPopupAction(
    val sequence: Long,
    val session: InboxSession,
    val notice: InboxNotice,
    val destination: InboxDestination,
)

data class InboxPopupState(
    val account: InboxPopupAccount = InboxPopupAccount(null, 0, null),
    val active: InboxNotice? = null,
    val queuedCount: Int = 0,
    val confirmed: Boolean = false,
    val mutating: Boolean = false,
    val error: InboxFailure? = null,
    val acknowledgementFailed: Boolean = false,
    val action: InboxPopupAction? = null,
) {
    fun forAccount(authority: InboxPopupAccount): InboxPopupState =
        if (account == authority) this else InboxPopupState(account = authority)
}

/** Build-65 ordering, with old-revision content quarantined until a new server head. */
internal class InboxPopupCoordinator(private val clock: () -> Instant) {
    var account = InboxPopupAccount(null, 0, null)
        private set

    private var seeded = false
    private val seen = mutableSetOf<String>()
    private val queue = mutableListOf<String>()
    private var activeId: String? = null
    private var head = emptyMap<String, InboxNotice>()
    var confirmed = false
        private set

    var held = false

    val active: InboxNotice?
        get() = if (confirmed && account.session != null) activeId?.let(head::get) else null

    val queuedCount: Int
        get() = if (confirmed) queue.size else 0

    fun configure(value: InboxPopupAccount) {
        if (account == value) return
        if (account.uid != value.uid) {
            seeded = false
            seen.clear()
            queue.clear()
            activeId = null
        }
        account = value
        held = false
        suspendHead()
    }

    fun suspendHead() {
        confirmed = false
        head = emptyMap()
    }

    fun receive(session: InboxSession, snapshot: InboxPopupHead): Boolean {
        if (account.session != session || account.uid != session.uid) return false
        if (snapshot.fromCache || snapshot.pendingWrites) {
            suspendHead()
            return true
        }
        if (snapshot.rows.map { it.id }.distinct().size != snapshot.rows.size)
            throw InboxException(InboxFailure.INVALID)
        val ids = snapshot.rows.map { it.id }.toSet()
        head = snapshot.rows.mapNotNull { decodeInboxNotice(session.uid, it) }.associateBy { it.id }
        confirmed = true
        if (!seeded) {
            // Even malformed initial rows are old IDs, not newly arriving notices.
            seen.addAll(ids)
            seeded = true
            return true
        }
        reconcile(present = false)
        queue.addAll(
            head.values.filter { it.id !in seen && it.eligibleForPopup(clock()) }.map { it.id }
        )
        queue.sortWith(compareBy<String> { head[it]?.createdAt }.thenBy { it })
        seen.addAll(ids)
        presentNext()
        return true
    }

    fun reconcile(present: Boolean = true) {
        if (!confirmed) return
        val now = clock()
        if (activeId?.let { head[it]?.eligibleForPopup(now) != true } == true) activeId = null
        queue.removeAll { head[it]?.eligibleForPopup(now) != true }
        if (present) presentNext()
    }

    fun beginDismiss(id: String): Boolean {
        reconcile()
        if (held || active?.id != id) return false
        held = true
        activeId = null
        queue.removeAll { it == id }
        return true
    }

    fun endDismiss() {
        held = false
        reconcile()
        presentNext()
    }

    fun nextExpiry(): Instant? =
        if (confirmed)
            (queue + listOfNotNull(activeId)).mapNotNull { head[it]?.expiresAt }.minOrNull()
        else null

    private fun presentNext() {
        if (confirmed && !held && activeId == null && queue.isNotEmpty())
            activeId = queue.removeAt(0)
    }
}
