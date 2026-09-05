package at.uac.android.feature.platformrolemanagement

import at.uac.android.feature.moderation.ModerationSession
import kotlinx.coroutines.flow.Flow

/** Source boundary; presentation readiness never replaces actual Firebase owner/TOTP checks. */
interface PlatformRoleSource {
    /** Server-only raw snapshot under actual owner/activated MFA/TOTP checks. */
    suspend fun read(session: ModerationSession, targetId: String): PlatformRoleSnapshot

    /** Fresh bound metadata, requested only for assignment, never for removal/reconciliation. */
    suspend fun targetAuth(session: ModerationSession, targetId: String): PlatformRoleTargetAuth

    fun changes(session: ModerationSession, targetId: String): Flow<Unit>

    /**
     * Recheck actual privilege, reviewed raw version and assignment-only Auth before one Task.
     * Invoke canDispatch immediately before Task creation on the presentation dispatcher. Await
     * settlement and parse the actual response; no retry, synthetic receipt or direct role write.
     * The repository keeps its non-cancellable settlement scope through durable acknowledgement.
     */
    suspend fun send(
        session: ModerationSession,
        entry: PlatformRolePending,
        reason: String,
        canDispatch: () -> Boolean,
    ): PlatformRoleReceipt

    /** Read-only; unavailable reads do not establish absence, acceptance or permission to retry. */
    suspend fun reconcile(
        session: ModerationSession,
        entry: PlatformRolePending,
    ): PlatformRoleObservation
}
