package at.uac.android.feature.registrations

import at.uac.android.feature.browse.*
import at.uac.android.feature.community.CommunityContract
import at.uac.android.feature.community.communityId
import at.uac.android.feature.personal.*
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout

interface RegistrationsSource {
    suspend fun page(uid: String, after: String?, size: Int): MarkerPage

    suspend fun events(ids: List<String>): List<RawDocument>
}

class RegistrationsRepository(
    private val source: RegistrationsSource,
    private val authority: () -> PersonalSession?,
) {
    suspend fun load(after: String? = null, size: Int = 50): RegistrationsPage {
        require(size in 1..50)
        val captured = authority() ?: throw PersonalException(PersonalFailure.SIGN_IN)
        if (!captured.ready) throw PersonalException(PersonalFailure.NOT_READY)
        if (!communityId(captured.uid, 128) || after?.let { !communityId(it, 1_500) } == true)
            throw PersonalException(PersonalFailure.INVALID)
        fun current() {
            if (authority() != captured) throw CancellationException("Registration account changed")
        }
        return try {
            withTimeout(20_000) {
                current()
                val page = source.page(captured.uid, after, size)
                current()
                if (
                    page.rows.size > size ||
                        page.rows.map { it.id }.distinct().size != page.rows.size ||
                        page.rows.any { after != null && it.id <= after } ||
                        page.rows.zipWithNext().any { (left, right) -> left.id >= right.id } ||
                        page.next != (page.rows.lastOrNull()?.id ?: after) ||
                        page.hasMore && (page.rows.isEmpty() || page.next == after)
                )
                    throw PersonalException(PersonalFailure.INVALID)
                val ids =
                    page.rows.map { row ->
                        val eventId = row.fields.string("eventId")
                        if (
                            !communityId(eventId) ||
                                row.id != CommunityContract.registrationId(eventId, captured.uid) ||
                                row.fields["id"] != row.id ||
                                row.fields["userId"] != captured.uid ||
                                row.fields["registeredAt"] !is Instant
                        )
                            throw PersonalException(PersonalFailure.INVALID)
                        eventId
                    }
                val events =
                    ids.chunked(10)
                        .flatMap { chunk ->
                            current()
                            source.events(chunk).also { rows ->
                                current()
                                if (
                                    rows.any { it.id !in chunk } ||
                                        rows.map { it.id }.distinct().size != rows.size
                                )
                                    throw PersonalException(PersonalFailure.INVALID)
                            }
                        }
                        .mapNotNull { row ->
                            try {
                                decodeContent(ContentKind.EVENTS, row).takeIf {
                                    it.fields.string("sourceType") == "organization"
                                }
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
                            }
                        }
                        .distinctBy { it.id }
                current()
                RegistrationsPage(
                    events,
                    page.next,
                    page.hasMore,
                    ids.distinct().size - events.size,
                )
            }
        } catch (error: TimeoutCancellationException) {
            current()
            throw PersonalException(PersonalFailure.OFFLINE, error)
        } catch (error: Exception) {
            current()
            throw error
        }
    }
}
