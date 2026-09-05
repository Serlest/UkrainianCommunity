package at.uac.android.feature.dsastatement

import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/** Caller projection only. A later Auth adapter must verify actual SDK identity and readiness. */
data class DsaStatementSession(
    val uid: String,
    val revision: Long,
    val backend: String,
    val ready: Boolean,
) {
    override fun toString() = "DsaStatementSession([redacted])"
}

fun interface DsaStatementSource {
    suspend fun read(session: DsaStatementSession, reportId: String): Any?
}

interface DsaStatementReadGate {
    suspend fun <T> withSession(session: DsaStatementSession, action: suspend () -> T): T
}

/**
 * Controlled read-only coordinator; no caching, journal, fallback case query or automatic retry.
 */
class DsaStatementRepository(
    private val source: DsaStatementSource,
    private val gate: DsaStatementReadGate,
    private val authority: () -> DsaStatementSession?,
) {
    suspend fun read(
        session: DsaStatementSession,
        reportId: String,
        isSelected: () -> Boolean,
    ): DsaStatement {
        val caller = currentCoroutineContext()
        fun ensure() {
            caller.ensureActive()
            if (
                !session.ready ||
                    session.revision < 0 ||
                    !DsaStatementContract.validId(session.uid, 128) ||
                    session.backend.isBlank() ||
                    session.backend.length > 200
            )
                DsaStatementContract.fail(DsaStatementFailure.ACCESS)
            if (authority() != session || !isSelected())
                throw CancellationException("Statement scope changed")
        }
        ensure()
        DsaStatementContract.payload(reportId)
        try {
            val result =
                gate.withSession(session) {
                    ensure()
                    val raw = source.read(session, reportId)
                    ensure()
                    DsaStatementContract.response(reportId, raw)
                }
            ensure()
            return result
        } catch (error: Exception) {
            // Prefer current scope/cancellation over even a late private error.
            ensure()
            when (error) {
                is TimeoutCancellationException ->
                    DsaStatementContract.fail(DsaStatementFailure.OFFLINE)
                is CancellationException -> throw error
                is DsaStatementException -> throw error
                is IOException -> DsaStatementContract.fail(DsaStatementFailure.OFFLINE)
                else -> DsaStatementContract.fail(DsaStatementFailure.UNKNOWN)
            }
        }
    }
}
