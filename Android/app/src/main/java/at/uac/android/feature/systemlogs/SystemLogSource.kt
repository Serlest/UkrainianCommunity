package at.uac.android.feature.systemlogs

import at.uac.android.feature.moderation.ModerationSession

interface SystemLogSource {
    suspend fun list(session: ModerationSession, access: SystemLogAccess, sort: SystemLogSort): List<SystemLogEntry>
    suspend fun find(session: ModerationSession, access: SystemLogAccess, id: String): SystemLogEntry?
    suspend fun review(session: ModerationSession, expected: SystemLogEntry): SystemLogEntry
    suspend fun delete(session: ModerationSession, expected: SystemLogEntry): Int
    suspend fun clear(session: ModerationSession): Int
    suspend fun testPush(session: ModerationSession): TestPushReceipt
}
