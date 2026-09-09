package at.uac.android.feature.push

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FirebaseFirestoreException
import com.google.firebase.firestore.SetOptions
import com.google.firebase.installations.FirebaseInstallations
import com.google.firebase.messaging.FirebaseMessaging
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.tasks.await

/** Identifier access is lazy: PushCoordinator invokes it only after both permission gates open. */
class FirebasePushTokenSource(app: FirebaseApp) : PushTokenSource {
    init {
        require(app.name == FirebaseApp.DEFAULT_APP_NAME) { "PUSH_REQUIRES_DEFAULT_FIREBASE_APP" }
    }

    private val installations = FirebaseInstallations.getInstance(app)
    private val messaging = FirebaseMessaging.getInstance()

    override val registrationType = "fid"

    override suspend fun installationId(): String = installations.id.await()

    override suspend fun token(): String {
        messaging.register().await()
        return installations.id.await()
    }

    override suspend fun unregister() {
        messaging.unregister().await()
    }
}

/** Firestore/Functions adapter for the existing, unchanged iOS-compatible registration contract. */
class FirebasePushRegistrationBackend(
    private val db: FirebaseFirestore,
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
) : PushRegistrationBackend {
    init {
        FirebaseBackendGuard.requireSameApp(auth, db)
        functions.requireBoundTo(auth)
    }

    override suspend fun upsert(capturedUid: String, registration: PushRegistration) = request {
        requireCurrent(capturedUid, requireVerified = true)
        db.document("users/$capturedUid/notificationPushTokens/${registration.documentId}")
            .set(
                mapOf(
                    "id" to registration.documentId,
                    "token" to registration.token.value(),
                    "registrationType" to registration.registrationType,
                    "platform" to registration.platform,
                    "deviceName" to registration.deviceName,
                    "appVersion" to registration.appVersion,
                    "updatedAt" to FieldValue.serverTimestamp(),
                    "createdAt" to FieldValue.serverTimestamp(),
                ),
                SetOptions.merge(),
            )
            .await()
        requireCurrent(capturedUid, requireVerified = true)
    }

    override suspend fun deleteExact(
        capturedUid: String,
        registration: PushRegistration,
    ) = request {
        requireCurrent(capturedUid, requireVerified = false)
        val result =
            functions
                .getHttpsCallable("deleteNotificationPushRegistration")
                .withTimeout(30, TimeUnit.SECONDS)
                .call(
                    mapOf(
                        "userId" to capturedUid,
                        "identifier" to registration.token.value(),
                        "registrationType" to registration.registrationType,
                    )
                )
                .await()
                .data as? Map<*, *> ?: throw PushException(PushFailure.UNKNOWN)
        val deleted = result["deletedRegistrationCount"] as? Number
        if (deleted == null || deleted.toLong() !in 0..1_000)
            throw PushException(PushFailure.UNKNOWN)
        requireCurrent(capturedUid, requireVerified = false)
    }

    private fun requireCurrent(capturedUid: String, requireVerified: Boolean) {
        val user = auth.currentUser ?: throw PushException(PushFailure.SIGN_IN)
        if (user.uid != capturedUid) throw PushException(PushFailure.CROSS_ACCOUNT)
        if (user.isAnonymous || requireVerified && !user.isEmailVerified)
            throw PushException(PushFailure.NOT_READY)
    }

    private suspend fun request(block: suspend () -> Unit) {
        try {
            block()
        } catch (error: CancellationException) {
            throw error
        } catch (error: PushException) {
            throw error
        } catch (error: FirebaseFirestoreException) {
            throw PushException(
                when (error.code) {
                    FirebaseFirestoreException.Code.PERMISSION_DENIED,
                    FirebaseFirestoreException.Code.UNAUTHENTICATED -> PushFailure.DENIED
                    FirebaseFirestoreException.Code.UNAVAILABLE,
                    FirebaseFirestoreException.Code.DEADLINE_EXCEEDED -> PushFailure.OFFLINE
                    else -> PushFailure.UNKNOWN
                },
                error,
            )
        } catch (error: LocalCallableException) {
            throw PushException(
                when (error.code) {
                    LocalCallableFailure.PERMISSION_DENIED,
                    LocalCallableFailure.UNAUTHENTICATED -> PushFailure.DENIED
                    LocalCallableFailure.UNAVAILABLE,
                    LocalCallableFailure.DEADLINE_EXCEEDED -> PushFailure.OFFLINE
                    else -> PushFailure.UNKNOWN
                },
                error,
            )
        } catch (error: Exception) {
            throw PushException(PushFailure.UNKNOWN, error)
        }
    }
}
