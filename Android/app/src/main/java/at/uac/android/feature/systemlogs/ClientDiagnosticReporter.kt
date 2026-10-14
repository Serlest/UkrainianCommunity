package at.uac.android.feature.systemlogs

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import at.uac.android.feature.feedback.FeedbackFailure
import at.uac.android.feature.feedback.FeedbackSession
import com.google.firebase.auth.FirebaseAuth
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.tasks.await

/** Fixed vocabulary only. No exception text, user content, IDs, URLs, tokens or metadata. */
enum class ClientDiagnosticOperation { FEEDBACK_READ, FEEDBACK_WRITE }

object ClientDiagnosticContract {
    fun payload(operation: ClientDiagnosticOperation, failure: FeedbackFailure): Map<String, Any> {
        require(failure in setOf(FeedbackFailure.UNKNOWN, FeedbackFailure.UNCONFIRMED, FeedbackFailure.OFFLINE))
        return mapOf(
            "eventType" to "technicalError",
            "severity" to "error",
            "targetType" to "diagnostics",
            "summary" to "Technical failure in Feedback.${operation.name}",
            "moduleName" to "Feedback",
            "operationName" to operation.name,
            "errorCode" to failure.name,
            "metadata" to emptyMap<String, String>(),
        )
    }
}

fun interface ClientDiagnosticWriter {
    suspend fun write(session: FeedbackSession, operation: ClientDiagnosticOperation, failure: FeedbackFailure)
}

class FirebaseClientDiagnosticWriter(
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
    private val clock: () -> Long = System::currentTimeMillis,
) : ClientDiagnosticWriter {
    private val recent = mutableMapOf<String, Long>()
    init { functions.requireBoundTo(auth); FirebaseBackendGuard.requireAuth(auth) }

    override suspend fun write(
        session: FeedbackSession,
        operation: ClientDiagnosticOperation,
        failure: FeedbackFailure,
    ) {
        if (!session.ready || auth.currentUser?.uid != session.uid ||
            auth.currentUser?.isAnonymous != false || auth.currentUser?.isEmailVerified != true) return
        val key = "${session.uid}:${operation.name}:${failure.name}"
        val now = clock()
        synchronized(recent) {
            if (now - (recent[key] ?: 0) < 60_000) return
            recent[key] = now
            recent.entries.removeAll { now - it.value >= 60_000 }
        }
        // Diagnostics are best effort and never block the original user action or retry a write.
        functions.getHttpsCallable("writeClientDiagnostic")
            .withTimeout(15_000, TimeUnit.MILLISECONDS)
            .call(ClientDiagnosticContract.payload(operation, failure)).await()
    }
}

fun localClientDiagnosticWriter(context: Context): ClientDiagnosticWriter =
    FirebaseClientDiagnosticWriter(AppBackend.auth(context), AppBackend.callables(context))
