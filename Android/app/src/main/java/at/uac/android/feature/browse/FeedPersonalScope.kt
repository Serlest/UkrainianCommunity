package at.uac.android.feature.browse

import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

data class NewsPersonalScope(
    val newsIds: Set<String> = emptySet(),
    val organizationIds: Set<String> = emptySet(),
)

fun interface NewsPersonalScopeSource {
    suspend fun load(source: NewsSource): NewsPersonalScope
}

fun interface OrganizationPersonalScopeSource {
    suspend fun load(scope: OrganizationScope): Set<String>
}

fun interface EventPersonalScopeSource {
    suspend fun load(scope: EventScope): Set<String>
}

class FirestoreFeedPersonalScopeSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
) : NewsPersonalScopeSource, OrganizationPersonalScopeSource, EventPersonalScopeSource {
    init {
        FirebaseBackendGuard.requireFirestore(db)
        FirebaseBackendGuard.requireAuth(auth)
        require(db.app == auth.app) { "NEWS_SCOPE_BACKEND_MISMATCH" }
    }

    override suspend fun load(source: NewsSource): NewsPersonalScope {
        if (source == NewsSource.ALL) return NewsPersonalScope()
        val uid = auth.currentUser?.takeUnless { it.isAnonymous }?.uid
            ?: throw ReadException(ReadFailure.DENIED)
        return request {
            when (source) {
                NewsSource.ALL -> NewsPersonalScope()
                NewsSource.SAVED ->
                    NewsPersonalScope(
                        newsIds = documentIds(db.collection("users/$uid/newsBookmarks"))
                    )
                NewsSource.SUBSCRIBED -> {
                    val rows =
                        documents(
                            db.collection("likes")
                                .whereEqualTo("userId", uid)
                                .orderBy(FieldPath.documentId())
                        )
                    NewsPersonalScope(
                        organizationIds =
                            rows
                                .mapNotNull { it.getString("subscribedOrganizationId") }
                                .filter(String::isNotBlank)
                                .toSet()
                    )
                }
            }
        }
            .also {
                if (auth.currentUser?.uid != uid)
                    throw CancellationException("News account changed")
            }
    }

    override suspend fun load(scope: OrganizationScope): Set<String> {
        if (scope == OrganizationScope.ALL) return emptySet()
        val uid = auth.currentUser?.takeUnless { it.isAnonymous }?.uid
            ?: throw ReadException(ReadFailure.DENIED)
        return request {
            when (scope) {
                OrganizationScope.ALL -> emptySet()
                OrganizationScope.BOOKMARKED ->
                    documentIds(db.collection("users/$uid/organizationBookmarks"))
                OrganizationScope.SUBSCRIBED ->
                    documents(
                        db.collection("likes")
                            .whereEqualTo("userId", uid)
                            .orderBy(FieldPath.documentId())
                    ).mapNotNull { it.getString("subscribedOrganizationId") }
                        .filter(String::isNotBlank).toSet()
            }
        }.also {
            if (auth.currentUser?.uid != uid)
                throw CancellationException("Organization account changed")
        }
    }

    override suspend fun load(scope: EventScope): Set<String> {
        if (scope == EventScope.ALL) return emptySet()
        val uid = auth.currentUser?.takeUnless { it.isAnonymous }?.uid
            ?: throw ReadException(ReadFailure.DENIED)
        return request {
            when (scope) {
                EventScope.ALL -> emptySet()
                EventScope.SAVED -> documentIds(db.collection("users/$uid/eventBookmarks"))
                EventScope.REGISTERED ->
                    documents(
                        db.collection("registrations")
                            .whereEqualTo("userId", uid)
                            .orderBy(FieldPath.documentId())
                    ).mapNotNull { it.getString("eventId") }
                        .filter(String::isNotBlank).toSet()
            }
        }.also {
            if (auth.currentUser?.uid != uid)
                throw CancellationException("Event account changed")
        }
    }

    private suspend fun documentIds(collection: com.google.firebase.firestore.CollectionReference) =
        documents(collection.orderBy(FieldPath.documentId())).map { it.id }.toSet()

    private suspend fun documents(
        initial: Query
    ): List<com.google.firebase.firestore.DocumentSnapshot> {
        val result = mutableListOf<com.google.firebase.firestore.DocumentSnapshot>()
        var query = initial
        repeat(20) {
            val page = query.limit(100).get(Source.SERVER).await().documents
            result += page
            if (page.size < 100) return result
            query = initial.startAfter(page.last())
        }
        throw ReadException(ReadFailure.INVALID)
    }

    private suspend fun <T> request(block: suspend () -> T): T =
        try {
            block()
        } catch (error: CancellationException) {
            throw error
        } catch (error: ReadException) {
            throw error
        } catch (error: FirebaseFirestoreException) {
            throw ReadException(
                when (error.code) {
                    FirebaseFirestoreException.Code.PERMISSION_DENIED,
                    FirebaseFirestoreException.Code.UNAUTHENTICATED -> ReadFailure.DENIED
                    FirebaseFirestoreException.Code.UNAVAILABLE,
                    FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> ReadFailure.OFFLINE
                    FirebaseFirestoreException.Code.FAILED_PRECONDITION -> ReadFailure.INDEX
                    FirebaseFirestoreException.Code.INVALID_ARGUMENT -> ReadFailure.INVALID
                    else -> ReadFailure.UNKNOWN
                },
                error,
            )
        }
}
