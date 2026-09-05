package at.uac.android

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableResult
import at.uac.android.core.LocalFirebase
import at.uac.android.core.LocalFunctions
import at.uac.android.core.backend.CallableCall
import at.uac.android.core.backend.CallableGateway
import at.uac.android.feature.auth.*
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.TaskCompletionSource
import com.google.firebase.FirebaseApp
import com.google.firebase.auth.FirebaseAuth
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Controlled Tasks are explicit doubles, not evidence of a completed network mutation. */
@RunWith(AndroidJUnit4::class)
class CallableGatewayDeviceTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun requireLocalEmulator() {
        check(context.packageName == "at.uac.android.local")
        check(Build.HARDWARE in setOf("ranchu", "goldfish") && Build.MODEL.startsWith("sdk_gphone"))
    }

    @Test
    fun actualLocalGatewayKeepsBoundAuthAndFluentPolicyWithoutDispatch() {
        requireLocalEmulator()
        val auth = LocalFirebase.auth(context)
        val gateway: CallableGateway = LocalFunctions.instance(context)
        gateway.requireBoundTo(auth)
        val reference: CallableCall = gateway.getHttpsCallable("saveComment")
        assertNotSame(reference, reference.withTimeout(20, TimeUnit.SECONDS))
        assertThrows(IllegalArgumentException::class.java) {
            reference.withTimeout(60_001, TimeUnit.MILLISECONDS)
        }
        assertThrows(IllegalArgumentException::class.java) {
            gateway.getHttpsCallable("trackAnalyticsEvent")
        }
        gateway
            .getHttpsCallable("uploadOrganizationContentCover")
            .withTimeout(120, TimeUnit.SECONDS)
        gateway.getHttpsCallable("deleteOwnAccount").withTimeout(300, TimeUnit.SECONDS)
        gateway
            .getHttpsCallable("createOrganizationPhotoMetadata")
            .withTimeout(60, TimeUnit.SECONDS)
        gateway
            .getHttpsCallable("deleteOrganizationPhotoMetadata")
            .withTimeout(60, TimeUnit.SECONDS)
        assertTrue(FirebaseApp.getApps(context).none { it.name == FirebaseApp.DEFAULT_APP_NAME })
    }

    @Test
    fun cancelledConsumerKeepsAuthGateUntilActualTaskSuccess() =
        cancellationWaitsForTask(fails = false)

    @Test
    fun cancelledConsumerKeepsAuthGateUntilActualTaskFailure() =
        cancellationWaitsForTask(fails = true)

    private fun cancellationWaitsForTask(fails: Boolean) = runBlocking {
        withTimeout(10_000) {
            requireLocalEmulator()
            val sdkAuth =
                LocalFirebase.auth(
                    context
                ) // Only used for the double's explicit binding; never signs in/out.
            val completion = TaskCompletionSource<LocalCallableResult>()
            val gateway: CallableGateway = ControlledGateway(sdkAuth, completion.task)
            gateway.requireBoundTo(sdkAuth)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
            val backend = MemoryBackend()
            val store = AuthStore(backend, MemoryProfiles(), scope)
            val started = CompletableDeferred<Unit>()
            val completionOwner = AtomicReference<String?>()
            val delivered = AtomicBoolean(false)
            val failure = AtomicReference<Throwable?>()
            try {
                store.restore().join()
                assertTrue(store.state.value.readyForActions)
                val captured = store.state.value
                val consumer = scope.async {
                    store.withReadySession("gateway-a", captured.revision) {
                        val task =
                            gateway
                                .getHttpsCallable("saveComment")
                                .withTimeout(20, TimeUnit.SECONDS)
                                .call(mapOf("synthetic" to true))
                        assertSame(completion.task, task)
                        started.complete(Unit)
                        try {
                            task.await()
                        } finally {
                            completionOwner.set(backend.current?.uid)
                        }
                    }
                    delivered.set(true)
                }
                consumer.invokeOnCompletion { failure.set(it) }
                started.await()
                val next =
                    withContext(Dispatchers.Main.immediate) {
                        consumer.cancel()
                        store.signIn("gateway-b@example.invalid", "synthetic-password")!!.also {
                            assertFalse(consumer.isCompleted)
                            assertFalse(it.isCompleted)
                            assertFalse(completion.task.isComplete)
                            assertEquals("gateway-a", backend.current?.uid)
                            assertNull(completionOwner.get())
                        }
                    }
                if (fails)
                    completion.setException(
                        LocalCallableException(LocalCallableFailure.UNCONFIRMED)
                    )
                else completion.setResult(LocalCallableResult(mapOf("synthetic" to true)))
                consumer.join()
                next.join()
                assertEquals("gateway-a", completionOwner.get())
                assertTrue(consumer.isCancelled)
                assertTrue(failure.get() is CancellationException)
                assertFalse(delivered.get())
                assertEquals("gateway-b", backend.current?.uid)
                assertEquals("gateway-b", store.state.value.identity?.uid)
                assertTrue(store.state.value.readyForActions)
            } finally {
                // A failing assertion must not leave an uncompleted task holding this private test
                // store.
                completion.trySetException(LocalCallableException(LocalCallableFailure.CANCELLED))
                scope.cancel()
                withContext(NonCancellable) {
                    withTimeout(3_000) { scope.coroutineContext[Job]?.join() }
                }
            }
        }
    }

    private class ControlledGateway(
        private val auth: FirebaseAuth,
        private val task: Task<LocalCallableResult>,
    ) : CallableGateway {
        override fun requireBoundTo(auth: FirebaseAuth) {
            require(this.auth === auth)
        }

        override fun getHttpsCallable(name: String): CallableCall {
            require(name == "saveComment")
            return object : CallableCall {
                override fun withTimeout(timeout: Long, units: TimeUnit): CallableCall {
                    require(units.toMillis(timeout) == 20_000L)
                    return this
                }

                override fun call(data: Any?): Task<LocalCallableResult> = task
            }
        }
    }

    private class MemoryBackend : AuthBackend {
        override var current: AuthIdentity? = identity("gateway-a")

        override suspend fun signIn(email: String, password: String) =
            identity(email.substringBefore('@')).also { current = it }

        override suspend fun reload() = checkNotNull(current)

        override suspend fun refreshToken() = false

        override suspend fun signOut() {
            current = null
        }

        override suspend fun create(
            email: String,
            password: String,
            displayName: String,
        ): AuthIdentity = error("Not used")

        override suspend fun deleteCreatedUser(uid: String) = error("Not used")

        override suspend fun sendVerification(language: String) = error("Not used")

        override suspend fun sendPasswordReset(email: String, language: String) = error("Not used")

        override suspend fun verifyEmailCode(code: String) = error("Not used")

        override suspend fun resetPasswordCode(code: String, password: String) = error("Not used")
    }

    private class MemoryProfiles : AuthProfiles {
        override suspend fun create(uid: String, draft: AuthRegistration) = error("Not used")

        override suspend fun fetch(uid: String) =
            AuthProfile(
                uid,
                "$uid@example.invalid",
                "Synthetic",
                region = "wien",
                acceptedTermsVersion = AuthRegistration.TERMS_VERSION,
                acceptedPrivacyVersion = AuthRegistration.PRIVACY_VERSION,
            )

        override suspend fun legalDocuments() =
            listOf(
                AuthLegalDocument(
                    "terms",
                    AuthRegistration.TERMS_VERSION,
                    true,
                    emptyMap(),
                    emptyMap(),
                ),
                AuthLegalDocument(
                    "privacy",
                    AuthRegistration.PRIVACY_VERSION,
                    true,
                    emptyMap(),
                    emptyMap(),
                ),
            )

        override suspend fun ensurePublicProfile(profile: AuthProfile) = Unit

        override fun observe(uid: String) = emptyFlow<Result<AuthProfile>>()
    }

    companion object {
        private fun identity(uid: String) = AuthIdentity(uid, "$uid@example.invalid", true)
    }
}
