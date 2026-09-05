package at.uac.android

import at.uac.android.core.LocalCallableClient
import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.core.LocalCallableProtocol
import at.uac.android.core.LocalCallableReference
import at.uac.android.core.LocalCallableResult
import at.uac.android.core.backend.CallableCall
import at.uac.android.core.backend.CallableGateway
import com.google.android.gms.tasks.Task
import com.google.firebase.auth.FirebaseAuth
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test

/** Recording contract double only; actual Task completion is checked on Android. */
class CallableGatewayTest {
    private class Dispatched : RuntimeException()

    private class RecordingGateway : CallableGateway {
        var dispatches = 0
        var payload: Any? = null
        var deadline: Long? = null
        val failure = Dispatched()

        override fun requireBoundTo(auth: FirebaseAuth) =
            error("Actual SDK binding is tested on Android")

        override fun getHttpsCallable(name: String): CallableCall {
            LocalCallableProtocol.endpoint(name)
            return Reference(this, name, 20_000)
        }

        class Reference(
            private val gateway: RecordingGateway,
            private val name: String,
            val timeout: Long,
        ) : CallableCall {
            override fun withTimeout(timeout: Long, units: TimeUnit): CallableCall {
                val millis = units.toMillis(timeout)
                require(millis in 100..LocalCallableProtocol.maximumTimeoutMillis(name))
                return Reference(gateway, name, millis)
            }

            override fun call(data: Any?): Task<LocalCallableResult> {
                gateway.dispatches++
                gateway.payload = data
                gateway.deadline = timeout
                throw gateway
                    .failure // No Android Task mock/class initialization in this JVM double.
            }
        }
    }

    @Test
    fun localClassesDirectlyImplementTheSeamWithoutADecorator() {
        assertTrue(CallableGateway::class.java.isAssignableFrom(LocalCallableClient::class.java))
        assertTrue(CallableCall::class.java.isAssignableFrom(LocalCallableReference::class.java))
    }

    @Test
    fun referenceAndTimeoutSelectionDoNotDispatch() {
        val recording = RecordingGateway()
        val gateway: CallableGateway = recording
        gateway.getHttpsCallable("saveComment").withTimeout(19, TimeUnit.SECONDS)
        assertEquals(0, recording.dispatches)
        assertNull(recording.deadline)
    }

    @Test
    fun timeoutSelectionCreatesAnIndependentImmutableReference() {
        val recording = RecordingGateway()
        val original = recording.getHttpsCallable("saveComment")
        val changed = original.withTimeout(12, TimeUnit.SECONDS)
        assertNotSame(original, changed)
        assertThrows(Dispatched::class.java) { original.call() }
        assertEquals(20_000L, recording.deadline)
        assertThrows(Dispatched::class.java) { changed.call() }
        assertEquals(12_000L, recording.deadline)
    }

    @Test
    fun inheritedDefaultPayloadIsNullAndDispatchIsNotRetried() {
        val recording = RecordingGateway()
        val failure =
            assertThrows(Dispatched::class.java) {
                recording.getHttpsCallable("getBlockedOrganizations").call()
            }
        assertSame(recording.failure, failure)
        assertEquals(1, recording.dispatches)
        assertNull(recording.payload)
    }

    @Test
    fun interfaceDoesNotCopyOrRewriteThePayload() {
        val recording = RecordingGateway()
        val payload = mapOf("contentId" to "synthetic", "version" to Long.MAX_VALUE)
        assertThrows(Dispatched::class.java) {
            recording.getHttpsCallable("saveComment").call(payload)
        }
        assertSame(payload, recording.payload)
        assertEquals(Long.MAX_VALUE, (recording.payload as Map<*, *>)["version"])
    }

    @Test
    fun referencePolicyStillRejectsUnknownCallsAndWrongDeadline() {
        val recording = RecordingGateway()
        assertThrows(IllegalArgumentException::class.java) {
            recording.getHttpsCallable("trackAnalyticsEvent")
        }
        val reference = recording.getHttpsCallable("saveComment")
        assertThrows(IllegalArgumentException::class.java) {
            reference.withTimeout(99, TimeUnit.MILLISECONDS)
        }
        assertThrows(IllegalArgumentException::class.java) {
            reference.withTimeout(60_001, TimeUnit.MILLISECONDS)
        }
        assertEquals(0, recording.dispatches)
    }

    @Test
    fun extendedAndReadOnlyDeadlinesKeepTheExistingCallShape() {
        val recording = RecordingGateway()
        for ((name, seconds) in
            mapOf(
                "deleteOwnAccount" to 300L,
                "uploadOrganizationContentCover" to 120L,
                "createOrganizationPhotoMetadata" to 60L,
                "deleteOrganizationPhotoMetadata" to 60L,
                "getBlockedOrganizations" to 6L,
            )) {
            assertThrows(Dispatched::class.java) {
                recording.getHttpsCallable(name).withTimeout(seconds, TimeUnit.SECONDS).call()
            }
            assertEquals(seconds * 1_000, recording.deadline)
        }
        assertEquals(5, recording.dispatches)
    }

    @Test
    fun historicalResultAndFailureRuntimeClassesRemainCompatible() {
        val details = mapOf("safe" to true)
        val cause = IllegalStateException()
        val error = LocalCallableException(LocalCallableFailure.UNCONFIRMED, details, cause)
        assertEquals("LocalCallableException", error.javaClass.simpleName)
        assertEquals("UNCONFIRMED", error.message)
        assertSame(details, error.details)
        assertSame(cause, error.cause)
        val result = LocalCallableResult(details)
        assertEquals("LocalCallableResult", result.javaClass.simpleName)
        assertSame(details, result.data)
    }
}
