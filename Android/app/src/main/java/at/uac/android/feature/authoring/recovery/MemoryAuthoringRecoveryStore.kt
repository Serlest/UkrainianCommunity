package at.uac.android.feature.authoring.recovery

import at.uac.android.feature.authoring.AuthoringContract
import at.uac.android.feature.authoring.AuthoringDraft
import at.uac.android.feature.authoring.AuthoringItem
import at.uac.android.feature.authoring.AuthoringSubmission
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Deterministic fake/default for pure tests. Main must inject the encrypted local disk store. */
class MemoryAuthoringRecoveryStore : AuthoringRecoveryStore {
    private val mutex = Mutex()
    private val drafts = mutableMapOf<AuthoringRecoveryScope, ByteArray>()
    private val pending = mutableMapOf<AuthoringRecoveryScope, ByteArray>()

    private fun limit(scope: AuthoringRecoveryScope) {
        val existing = (drafts.keys + pending.keys).filter { it.uid == scope.uid }.toSet()
        if (scope !in existing && existing.size >= 32)
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.LIMIT)
    }

    override suspend fun load(scope: AuthoringRecoveryScope): AuthoringRecoveredCreation? =
        mutex.withLock {
            val draft = drafts[scope]?.let { AuthoringRecoveryCodec.readDraft(scope, it) }
            val intent = pending[scope]?.let { AuthoringRecoveryCodec.readPending(scope, it) }
            if (draft == null && intent == null) null
            else AuthoringRecoveredCreation(draft?.draft, draft?.zoneId, intent)
        }

    override suspend fun saveDraft(
        scope: AuthoringRecoveryScope,
        draft: AuthoringDraft,
        zoneId: String,
    ) = mutex.withLock {
        limit(scope)
        if (pending.containsKey(scope))
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.PENDING_CONFLICT)
        val value = RecoveryDraft(draft, zoneId)
        val encoded = AuthoringRecoveryCodec.draft(scope, value)
        if (AuthoringRecoveryCodec.readDraft(scope, encoded) != value) RecoveryValidation.invalid()
        drafts[scope] = encoded
    }

    override suspend fun prepareCreation(
        scope: AuthoringRecoveryScope,
        intent: AuthoringSubmission,
    ): AuthoringSubmission = mutex.withLock {
        limit(scope)
        RecoveryValidation.intent(scope, intent)
        if (
            drafts[scope]?.let {
                AuthoringRecoveryCodec.readDraft(scope, it).draft.id != intent.id
            } == true
        )
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.PENDING_CONFLICT)
        pending[scope]?.let { existing ->
            val stored = AuthoringRecoveryCodec.readPending(scope, existing)
            if (!RecoveryValidation.same(stored, intent))
                throw AuthoringRecoveryException(AuthoringRecoveryFailure.PENDING_CONFLICT)
            return@withLock stored
        }
        val bytes = AuthoringRecoveryCodec.pending(scope, intent)
        val actual = AuthoringRecoveryCodec.readPending(scope, bytes)
        if (!RecoveryValidation.same(intent, actual)) RecoveryValidation.invalid()
        pending[scope] = bytes
        actual
    }

    override suspend fun confirmCreation(
        scope: AuthoringRecoveryScope,
        expectedIntent: AuthoringSubmission,
        actual: AuthoringItem,
    ): Unit = mutex.withLock {
        RecoveryValidation.intent(scope, expectedIntent)
        if (!AuthoringContract.matches(expectedIntent, actual))
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.PENDING_CONFLICT)
        val existing = pending[scope]?.let { AuthoringRecoveryCodec.readPending(scope, it) }
        if (existing != null && !RecoveryValidation.same(existing, expectedIntent))
            throw AuthoringRecoveryException(AuthoringRecoveryFailure.PENDING_CONFLICT)
        pending.remove(scope)
        if (
            drafts[scope]?.let { AuthoringRecoveryCodec.readDraft(scope, it).draft.id } ==
                expectedIntent.id
        )
            drafts.remove(scope)
    }

    override suspend fun discardUnsent(
        scope: AuthoringRecoveryScope,
        expectedDraftId: String,
    ): Unit = mutex.withLock {
        if (
            drafts[scope]?.let { AuthoringRecoveryCodec.readDraft(scope, it).draft.id } ==
                expectedDraftId
        )
            drafts.remove(scope)
    }

    override suspend fun clearUnsentForAccount(uid: String): Unit = mutex.withLock {
        drafts.keys.removeAll { it.uid == uid }
    }
}
