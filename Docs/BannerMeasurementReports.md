# Banner reports

The measurement/consent/receipt contract and UTC source shards are unchanged.
Current and previously shipped apps continue writing through recordBannerMeasurement.

Owner reports use getBannerMeasurementReport (verified active owner, current legal
acknowledgements, privileged MFA when required, and enforced App Check). Readers
cannot access summary/checkpoint collections directly. One request reads at most
480 summary documents and returns at most 1,320 day/section/region rows for either
the overview or a specific banner, independently of the number of other banners.
Overview contains historic totals, including deleted banners. Per-banner reports
remain accessible only for banners still present in the owner catalog.

rollupBannerMeasurementReports runs every five minutes with one instance and no
minimum instances. It scans only source shards updated since the previous completed
window. Each transaction reads the latest source and its applied checkpoint,
then applies only the missing positive delta to overview and banner summaries.
Five concurrent transactions and 250-source pages bound memory. Durable page
cursors resume fixed windows after interruptions; repeated pages are idempotent.
The existing retention job also cleans summaries and checkpoints after 395 days.
No extra summary write is made on every impression.

Before using summary reads, after deploying the functions:

```
node functions/scripts/materializeBannerReports.mjs --project=ukrainiancommunity-dbd5f
node functions/scripts/materializeBannerReports.mjs --project=ukrainiancommunity-dbd5f --apply
```

The first command is read-only. Apply projects existing shards idempotently and
checks every day/banner/section/region/shard total in one transactional snapshot
before setting bannerMeasurementReportState/v1.ready. If source writes race the
verification, retry; do not bypass it. No old measurement records are rewritten.

Banner days stay UTC to preserve historic day boundaries. UI marks the period as
UTC beside both the overview and detailed selector and states that other analytics
uses Vienna time. Historical UTC buckets cannot be exactly shifted into Vienna
days. Report-window anchor and last successful materialization time are separate,
so midnight cannot move the chart back to yesterday while the next rollup runs.

Screens refresh old caches on foreground and invalidate both Vienna/UTC day
transitions while visible. The clock check does not poll the network every minute.
