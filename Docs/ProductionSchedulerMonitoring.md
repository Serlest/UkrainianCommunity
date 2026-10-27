# Production Scheduler monitoring

Verified on 2026-10-13 in `ukrainiancommunity-dbd5f`.

## Retry-enabled jobs

Monitoring policy `10611206044681368285` watches Cloud Run `request_count`
for successful (2xx) executions, grouped by service across revisions. An
individual failed attempt does not notify if a retry succeeds within the
window. The policy sends an opening notification only.

| Frequency | Functions | No-success window |
| --- | --- | --- |
| Every minute | `deliverAnnouncements`, `publishScheduledContent` | 10 minutes, then 1 minute confirmation |
| Hourly | `restoreExpiredTemporarySuspensions`, `rollupAnalyticsPeriods`, `rollupUserAnalyticsStats`, `cleanupExpiredPasskeyChallenges` | 100 minutes, then 1 minute confirmation |
| Daily | `cleanupAbandonedOrganizationRequests` | 25 hours, then 10 minutes confirmation |

The 100-minute hourly window tolerates a schedule shift during deployment plus
Monitoring ingestion delay; it still reports a missing hourly run. The daily
window includes the longer interval when Vienna changes from summer to winter
time. Monitoring data can arrive later than an execution. A 2xx
response proves that the HTTP invocation finished successfully; content and
data correctness still require their own checks.

## Jobs without retries

Log alert policy `2691316956313024601` still reports a failed Scheduler
`AttemptFinished` for jobs outside the seven above. Its filter explicitly excludes
the retry-enabled jobs, which are covered by the no-success policy instead.
Failed attempts remain in Cloud Logging for investigation.

The separate Cloud Run 5xx policy `10153290522722410887` warns after three
server errors from one service within five minutes.

No minimum Cloud Run instances are required for these alerts. As checked on
2026-10-12, [Google's alerting price schedule](https://cloud.google.com/products/observability/pricing)
starts no earlier than 2027-09-01; built-in [Cloud Run metrics](https://cloud.google.com/run/docs/monitoring)
have no separate collection charge. Recheck pricing before that date.

## 2026-10-13 incident and verification

- `cleanupExpiredPasskeyChallenges` received one Cloud Run HTTP 429 at 06:47 UTC:
  no instance was available. The previous 22 scheduled requests succeeded with
  HTTP 200. Its Scheduler job had no retry configuration, so this transient
  failure left one hourly cleanup cycle undone and opened an alert.
- An earlier `restoreExpiredTemporarySuspensions` no-success alert at 17:11 UTC
  on 2026-10-12 was false: the function returned HTTP 200 at 17:08. Deployment
  shifted its hourly execution from 15:49 to 17:08; the old 75-minute window
  and Monitoring data delay were too narrow for that shift.
- The passkey cleanup now uses three short Scheduler retries. Both alert policies
  were updated and read back: hourly success window 100 minutes; passkey cleanup
  excluded from the per-attempt failure alert. A manual Scheduler invocation
  after deployment returned HTTP 200 at 07:37 UTC. The function remains at zero
  minimum instances; the next automatic execution still requires observation.

## 2026-10-27 journal audit follow-up

The existing no-success policy now also covers all seven previously uncovered,
**enabled** maintenance jobs. The original three conditions, email channel,
notification preferences, and all schedules are preserved.

| Added scope | Functions | Window and confirmation |
| --- | --- | --- |
| Every five minutes | `rollupBannerMeasurementReports` | 20 minutes without 2xx, then 2 minutes confirmation |
| Daily maintenance | `migrateLegacyContentMedia`, `cleanupStaleFeaturedBannerOrphans`, `cleanupExpiredData`, `cleanupUnverifiedAccounts`, `cleanupStaleContentMediaOrphans`, `cleanupAnnouncements` | 25 hours without 2xx, then 30 minutes confirmation |

Cloud Monitoring limits metric alignment to 25 hours. The additional daily
confirmation period accommodates the Vienna 25-hour DST interval and metric
arrival delay. An initial 26-hour alignment request was rejected before saving;
the accepted configuration above was read back from the server. Existing daily
organization-request coverage retains its original 25-hour/10-minute condition.
All 14 enabled jobs have matching recent Cloud Run 2xx series; aligned bucket
counts are not exact execution counts for the requested wall-clock interval.

`cleanupOrganizationPhotoLifecycle` remains intentionally paused and excluded;
its independent cleanup gates remain intact. No cleanup job was manually run.
New saved conditions still need subsequent natural missing/success behavior to
be observed; no production failure was induced to manufacture an alert.

The idempotent configuration helper is
`scripts/configure_scheduler_monitoring.py` (dry run by default; `--apply` changes
only the existing policy's conditions). Its contract tests run in static CI.
Local saved configuration and readback: `build/fix-system17-20261027/monitoring/`.
