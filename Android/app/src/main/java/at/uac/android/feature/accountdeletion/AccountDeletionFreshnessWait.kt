package at.uac.android.feature.accountdeletion

import android.os.SystemClock
import java.time.Duration
import java.time.Instant
import kotlinx.coroutines.delay

/** This timer is independent of the device wall clock and includes time spent asleep. */
interface AccountDeletionWaitTimer {
    fun elapsedRealtimeNanos(): Long

    suspend fun pauseMillis(milliseconds: Long)
}

private object AndroidAccountDeletionWaitTimer : AccountDeletionWaitTimer {
    override fun elapsedRealtimeNanos(): Long = SystemClock.elapsedRealtimeNanos()

    override suspend fun pauseMillis(milliseconds: Long) = delay(milliseconds)
}

/**
 * A one-time pre-dispatch catch-up for a genuinely authenticated, slightly future-dated proof.
 * Never repeats authentication, token retrieval, policy reads, journal writes or deletion. The
 * caller must still apply the original strict proof-age check to the returned sample.
 */
class AccountDeletionFreshnessWait(
    private val timer: AccountDeletionWaitTimer = AndroidAccountDeletionWaitTimer
) {
    suspend fun sampledNow(
        authenticatedAt: Instant,
        initialNow: Instant,
        wallClock: () -> Instant,
        requireCurrent: () -> Unit,
    ): Instant {
        requireCurrent()
        if (
            !authenticatedAt.isAfter(initialNow) ||
                Duration.between(initialNow, authenticatedAt) > Duration.ofSeconds(2)
        )
            return initialNow

        val started = timer.elapsedRealtimeNanos()
        var now = initialNow
        while (true) {
            requireCurrent()
            val elapsed = timer.elapsedRealtimeNanos() - started
            // A timer reset, an overslept deadline or a wall-clock rollback never grants access.
            if (
                elapsed < 0 ||
                    elapsed > MAX_WAIT_NANOS ||
                    elapsed == MAX_WAIT_NANOS && authenticatedAt.isAfter(now)
            )
                limitReached(authenticatedAt, now)
            if (!authenticatedAt.isAfter(now)) return now
            val remaining = MAX_WAIT_NANOS - elapsed
            // Never ask the millisecond scheduler to sleep beyond the remaining budget.
            if (remaining < 1_000_000L) limitReached(authenticatedAt, now)
            val millis = minOf(POLL_MILLIS, remaining / 1_000_000L)
            timer.pauseMillis(millis)
            requireCurrent()
            now = wallClock()
        }
    }

    private fun limitReached(authenticatedAt: Instant, now: Instant): Nothing =
        throw AccountDeletionException(
            AccountDeletionFailure.RECENT_AUTH_REQUIRED,
            freshnessDiagnostic =
                AccountDeletionFreshnessDiagnostic.rejectedClock(
                        AccountDeletionFreshnessStage.FIRST_CLOCK_CHECK,
                        authenticatedAt,
                        now,
                    )
                    .copy(reason = AccountDeletionFreshnessReason.WAIT_LIMIT_REACHED),
        )

    companion object {
        internal const val MAX_WAIT_NANOS = 2_000_000_000L
        internal const val POLL_MILLIS = 25L
    }
}
