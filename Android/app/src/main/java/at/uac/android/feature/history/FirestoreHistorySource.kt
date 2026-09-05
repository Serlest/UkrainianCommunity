package at.uac.android.feature.history

import android.content.Context
import at.uac.android.core.LocalEnvironment
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.auth.AuthException
import at.uac.android.feature.auth.AuthProblem
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.browse.Content
import at.uac.android.feature.browse.ContentKind
import at.uac.android.feature.browse.Fields
import at.uac.android.feature.browse.RawDocument
import at.uac.android.feature.browse.string
import at.uac.android.feature.personal.validDocumentId
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

class AuthHistoryMutationGate(private val auth: AuthStore) : HistoryMutationGate {
    override suspend fun <T> withSession(session: HistorySession, operation: suspend () -> T): T =
        try {
            auth.withReadySession(session.uid, session.revision, operation)
        } catch (error: AuthException) {
            if (error.problem == AuthProblem.SESSION_CHANGED)
                throw CancellationException("History account changed")
            throw HistoryException(HistoryFailure.NOT_READY, error)
        }
}

class FirestoreHistorySource(private val db: FirebaseFirestore, private val auth: FirebaseAuth) :
    HistorySource {
    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireSameApp(auth, db)
    }

    private fun check(session: HistorySession, current: () -> Boolean = { true }) {
        HistoryContract.ready(session)
        if (auth.currentUser?.uid != session.uid || !current())
            throw CancellationException("History account changed")
    }

    private fun convert(value: Any?): Any? =
        when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            is Map<*, *> -> value.entries.associate { it.key.toString() to convert(it.value) }
            is List<*> -> value.map(::convert)
            else -> value
        }

    @Suppress("UNCHECKED_CAST")
    private fun raw(snapshot: DocumentSnapshot): RawDocument? =
        snapshot.data?.let { RawDocument(snapshot.id, convert(it) as Fields) }

    private suspend fun <T> request(write: Boolean = false, operation: suspend () -> T): T =
        try {
            operation()
        } catch (error: CancellationException) {
            throw error
        } catch (error: HistoryException) {
            throw error
        } catch (error: FirebaseFirestoreException) {
            throw HistoryException(
                when (error.code) {
                    FirebaseFirestoreException.Code.PERMISSION_DENIED,
                    FirebaseFirestoreException.Code.UNAUTHENTICATED -> HistoryFailure.DENIED
                    FirebaseFirestoreException.Code.INVALID_ARGUMENT -> HistoryFailure.INVALID
                    FirebaseFirestoreException.Code.NOT_FOUND -> HistoryFailure.MISSING
                    FirebaseFirestoreException.Code.FAILED_PRECONDITION ->
                        if (write) HistoryFailure.CONFLICT else HistoryFailure.INDEX
                    FirebaseFirestoreException.Code.UNAVAILABLE,
                    FirebaseFirestoreException.Code.DEADLINE_EXCEEDED ->
                        if (write) HistoryFailure.UNCONFIRMED else HistoryFailure.OFFLINE
                    else -> if (write) HistoryFailure.UNCONFIRMED else HistoryFailure.UNKNOWN
                },
                error,
            )
        }

    private fun collection(session: HistorySession, section: HistorySection) =
        db.collection("users/${session.uid}/${section.collection}")

    override suspend fun page(
        session: HistorySession,
        section: HistorySection,
        cursor: HistoryCursor?,
        size: Int,
    ): HistoryRawPage = request {
        check(session)
        require(size in 1..section.pageSize)
        require(
            cursor == null ||
                (cursor.session == session &&
                    cursor.section == section &&
                    validDocumentId(cursor.id) &&
                    cursor.consumed in 1 until section.cap &&
                    size <= section.cap - cursor.consumed)
        )
        var query =
            collection(session, section)
                .orderBy(section.dateField, Query.Direction.DESCENDING)
                .orderBy(FieldPath.documentId(), Query.Direction.DESCENDING)
        if (cursor != null)
            query = query.startAfter(Timestamp(cursor.at.epochSecond, cursor.at.nano), cursor.id)
        val rows =
            query.limit((size + 1).toLong()).get(Source.SERVER).await().documents.mapNotNull(::raw)
        check(session)
        HistoryRawPage(rows.take(size), rows.size > size)
    }

    override suspend fun targets(
        kind: ContentKind,
        ids: List<String>,
        stillCurrent: () -> Boolean,
    ): List<RawDocument> = request {
        require(ids.size in 1..10 && ids.all(::validDocumentId))
        val uid = auth.currentUser?.uid ?: throw HistoryException(HistoryFailure.SIGN_IN)
        fun current() {
            if (!stillCurrent() || auth.currentUser?.uid != uid)
                throw CancellationException("History target account changed")
        }
        val rows = mutableListOf<RawDocument>()
        // Missing document-ID query literals can deny an entire `in` query under the unchanged
        // content Rules.
        // Individual server reads distinguish available targets without letting one deleted/private
        // item hide its neighbours.
        // Sequential reads bound concurrency to one; each repository batch contains at most ten
        // distinct targets.
        for (id in ids.distinct()) {
            current()
            val document =
                try {
                    raw(db.collection(kind.collection).document(id).get(Source.SERVER).await())
                } catch (error: FirebaseFirestoreException) {
                    if (
                        error.code in
                            setOf(
                                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                                FirebaseFirestoreException.Code.NOT_FOUND,
                            )
                    )
                        null
                    else throw error
                }
            current()
            document?.let(rows::add)
        }
        rows
    }

    override suspend fun record(
        session: HistorySession,
        section: HistorySection,
        id: String,
    ): RawDocument? = request {
        check(session)
        require(validDocumentId(id))
        raw(collection(session, section).document(id).get(Source.SERVER).await()).also {
            check(session)
        }
    }

    override suspend fun write(
        value: HistoryWrite,
        current: () -> Boolean,
        visible: (Content) -> Boolean,
    ): HistoryWriteReceipt =
        request(write = true) {
            HistoryContract.validate(value)
            check(value.session, current)
            val ref = collection(value.session, value.section).document(value.id)
            val target = value.target
            val marker =
                when (target.type) {
                    HistoryType.NEWS ->
                        db.document("users/${value.session.uid}/newsViews/${target.id}")
                    HistoryType.EVENT ->
                        db.document("users/${value.session.uid}/eventViews/${target.id}")
                    HistoryType.ORGANIZATION -> null
                }.takeIf { value.section == HistorySection.RECENT }
            // Transaction retries retain the same activity UUID. No app-level resubmission or
            // offline queue is used.
            val expected =
                db.runTransaction { transaction ->
                        check(value.session, current)
                        val document =
                            raw(transaction.get(db.document(target.path)))
                                ?: throw HistoryException(HistoryFailure.MISSING)
                        val content = HistoryContract.content(target, document)
                        if (!visible(content)) throw HistoryException(HistoryFailure.DENIED)
                        if (
                            value.section == HistorySection.RECENT &&
                                target.type == HistoryType.EVENT &&
                                document.fields["cancellationState"] == "cancelled"
                        )
                            throw HistoryException(HistoryFailure.DENIED)
                        val existing =
                            raw(transaction.get(ref))?.let {
                                HistoryContract.record(value.section, it)
                            }
                        val previousMarker = marker?.let { transaction.get(it) }
                        if (previousMarker?.exists() == true) checkMarker(previousMarker, value)
                        if (existing != null && value.section == HistorySection.ACTIVITY) {
                            if (existing.target != target || existing.action != value.action)
                                throw HistoryException(HistoryFailure.CONFLICT)
                            existing to false
                        } else {
                            val fields =
                                HistoryContract.fields(
                                    target,
                                    value.action,
                                    content.title(value.language),
                                    content.summary(value.language),
                                    document.fields
                                        .string(
                                            if (target.type == HistoryType.ORGANIZATION) "logoURL"
                                            else "imageURL"
                                        )
                                        .takeIf { it.isNotEmpty() },
                                    value.id,
                                    FieldValue.serverTimestamp(),
                                )
                            check(value.session, current)
                            transaction.set(ref, fields)
                            val created = marker != null && previousMarker?.exists() == false
                            if (created)
                                transaction.set(
                                    marker,
                                    mapOf(
                                        "id" to target.id,
                                        "${target.type.wire}Id" to target.id,
                                        "userId" to value.session.uid,
                                        "createdAt" to FieldValue.serverTimestamp(),
                                    ),
                                )
                            // A placeholder date is never written: it exists only in the
                            // expected-payload comparison.
                            HistoryContract.record(
                                value.section,
                                RawDocument(
                                    value.id,
                                    fields + (value.section.dateField to Instant.EPOCH),
                                ),
                            ) to created
                        }
                    }
                    .await()
            // Actual SDK completion remains inside Auth's NonCancellable identity gate, including
            // this read-back.
            historyWriteReadBack {
                check(value.session, current)
                val actual =
                    record(value.session, value.section, value.id)?.let {
                        HistoryContract.record(value.section, it)
                    } ?: throw HistoryException(HistoryFailure.UNCONFIRMED)
                if (actual.copy(at = expected.first.at) != expected.first)
                    throw HistoryException(HistoryFailure.UNCONFIRMED)
                if (marker != null) checkMarker(marker.get(Source.SERVER).await(), value)
                check(value.session, current)
                HistoryWriteReceipt(actual, expected.second)
            }
        }

    private fun checkMarker(row: DocumentSnapshot, value: HistoryWrite) {
        val expectedKeys = setOf("id", "${value.target.type.wire}Id", "userId", "createdAt")
        if (
            !row.exists() ||
                row.data?.keys != expectedKeys ||
                row.getString("id") != value.target.id ||
                row.getString("${value.target.type.wire}Id") != value.target.id ||
                row.getString("userId") != value.session.uid ||
                row.getTimestamp("createdAt") == null
        )
            throw HistoryException(HistoryFailure.INVALID)
    }

    override suspend fun delete(value: HistoryDelete, current: () -> Boolean) =
        request(write = true) {
            HistoryContract.delete(value)
            check(value.session, current)
            val references =
                value.records.map { collection(value.session, value.section).document(it.id) }
            db.runTransaction { transaction ->
                    check(value.session, current)
                    // Read every version before any delete. A newly viewed row must not be removed
                    // by an old confirmation.
                    val rows = references.map {
                        raw(transaction.get(it))?.let { row ->
                            HistoryContract.record(value.section, row)
                        }
                    }
                    if (
                        rows.zip(value.records).any { (actual, expected) ->
                            actual != null && actual != expected
                        }
                    )
                        throw HistoryException(HistoryFailure.CONFLICT)
                    check(value.session, current)
                    references.zip(rows).forEach { (ref, row) ->
                        if (row != null) transaction.delete(ref)
                    }
                    Unit
                }
                .await()
            check(value.session, current)
            for (ref in references) if (ref.get(Source.SERVER).await().exists())
                throw HistoryException(HistoryFailure.UNCONFIRMED)
            check(value.session, current)
        }
}

fun localHistorySource(context: Context): HistorySource =
    FirestoreHistorySource(AppBackend.firestore(context), AppBackend.auth(context))
