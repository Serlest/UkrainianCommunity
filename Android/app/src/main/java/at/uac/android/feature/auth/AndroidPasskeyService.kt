package at.uac.android.feature.auth

import android.content.Context
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.backend.CallableGateway
import com.google.firebase.auth.FirebaseAuth
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject

data class AndroidPasskey(val id: String, val createdAt: String?)

interface AuthPasskeys {
    suspend fun signInToken(context: Context): String
    suspend fun register(context: Context, uid: String)
    suspend fun list(uid: String): List<AndroidPasskey>
    suspend fun remove(uid: String, id: String)
}

/** Credential Manager transports the assertion; the server owns challenge and origin checks. */
class AndroidPasskeyService(
    private val auth: FirebaseAuth,
    private val functions: CallableGateway,
) : AuthPasskeys {
    init { functions.requireBoundTo(auth) }

    private suspend fun call(name: String, data: Any? = emptyMap<String, String>()): Map<*, *> {
        val result = try {
            withContext(NonCancellable) {
                functions.getHttpsCallable(name).withTimeout(60, TimeUnit.SECONDS)
                    .call(data).await().data
            }
        } catch (error: LocalCallableException) {
            throw AuthException(when (error.code) {
                LocalCallableFailure.UNAVAILABLE,
                LocalCallableFailure.DEADLINE_EXCEEDED -> AuthProblem.NETWORK
                LocalCallableFailure.PERMISSION_DENIED -> AuthProblem.PERMISSION_DENIED
                LocalCallableFailure.UNAUTHENTICATED -> AuthProblem.SESSION_CHANGED
                LocalCallableFailure.RESOURCE_EXHAUSTED -> AuthProblem.RATE_LIMITED
                LocalCallableFailure.FAILED_PRECONDITION -> AuthProblem.CODE_EXPIRED
                else -> AuthProblem.PROVIDER_SIGN_IN_FAILED
            })
        }
        return result as? Map<*, *> ?: throw AuthException(AuthProblem.INVALID_PROFILE)
    }

    private fun Map<*, *>.required(key: String): String =
        (this[key] as? String)?.takeIf(String::isNotBlank)
            ?: throw AuthException(AuthProblem.INVALID_PROFILE)

    private fun requireUser(uid: String) {
        val user = auth.currentUser
        if (user?.uid != uid || !user.isEmailVerified || user.isAnonymous)
            throw AuthException(AuthProblem.SESSION_CHANGED)
    }

    override suspend fun signInToken(context: Context): String {
        val begin = call("beginPasskeySignIn")
        val request = JSONObject()
            .put("challenge", begin.required("challenge"))
            .put("rpId", begin.required("rpID"))
            .put("userVerification", "required")
            .put("timeout", 300_000)
        val option = GetPublicKeyCredentialOption(request.toString())
        val credential = CredentialManager.create(context)
            .getCredential(context, GetCredentialRequest.Builder()
                .addCredentialOption(option).build()).credential as? PublicKeyCredential
            ?: throw AuthException(AuthProblem.PROVIDER_SIGN_IN_FAILED)
        val assertion = JSONObject(credential.authenticationResponseJson)
        val response = assertion.getJSONObject("response")
        val assertionFields = mutableMapOf<String, String>(
            "clientDataJSON" to response.getString("clientDataJSON"),
            "authenticatorData" to response.getString("authenticatorData"),
            "signature" to response.getString("signature"),
        )
        if (response.has("userHandle") && !response.isNull("userHandle"))
            assertionFields["userHandle"] = response.getString("userHandle")
        val payload = mapOf(
            "requestID" to begin.required("requestID"),
            "credential" to mapOf(
                "id" to assertion.getString("id"),
                "rawId" to assertion.getString("rawId"),
                "response" to assertionFields,
            ),
        )
        return call("finishPasskeySignIn", payload).required("token")
    }

    override suspend fun register(context: Context, uid: String) {
        requireUser(uid)
        val begin = call("beginPasskeyRegistration")
        requireUser(uid)
        val request = JSONObject()
            .put("challenge", begin.required("challenge"))
            .put("rp", JSONObject().put("id", begin.required("rpID"))
                .put("name", "Ukrainian Community"))
            .put("user", JSONObject().put("id", begin.required("userID"))
                .put("name", begin.required("userName"))
                .put("displayName", begin.required("userName")))
            .put("pubKeyCredParams", org.json.JSONArray()
                .put(JSONObject().put("type", "public-key").put("alg", -7)))
            .put("attestation", "none")
            .put("authenticatorSelection", JSONObject()
                .put("residentKey", "required")
                .put("userVerification", "required"))
            .put("timeout", 300_000)
        val created = CredentialManager.create(context)
            .createCredential(context, CreatePublicKeyCredentialRequest(request.toString()))
                as? CreatePublicKeyCredentialResponse
            ?: throw AuthException(AuthProblem.PROVIDER_SIGN_IN_FAILED)
        val registration = JSONObject(created.registrationResponseJson)
        val response = registration.getJSONObject("response")
        requireUser(uid)
        call("finishPasskeyRegistration", mapOf(
            "requestID" to begin.required("requestID"),
            "credential" to mapOf(
                "id" to registration.getString("id"),
                "rawId" to registration.getString("rawId"),
                "response" to mapOf(
                    "clientDataJSON" to response.getString("clientDataJSON"),
                    "attestationObject" to response.getString("attestationObject"),
                ),
            ),
        ))
        requireUser(uid)
    }

    override suspend fun list(uid: String): List<AndroidPasskey> {
        requireUser(uid)
        val result = call("listMyPasskeys")
        requireUser(uid)
        return (result["passkeys"] as? List<*>)?.map { item ->
            val record = item as? Map<*, *> ?: throw AuthException(AuthProblem.INVALID_PROFILE)
            AndroidPasskey(record.required("id"), record["createdAt"] as? String)
        } ?: throw AuthException(AuthProblem.INVALID_PROFILE)
    }

    override suspend fun remove(uid: String, id: String) {
        requireUser(uid)
        if (id.isBlank()) throw AuthException(AuthProblem.INVALID_PROFILE)
        call("removeMyPasskey", mapOf("id" to id))
        requireUser(uid)
    }
}
