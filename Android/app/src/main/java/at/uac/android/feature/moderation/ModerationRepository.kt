package at.uac.android.feature.moderation

import at.uac.android.feature.browse.RawDocument
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.flow

/** Read-only by design: there is no mutation port or pending callable in this first A01 package. */
interface ModerationSource {
    suspend fun head(session: ModerationSession, kind: ModerationKind): List<RawDocument>

    suspend fun preview(session: ModerationSession, target: ModerationTarget): RawDocument?

    fun changes(
        session: ModerationSession,
        kind: ModerationKind,
        selected: ModerationTarget?,
    ): Flow<Unit>
}

class ModerationRepository(
    private val source: ModerationSource,
    private val authority: () -> ModerationSession?,
) {
    private fun capture(): ModerationSession =
        authority().also(ModerationContract::requireSession)!!

    private fun current(session: ModerationSession) {
        if (authority() != session) throw CancellationException("Moderation session changed")
        ModerationContract.requireSession(session)
    }

    suspend fun head(kind: ModerationKind): ModerationHead {
        val session = capture()
        val rows = source.head(session, kind)
        current(session)
        return ModerationContract.head(kind, rows)
    }

    suspend fun preview(target: ModerationTarget): ModerationPreview? {
        val session = capture()
        ModerationContract.validate(target)
        val row = source.preview(session, target)
        current(session)
        return row?.let { ModerationContract.preview(target, it) }
    }

    fun changes(kind: ModerationKind, target: ModerationTarget?): Flow<Unit> = flow {
        val session = capture()
        target?.let {
            ModerationContract.validate(it)
            if (it.kind != kind) ModerationContract.fail(ModerationFailure.INVALID)
        }
        source.changes(session, kind, target).collect {
            current(session)
            emit(Unit)
        }
    }
}
