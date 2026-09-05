package at.uac.android

import at.uac.android.feature.moderation.ModerationDecisionGate
import at.uac.android.feature.moderation.ModerationException
import at.uac.android.feature.moderation.ModerationFailure
import at.uac.android.feature.moderation.ModerationSession
import at.uac.android.feature.userstatusmanagement.*
import java.io.IOException
import java.time.Instant
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
class UserStatusReadFailureTest {
    private suspend fun captured(action: suspend () -> Any?): Throwable =
        runCatching { action() }.exceptionOrNull() ?: throw AssertionError("Expected failure")

    private fun failure(expected: UserStatusFailure, original: Throwable, error: Throwable) {
        assertTrue(error is UserStatusException)
        assertEquals(expected, (error as UserStatusException).failure)
        assertSame(original, error.cause)
    }

    @Test
    fun successfulReadAndListenerValuesAreUnchanged() = runTest {
        val value = Any()
        assertSame(value, userStatusReadOperation { value })
        assertEquals(listOf(1, 2), flowOf(1, 2).withUserStatusReadErrors().toList())
    }

    @Test
    fun everyAlreadyTypedFailureIsPreservedWithoutAnotherWrapper() = runTest {
        for (kind in UserStatusFailure.entries) {
            val original = UserStatusException(kind, IOException("synthetic cause"))
            assertSame(original, captured { userStatusReadOperation<Nothing> { throw original } })
            assertSame(
                original,
                captured {
                    flow<Unit> { throw original }.withUserStatusReadErrors().collect()
                },
            )
        }
    }

    @Test
    fun actualModerationErrorTypesKeepAccessAndFreshnessMeaning() = runTest {
        val mapping =
            mapOf(
                ModerationFailure.SIGN_IN to UserStatusFailure.ACCESS,
                ModerationFailure.NOT_READY to UserStatusFailure.ACCESS,
                ModerationFailure.DENIED to UserStatusFailure.ACCESS,
                ModerationFailure.STALE to UserStatusFailure.STALE,
                ModerationFailure.MISSING to UserStatusFailure.STALE,
                ModerationFailure.INVALID to UserStatusFailure.INVALID,
                ModerationFailure.OFFLINE to UserStatusFailure.OFFLINE,
            )
        mapping.forEach { (input, output) ->
            val original = ModerationException(input)
            failure(
                output,
                original,
                captured { userStatusReadOperation<Nothing> { throw original } },
            )
        }
    }

    @Test
    fun readIOExceptionIsOfflineNotAnUncertainMutation() = runTest {
        val original = IOException("synthetic read failure")
        failure(
            UserStatusFailure.OFFLINE,
            original,
            captured { userStatusReadOperation<Nothing> { throw original } },
        )
    }

    @Test
    fun externalCancellationIsNeverReclassifiedAsOffline() = runTest {
        val original = CancellationException("synthetic caller cancellation")
        assertSame(original, captured { userStatusReadOperation<Nothing> { throw original } })
        assertSame(
            original,
            captured {
                flow<Unit> { throw original }.withUserStatusReadErrors().collect()
            },
        )
    }

    @Test
    fun boundedReadTimeoutIsTypedOfflineWithItsOriginalCause() = runTest {
        val error = captured { userStatusReadOperation { withTimeout(1) { delay(2) } } }
        assertTrue(error is UserStatusException)
        assertEquals(UserStatusFailure.OFFLINE, (error as UserStatusException).failure)
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
                .withUserStatusReadErrors()
                .collect()
        }
        val received = delivered ?: throw AssertionError("Listener error never reached adapter")
        failure(UserStatusFailure.OFFLINE, received, error)
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
                .withUserStatusReadErrors()
                .collect()
        }
        assertTrue(timeout is UserStatusException)
        assertEquals(UserStatusFailure.OFFLINE, (timeout as UserStatusException).failure)
        assertTrue(timeout.cause is TimeoutCancellationException)
        val downstream = IOException("synthetic downstream failure")
        assertSame(
            downstream,
            captured {
                flowOf(Unit).withUserStatusReadErrors().collect { throw downstream }
            },
        )
    }

    @Test
    fun fatalErrorsAreNotPresentedAsOrdinaryReadFailures() = runTest {
        val original = AssertionError("synthetic invariant")
        assertSame(original, captured { userStatusReadOperation<Nothing> { throw original } })
        assertSame(
            original,
            captured {
                flow<Unit> { throw original }.withUserStatusReadErrors().collect()
            },
        )
    }

    @Test
    fun acknowledgedReceiptSurvivesNormalizedNetworkReadFailure() = runTest {
        val entry = UserStatusUnitFixture.acknowledged()
        val (repository, journal) = offlineReconcile(entry)
        assertEquals(
            UserStatusObservation.CONFIRMED_UNAVAILABLE,
            repository.reconcile(UserStatusUnitFixture.actor, entry),
        )
        assertEquals(listOf(entry), journal.entries)
        assertEquals(0, journal.writes)
        assertEquals(0, journal.clears)
    }

    @Test
    fun missingReceiptNeverGainsConfirmationFromNetworkFailure() = runTest {
        val entry = UserStatusUnitFixture.prepared().copy(phase = UserStatusPhase.DISPATCHED)
        val (repository, journal) = offlineReconcile(entry)
        val error = captured { repository.reconcile(UserStatusUnitFixture.actor, entry) }
        assertTrue(error is UserStatusException)
        assertEquals(UserStatusFailure.OFFLINE, (error as UserStatusException).failure)
        assertEquals(listOf(entry), journal.entries)
        assertEquals(0, journal.writes)
        assertEquals(0, journal.clears)
    }

    private class Journal(entry: UserStatusPending) : UserStatusJournal {
        val entries = listOf(entry)
        var writes = 0
        var clears = 0

        override suspend fun pending(uid: String) = entries

        override suspend fun put(
            uid: String,
            entry: UserStatusPending,
            expected: UserStatusPending?,
        ): UserStatusPending {
            writes++
            throw AssertionError("Read-only reconciliation must not write")
        }

        override suspend fun clear(uid: String, expected: UserStatusPending) {
            clears++
            throw AssertionError("Unavailable reconciliation must retain pending")
        }
    }

    private fun offlineReconcile(entry: UserStatusPending): Pair<UserStatusRepository, Journal> {
        val journal = Journal(entry)
        val source =
            object : UserStatusSource {
                override suspend fun read(
                    session: ModerationSession,
                    targetId: String,
                ): UserStatusSnapshot = throw AssertionError("No target preview expected")

                override fun changes(session: ModerationSession, targetId: String) =
                    emptyFlow<Unit>()

                override suspend fun send(
                    session: ModerationSession,
                    entry: UserStatusPending,
                    reason: String,
                    until: Instant?,
                    canDispatch: () -> Boolean,
                ): UserStatusReceipt =
                    throw AssertionError("Read-only reconciliation must never send")

                override suspend fun reconcile(
                    session: ModerationSession,
                    entry: UserStatusPending,
                ): UserStatusObservation = userStatusReadOperation {
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
        return UserStatusRepository(source, journal, { UserStatusUnitFixture.actor }, gate) to
            journal
    }
}
