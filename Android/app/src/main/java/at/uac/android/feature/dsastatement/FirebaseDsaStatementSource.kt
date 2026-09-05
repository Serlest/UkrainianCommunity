package at.uac.android.feature.dsastatement

import android.content.Context
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.firebase.FirebaseNetworkException
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.Source
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.tasks.await

fun localDsaStatementSource(context: Context): DsaStatementSource =
    FirebaseDsaStatementSource(
        AppBackend.firestore(context),
        AppBackend.auth(context),
        AppBackend.callables(context),
    )

/** Only the sanitized author projection. Never reads dsaCases or accepts a portal access token. */
class FirebaseDsaStatementSource(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val gateway: CallableGateway,
) : DsaStatementSource {
    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        gateway.requireBoundTo(auth)
    }

    private fun identity(session: DsaStatementSession) {
        FirebaseBackendGuard.requireSameApp(auth, db)
        gateway.requireBoundTo(auth)
        if (
            !session.ready ||
                session.revision < 0 ||
                session.backend != dsaStatementBackendBinding ||
                !DsaStatementContract.validId(session.uid, 128)
        )
            DsaStatementContract.fail(DsaStatementFailure.ACCESS)
        val user = auth.currentUser
        if (user?.uid != session.uid) throw CancellationException("Statement SDK account changed")
        if (user.isAnonymous || !user.isEmailVerified)
            DsaStatementContract.fail(DsaStatementFailure.ACCESS)
    }

    override suspend fun read(session: DsaStatementSession, reportId: String): Any? {
        val caller = currentCoroutineContext()
        try {
            caller.ensureActive()
            identity(session)
            val payload = DsaStatementContract.payload(reportId)
            val user = auth.currentUser ?: DsaStatementContract.fail(DsaStatementFailure.ACCESS)
            val profile = db.document("users/${session.uid}").get(Source.SERVER).await()
            val token = user.getIdToken(false).await()
            caller.ensureActive()
            identity(session)
            if (
                !profile.exists() ||
                    profile.metadata.isFromCache ||
                    profile.metadata.hasPendingWrites()
            )
                DsaStatementContract.fail(DsaStatementFailure.ACCESS)
            DsaStatementSdkPolicy.requireProfile(
                profile.data,
                (token.claims["firebase"] as? Map<*, *>)?.get("sign_in_second_factor"),
            )
            // Await the actual task inside AuthStore's identity gate; no coroutine timeout/detach.
            val raw =
                gateway
                    .getHttpsCallable(DsaStatementContract.CALLABLE)
                    .withTimeout(20, TimeUnit.SECONDS)
                    .call(payload)
                    .await()
                    .data
            caller.ensureActive()
            identity(session)
            DsaStatementContract.response(reportId, raw)
            return raw
        } catch (error: CancellationException) {
            throw error
        } catch (error: Exception) {
            caller.ensureActive()
            identity(session)
            DsaStatementContract.fail(dsaStatementReadFailure(error))
        }
    }
}

fun dsaStatementReadFailure(error: Throwable): DsaStatementFailure =
    when (error) {
        is DsaStatementException -> error.failure
        is IOException,
        is FirebaseNetworkException -> DsaStatementFailure.OFFLINE
        is LocalCallableException ->
            when (error.code) {
                LocalCallableFailure.NOT_FOUND -> DsaStatementFailure.MISSING
                LocalCallableFailure.PERMISSION_DENIED,
                LocalCallableFailure.UNAUTHENTICATED,
                LocalCallableFailure.FAILED_PRECONDITION -> DsaStatementFailure.ACCESS
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableFailure.DEADLINE_EXCEEDED,
                LocalCallableFailure.RESOURCE_EXHAUSTED -> DsaStatementFailure.OFFLINE
                LocalCallableFailure.INVALID_ARGUMENT,
                LocalCallableFailure.DATA_LOSS -> DsaStatementFailure.INVALID
                else -> DsaStatementFailure.UNKNOWN
            }
        is FirebaseFirestoreException ->
            // Do not put Android-backed Firestore Code into the shared generated enum table:
            // callable-only JVM error mapping must not initialize android.util.SparseArray.
            when (error.code.name) {
                "PERMISSION_DENIED",
                "UNAUTHENTICATED" -> DsaStatementFailure.ACCESS
                "UNAVAILABLE",
                "DEADLINE_EXCEEDED" -> DsaStatementFailure.OFFLINE
                else -> DsaStatementFailure.UNKNOWN
            }
        else -> DsaStatementFailure.UNKNOWN
    }
