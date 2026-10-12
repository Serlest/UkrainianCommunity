# Production Scheduler monitoring

Verified on 2026-10-12 in `ukrainiancommunity-dbd5f`.

## Retry-enabled jobs

Monitoring policy `10611206044681368285` watches Cloud Run `request_count`
for successful (2xx) executions, grouped by service across revisions. An
individual failed attempt does not notify if a retry succeeds within the
window. The policy sends an opening notification only.

| Frequency | Functions | No-success window |
| --- | --- | --- |
| Every minute | `deliverAnnouncements`, `publishScheduledContent` | 10 minutes, then 1 minute confirmation |
| Hourly | `restoreExpiredTemporarySuspensions`, `rollupAnalyticsPeriods`, `rollupUserAnalyticsStats` | 75 minutes, then 1 minute confirmation |
| Daily | `cleanupAbandonedOrganizationRequests` | 25 hours, then 10 minutes confirmation |

The daily window includes the longer interval when Vienna changes from summer
to winter time. Monitoring data can arrive later than an execution. A 2xx
response proves that the HTTP invocation finished successfully; content and
data correctness still require their own checks.

## Jobs without retries

Log alert policy `2691316956313024601` still reports a failed Scheduler
`AttemptFinished` for jobs outside the six above. Its filter explicitly excludes
the retry-enabled jobs, which are covered by the no-success policy instead.
Failed attempts remain in Cloud Logging for investigation.

The separate Cloud Run 5xx policy `10153290522722410887` warns after three
server errors from one service within five minutes.

No minimum Cloud Run instances are required for these alerts. As checked on
2026-10-12, [Google's alerting price schedule](https://cloud.google.com/products/observability/pricing)
starts no earlier than 2027-09-01; built-in [Cloud Run metrics](https://cloud.google.com/run/docs/monitoring)
have no separate collection charge. Recheck pricing before that date.
