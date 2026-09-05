package at.uac.android.feature.contentmedia

import at.uac.android.feature.authoring.AuthoringContract
import at.uac.android.feature.organization.OrganizationMutationGate
import at.uac.android.feature.organization.OrganizationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow

interface ContentCoverSource {
    suspend fun snapshot(
        target: ContentCoverTarget,
        session: OrganizationSession,
    ): ContentCoverSnapshot

    suspend fun image(
        snapshot: ContentCoverSnapshot,
        session: OrganizationSession,
    ): ContentCoverAsset?

    fun changes(snapshot: ContentCoverSnapshot, session: OrganizationSession): Flow<Result<Unit>>

    suspend fun upload(
        intent: ContentCoverIntent.Upload,
        session: OrganizationSession,
    ): ContentCoverResponse

    suspend fun remove(intent: ContentCoverIntent.Remove, session: OrganizationSession)
}

class ContentCoverRepository(
    private val source: ContentCoverSource,
    private val current: () -> OrganizationSession?,
    private val gate: OrganizationMutationGate,
) {
    private fun capture(): OrganizationSession =
        (current() ?: ContentCoverContract.fail(ContentCoverFailure.SIGN_IN)).also {
            if (!it.ready) ContentCoverContract.fail(ContentCoverFailure.NOT_READY)
        }

    private fun ensure(session: OrganizationSession) {
        if (session != current()) throw CancellationException("Content cover session changed")
    }

    private suspend fun load(
        target: ContentCoverTarget,
        session: OrganizationSession,
    ): ContentCoverSnapshot {
        ensure(session)
        val snapshot =
            source.snapshot(target, session).also {
                ensure(session)
                ContentCoverContract.validate(it, target)
            }
        AuthoringContract.authority(snapshot.organization, session)
        return snapshot
    }

    suspend fun load(target: ContentCoverTarget): ContentCoverSnapshot = load(target, capture())

    suspend fun image(snapshot: ContentCoverSnapshot): ContentCoverAsset? {
        val session = capture()
        ensure(session)
        return source.image(snapshot, session).also { ensure(session) }
    }

    fun changes(snapshot: ContentCoverSnapshot, session: OrganizationSession) =
        source.changes(snapshot, session)

    suspend fun execute(intent: ContentCoverIntent): ContentCoverConfirmation {
        val session = capture()
        return gate
            .withSession(session) {
                val current = load(intent.snapshot.target, session)
                if (!current.editable) ContentCoverContract.fail(ContentCoverFailure.READ_ONLY)
                ContentCoverContract.unchanged(intent.snapshot, current)
                when (intent) {
                    is ContentCoverIntent.Upload -> {
                        val response = source.upload(intent, session)
                        ensure(session)
                        postWrite {
                            val saved =
                                staged(ContentCoverStage.READ_DOCUMENT) {
                                    load(current.target, session)
                                }
                            val asset =
                                staged(ContentCoverStage.READ_IMAGE) {
                                    source.image(saved, session).also { ensure(session) }
                                }
                                    ?: throw ContentCoverException(
                                        ContentCoverFailure.UNCONFIRMED,
                                        diagnostic =
                                            ContentCoverDiagnostic(
                                                ContentCoverStage.READ_IMAGE,
                                                failedChecks =
                                                    setOf(ContentCoverCheck.MISSING_ASSET),
                                            ),
                                    )
                            val checks = linkedSetOf<ContentCoverCheck>()
                            if (response.target != current.target)
                                checks += ContentCoverCheck.TARGET
                            if (saved.imageUrl != response.imageUrl)
                                checks += ContentCoverCheck.DOCUMENT_URL
                            if (response.byteCount != intent.photo.byteCount)
                                checks += ContentCoverCheck.BYTE_COUNT
                            if (!intent.photo.matches(asset.bytes))
                                checks += ContentCoverCheck.BYTES
                            if (
                                ContentCoverContract.token(response.imageUrl, current.target) !=
                                    asset.token
                            )
                                checks += ContentCoverCheck.TOKEN
                            if (!ContentCoverContract.preserved(current, saved))
                                checks += ContentCoverCheck.PRESERVED_FIELDS
                            if (checks.isNotEmpty())
                                throw ContentCoverException(
                                    ContentCoverFailure.UNCONFIRMED,
                                    diagnostic =
                                        ContentCoverDiagnostic(
                                            ContentCoverStage.VERIFY_UPLOAD,
                                            failedChecks = checks,
                                            changedFields =
                                                contentCoverChangedFields(current, saved),
                                        ),
                                )
                            ContentCoverConfirmation(saved, asset)
                        }
                    }
                    is ContentCoverIntent.Remove -> {
                        if (!current.removable)
                            ContentCoverContract.fail(ContentCoverFailure.READ_ONLY)
                        staged(ContentCoverStage.REMOVE_CALL) { source.remove(intent, session) }
                        ensure(session)
                        postWrite {
                            val saved =
                                staged(ContentCoverStage.READ_DOCUMENT) {
                                    load(current.target, session)
                                }
                            val checks = linkedSetOf<ContentCoverCheck>()
                            if (saved.imageUrl != null)
                                checks += ContentCoverCheck.REFERENCE_PRESENT
                            if (!ContentCoverContract.preserved(current, saved))
                                checks += ContentCoverCheck.PRESERVED_FIELDS
                            if (checks.isNotEmpty())
                                throw ContentCoverException(
                                    ContentCoverFailure.UNCONFIRMED,
                                    diagnostic =
                                        ContentCoverDiagnostic(
                                            ContentCoverStage.VERIFY_REMOVE,
                                            failedChecks = checks,
                                            changedFields =
                                                contentCoverChangedFields(current, saved),
                                        ),
                                )
                            ContentCoverConfirmation(saved, null)
                        }
                    }
                }
            }
            .also { ensure(session) }
    }

    /**
     * Read-only recovery. Even a nonmatching or absent object never triggers reupload, deletion, or
     * rollback.
     */
    suspend fun recover(intent: ContentCoverIntent): ContentCoverRecovery {
        val session = capture()
        val current = load(intent.snapshot.target, session)
        val confirmed =
            if (!ContentCoverContract.preserved(intent.snapshot, current)) null
            else
                when (intent) {
                    is ContentCoverIntent.Remove ->
                        if (current.imageUrl == null) ContentCoverConfirmation(current, null)
                        else null
                    is ContentCoverIntent.Upload -> {
                        val asset = source.image(current, session).also { ensure(session) }
                        if (
                            asset != null &&
                                intent.photo.matches(asset.bytes) &&
                                current.imageUrl?.let {
                                    ContentCoverContract.token(it, current.target)
                                } == asset.token
                        )
                            ContentCoverConfirmation(current, asset)
                        else null
                    }
                }
        return ContentCoverRecovery(confirmed, current)
    }

    private suspend fun <T> postWrite(action: suspend () -> T): T =
        try {
            action()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw ContentCoverException(ContentCoverFailure.UNCONFIRMED, error)
        }

    private suspend fun <T> staged(stage: ContentCoverStage, action: suspend () -> T): T =
        try {
            action()
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            throw ContentCoverException(
                contentCoverFailure(error),
                error,
                contentCoverDiagnostic(stage, error),
            )
        }
}
