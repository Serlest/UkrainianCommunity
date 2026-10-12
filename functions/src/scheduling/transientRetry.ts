/** Retry brief scheduler-to-Cloud-Run failures before the next minute tick. */
export const transientSchedulerRetry = {
  retryCount: 3,
  maxRetrySeconds: 50,
  minBackoffSeconds: 10,
  maxBackoffSeconds: 20,
  maxDoublings: 1,
} as const;
