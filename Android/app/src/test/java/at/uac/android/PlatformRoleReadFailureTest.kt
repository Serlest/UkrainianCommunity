package at.uac.android

import at.uac.android.core.LocalCallableException
import at.uac.android.core.LocalCallableFailure
import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationException
import at.uac.android.feature.moderation.ModerationFailure
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.platformrolemanagement.*
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

/** Real error-boundary code with pure inputs; no Firebase dispatch or privileged SDK/TOTP proof. */
@OptIn(ExperimentalCoroutinesApi::class)
class PlatformRoleReadFailureTest {
    @Test
    fun metadataTransportFailuresKeepReadOnlyMeaningAndUnknownMutationRemainsUnknown() = runTest {
        for ((input, output) in
            mapOf(
                LocalCallableFailure.PERMISSION_DENIED to PlatformRoleFailure.ACCESS,
                LocalCallableFailure.UNAUTHENTICATED to PlatformRoleFailure.ACCESS,
                LocalCallableFailure.UNAVAILABLE to PlatformRoleFailure.OFFLINE,
                LocalCallableFailure.DEADLINE_EXCEEDED to PlatformRoleFailure.OFFLINE,
                LocalCallableFailure.NOT_FOUND to PlatformRoleFailure.STALE,
                LocalCallableFailure.FAILED_PRECONDITION to PlatformRoleFailure.STALE,
                LocalCallableFailure.INVALID_ARGUMENT to PlatformRoleFailure.INVALID,
                LocalCallableFailure.UNCONFIRMED to PlatformRoleFailure.UNCONFIRMED,
            )) {
            val error = LocalCallableException(input)
            failure(output, error, captured { platformRoleReadOperation<Nothing> { throw error } })
        }
    }

    private suspend fun captured(action: suspend () -> Any?): Throwable =
        runCatching { action() }.exceptionOrNull() ?: throw AssertionError("Expected failure")

    private fun failure(expected: PlatformRoleFailure, original: Throwable, error: Throwable) {
        assertTrue(error is PlatformRoleException)
        assertEquals(expected, (error as PlatformRoleException).failure)
        assertSame(original, error.cause)
    }

    @Test
    fun successfulReadAndListenerValuesAreUnchanged() = runTest {
        val value = Any()
        assertSame(value, platformRoleReadOperation { value })
        assertEquals(listOf(1, 2), flowOf(1, 2).withPlatformRoleReadErrors().toList())
    }

    @Test
    fun everyAlreadyTypedFailureIsPreservedWithoutAnotherWrapper() = runTest {
        for (kind in PlatformRoleFailure.entries) {
            val original = PlatformRoleException(kind, IOException("synthetic cause"))
            assertSame(original, captured { platformRoleReadOperation<Nothing> { throw original } })
            assertSame(
                original,
                captured {
                    flow<Unit> { throw original }.withPlatformRoleReadErrors().collect()
                },
            )
        }
    }

    @Test
    fun actualModerationErrorTypesKeepAccessAndFreshnessMeaning() = runTest {
        val mapping =
            mapOf(
                ModerationFailure.SIGN_IN to PlatformRoleFailure.ACCESS,
                ModerationFailure.NOT_READY to PlatformRoleFailure.ACCESS,
                ModerationFailure.DENIED to PlatformRoleFailure.ACCESS,
                ModerationFailure.STALE to PlatformRoleFailure.STALE,
                ModerationFailure.MISSING to PlatformRoleFailure.STALE,
                ModerationFailure.INVALID to PlatformRoleFailure.INVALID,
                ModerationFailure.OFFLINE to PlatformRoleFailure.OFFLINE,
            )
        mapping.forEach { (input, output) ->
            val original = ModerationException(input)
            failure(
                output,
                original,
                captured { platformRoleReadOperation<Nothing> { throw original } },
            )
        }
    }

    @Test
    fun readIOExceptionIsOfflineNotAnUncertainMutation() = runTest {
        val original = IOException("synthetic read failure")
        failure(
            PlatformRoleFailure.OFFLINE,
            original,
            captured { platformRoleReadOperation<Nothing> { throw original } },
        )
    }

    @Test
    fun externalCancellationIsNeverReclassifiedAsOffline() = runTest {
        val original = CancellationException("synthetic caller cancellation")
        assertSame(original, captured { platformRoleReadOperation<Nothing> { throw original } })
        assertSame(
            original,
            captured {
                flow<Unit> { throw original }.withPlatformRoleReadErrors().collect()
            },
        )
    }

    @Test
    fun boundedReadTimeoutIsTypedOfflineWithItsOriginalCause() = runTest {
        val error = captured { platformRoleReadOperation { withTimeout(1) { delay(2) } } }
        assertTrue(error is PlatformRoleException)
        assertEquals(PlatformRoleFailure.OFFLINE, (error as PlatformRoleException).failure)
        assertTrue(error.cause is TimeoutCancellationException)
    }

    @Test
    fun asynchronousListenerCloseIsNormalizedAndItsCleanupStillRuns() = runTest {
        val original = IOException("synthetic listener failure")
        var delivered: Throwable? = null
        var cleaned = false
        val error = captured {
            callbackFlow<Unit> {
                    close(original)
                    awaitClose { cleaned = true }
                }
                .catch { upstream ->
                    delivered = upstream
                    throw upstream
                }
                .withPlatformRoleReadErrors()
                .collect()
        }
        val received = delivered ?: throw AssertionError("Listener error never reached adapter")
        failure(PlatformRoleFailure.OFFLINE, received, error)
        // Coroutines 1.10.2 may recover channel stack traces by copying the exception and
        // retaining its exact original as cause. The adapter must preserve the RECEIVED object.
        // https://github.com/Kotlin/kotlinx.coroutines/blob/1.10.2/kotlinx-coroutines-core/jvm/src/Debug.kt
        if (received !== original) {
            assertEquals(original.javaClass, received.javaClass)
            assertEquals(original.message, received.message)
            assertTrue(received.stackTrace.any { it.className.startsWith("_COROUTINE.") })
            assertSame(original, received.cause)
        }
        assertTrue(cleaned)
    }

    @Test
    fun listenerTimeoutIsOfflineButCollectorFailureIsNotRewritten() = runTest {
        val timeout = captured {
            flow<Unit> {
                    withTimeout(1) {
                        delay(2)
                        emit(Unit)
                    }
                }
                .withPlatformRoleReadErrors()
                .collect()
        }
        assertTrue(timeout is PlatformRoleException)
        assertEquals(PlatformRoleFailure.OFFLINE, (timeout as PlatformRoleException).failure)
        assertTrue(timeout.cause is TimeoutCancellationException)
        val downstream = IOException("synthetic downstream failure")
        assertSame(
            downstream,
            captured {
                flowOf(Unit).withPlatformRoleReadErrors().collect { throw downstream }
            },
        )
    }

    @Test
    fun fatalErrorsAreNotPresentedAsOrdinaryReadFailures() = runTest {
        val original = AssertionError("synthetic invariant")
        assertSame(original, captured { platformRoleReadOperation<Nothing> { throw original } })
        assertSame(
            original,
            captured {
                flow<Unit> { throw original }.withPlatformRoleReadErrors().collect()
            },
        )
    }

    @Test
    fun acknowledgedReceiptSurvivesNormalizedNetworkReadFailure() = runTest {
        val entry = PlatformRoleUnitFixture.acknowledged()
        val (repository, journal) = offlineReconcile(entry)
        assertEquals(
            PlatformRoleObservation.CONFIRMED_UNAVAILABLE,
            repository.reconcile(PlatformRoleUnitFixture.actor, entry),
        )
        assertEquals(listOf(entry), journal.entries)
        assertEquals(0, journal.writes)
        assertEquals(0, journal.clears)
    }

    @Test
    fun missingReceiptNeverGainsConfirmationFromNetworkFailure() = runTest {
        val entry = PlatformRoleUnitFixture.prepared().copy(phase = PlatformRolePhase.DISPATCHED)
        val (repository, journal) = offlineReconcile(entry)
        val error = captured { repository.reconcile(PlatformRoleUnitFixture.actor, entry) }
        assertTrue(error is PlatformRoleException)
        assertEquals(PlatformRoleFailure.OFFLINE, (error as PlatformRoleException).failure)
        assertEquals(listOf(entry), journal.entries)
        assertEquals(0, journal.writes)
        assertEquals(0, journal.clears)
    }

    private class Journal(entry: PlatformRolePending) : PlatformRoleJournal {
        val entries = listOf(entry)
        var writes = 0
        var clears = 0

        override suspend fun pending(uid: String) = entries

        override suspend fun put(
            uid: String,
            entry: PlatformRolePending,
            expected: PlatformRolePending?,
        ): PlatformRolePending {
            writes++
            throw AssertionError("Read-only reconciliation must not write")
        }

        override suspend fun clear(uid: String, expected: PlatformRolePending) {
            clears++
            throw AssertionError("Unavailable reconciliation must retain pending")
        }
    }

    private fun offlineReconcile(
        entry: PlatformRolePending
    ): Pair<PlatformRoleRepository, Journal> {
        val journal = Journal(entry)
        val source =
            object : PlatformRoleSource {
                override suspend fun read(
                    session: ModerationSession,
                    targetId: String,
                ): PlatformRoleSnapshot = throw AssertionError("No target preview expected")

                override suspend fun targetAuth(
                    session: ModerationSession,
                    targetId: String,
                ): PlatformRoleTargetAuth =
                    throw AssertionError("Read-only reconciliation must never request target Auth")

                override fun changes(session: ModerationSession, targetId: String) =
                    emptyFlow<Unit>()

                override suspend fun send(
                    session: ModerationSession,
                    entry: PlatformRolePending,
                    reason: String,
                    canDispatch: () -> Boolean,
                ): PlatformRoleReceipt =
                    throw AssertionError("Read-only reconciliation must never send")

                override suspend fun reconcile(
                    session: ModerationSession,
                    entry: PlatformRolePending,
                ): PlatformRoleObservation = platformRoleReadOperation {
                    throw IOException("synthetic unavailable readback")
                }
            }
        val gate =
            object : ModerationDecisionGate {
                override suspend fun <T> withSession(
                    session: ModerationSession,
                    action: suspend () -> T,
                ): T = action()
            }
        return PlatformRoleRepository(source, journal, { PlatformRoleUnitFixture.actor }, gate) to
            journal
    }
}
