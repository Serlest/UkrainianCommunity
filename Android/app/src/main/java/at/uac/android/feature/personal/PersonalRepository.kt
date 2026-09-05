package at.uac.android.feature.personal

import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.ReadException
import at.uac.android.feature.browse.ReadFailure
import at.uac.android.feature.browse.decodeContent
import at.uac.android.feature.browse.string
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

interface PersonalSource {
    suspend fun profile(uid: String): PersonalProfile

    suspend fun saveProfile(
        uid: String,
        draft: ProfileDraft,
        stillCurrent: () -> Boolean,
    ): PersonalProfile

    suspend fun marker(marker: PersonalMarker): RawDocument?

    suspend fun setMarker(marker: PersonalMarker, enabled: Boolean, stillCurrent: () -> Boolean)

    /**
     * Null means a legacy/test source cannot prove whether the server transaction changed anything.
     */
    suspend fun setMarkerConfirmed(
        marker: PersonalMarker,
        enabled: Boolean,
        stillCurrent: () -> Boolean,
    ): Boolean? {
        setMarker(marker, enabled, stillCurrent)
        return null
    }

    suspend fun bookmarkPage(uid: String, kind: ContentKind, after: String?, size: Int): MarkerPage

    suspend fun relationPage(uid: String, after: String?, size: Int): MarkerPage

    suspend fun approvedContent(kind: ContentKind, ids: List<String>): List<RawDocument>

    suspend fun approvedContentCurrent(
        kind: ContentKind,
        ids: List<String>,
        stillCurrent: () -> Boolean,
    ): List<RawDocument> {
        if (!stillCurrent()) throw CancellationException("Account scope changed")
        return approvedContent(kind, ids).also {
            if (!stillCurrent()) throw CancellationException("Account scope changed")
        }
    }
}

data class PersonalChangeReceipt(
    val session: PersonalSession,
    val target: PersonalTarget,
    val action: PersonalAction,
    val enabled: Boolean,
    val didChange: Boolean?,
)

interface PersonalMutationGate {
    suspend fun <T> withSession(session: PersonalSession, operation: suspend () -> T): T
}

/** Pure/test source default. The application injects the AuthStore-backed identity mutex. */
object DirectPersonalMutationGate : PersonalMutationGate {
    override suspend fun <T> withSession(session: PersonalSession, operation: suspend () -> T): T =
        withContext(NonCancellable) { operation() }
}

class PersonalRepository(
    private val source: PersonalSource,
    private val session: () -> PersonalSession?,
    private val visible: (Content) -> Boolean = { true },
    private val mutations: PersonalMutationGate = DirectPersonalMutationGate,
) {
    private fun capture(write: Boolean = false): PersonalSession {
        val value = session() ?: throw PersonalException(PersonalFailure.SIGN_IN)
        if (!validDocumentId(value.uid)) throw PersonalException(PersonalFailure.INVALID)
        if (write && !value.ready) throw PersonalException(PersonalFailure.NOT_READY)
        return value
    }

    private fun ensureCurrent(captured: PersonalSession) {
        if (session() != captured) throw CancellationException("Account scope changed")
    }

    private suspend fun <T> scoped(
        captured: PersonalSession,
        readOnly: Boolean = true,
        operation: suspend () -> T,
    ): T {
        ensureCurrent(captured)
        return try {
            val result =
                if (readOnly) withTimeout(15_000) { operation() }
                else mutations.withSession(captured, operation)
            ensureCurrent(captured)
            result
        } catch (error: TimeoutCancellationException) {
            ensureCurrent(captured)
            throw PersonalException(PersonalFailure.OFFLINE, error)
        } catch (error: Exception) {
            ensureCurrent(captured)
            throw error
        }
    }

    suspend fun profile(): PersonalProfile {
        val captured = capture()
        return scoped(captured) { source.profile(captured.uid) }
    }

    suspend fun saveProfile(draft: ProfileDraft): PersonalProfile {
        val captured = capture(write = true)
        val normalized = draft.normalized()
        if (!normalized.validFor(captured.uid)) throw PersonalException(PersonalFailure.INVALID)
        return scoped(captured, readOnly = false) {
            source.saveProfile(captured.uid, normalized) { session() == captured }
        }
    }

    suspend fun actions(target: PersonalTarget): PersonalActions {
        val captured = capture(write = true)
        return scoped(captured) {
            coroutineScope {
                val like = async {
                    exists(PersonalMarker(target, captured.uid, PersonalAction.LIKE))
                }
                val bookmark = async {
                    exists(PersonalMarker(target, captured.uid, PersonalAction.BOOKMARK))
                }
                val subscription =
                    if (target.kind == ContentKind.ORGANIZATIONS)
                        async {
                            exists(PersonalMarker(target, captured.uid, PersonalAction.SUBSCRIBE))
                        }
                    else null
                PersonalActions(like.await(), bookmark.await(), subscription?.await() ?: false)
            }
        }
    }

    private suspend fun exists(marker: PersonalMarker): Boolean {
        val document = source.marker(marker) ?: return false
        if (!marker.matches(document)) throw PersonalException(PersonalFailure.INVALID)
        return true
    }

    /**
     * Explicit desired state is safe to retry after an uncertain network result. Never invert a
     * fresh read.
     */
    suspend fun set(target: PersonalTarget, action: PersonalAction, enabled: Boolean): Boolean =
        setConfirmed(target, action, enabled).enabled

    suspend fun setConfirmed(
        target: PersonalTarget,
        action: PersonalAction,
        enabled: Boolean,
    ): PersonalChangeReceipt {
        val captured = capture(write = true)
        val marker =
            try {
                PersonalMarker(target, captured.uid, action)
            } catch (error: IllegalArgumentException) {
                throw PersonalException(PersonalFailure.INVALID, error)
            }
        return scoped(captured, readOnly = false) {
            val changed = source.setMarkerConfirmed(marker, enabled) { session() == captured }
            ensureCurrent(captured)
            val actual = withTimeout(5_000) { exists(marker) }
            if (actual != enabled) throw PersonalException(PersonalFailure.UNKNOWN)
            PersonalChangeReceipt(captured, target, action, actual, changed)
        }
    }

    suspend fun saved(kind: ContentKind, after: String? = null, size: Int = 30): PersonalListPage {
        require(size in 1..50)
        val captured = capture()
        return scoped(captured) {
            val page = source.bookmarkPage(captured.uid, kind, after, size)
            val ids =
                page.rows.map { row ->
                    val target =
                        try {
                            PersonalTarget(kind, row.id)
                        } catch (error: IllegalArgumentException) {
                            throw PersonalException(PersonalFailure.INVALID, error)
                        }
                    if (!PersonalMarker(target, captured.uid, PersonalAction.BOOKMARK).matches(row))
                        throw PersonalException(PersonalFailure.INVALID)
                    row.id
                }
            resolve(kind, ids, page, captured)
        }
    }

    suspend fun subscriptions(after: String? = null, size: Int = 30): PersonalListPage {
        require(size in 1..50)
        val captured = capture(write = true)
        return scoped(captured) {
            // The shared likes collection also contains likes. Continue through those rows and
            // expose a cursor.
            val page = source.relationPage(captured.uid, after, size)
            val ids =
                page.rows.mapNotNull { row ->
                    val id = row.fields.string("subscribedOrganizationId")
                    if (id.isBlank()) return@mapNotNull null
                    if (
                        !validDocumentId(id) ||
                            !PersonalMarker(
                                    PersonalTarget(ContentKind.ORGANIZATIONS, id),
                                    captured.uid,
                                    PersonalAction.SUBSCRIBE,
                                )
                                .matches(row)
                    )
                        throw PersonalException(PersonalFailure.INVALID)
                    id
                }
            resolve(ContentKind.ORGANIZATIONS, ids, page, captured)
        }
    }

    private suspend fun resolve(
        kind: ContentKind,
        ids: List<String>,
        page: MarkerPage,
        captured: PersonalSession,
    ): PersonalListPage {
        val rows =
            ids.chunked(10).flatMap { chunk ->
                ensureCurrent(captured)
                source
                    .approvedContentCurrent(kind, chunk) { session() == captured }
                    .also { ensureCurrent(captured) }
            }
        val items =
            rows
                .mapNotNull { row ->
                    if (row.id !in ids) throw PersonalException(PersonalFailure.INVALID)
                    try {
                        decodeContent(kind, row).takeIf {
                            (kind == ContentKind.ORGANIZATIONS ||
                                it.fields.string("sourceType") == "organization") && visible(it)
                        }
                    } catch (error: ReadException) {
                        if (
                            error.reason in
                                setOf(ReadFailure.INVALID, ReadFailure.DENIED, ReadFailure.MISSING)
                        )
                            null
                        else throw error
                    }
                }
                .distinctBy { it.id }
        // Missing/private/malformed targets remain bookmarked; never delete a marker as a read side
        // effect.
        return PersonalListPage(
            items,
            page.next,
            page.hasMore,
            (ids.distinct().size - items.size).coerceAtLeast(0),
        )
    }
}
