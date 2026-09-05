package at.uac.android.feature.history

import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.ReadException
import at.uac.android.feature.browse.ReadFailure
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

interface HistorySource {
    suspend fun page(
        session: HistorySession,
        section: HistorySection,
        cursor: HistoryCursor?,
        size: Int,
    ): HistoryRawPage

    suspend fun targets(
        kind: ContentKind,
        ids: List<String>,
        stillCurrent: () -> Boolean,
    ): List<RawDocument>

    suspend fun record(session: HistorySession, section: HistorySection, id: String): RawDocument?

    suspend fun write(
        value: HistoryWrite,
        current: () -> Boolean,
        visible: (Content) -> Boolean,
    ): HistoryWriteReceipt

    suspend fun delete(value: HistoryDelete, current: () -> Boolean)
}

interface HistoryMutationGate {
    suspend fun <T> withSession(session: HistorySession, operation: suspend () -> T): T
}

/** Unit fixtures only; the application injects AuthHistoryMutationGate. */
object DirectHistoryMutationGate : HistoryMutationGate {
    override suspend fun <T> withSession(session: HistorySession, operation: suspend () -> T): T =
        withContext(NonCancellable) { operation() }
}

class HistoryRepository(
    private val source: HistorySource,
    private val session: () -> HistorySession?,
    private val visible: (Content) -> Boolean,
    private val mutations: HistoryMutationGate,
) {
    private fun capture(): HistorySession =
        (session() ?: throw HistoryException(HistoryFailure.SIGN_IN)).also(HistoryContract::ready)

    private fun current(value: HistorySession) {
        if (value != session()) throw CancellationException("History account changed")
    }

    private suspend fun <T> read(value: HistorySession, operation: suspend () -> T): T =
        try {
            current(value)
            withTimeout(15_000) { operation() }.also { current(value) }
        } catch (error: TimeoutCancellationException) {
            current(value)
            throw HistoryException(HistoryFailure.OFFLINE, error)
        } catch (error: Exception) {
            current(value)
            throw error
        }

    suspend fun page(section: HistorySection, cursor: HistoryCursor? = null): HistoryPage {
        val captured = capture()
        if (
            cursor != null &&
                (cursor.session != captured ||
                    cursor.section != section ||
                    cursor.consumed !in 1 until section.cap)
        )
            throw HistoryException(HistoryFailure.INVALID)
        val consumed = cursor?.consumed ?: 0
        val size = minOf(section.pageSize, section.cap - consumed)
        return read(captured) {
            val raw = source.page(captured, section, cursor, size)
            if (raw.rows.size > size || (raw.hasMore && raw.rows.size != size))
                throw HistoryException(HistoryFailure.INVALID)
            val rows = raw.rows.map { HistoryContract.record(section, it) }
            if (
                rows.map { it.id }.distinct().size != rows.size ||
                    rows.zipWithNext().any { (a, b) ->
                        HistoryContract.compare(a.at, a.id, b.at, b.id) >= 0
                    } ||
                    (cursor != null &&
                        rows.firstOrNull()?.let {
                            HistoryContract.compare(cursor.at, cursor.id, it.at, it.id) >= 0
                        } == true)
            )
                throw HistoryException(HistoryFailure.INVALID)
            val resolved = mutableMapOf<HistoryTarget, Content>()
            rows
                .map { it.target }
                .distinct()
                .groupBy { it.type }
                .forEach { (type, targets) ->
                    targets.chunked(10).forEach { chunk ->
                        val ids = chunk.map { it.id }
                        current(captured)
                        val documents = source.targets(type.kind, ids) { session() == captured }
                        current(captured)
                        if (
                            documents.map { it.id }.distinct().size != documents.size ||
                                documents.any { it.id !in ids }
                        )
                            throw HistoryException(HistoryFailure.INVALID)
                        documents.forEach { document ->
                            val target = HistoryTarget(type, document.id)
                            val content =
                                try {
                                    HistoryContract.content(target, document)
                                } catch (error: ReadException) {
                                    if (
                                        error.reason in
                                            setOf(
                                                ReadFailure.INVALID,
                                                ReadFailure.DENIED,
                                                ReadFailure.MISSING,
                                            )
                                    )
                                        null
                                    else throw error
                                } catch (error: HistoryException) {
                                    if (
                                        error.failure in
                                            setOf(
                                                HistoryFailure.INVALID,
                                                HistoryFailure.DENIED,
                                                HistoryFailure.MISSING,
                                            )
                                    )
                                        null
                                    else throw error
                                }
                            content?.takeIf(visible)?.let { resolved[target] = it }
                        }
                    }
                }
            current(captured)
            val count = consumed + rows.size
            val next =
                rows
                    .lastOrNull()
                    ?.takeIf { raw.hasMore && count < section.cap }
                    ?.let {
                        HistoryCursor(captured, section, it.at, it.id, count)
                    }
            HistoryPage(
                captured,
                section,
                rows.map { HistoryEntry(it, resolved[it.target]?.takeIf(visible)) },
                next,
                raw.hasMore && count == section.cap,
                count,
            )
        }
    }

    suspend fun write(value: HistoryWrite, stillEligible: () -> Boolean): HistoryWriteReceipt {
        HistoryContract.validate(value)
        current(value.session)
        if (!stillEligible()) throw CancellationException("History target is no longer eligible")
        val receipt =
            mutations.withSession(value.session) {
                source.write(value, { session() == value.session && stillEligible() }, visible)
            }
        current(value.session)
        if (!stillEligible()) throw CancellationException("History target changed")
        if (
            receipt.record.id != value.id ||
                receipt.record.target != value.target ||
                receipt.record.action != value.action ||
                receipt.record.section != value.section
        )
            throw HistoryException(HistoryFailure.UNCONFIRMED)
        return receipt
    }

    suspend fun delete(value: HistoryDelete) {
        HistoryContract.delete(value)
        current(value.session)
        mutations.withSession(value.session) { source.delete(value) { session() == value.session } }
        current(value.session)
    }

    /**
     * Read-only reconciliation. PRESENT is an observation, not proof that this device created a
     * recent view.
     */
    suspend fun reconcile(value: HistoryWrite): HistoryReconciliation {
        HistoryContract.validate(value)
        return read(value.session) {
            val raw =
                source.record(value.session, value.section, value.id)
                    ?: return@read HistoryReconciliation.ABSENT
            val row = HistoryContract.record(value.section, raw)
            if (row.target != value.target || row.action != value.action)
                throw HistoryException(HistoryFailure.CONFLICT)
            HistoryReconciliation.PRESENT
        }
    }

    suspend fun reconcile(value: HistoryDelete): HistoryReconciliation {
        HistoryContract.delete(value)
        return read(value.session) {
            var found = false
            value.records.forEach { record ->
                if (source.record(value.session, value.section, record.id) != null) found = true
            }
            if (found) HistoryReconciliation.PRESENT else HistoryReconciliation.ABSENT
        }
    }
}

fun historyFailure(error: Throwable): HistoryFailure =
    when (error) {
        is HistoryException -> error.failure
        is ReadException ->
            when (error.reason) {
                ReadFailure.OFFLINE -> HistoryFailure.OFFLINE
                ReadFailure.DENIED -> HistoryFailure.DENIED
                ReadFailure.MISSING -> HistoryFailure.MISSING
                ReadFailure.INDEX -> HistoryFailure.INDEX
                ReadFailure.INVALID -> HistoryFailure.INVALID
                ReadFailure.UNKNOWN -> HistoryFailure.UNKNOWN
            }
        else -> HistoryFailure.UNKNOWN
    }

/**
 * The transaction has already settled. Failure to read its receipt is not proof that nothing was
 * written.
 */
internal suspend fun <T> historyWriteReadBack(operation: suspend () -> T): T =
    try {
        operation()
    } catch (error: CancellationException) {
        throw error
    } catch (error: Exception) {
        throw HistoryException(HistoryFailure.UNCONFIRMED, error)
    }
