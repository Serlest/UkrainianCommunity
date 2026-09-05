package at.uac.android.feature.gallery

import at.uac.android.feature.browse.Content
import at.uac.android.feature.organization.OrganizationMutationGate
import at.uac.android.feature.organization.OrganizationSession
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.withContext

interface GallerySource {
    suspend fun snapshot(organizationId: String, session: OrganizationSession): GallerySnapshot

    suspend fun photo(target: GalleryTarget, session: OrganizationSession): GalleryPhoto?

    suspend fun blob(target: GalleryTarget, session: OrganizationSession): GalleryBlob?

    suspend fun upload(
        target: GalleryTarget,
        photo: PreparedGalleryPhoto,
        session: OrganizationSession,
    ): GalleryBlob

    suspend fun create(
        intent: GalleryUploadIntent,
        imageUrl: String,
        session: OrganizationSession,
    ): GalleryReceipt

    suspend fun remove(target: GalleryTarget, session: OrganizationSession): GalleryReceipt

    suspend fun removeBlob(target: GalleryTarget, session: OrganizationSession)

    fun changes(organizationId: String, session: OrganizationSession): Flow<Result<Unit>>
}

/**
 * All writes run within one real Auth identity lease; no retry, detached Task or compensating
 * overwrite.
 */
class GalleryRepository(
    private val source: GallerySource,
    private val journal: GalleryJournal,
    private val currentSession: () -> OrganizationSession?,
    private val gate: OrganizationMutationGate,
    private val visibleOrganization: (Content) -> Boolean = { true },
) {
    private fun session(): OrganizationSession =
        (currentSession() ?: GalleryContract.fail(GalleryFailure.SIGN_IN)).also {
            if (!it.ready) GalleryContract.fail(GalleryFailure.NOT_READY)
        }

    private fun current(session: OrganizationSession) {
        if (currentSession() != session)
            throw CancellationException("Gallery account scope changed")
    }

    private suspend fun fresh(id: String, session: OrganizationSession): GallerySnapshot {
        current(session)
        return source.snapshot(id, session).also {
            current(session)
            GalleryContract.authorize(it.organization, session)
            if (it.organizationId != id || !visibleOrganization(it.content))
                GalleryContract.fail(GalleryFailure.POLICY)
        }
    }

    private suspend fun photo(target: GalleryTarget, session: OrganizationSession) =
        source.photo(target, session).also { current(session) }

    private suspend fun blob(target: GalleryTarget, session: OrganizationSession) =
        source.blob(target, session).also { current(session) }

    suspend fun load(id: String) = fresh(id, session())

    suspend fun pending(id: String): List<GalleryJournalEntry> {
        val s = session()
        return journal.pending(s.uid).also { current(s) }.filter { it.target.organizationId == id }
    }

    suspend fun image(expected: GalleryPhoto): GalleryBlob {
        val s = session()
        fresh(expected.target.organizationId, s)
        if (photo(expected.target, s) != expected) GalleryContract.fail(GalleryFailure.STALE)
        val image =
            blob(expected.target, s) ?: GalleryContract.fail(GalleryFailure.IMAGE_UNAVAILABLE)
        if (GalleryContract.token(expected.imageUrl, expected.target) != image.token)
            GalleryContract.fail(GalleryFailure.CONFLICT)
        fresh(expected.target.organizationId, s)
        if (photo(expected.target, s) != expected) GalleryContract.fail(GalleryFailure.STALE)
        return image
    }

    fun changes(id: String, session: OrganizationSession) = source.changes(id, session)

    private suspend fun <T> mutate(session: OrganizationSession, action: suspend () -> T): T {
        current(session)
        // SDK uploads/callables/deletes are awaited to their actual completion even when the
        // consumer leaves.
        return gate
            .withSession(session) {
                withContext(NonCancellable) {
                    current(session)
                    action()
                }
            }
            .also { current(session) }
    }

    private suspend fun noPending(id: String, session: OrganizationSession) {
        if (journal.pending(session.uid).any { it.target.organizationId == id })
            GalleryContract.fail(GalleryFailure.UNCONFIRMED)
        current(session)
    }

    private fun writable(snapshot: GallerySnapshot) {
        if (snapshot.overflow) GalleryContract.fail(GalleryFailure.LIMIT)
    }

    private fun terminal(error: Exception) =
        (error as? GalleryException)?.failure in
            setOf(
                GalleryFailure.DENIED,
                GalleryFailure.NOT_READY,
                GalleryFailure.MISSING,
                GalleryFailure.INVALID,
                GalleryFailure.LIMIT,
            )

    suspend fun upload(intent: GalleryUploadIntent): GalleryMutationResult {
        val s = session()
        return mutate(s) {
            val target = intent.target
            val initial = fresh(target.organizationId, s)
            writable(initial)
            if (initial.photos.size >= GalleryContract.MAX_PHOTOS)
                GalleryContract.fail(GalleryFailure.LIMIT)
            noPending(target.organizationId, s)
            if (photo(target, s) != null || blob(target, s) != null)
                GalleryContract.fail(GalleryFailure.CONFLICT)
            var entry =
                journal.put(
                    s.uid,
                    GalleryJournalEntry(
                        GalleryContract.accountHash(s.uid),
                        target,
                        GalleryPhase.UPLOADING,
                        intent.photo.hash,
                        GalleryContract.hashText(intent.caption.orEmpty()),
                        GalleryContract.accountHash(s.uid),
                    ),
                )
            current(s)
            val image =
                try {
                    source.upload(target, intent.photo, s).also { current(s) }
                } catch (error: GalleryUploadRejected) {
                    journal.put(s.uid, entry.copy(phase = GalleryPhase.UPLOAD_REJECTED), entry)
                    throw GalleryException(error.failure, error)
                }
            if (image.hash != intent.photo.hash) GalleryContract.fail(GalleryFailure.CONFLICT)
            entry =
                journal.put(
                    s.uid,
                    entry.copy(phase = GalleryPhase.UPLOADED, token = image.token),
                    entry,
                )
            val beforeMetadata = fresh(target.organizationId, s)
            writable(beforeMetadata)
            if (beforeMetadata.photos.size >= GalleryContract.MAX_PHOTOS)
                GalleryContract.fail(GalleryFailure.LIMIT)
            if (photo(target, s) != null) GalleryContract.fail(GalleryFailure.CONFLICT)
            entry = journal.put(s.uid, entry.copy(phase = GalleryPhase.CREATE_SUBMITTED), entry)
            current(s)
            val receipt =
                try {
                    source.create(intent, GalleryContract.alias(target, image.token), s)
                } catch (error: Exception) {
                    if (error is CancellationException) throw error
                    if (terminal(error))
                        journal.put(s.uid, entry.copy(phase = GalleryPhase.CREATE_REJECTED), entry)
                    throw error
                }
            current(s)
            val saved = photo(target, s) ?: GalleryContract.fail(GalleryFailure.UNCONFIRMED)
            if (
                !GalleryContract.matches(saved, entry) ||
                    receipt.uploadedBy != s.uid ||
                    receipt.createdAt != saved.createdAt
            )
                GalleryContract.fail(GalleryFailure.UNCONFIRMED)
            val readImage = blob(target, s) ?: GalleryContract.fail(GalleryFailure.UNCONFIRMED)
            if (readImage.hash != entry.jpegHash || readImage.token != entry.token)
                GalleryContract.fail(GalleryFailure.UNCONFIRMED)
            val final = fresh(target.organizationId, s)
            GalleryContract.verifyCount(final, receipt)
            if (final.photos.none { it == saved }) GalleryContract.fail(GalleryFailure.UNCONFIRMED)
            journal.clear(s.uid, entry)
            GalleryMutationResult(final)
        }
    }

    suspend fun remove(expected: GalleryPhoto): GalleryMutationResult {
        val s = session()
        return mutate(s) {
            val target = expected.target
            writable(fresh(target.organizationId, s))
            noPending(target.organizationId, s)
            if (photo(target, s) != expected) GalleryContract.fail(GalleryFailure.STALE)
            val image = blob(target, s)
            val token =
                GalleryContract.token(expected.imageUrl, target)
                    ?: GalleryContract.fail(GalleryFailure.INVALID)
            if (image != null && image.token != token) GalleryContract.fail(GalleryFailure.CONFLICT)
            var entry =
                journal.put(
                    s.uid,
                    GalleryJournalEntry(
                        GalleryContract.accountHash(s.uid),
                        target,
                        GalleryPhase.DELETE_SUBMITTED,
                        image?.hash ?: GalleryContract.hash(byteArrayOf()),
                        GalleryContract.hashText(expected.caption.orEmpty()),
                        GalleryContract.accountHash(expected.uploadedBy),
                        token,
                    ),
                )
            current(s)
            val receipt =
                try {
                    source.remove(target, s)
                } catch (error: Exception) {
                    if (error is CancellationException) throw error
                    if (terminal(error))
                        journal.put(s.uid, entry.copy(phase = GalleryPhase.DELETE_REJECTED), entry)
                    throw error
                }
            current(s)
            entry = journal.put(s.uid, entry.copy(phase = GalleryPhase.METADATA_REMOVED), entry)
            val final = fresh(target.organizationId, s)
            GalleryContract.verifyCount(final, receipt)
            if (photo(target, s) != null || final.photos.any { it.target == target })
                GalleryContract.fail(GalleryFailure.UNCONFIRMED)
            try {
                cleanupChecked(entry, s)
                GalleryMutationResult(final)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                current(s)
                GalleryMutationResult(final, entry)
            }
        }
    }

    /** Server reads only. Local journal transitions do not retry either callable or upload. */
    suspend fun reconcile(expected: GalleryJournalEntry): GalleryRecoveryResult {
        val s = session()
        val id = expected.target.organizationId
        return mutate(s) {
            requirePending(expected, s)
            val snapshot = fresh(id, s)
            val saved = photo(expected.target, s)
            val image = blob(expected.target, s)
            var entry = expected
            if (saved != null && !GalleryContract.matches(saved, entry))
                GalleryContract.fail(GalleryFailure.CONFLICT)
            if (
                image != null &&
                    (image.hash != entry.jpegHash || entry.token?.let { it != image.token } == true)
            )
                GalleryContract.fail(GalleryFailure.CONFLICT)
            if (
                saved != null &&
                    entry.phase in
                        setOf(
                            GalleryPhase.CREATE_SUBMITTED,
                            GalleryPhase.UPLOADED,
                            GalleryPhase.UPLOADING,
                        )
            ) {
                // UPLOADING cannot match a published record without a token; no receipt is invented
                // from its mere presence.
                if (
                    image != null &&
                        entry.token != null &&
                        snapshot.photos.any { it == saved } &&
                        !snapshot.overflow &&
                        snapshot.counter == snapshot.photos.size
                ) {
                    journal.clear(s.uid, entry)
                    return@mutate GalleryRecoveryResult(GalleryRecovery.PUBLISHED, snapshot, null)
                }
            }
            if (saved != null && entry.phase == GalleryPhase.DELETE_REJECTED) {
                journal.clear(s.uid, entry)
                return@mutate GalleryRecoveryResult(GalleryRecovery.UNCHANGED, snapshot, null)
            }
            if (
                saved == null &&
                    entry.phase in
                        setOf(
                            GalleryPhase.DELETE_SUBMITTED,
                            GalleryPhase.DELETE_REJECTED,
                            GalleryPhase.METADATA_REMOVED,
                        )
            ) {
                if (entry.phase != GalleryPhase.METADATA_REMOVED)
                    entry =
                        journal.put(s.uid, entry.copy(phase = GalleryPhase.METADATA_REMOVED), entry)
                if (image == null) {
                    journal.clear(s.uid, entry)
                    return@mutate GalleryRecoveryResult(GalleryRecovery.REMOVED, snapshot, null)
                }
                return@mutate GalleryRecoveryResult(
                    GalleryRecovery.CLEANUP_AVAILABLE,
                    snapshot,
                    entry,
                )
            }
            if (
                saved == null &&
                    entry.phase in
                        setOf(
                            GalleryPhase.UPLOADING,
                            GalleryPhase.UPLOADED,
                            GalleryPhase.CREATE_REJECTED,
                            GalleryPhase.UPLOAD_REJECTED,
                        )
            ) {
                if (image != null) {
                    // Pre-metadata upload may have lost its download-token receipt. Recover it only
                    // from the exact expected JPEG.
                    if (entry.token == null)
                        entry = journal.put(s.uid, entry.copy(token = image.token), entry)
                    return@mutate GalleryRecoveryResult(
                        GalleryRecovery.CLEANUP_AVAILABLE,
                        snapshot,
                        entry,
                    )
                }
                if (
                    entry.phase in setOf(GalleryPhase.CREATE_REJECTED, GalleryPhase.UPLOAD_REJECTED)
                ) {
                    journal.clear(s.uid, entry)
                    return@mutate GalleryRecoveryResult(GalleryRecovery.UNCHANGED, snapshot, null)
                }
            }
            // A missing CREATE_SUBMITTED document does not prove that the outstanding callable will
            // never commit.
            GalleryRecoveryResult(GalleryRecovery.UNRESOLVED, snapshot, entry)
        }
    }

    suspend fun cleanup(expected: GalleryJournalEntry): GalleryMutationResult {
        val s = session()
        return mutate(s) {
            requirePending(expected, s)
            if (
                expected.phase !in
                    setOf(
                        GalleryPhase.UPLOADING,
                        GalleryPhase.UPLOADED,
                        GalleryPhase.CREATE_REJECTED,
                        GalleryPhase.METADATA_REMOVED,
                        GalleryPhase.UPLOAD_REJECTED,
                    )
            )
                GalleryContract.fail(GalleryFailure.UNCONFIRMED)
            fresh(expected.target.organizationId, s)
            cleanupChecked(expected, s)
            GalleryMutationResult(fresh(expected.target.organizationId, s))
        }
    }

    private suspend fun requirePending(
        expected: GalleryJournalEntry,
        session: OrganizationSession,
    ) {
        if (
            expected.accountHash != GalleryContract.accountHash(session.uid) ||
                journal.pending(session.uid).none { it == expected }
        )
            GalleryContract.fail(GalleryFailure.JOURNAL)
        current(session)
    }

    private suspend fun cleanupChecked(entry: GalleryJournalEntry, session: OrganizationSession) {
        if (entry.phase == GalleryPhase.UPLOADING && entry.token == null)
            GalleryContract.fail(GalleryFailure.UNCONFIRMED)
        fresh(entry.target.organizationId, session)
        if (photo(entry.target, session) != null) GalleryContract.fail(GalleryFailure.CONFLICT)
        val existing = blob(entry.target, session)
        if (existing != null) {
            if (
                entry.token == null ||
                    existing.hash != entry.jpegHash ||
                    existing.token != entry.token
            )
                GalleryContract.fail(GalleryFailure.CONFLICT)
            // Never call delete from a URL. Source uses only the canonical path and named demo
            // bucket.
            source.removeBlob(entry.target, session)
            current(session)
        }
        if (blob(entry.target, session) != null || photo(entry.target, session) != null)
            GalleryContract.fail(GalleryFailure.CLEANUP_PENDING)
        journal.clear(session.uid, entry)
    }
}
