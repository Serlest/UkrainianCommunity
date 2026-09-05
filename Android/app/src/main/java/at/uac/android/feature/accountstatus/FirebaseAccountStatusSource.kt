package at.uac.android.feature.accountstatus

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.firebase.Timestamp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import com.google.firebase.firestore.TransactionOptions
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

fun localAccountStatusSource(context: Context): AccountStatusSource =
    FirebaseAccountStatusSource(AppBackend.firestore(context), AppBackend.auth(context))

class FirebaseAccountStatusSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
) : AccountStatusSource {
    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
    }

    private fun identity(session: AccountStatusSession, verified: Boolean = false) {
        val user = auth.currentUser
        statusRequire(user?.uid == session.uid && !user.isAnonymous, AccountStatusFailure.STALE)
        if (verified) statusRequire(user?.isEmailVerified == true, AccountStatusFailure.DENIED)
    }

    override suspend fun read(session: AccountStatusSession): AccountStatusObservation =
        sourceFailure {
            identity(session)
            val snapshot =
                withTimeout(12_000) {
                    db.collection("users").document(session.uid).get(Source.SERVER).await()
                }
            identity(session)
            statusRequire(
                snapshot.exists() &&
                    !snapshot.metadata.isFromCache &&
                    !snapshot.metadata.hasPendingWrites(),
                AccountStatusFailure.OFFLINE,
            )
            decodeAccountStatus(session.uid, snapshot.data.orEmpty())
        }

    override suspend fun acknowledge(
        session: AccountStatusSession,
        expected: AccountStatusVersion,
        canDispatch: () -> Boolean,
        onDispatch: () -> Unit,
    ) = sourceFailure {
        identity(session, verified = true)
        statusRequire(
            session.canAcknowledge && session.uid == expected.uid && !expected.requiresSignOut,
            AccountStatusFailure.DENIED,
        )
        statusRequire(canDispatch(), AccountStatusFailure.STALE)
        val own = db.collection("users").document(session.uid)
        onDispatch()
        // Await real settlement under Auth's mutex; no coroutine timeout/detached write.
        db.runTransaction(TransactionOptions.Builder().setMaxAttempts(3).build()) { transaction ->
                val document = transaction.get(own)
                val fields =
                    document.data ?: throw AccountStatusException(AccountStatusFailure.INVALID)
                statusRequire(fields["id"] == session.uid, AccountStatusFailure.INVALID)
                val observation = decodeAccountStatus(session.uid, fields)
                statusRequire(observation.version == expected, AccountStatusFailure.STALE)
                requireAcknowledgementProfile(session, fields)
                // Recheck every retried callback: presentation/privacy/auth leases may have changed
                // after the SDK Task started, even while the Firebase identity stays serialized.
                statusRequire(canDispatch(), AccountStatusFailure.STALE)
                if (!observation.confirms(expected)) {
                    transaction.update(
                        own,
                        mapOf("statusAcknowledgedAt" to FieldValue.serverTimestamp()),
                    )
                }
                Unit
            }
            .await()
        identity(session, verified = true)
    }
}

internal fun decodeAccountStatus(uid: String, fields: Map<String, Any?>): AccountStatusObservation {
    fun text(name: String): String? {
        val value = fields[name] ?: return null
        return value as? String ?: throw AccountStatusException(AccountStatusFailure.INVALID)
    }
    fun instant(name: String): Instant? {
        val value = fields[name] ?: return null
        return when (value) {
            is Timestamp -> Instant.ofEpochSecond(value.seconds, value.nanoseconds.toLong())
            else -> throw AccountStatusException(AccountStatusFailure.INVALID)
        }
    }
    fun authority(name: String, fallback: () -> String): String =
        if (!fields.containsKey(name)) fallback()
        else fields[name] as? String ?: throw AccountStatusException(AccountStatusFailure.INVALID)
    val account = authority("accountStatus") { "active" }
    val blocked =
        authority("blockState") {
            when {
                !fields.containsKey("isBlocked") -> "active"
                fields["isBlocked"] == true -> "suspendedUntil"
                fields["isBlocked"] == false -> "active"
                else -> throw AccountStatusException(AccountStatusFailure.INVALID)
            }
        }
    statusRequire(
        account in
            setOf(
                "active",
                "warned",
                "suspendedUntil",
                "temporarilyBanned",
                "bannedPermanent",
                "permanentlyBanned",
                "deactivated",
            ),
        AccountStatusFailure.INVALID,
    )
    statusRequire(
        blocked in
            setOf(
                "active",
                "warned",
                "suspendedUntil",
                "bannedPermanent",
                "deactivated",
                "blocked",
            ),
        AccountStatusFailure.INVALID,
    )
    val updated = instant("statusUpdatedAt")
    val reason = text("statusReason")
    val message = text("statusMessage")
    val expiry = instant("banExpiresAt")
    val ack = instant("statusAcknowledgedAt")
    return AccountStatusObservation(
        updated?.let { AccountStatusVersion(uid, account, blocked, it, reason, message, expiry) },
        ack,
    )
}

internal fun requireAcknowledgementProfile(
    session: AccountStatusSession,
    fields: Map<String, Any?>,
) {
    statusRequire(fields["id"] == session.uid, AccountStatusFailure.INVALID)
    val observed = decodeAccountStatus(session.uid, fields)
    statusRequire(
        observed.version?.status in setOf("active", "warned") &&
            observed.version?.blockState in setOf("active", "warned"),
        AccountStatusFailure.DENIED,
    )
    val role = (fields["globalRole"] as? String)?.takeIf { it in setOf("owner", "admin") } ?: "user"
    statusRequire(role == session.role, AccountStatusFailure.STALE)
    if (role in setOf("owner", "admin")) {
        statusRequire(
            fields["requiresMultiFactorAuth"] == true && session.totpAuthenticated,
            AccountStatusFailure.DENIED,
        )
    }
}

private suspend fun <T> sourceFailure(action: suspend () -> T): T =
    try {
        action()
    } catch (error: CancellationException) {
        if (error is TimeoutCancellationException)
            throw AccountStatusException(AccountStatusFailure.OFFLINE, error)
        throw error
    } catch (error: Exception) {
        val known = statusFailure(error)
        if (known != AccountStatusFailure.UNKNOWN) throw AccountStatusException(known, error)
        val code =
            generateSequence<Throwable>(error) { it.cause }
                .filterIsInstance<FirebaseFirestoreException>()
                .firstOrNull()
                ?.code
        val failure =
            when (code) {
                FirebaseFirestoreException.Code.PERMISSION_DENIED,
                FirebaseFirestoreException.Code.UNAUTHENTICATED -> AccountStatusFailure.DENIED
                FirebaseFirestoreException.Code.UNAVAILABLE,
                FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> AccountStatusFailure.OFFLINE
                else -> AccountStatusFailure.UNKNOWN
            }
        throw AccountStatusException(failure, error)
    }
