package at.uac.android.feature.directory

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.auth.AuthStore
import at.uac.android.feature.moderation.ModerationAccess
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.moderation.moderationScope
import at.uac.android.feature.usermanagement.ManagedUser
import at.uac.android.feature.usermanagement.ManagedUsersContract
import at.uac.android.feature.usermanagement.ManagedUsersQuery
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentSnapshot
import com.google.firebase.firestore.FieldPath
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.google.firebase.firestore.Source
import java.time.Instant
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.tasks.await

data class DirectoryGrant(
    val uid: String,
    val name: String,
    val grantedBy: String,
    val grantedAt: Timestamp?,
    val email: String? = null,
    val profileState: DirectoryGrantProfileState = DirectoryGrantProfileState.LOADED,
)

enum class DirectoryGrantProfileState { LOADED, MISSING, READ_FAILED }

data class DirectoryCandidates(
    val users: List<ManagedUser>,
    val next: DocumentSnapshot?,
)

class DirectoryGrantStale : Exception("Directory editor grant changed")
class DirectoryGrantInvalid : Exception("Directory editor target is not active")

interface DirectoryEditorsSource {
    suspend fun grants(session: ModerationSession): List<DirectoryGrant>
    suspend fun candidates(session: ModerationSession, after: DocumentSnapshot? = null): DirectoryCandidates
    suspend fun search(session: ModerationSession, query: String): List<ManagedUser>
    suspend fun change(session: ModerationSession, uid: String, expected: DirectoryGrant?, enable: Boolean)
}

/** Uses the iOS 107 grant document exactly; optimistic transactions add Android stale-state protection. */
class FirebaseDirectoryEditorsSource(context: Context, private val store: AuthStore) : DirectoryEditorsSource {
    private val db: FirebaseFirestore = AppBackend.firestore(context)
    private val auth: FirebaseAuth = AppBackend.auth(context)
    private val functions = AppBackend.callables(context)
    private val access = ModerationAccess(db, auth)

    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
    }

    private suspend fun <T> owner(session: ModerationSession, operation: suspend () -> T): T {
        if (!session.ready || session.role != "owner") throw IllegalAccessException("Owner access required")
        return store.withReadySession(session.uid, session.revision) {
            access.privileged(session)
            if (store.state.value.moderationScope() != session) throw IllegalAccessException("Owner session changed")
            operation().also {
                if (store.state.value.moderationScope() != session) throw IllegalAccessException("Owner session changed")
            }
        }
    }

    private fun user(document: DocumentSnapshot): ManagedUser =
        ManagedUsersContract.user(document.id, document.data.orEmpty().mapValues { (_, value) ->
            if (value is Timestamp) Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong()) else value
        })

    override suspend fun grants(session: ModerationSession): List<DirectoryGrant> = owner(session) {
        val snapshot = db.collection("directoryEditors").get(Source.SERVER).await()
        if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites()) throw DirectoryGrantStale()
        snapshot.documents.filter { it.getBoolean("enabled") == true }.map { grant ->
            val target = try {
                db.collection("users").document(grant.id).get(Source.SERVER).await().also {
                    if (it.metadata.isFromCache || it.metadata.hasPendingWrites()) throw DirectoryGrantStale()
                }
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                null
            }
            val profile = try {
                target?.takeIf { it.exists() }?.let(::user)
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                null
            }
            DirectoryGrant(
                uid = grant.id,
                name = profile?.displayName?.ifBlank { profile.fullName }?.ifBlank { grant.id }
                    ?: grant.id,
                grantedBy = grant.getString("grantedBy").orEmpty(),
                grantedAt = grant.getTimestamp("grantedAt"),
                email = profile?.email?.takeIf(String::isNotBlank),
                profileState = when {
                    target == null || (target.exists() && profile == null) -> DirectoryGrantProfileState.READ_FAILED
                    profile == null -> DirectoryGrantProfileState.MISSING
                    else -> DirectoryGrantProfileState.LOADED
                },
            )
        }.sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
    }

    override suspend fun candidates(session: ModerationSession, after: DocumentSnapshot?): DirectoryCandidates = owner(session) {
        var query = db.collection("users").orderBy("createdAt", Query.Direction.DESCENDING).limit(40)
        if (after != null) query = query.startAfter(after)
        val snapshot = query.get(Source.SERVER).await()
        if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites()) throw DirectoryGrantStale()
        DirectoryCandidates(snapshot.documents.map(::user), snapshot.documents.lastOrNull().takeIf { snapshot.size() == 40 })
    }

    override suspend fun search(session: ModerationSession, query: String): List<ManagedUser> = owner(session) {
        val normalized = ManagedUsersQuery.from(query).value
        val result = functions.getHttpsCallable("searchManagedUsers")
            .withTimeout(20, TimeUnit.SECONDS)
            .call(mapOf("query" to normalized, "limit" to 100)).await()
        val ids = ManagedUsersContract.searchIds(result.data).first
        val found = mutableMapOf<String, ManagedUser>()
        for (batch in ids.chunked(30)) {
            val docs = db.collection("users").whereIn(FieldPath.documentId(), batch)
                .get(Source.SERVER).await()
            if (docs.metadata.isFromCache || docs.metadata.hasPendingWrites()) throw DirectoryGrantStale()
            docs.documents.forEach { found[it.id] = user(it) }
        }
        ids.mapNotNull(found::get)
    }

    override suspend fun change(session: ModerationSession, uid: String, expected: DirectoryGrant?, enable: Boolean) = owner(session) {
        ManagedUsersContract.requireId(uid)
        if (uid == session.uid || enable == (expected != null) ||
            (expected != null && expected.uid != uid)) throw DirectoryGrantStale()
        val reference = db.collection("directoryEditors").document(uid)
        val target = db.collection("users").document(uid)
        db.runTransaction { tx ->
            val current = tx.get(reference)
            if (current.exists() != (expected != null) ||
                (expected != null && (current.getBoolean("enabled") != true ||
                    current.getTimestamp("grantedAt") != expected.grantedAt)))
                throw DirectoryGrantStale()
            if (enable) {
                val account = tx.get(target)
                val data = account.data.orEmpty()
                val accountStatus = data["accountStatus"] ?: "active"
                val blockState = data["blockState"] ?:
                    if (data["isBlocked"] == true) "suspendedUntil" else "active"
                if (!account.exists() || accountStatus !in setOf("active", "warned") ||
                    blockState !in setOf("active", "warned") || data["globalRole"] == "owner")
                    throw DirectoryGrantInvalid()
                tx.set(reference, mapOf("enabled" to true, "grantedBy" to session.uid,
                    "grantedAt" to FieldValue.serverTimestamp()))
            } else tx.delete(reference)
        }.await()
        val readback = reference.get(Source.SERVER).await()
        if (readback.metadata.isFromCache || readback.metadata.hasPendingWrites() ||
            readback.exists() != enable ||
            (enable && (readback.getBoolean("enabled") != true ||
                readback.getString("grantedBy") != session.uid ||
                readback.getTimestamp("grantedAt") == null))) throw DirectoryGrantStale()
    }
}
