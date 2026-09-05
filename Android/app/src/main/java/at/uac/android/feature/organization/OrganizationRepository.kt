package at.uac.android.feature.organization

import at.uac.android.feature.auth.AuthLegalDocument
import at.uac.android.feature.browse.RawDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow

interface OrganizationSource {
    suspend fun hub(session: OrganizationSession): OrganizationHub

    suspend fun request(id: String, session: OrganizationSession): OrganizationRecord?

    suspend fun rules(): AuthLegalDocument

    fun changes(session: OrganizationSession, requestId: String? = null): Flow<Result<Unit>>

    suspend fun create(
        draft: OrganizationDraft,
        rules: AuthLegalDocument,
        session: OrganizationSession,
        language: String,
    ): OrganizationRecord

    suspend fun revise(
        base: OrganizationRecord,
        draft: OrganizationDraft,
        session: OrganizationSession,
    ): OrganizationRecord

    suspend fun discard(base: OrganizationRecord, session: OrganizationSession)

    suspend fun logo(
        base: OrganizationRecord,
        jpeg: ByteArray,
        session: OrganizationSession,
    ): OrganizationRecord
}

interface OrganizationMutationGate {
    suspend fun <T> withSession(session: OrganizationSession, operation: suspend () -> T): T
}

class OrganizationRepository(
    private val source: OrganizationSource,
    private val current: () -> OrganizationSession?,
    private val gate: OrganizationMutationGate,
) {
    private fun session(): OrganizationSession =
        (current() ?: throw OrganizationException(OrganizationFailure.SIGN_IN)).also {
            if (!it.ready) throw OrganizationException(OrganizationFailure.NOT_READY)
        }

    private fun ensure(session: OrganizationSession) {
        if (current() != session) throw CancellationException("Organization session changed")
    }

    suspend fun hub(): OrganizationHub {
        val s = session()
        val hub = source.hub(s).also { ensure(s) }
        val requests =
            hub.requests.map { OrganizationContract.record(RawDocument(it.id, it.fields), s) }
        if (
            requests.any {
                it.submitter != s.uid || it.status !in OrganizationContract.requestStatuses
            }
        )
            throw OrganizationException(OrganizationFailure.INVALID)
        val managed =
            hub.managed
                .map { OrganizationContract.record(RawDocument(it.id, it.fields), s) }
                .filter { it.authority != OrganizationAuthority.NONE }
        return hub.copy(requests = requests, managed = managed)
    }

    suspend fun rules(): AuthLegalDocument {
        val s = session()
        return source.rules().also { ensure(s) }
    }

    suspend fun request(id: String): OrganizationRecord? {
        val s = session()
        if (!OrganizationContract.id(id)) throw OrganizationException(OrganizationFailure.MISSING)
        val raw = source.request(id, s).also { ensure(s) } ?: return null
        val record = OrganizationContract.record(RawDocument(raw.id, raw.fields), s)
        return record.takeIf {
            it.id == id &&
                it.submitter == s.uid &&
                it.status in OrganizationContract.requestStatuses + "approved"
        }
    }

    fun changes(session: OrganizationSession, requestId: String? = null): Flow<Result<Unit>> =
        source.changes(session, requestId)

    suspend fun submit(
        draft: OrganizationDraft,
        rules: AuthLegalDocument?,
        base: OrganizationRecord?,
        jpeg: ByteArray?,
        language: String,
    ): OrganizationSubmitResult {
        val s = session()
        val normalized = OrganizationContract.validate(draft)
        if (base != null) {
            if (base.id != draft.id) throw OrganizationException(OrganizationFailure.INVALID)
            OrganizationContract.requireEditable(base, s)
        } else if (rules == null) throw OrganizationException(OrganizationFailure.LEGAL_CHANGED)
        else if (draft.acceptedRulesVersion != rules.version)
            throw OrganizationException(OrganizationFailure.CONSENT)
        return gate
            .withSession(s) {
                ensure(s)
                val saved =
                    if (base == null) source.create(normalized, requireNotNull(rules), s, language)
                    else source.revise(base, normalized, s)
                ensure(s)
                if (jpeg == null) OrganizationSubmitResult(saved)
                else
                    try {
                        OrganizationSubmitResult(source.logo(saved, jpeg, s).also { ensure(s) })
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        ensure(s)
                        OrganizationSubmitResult(saved, logoIncomplete = true)
                    }
            }
            .also { ensure(s) }
    }

    suspend fun discard(base: OrganizationRecord) {
        val s = session()
        OrganizationContract.requireEditable(base, s)
        if (s.globalRole == "owner") throw OrganizationException(OrganizationFailure.DENIED)
        gate.withSession(s) {
            ensure(s)
            source.discard(base, s)
            ensure(s)
        }
    }
}
