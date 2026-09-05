package at.uac.android.feature.registrations

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.browse.*
import at.uac.android.feature.community.communityId
import at.uac.android.feature.personal.*
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

class FirestoreRegistrationsSource(private val db: FirebaseFirestore) : RegistrationsSource {
    private val content = FirestorePersonalSource(db)

    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireFirestore(db)
    }

    override suspend fun page(uid: String, after: String?, size: Int): MarkerPage {
        require(communityId(uid, 128) && size in 1..50)
        require(after == null || communityId(after, 1_500))
        var query =
            db.collection("registrations")
                .whereEqualTo("userId", uid)
                .orderBy(FieldPath.documentId())
        if (after != null) query = query.startAfter(after)
        return try {
            val rows =
                query.limit((size + 1).toLong()).get(Source.SERVER).await().documents.map { document
                    ->
                    val fields =
                        document.data.orEmpty().mapValues { (_, value) ->
                            if (value is Timestamp)
                                Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
                            else value
                        }
                    RawDocument(document.id, fields)
                }
            val selected = rows.take(size)
            MarkerPage(selected, selected.lastOrNull()?.id ?: after, rows.size > size)
        } catch (error: CancellationException) {
            throw error
        } catch (error: FirebaseFirestoreException) {
            throw PersonalException(
                when (error.code) {
                    FirebaseFirestoreException.Code.PERMISSION_DENIED,
                    FirebaseFirestoreException.Code.UNAUTHENTICATED -> PersonalFailure.DENIED
                    FirebaseFirestoreException.Code.UNAVAILABLE,
                    FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> PersonalFailure.OFFLINE
                    FirebaseFirestoreException.Code.NOT_FOUND -> PersonalFailure.MISSING
                    FirebaseFirestoreException.Code.INVALID_ARGUMENT -> PersonalFailure.INVALID
                    else -> PersonalFailure.UNKNOWN
                },
                error,
            )
        }
    }

    override suspend fun events(ids: List<String>): List<RawDocument> =
        content.approvedContent(ContentKind.EVENTS, ids)
}

fun localRegistrationsSource(context: Context): RegistrationsSource =
    FirestoreRegistrationsSource(AppBackend.firestore(context))
