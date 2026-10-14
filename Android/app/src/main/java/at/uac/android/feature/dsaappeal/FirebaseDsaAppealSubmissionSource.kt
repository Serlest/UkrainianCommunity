package at.uac.android.feature.dsaappeal

import android.content.Context
import at.uac.android.core.backend.AppBackend
import at.uac.android.core.backend.CallableGateway
import com.google.firebase.auth.FirebaseAuth
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

fun localDsaAppealSubmissionSource(context: Context): DsaAppealSubmissionSource =
    FirebaseDsaAppealSubmissionSource(AppBackend.callables(context), AppBackend.auth(context))

class FirebaseDsaAppealSubmissionSource(
    private val functions: CallableGateway,
    private val auth: FirebaseAuth,
) : DsaAppealSubmissionSource {
    init { functions.requireBoundTo(auth) }

    override suspend fun submit(session: DsaAppealSession, payload: Map<String, String>): Any? {
        functions.requireBoundTo(auth)
        if (!session.ready || session.backend != dsaAppealBackendBinding ||
            auth.currentUser?.uid != session.uid || auth.currentUser?.isEmailVerified != true)
            DsaAppealReviewContract.fail(DsaAppealReviewFailure.ACCESS)
        // The surrounding Auth gate holds identity until this SDK Task settles.
        val result = functions.getHttpsCallable("submitDsaAppeal").call(payload).await().data
        if (auth.currentUser?.uid != session.uid)
            throw CancellationException("Appeal SDK account changed")
        return result
    }
}
