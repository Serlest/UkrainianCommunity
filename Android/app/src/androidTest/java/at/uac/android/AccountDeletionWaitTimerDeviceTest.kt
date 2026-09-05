package at.uac.android

import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import at.uac.android.core.LocalEnvironment
import at.uac.android.feature.accountdeletion.AccountDeletionException
import at.uac.android.feature.accountdeletion.AccountDeletionFailure
import at.uac.android.feature.accountdeletion.AccountDeletionFreshnessReason
import at.uac.android.feature.accountdeletion.AccountDeletionFreshnessStage
import at.uac.android.feature.accountdeletion.AccountDeletionFreshnessWait
import java.time.Instant
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Actual default Android elapsed-realtime/delay bridge only. The future instant is synthetic; there
 * is no Firebase authentication, account, repository, journal or destructive request here. These
 * tests neither change system time nor claim a real authentication proof.
 */
@RunWith(AndroidJUnit4::class)
class AccountDeletionWaitTimerDeviceTest {
    private fun requireExplicitLocalAvd() {
        assumeTrue(
            "Explicit local timer instrumentation opt-in required",
            InstrumentationRegistry.getArguments().getString("expectLocalDeletionTimer") == "true",
        )
        LocalEnvironment.requireSafe()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        check(instrumentation.targetContext.packageName == "at.uac.android.local")
        fun property(name: String): String =
            ParcelFileDescriptor.AutoCloseInputStream(
                    instrumentation.uiAutomation.executeShellCommand("getprop $name")
                )
                .bufferedReader()
                .use { it.readLine()?.trim().orEmpty() }
        val modern =
            Build.VERSION.SDK_INT == 37 &&
                Build.HARDWARE == "ranchu" &&
                Build.MODEL.startsWith("sdk_gphone") &&
                property("ro.kernel.qemu") == "1" &&
                property("ro.boot.qemu.avd_name") == "UAC_API_37_Play_ARM64"
        check(modern || isExplicitApi26CompatibilityAvd()) {
            "Native timer tests require an exact opted-in disposable UAC AVD."
        }
    }

    @Test
    fun defaultAndroidTimerAcceptsOnlyCaughtUpSyntheticInstantOrExplicitlyDeniesOversleep() =
        runBlocking {
            requireExplicitLocalAvd()
            withTimeout(OUTER_TEST_LIMIT_MILLIS) {
                val originalCaller = currentCoroutineContext()
                val checks = AtomicInteger()
                val started = SystemClock.elapsedRealtimeNanos()
                val initialNow = Instant.now()
                val syntheticTarget = initialNow.plusMillis(107)
                try {
                    val returned =
                        AccountDeletionFreshnessWait().sampledNow(
                            syntheticTarget,
                            initialNow,
                            Instant::now,
                        ) {
                            originalCaller.ensureActive()
                            checks.incrementAndGet()
                        }
                    val elapsedMillis = (SystemClock.elapsedRealtimeNanos() - started) / 1_000_000
                    val strictFresh =
                        !syntheticTarget.isAfter(returned) &&
                            syntheticTarget.plusSeconds(240).isAfter(returned)
                    System.out.println(
                        "NATIVE_DELETION_TIMER outcome=CAUGHT_UP elapsedMillis=$elapsedMillis " +
                            "checks=${checks.get()} strictFresh=$strictFresh"
                    )
                    assertTrue(
                        "Returned sample must pass the unchanged strict time predicate",
                        strictFresh,
                    )
                    assertTrue(
                        "The default helper must have entered its actual polling path",
                        checks.get() >= 3,
                    )
                    // The product enforces <=2s internally. This external observer may itself be
                    // scheduled later; the extra 1s is a test observation tolerance, not a guard.
                    assertTrue(
                        "Observed completion exceeded bounded scheduler tolerance",
                        elapsedMillis in 0..(2000 + OBSERVER_TOLERANCE_MILLIS),
                    )
                } catch (error: AccountDeletionException) {
                    val elapsedMillis = (SystemClock.elapsedRealtimeNanos() - started) / 1_000_000
                    System.out.println(
                        "NATIVE_DELETION_TIMER outcome=EXPLICIT_DEADLINE_DENIAL " +
                            "elapsedMillis=$elapsedMillis checks=${checks.get()}"
                    )
                    assertEquals(AccountDeletionFailure.RECENT_AUTH_REQUIRED, error.failure)
                    assertEquals(
                        AccountDeletionFreshnessStage.FIRST_CLOCK_CHECK,
                        error.freshnessDiagnostic?.stage,
                    )
                    assertEquals(
                        AccountDeletionFreshnessReason.WAIT_LIMIT_REACHED,
                        error.freshnessDiagnostic?.reason,
                    )
                    // Oversleep is a separately reported fail-closed outcome, never re-labelled
                    // successful catch-up. Do not turn a loaded runner into a fake Auth success.
                    assertTrue(
                        "A deadline rejection must have consumed the real wait budget",
                        elapsedMillis >= 1990,
                    )
                    assertTrue(
                        "Native deadline denial was not observed within test limit",
                        elapsedMillis < OUTER_TEST_LIMIT_MILLIS,
                    )
                }
            }
        }

    @Test
    fun originalCallerCancellationStopsTheRealPollingLoopInsideNonCancellableScope() = runBlocking {
        requireExplicitLocalAvd()
        val entered = CompletableDeferred<Unit>()
        val finishedNanos = AtomicLong()
        val accepted = AtomicBoolean(false)
        val checks = AtomicInteger()
        val operation =
            async(Dispatchers.Default) {
                val originalCaller = currentCoroutineContext()
                try {
                    withContext(NonCancellable) {
                        val initialNow = Instant.now()
                        // Keep the window open long enough for an explicit cancellation signal.
                        // This is still a synthetic instant, never a fabricated Firebase claim.
                        AccountDeletionFreshnessWait().sampledNow(
                            initialNow.plusSeconds(2),
                            initialNow,
                            Instant::now,
                        ) {
                            originalCaller.ensureActive()
                            if (checks.incrementAndGet() >= 2) entered.complete(Unit)
                        }
                        accepted.set(true)
                    }
                } finally {
                    finishedNanos.set(SystemClock.elapsedRealtimeNanos())
                }
            }
        try {
            withTimeout(OUTER_TEST_LIMIT_MILLIS) { entered.await() }
            assertFalse("The native polling operation must still be pending", operation.isCompleted)
            val cancelledAt = SystemClock.elapsedRealtimeNanos()
            operation.cancel(CancellationException("Explicit native timer test cancellation"))
            withTimeout(OUTER_TEST_LIMIT_MILLIS) { operation.join() }
            val cancellationMillis = (finishedNanos.get() - cancelledAt) / 1_000_000
            System.out.println(
                "NATIVE_DELETION_TIMER_CANCEL cancellationMillis=$cancellationMillis " +
                    "checks=${checks.get()} accepted=${accepted.get()} cancelled=${operation.isCancelled}"
            )
            assertTrue("Original caller must really be cancelled", operation.isCancelled)
            assertFalse("No sample may escape after original caller cancellation", accepted.get())
            assertTrue(
                "The polling loop must stop after the actual cancellation signal",
                finishedNanos.get() >= cancelledAt,
            )
            assertTrue(
                "Native polling cancellation exceeded 25ms plus observer tolerance",
                cancellationMillis in 0..(25 + OBSERVER_TOLERANCE_MILLIS),
            )
        } finally {
            operation.cancel()
            // No detached timer remains, including if an assertion or outer wait fails.
            withContext(NonCancellable) {
                withTimeout(OUTER_TEST_LIMIT_MILLIS) { operation.join() }
            }
        }
    }

    companion object {
        private const val OUTER_TEST_LIMIT_MILLIS = 5000L
        private const val OBSERVER_TOLERANCE_MILLIS = 1000L
    }
}
