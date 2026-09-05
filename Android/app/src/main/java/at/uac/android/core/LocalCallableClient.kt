package at.uac.android.core

import at.uac.android.core.backend.CallableCall
import at.uac.android.core.backend.CallableGateway
import at.uac.android.core.backend.FirebaseBackendGuard
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.TaskCompletionSource
import com.google.firebase.auth.FirebaseAuth
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InterruptedIOException
import java.net.Proxy
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import okhttp3.ConnectionPool
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okio.BufferedSink
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener

/**
 * Local onCall protocol only. No cloud URL/config, App Check bypass, FIS/IID, redirects, automatic
 * retries or logging. Firebase Auth and Firestore remain the real Android SDKs.
 */
class LocalCallableClient internal constructor(private val auth: FirebaseAuth) : CallableGateway {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val http =
        OkHttpClient.Builder()
            .proxy(Proxy.NO_PROXY)
            .retryOnConnectionFailure(false)
            .followRedirects(false)
            .followSslRedirects(false)
            // Local emulator closes idle sockets after ~6s; OkHttp probes only after 10s. Never
            // reuse that stale socket or replay a mutation.
            .connectionPool(ConnectionPool(0, 1, TimeUnit.SECONDS))
            .connectTimeout(10, TimeUnit.SECONDS)
            .build()

    init {
        LocalEnvironment.requireSafe()
        FirebaseBackendGuard.requireAuth(auth)
    }

    override fun requireBoundTo(auth: FirebaseAuth) {
        FirebaseBackendGuard.requireAuth(this.auth)
        FirebaseBackendGuard.requireAuth(auth)
        require(this.auth === auth && this.auth.app === auth.app) { "LOCAL_CALLABLE_AUTH_BINDING" }
    }

    override fun getHttpsCallable(name: String): LocalCallableReference {
        LocalCallableProtocol.endpoint(name)
        return LocalCallableReference(this, name, 20_000)
    }

    internal fun call(name: String, data: Any?, timeoutMillis: Long): Task<LocalCallableResult> {
        FirebaseBackendGuard.requireAuth(auth)
        val endpoint = LocalCallableProtocol.endpoint(name)
        val completion = TaskCompletionSource<LocalCallableResult>()
        val bytes =
            try {
                JSONObject(LocalCallableProtocol.request(name, data))
                    .toString()
                    .toByteArray(Charsets.UTF_8)
                    .also {
                        if (it.size > LocalCallableProtocol.maximumRequestBytes(name))
                            throw LocalCallableException(LocalCallableFailure.INVALID_ARGUMENT)
                    }
            } catch (error: Exception) {
                completion.setException(error)
                return completion.task
            }
        val capturedUser = auth.currentUser
        scope.launch {
            val requestStarted = AtomicBoolean(false)
            try {
                // Token lookup is also awaited to completion. The shared Auth mutex owns identity.
                val token = capturedUser?.getIdToken(false)?.await()?.token
                if (auth.currentUser?.uid != capturedUser?.uid)
                    throw LocalCallableException(LocalCallableFailure.UNAUTHENTICATED)
                if (capturedUser != null && token.isNullOrBlank())
                    throw LocalCallableException(LocalCallableFailure.UNAUTHENTICATED)
                val body =
                    object : RequestBody() {
                        override fun contentType() = "application/json; charset=utf-8".toMediaType()

                        override fun contentLength() = bytes.size.toLong()

                        override fun isOneShot() = true

                        override fun writeTo(sink: BufferedSink) {
                            requestStarted.set(true)
                            sink.write(bytes)
                        }
                    }
                val request =
                    Request.Builder()
                        .url(endpoint)
                        .post(body)
                        .apply {
                            token?.let { header("Authorization", "Bearer $it") }
                        }
                        .build()
                val client =
                    http
                        .newBuilder()
                        .callTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
                        .readTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
                        .writeTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
                        .build()
                val result =
                    client.newCall(request).execute().use { response ->
                        if (response.isRedirect)
                            throw LocalCallableException(LocalCallableFailure.INTERNAL)
                        val responseBody =
                            response.body
                                ?: throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
                        if (responseBody.contentLength() > LocalCallableProtocol.MAX_RESPONSE_BYTES)
                            throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
                        val output = ByteArrayOutputStream()
                        responseBody.byteStream().use { stream ->
                            val buffer = ByteArray(4_096)
                            while (true) {
                                val count = stream.read(buffer)
                                if (count < 0) break
                                if (
                                    output.size() + count > LocalCallableProtocol.MAX_RESPONSE_BYTES
                                )
                                    throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
                                output.write(buffer, 0, count)
                            }
                        }
                        val decoded =
                            try {
                                val text =
                                    Charsets.UTF_8.newDecoder()
                                        .onMalformedInput(CodingErrorAction.REPORT)
                                        .onUnmappableCharacter(CodingErrorAction.REPORT)
                                        .decode(ByteBuffer.wrap(output.toByteArray()))
                                        .toString()
                                LocalCallableProtocol.validateRawResponse(text)
                                val tokener = JSONTokener(text)
                                val json =
                                    tokener.nextValue() as? JSONObject
                                        ?: throw LocalCallableException(
                                            LocalCallableFailure.DATA_LOSS
                                        )
                                if (tokener.nextClean() != '\u0000')
                                    throw LocalCallableException(LocalCallableFailure.DATA_LOSS)
                                jsonFields(json)
                            } catch (error: LocalCallableException) {
                                throw error
                            } catch (error: Exception) {
                                throw LocalCallableException(
                                    LocalCallableFailure.DATA_LOSS,
                                    cause = error,
                                )
                            }
                        LocalCallableProtocol.response(response.code, decoded)
                    }
                completion.setResult(result)
            } catch (error: Exception) {
                val failure =
                    when (error) {
                        is LocalCallableException -> error.code
                        is InterruptedIOException -> LocalCallableFailure.DEADLINE_EXCEEDED
                        is IOException -> LocalCallableFailure.UNAVAILABLE
                        else -> LocalCallableFailure.UNKNOWN
                    }
                completion.setException(
                    LocalCallableException(
                        LocalCallableProtocol.transportFailure(name, requestStarted.get(), failure),
                        (error as? LocalCallableException)?.details,
                        error,
                    )
                )
            }
        }
        return completion.task
    }

    private fun jsonFields(value: JSONObject): Map<String, Any?> =
        value.keys().asSequence().associateWith { jsonValue(value.get(it)) }

    private fun jsonValue(value: Any?): Any? =
        when {
            value == JSONObject.NULL -> null
            value is JSONObject -> jsonFields(value)
            value is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
            else -> value
        }
}

class LocalCallableReference
internal constructor(
    private val client: LocalCallableClient,
    private val name: String,
    private val timeoutMillis: Long,
) : CallableCall {
    override fun withTimeout(timeout: Long, units: TimeUnit): LocalCallableReference {
        val millis = units.toMillis(timeout)
        require(millis in 100..LocalCallableProtocol.maximumTimeoutMillis(name))
        return LocalCallableReference(client, name, millis)
    }

    /**
     * Completion means the whole transport finished, including reads/errors. Never detach this task
     * from a mutation gate.
     */
    override fun call(data: Any?): Task<LocalCallableResult> =
        client.call(name, data, timeoutMillis)
}
