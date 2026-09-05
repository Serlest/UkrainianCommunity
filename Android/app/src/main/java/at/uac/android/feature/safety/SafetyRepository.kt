package at.uac.android.feature.safety

import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

interface SafetySource {
    suspend fun userBlocks(uid: String): List<RawDocument>

    suspend fun userBlock(uid: String, id: String): RawDocument?

    suspend fun report(uid: String, id: String): RawDocument?

    suspend fun call(name: String, fields: Fields, uid: String): Any?
}

interface SafetyMutationGate {
    suspend fun <T> withSession(session: SafetySession, operation: suspend () -> T): T
}

object DirectSafetyMutationGate : SafetyMutationGate {
    override suspend fun <T> withSession(session: SafetySession, operation: suspend () -> T): T =
        withContext(NonCancellable) { operation() }
}

class SafetyRepository(
    private val source: SafetySource,
    private val authority: () -> SafetySession?,
    private val gate: SafetyMutationGate = DirectSafetyMutationGate,
) {
    private fun capture(): SafetySession =
        (authority() ?: throw SafetyException(SafetyFailure.SIGN_IN)).also {
            if (!it.ready) throw SafetyException(SafetyFailure.NOT_READY)
            if (!safetyId(it.uid, 128)) throw SafetyException(SafetyFailure.INVALID)
        }

    private fun current(session: SafetySession) {
        if (authority() != session) throw CancellationException("Safety account scope changed")
    }

    private suspend fun <T> read(
        session: SafetySession,
        stage: SafetyOperation,
        operation: suspend () -> T,
    ): T =
        try {
            current(session)
            withTimeout(15_000) { operation() }.also { current(session) }
        } catch (error: TimeoutCancellationException) {
            current(session)
            throw SafetyException(SafetyFailure.OFFLINE, error, stage)
        } catch (error: Exception) {
            current(session)
            throw error
        }

    private suspend fun <T> request(session: SafetySession, operation: suspend () -> T): T =
        try {
            current(session)
            gate.withSession(session, operation).also { current(session) }
        } catch (error: Exception) {
            current(session)
            throw error
        }

    suspend fun blocks(): SafetyBlocks {
        val session = capture()
        return request(session) {
            val users =
                read(session, SafetyOperation.USER_BLOCKS) {
                    source.userBlocks(session.uid).map(SafetyContract::user)
                }
            val organizations =
                SafetyContract.organizations(
                    source.call("getBlockedOrganizations", emptyMap(), session.uid)
                )
            SafetyBlocks(users, organizations)
        }
    }

    suspend fun setUser(id: String, blocked: Boolean): SafetyUserBlock? {
        val session = capture()
        if (!safetyId(id)) throw SafetyException(SafetyFailure.INVALID)
        if (id == session.uid) throw SafetyException(SafetyFailure.OWN_TARGET)
        return request(session) {
            val value =
                source.call(
                    "setUserBlocked",
                    mapOf("targetUserId" to id, "isBlocked" to blocked),
                    session.uid,
                )
            SafetyContract.userReceipt(value, id, blocked)
            val result =
                read(session, SafetyOperation.USER_BLOCK) {
                    source.userBlock(session.uid, id)?.let(SafetyContract::user)
                }
            if ((result != null) != blocked || (result != null && result.id != id))
                throw SafetyException(SafetyFailure.UNCONFIRMED)
            result
        }
    }

    suspend fun setOrganization(id: String, blocked: Boolean): SafetyOrganizationBlock? {
        val session = capture()
        if (!safetyId(id, 160)) throw SafetyException(SafetyFailure.INVALID)
        return request(session) {
            val value =
                source.call(
                    "setOrganizationBlocked",
                    mapOf("organizationId" to id, "isBlocked" to blocked),
                    session.uid,
                )
            SafetyContract.organizationReceipt(value, id, blocked)
            current(session)
            val actual =
                SafetyContract.organizations(
                        source.call("getBlockedOrganizations", emptyMap(), session.uid)
                    )
                    .find { it.id == id }
            if ((actual != null) != blocked) throw SafetyException(SafetyFailure.UNCONFIRMED)
            actual
        }
    }

    /**
     * The server creates a NEW DSA case per call. Unknown transport/response outcomes must never
     * auto-retry.
     */
    suspend fun submit(target: SafetyReportTarget, input: SafetyReportDraft): SafetyReportReceipt {
        val session = capture()
        val draft = input.normalized()
        if (!target.valid() || !draft.valid()) throw SafetyException(SafetyFailure.INVALID)
        if (target.authorId == session.uid) throw SafetyException(SafetyFailure.OWN_TARGET)
        return request(session) {
            val value =
                try {
                    source.call(
                        "submitContentReport",
                        target.identityFields() + draft.fields(),
                        session.uid,
                    )
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    if (safetyFailure(error) in setOf(SafetyFailure.OFFLINE, SafetyFailure.UNKNOWN))
                        throw SafetyException(SafetyFailure.UNCONFIRMED, error)
                    throw error
                }
            current(session)
            try {
                val receipt = SafetyContract.reportReceipt(value)
                val row =
                    read(session, SafetyOperation.REPORT_READ) {
                        source.report(session.uid, receipt.id)
                    } ?: throw SafetyException(SafetyFailure.UNCONFIRMED)
                SafetyContract.confirmReport(row, session.uid, target, draft, receipt)
                receipt
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                throw SafetyException(SafetyFailure.UNCONFIRMED, error)
            }
        }
    }
}
