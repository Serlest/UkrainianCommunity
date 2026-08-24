# Analytics architecture and operations runbook

Last code audit: 2026-08-24

This document describes the first-party analytics implementation shipped by
UkrainianCommunity. It is both an architecture contract and an operator runbook.
It does not authorize a Firebase deployment and it does not replace the public
privacy policy, the App Store privacy answers, or a legal review.

## System contract

The implementation has five non-negotiable properties:

1. Product-interaction analytics is disabled by default and starts only after
   an explicit opt-in by the current Firebase principal.
2. The client sends aggregate events only for a verified, non-anonymous
   account. The callable independently requires a verified, active account.
3. Analytics never controls a user-facing feature. Likes, bookmarks, follows,
   registrations, public view counters, and their removals use their own
   operational records and remain the source of truth.
4. The backend stores deduplication and activity markers, then exposes only
   aggregate counts and canonical public-content metadata to an owner.
5. Analytics days and rolling periods use the `Europe/Vienna` calendar on both
   client and server, including daylight-saving transitions.

Google/Firebase Analytics is not linked into the iOS target. This pipeline uses
Firebase Authentication, App Check, callable Cloud Functions, and Firestore in
the application's own Firebase project; it does not use advertising identifiers
or cross-app tracking.

## End-to-end flow

```text
eligible content view or successful positive feature interaction
        |
        +--> operational repository and records (authoritative feature state)
        |
        `--> FirstPartyAnalyticsService (verified account + local opt-in)
                  |
                  `--> durable, principal-scoped outbox
                            |
                            `--> trackAnalyticsEvent callable
                                      |-- Auth and active-account check
                                      |-- per-account rate limit
                                      |-- canonical content lookup
                                      |-- proof-record check for actions
                                      |-- idempotency receipt
                                      `-- dated aggregate writes
                                                |
                                                +--> live dated owner data
                                                `--> hourly 7/30-day rollups
```

The callable payload from the current client contains only:

- the supported event name;
- `content_id`;
- the current consent UUID;
- an optional one-time immutable action-proof binding;
- a bounded occurrence timestamp.

The Firebase ID token carries the authenticated identity. The consent ID is an
authorization epoch and is sent so the backend can require the exact current
server-recorded grant. Titles, category,
organization, and region are re-read from the approved canonical Firestore
content document; client-supplied display metadata is not trusted.

Canonical optional metadata uses explicit null tombstones in live dated maps.
When a category, owning organization, region or federal state is removed, a
later event clears the prior value instead of leaving a stale merged leaf.
Rolling reports treat the newest day containing that item as authoritative,
including an explicit absence; older days contribute counts but cannot restore
metadata that the newer source removed. During schema compatibility reads, a
legacy ranked array is used only when the preferred keyed map has no valid
entries.

## Consent, account transitions, and the outbox

### Principal-scoped opt-in

`AnalyticsConsentService` stores a consent UUID under a SHA-256-derived local
key for each Firebase principal. A missing value means disabled. The former
installation-wide boolean is deleted and is deliberately not migrated because
it cannot safely be assigned to whichever person signs in after an upgrade.

The settings switch is unavailable for guests, anonymous users, and accounts
whose email is not verified. A server event additionally fails when the account
is suspended, banned, deactivated, or otherwise not active.

`updateAnalyticsConsent` records a versioned server-owned state and immutable
receipt containing the purpose, privacy/disclosure versions, disclosed copy,
locale, app version, grant time and withdrawal time. Delivery is fail-closed
until the exact consent generation is confirmed, and `trackAnalyticsEvent`
enforces that state transactionally. A failed withdrawal remains locally
disabled and is retried on foreground. Before production enablement, the
controller must still document the lawful basis with qualified Austrian/EU
counsel.
This gate follows GDPR Article 7(1) and EDPB Guidelines 05/2020, paragraph 108;
it is an engineering release constraint, not legal advice.

### Consent epoch and generation fence

Every auth or consent transition creates an `AnalyticsDeliverySession` with:

- the current principal ID;
- the current consent UUID;
- a monotonically increasing in-memory generation.

`AnalyticsDeliveryAuthorization` updates this state synchronously behind a
lock. Enqueue, token acquisition, App Check acquisition, HTTP delivery, and
response handling all revalidate the exact session. A delayed task from an old
account or an old consent epoch cannot become valid after a newer transition.

Opt-out, logout, or account replacement cancels the active drain and scheduled
retry and removes entries that do not belong to the new authorized session.
Opting in again creates a new consent UUID, so data queued under the revoked
consent cannot be replayed.

An opt-out cannot retract an event that the server accepted before the opt-out.
It prevents future and incompatible queued delivery; already aggregated counts
remain subject to the backend retention policy.

### Durable delivery behavior

The local outbox is an actor persisted in `UserDefaults` under
`analyticsAggregateOutbox.v1`:

- the stored owner is a SHA-256 hash of the principal, not the raw UID;
- each entry contains the minimal request, consent UUID, creation time, retry
  count, and next-attempt time;
- the queue holds at most 200 entries and drops the oldest overflow;
- entries expire after 48 hours;
- transient errors use exponential backoff from 2 seconds up to 1 hour,
  measured from completion of the failed request rather than its start;
- a delayed entry does not block newer entries that are currently eligible;
- invalid argument, not found, already exists, permission denied, failed
  precondition, out of range, and unimplemented errors are terminal and the
  entry is discarded;
- foregrounding the app resumes delivery.

The server accepts an occurrence time up to 48 hours old and at most 5 minutes
in the future. The matching client and server window allows normal offline
recovery without accepting arbitrarily backdated data.

## Operational feature data is separate

Analytics is a secondary observation of successful product interactions, not
the business ledger:

| Concern | Authoritative source | Analytics behavior |
| --- | --- | --- |
| Public news/event view count | Content repository view mutation | A separate opted-in aggregate view may be queued. The two totals are not expected to match. |
| News like | `likes/{newsId}_{uid}` and content counters | A positive analytics event is queued only after the like succeeds. Unlike is not an analytics event. |
| Bookmark | Principal bookmark subcollection | A positive analytics event is queued only after creation succeeds. Removal is not an analytics event. |
| Event registration | Registration callable and registration document | A positive analytics event is queued only when the authoritative mutation reports a new registration. Cancellation remains operational only. |
| Organization follow | Follow/like record and subscriber counters | A positive analytics event is queued only after follow succeeds. Unfollow remains operational only. |

Consequences:

- turning analytics off never disables a feature;
- analytics delivery failure never rolls back a successful feature mutation;
- owner analytics counts opted-in, deduplicated interactions and must not be
  presented as the authoritative public counter or current membership count;
- account totals, status totals, registration/deletion totals, and profile
  federal-state totals are operational platform statistics calculated from all
  accounts, independently of interaction-analytics consent;
- active-user windows are consent-based because activity markers are created
  only by accepted analytics events.

## Supported event and metric contract

Only positive events below are accepted by the current callable. Cancellation,
unfollow, search, filter, language, theme, and consent-change names are not
forwarded by the current client and are rejected by the current server event
union. Some reader fields for cancellation/unfollow remain only for legacy data
compatibility.

| Event | Required server proof | Daily/detail metrics | Additional output |
| --- | --- | --- | --- |
| `news_view` | None beyond approved canonical news | `newsViews`, `totalViews`, content `views` | Daily top content, region, organization `newsViews` when owned |
| `news_like` | One-time immutable action proof; legacy operational check during rollout | `newsLikes`, compatibility `totalLikes`, `totalActions`, content `likes` | — |
| `news_bookmark` | One-time immutable action proof; legacy operational check during rollout | `newsBookmarks`, `totalBookmarks`, `totalActions`, content `bookmarks` | — |
| `event_view` | None beyond approved canonical event | `eventViews`, `totalViews`, content `views` | Daily top content, region, organization `eventViews` when owned |
| `event_register` | One-time immutable proof created by the registration transaction | `eventRegistrations`, `totalActions`, content `registrations` | Organization `eventRegistrations` when owned |
| `event_bookmark` | One-time immutable action proof; legacy operational check during rollout | `eventBookmarks`, `totalBookmarks`, `totalActions`, content `bookmarks` | — |
| `organization_view` | None beyond approved canonical organization | `organizationViews`, `totalViews`, content `views` | Daily top content, region, organization `profileViews` |
| `organization_follow` | One-time immutable action proof; legacy operational check during rollout | `organizationFollows`, `totalActions`, content `follows` | Organization `follows` |
| `organization_bookmark` | One-time immutable action proof; legacy operational check during rollout | `organizationBookmarks`, `totalBookmarks`, `totalActions`, content `bookmarks` | Organization `bookmarks` |

Each immutable proof stores opaque actor/session bindings, event/content identity,
server `createdAt`, and a maximum 48-hour expiry. Its server timestamp is the
authoritative Vienna analytics day. View events have no
feature proof document, but the target must exist, be moderation-approved, not
archived, and have valid canonical display data.

The receipt ID is a SHA-256 digest of UID, Vienna day, event name, content type,
and content ID. Therefore a metric represents at most one accepted occurrence
of that event for that account/content/day. A duplicate returns `tracked=false`
but still refreshes the account activity write without allowing its activity
timestamp to regress.

The callable consumes one rate-limit attempt before canonical-content and proof
reads. The current limit is 120 attempts per verified account per five-minute
bucket; the rate-limit document expires after two hours.

## Region and location semantics

Region data comes from canonical published content, never from device location.
The app does not request Core Location permission for this pipeline.

Accepted reporting buckets are Austria and the nine federal states. A content
record with city scope is folded into its federal state because the pipeline
does not retain a city name. Invalid or incomplete region data creates no region
bucket. This avoids a misleading `city_all` bucket and double-counting the same
state under two scopes.

## Vienna time and period semantics

- Daily document IDs are `YYYY-MM-DD` in `Europe/Vienna`.
- Today is one Vienna calendar day.
- Seven days means today plus the six preceding Vienna calendar days.
- Thirty days means today plus the 29 preceding Vienna calendar days.
- Period construction uses calendar IDs rather than fixed 24-hour subtraction,
  so the 23-hour and 25-hour daylight-saving days remain one analytics day.
- One immutable time anchor is captured for a server rollup or iOS repository
  fetch so an async operation cannot mix periods if it crosses midnight.

Daily event documents are live. The hourly scheduler derives fixed
`today`, `seven_days`, and `thirty_days` top-content, region, content-detail, and
organization-detail rollups from dated documents. The current iOS repository
reads the dated document for Today and the fixed IDs for seven/thirty days; the
fixed Today rollup remains a server-produced compatibility/read-model document.

The dashboard fetches both the current and immediately preceding window from
daily documents, zero-fills missing dates, and uses the preceding window for
trend comparison. A zero current value with a positive previous value is valid
content, not an empty state.

## Firestore collections, access, and retention

| Collection | Purpose and identifiers | Client access | Repository retention |
| --- | --- | --- | --- |
| `analyticsDailyStats` | Dated aggregate counters and active region keys | Owner read; no client writes | Dated roots: 60 Vienna calendar days |
| `analyticsTopContent` | Live dated `itemsByKey`; fixed ranked read models | Owner read; no client writes | Dated roots: 60 days; fixed IDs preserved |
| `analyticsRegionStats` | Live dated region maps; fixed ranked read models | Owner read; no client writes | Dated roots: 60 days; fixed IDs preserved |
| `analyticsContentStats/{period}/items` | Dated per-content details and fixed period read models | Owner read; no client writes | Dated roots recursively removed after 60 days; fixed IDs preserved |
| `analyticsOrganizationStats/{period}/organizations` | Dated per-organization details and fixed period read models | Owner read; no client writes | Dated roots recursively removed after 60 days; fixed IDs preserved |
| `analyticsUserStats` | Dated Today plus fixed Today/7/30 account aggregates | Owner read; no client writes | Dated roots: 60 days; fixed IDs preserved |
| `analyticsEventReceipts` | Server idempotency receipts with opaque IDs | No client access | 72 hours (longer than the 48-hour accepted delivery horizon) |
| `analyticsRateLimits` | Per-account/five-minute rate buckets with opaque IDs | No client access | 2 hours |
| `analyticsUserActivity` | UID-keyed latest accepted activity timestamp; no content/event payload | No client access | 60 days from latest activity |
| `analyticsUserRegistrationEvents` | Retry-idempotent registration ledger with opaque event ID and user key | No client access | 60 days |
| `analyticsDeletedUserEvents` | Retry-idempotent deletion ledger with opaque event ID | No client access | 60 days |
| `analyticsUserLifecycleBaselines` | Thirty-day normalized v1 migration counts with an inclusive deployment boundary | No client access | 60 days from cutover |
| `analyticsSchemaState` | Fail-closed v2 cutover generation and deployment evidence | No client access | Operational state |
| `analyticsSchemaCutoverArchives` | Digest-covered v1 roots, lifetime detail, and baseline evidence | No client access | Preserve with release/change evidence |
| `analyticsAggregateCleanupState` | Server cursor per aggregate collection | No client access | Operational state, replaced/deleted as scans complete |

Firestore Rules allow reads of aggregate and detail read models only to the
platform owner. All analytics client writes are denied. Short-lived markers,
receipts, lifecycle ledgers, rate limits, and cleanup cursors are neither
readable nor writable by clients. Cloud Functions use the Admin SDK.

Retention is implemented by scheduled code in this repository; `expiresAt`
alone must not be assumed to prove that a Firebase Console TTL policy exists.

### Cleanup schedules

- `cleanupAnalyticsAggregates`: daily at 03:30 Vienna time, 540 seconds,
  512 MiB, one instance. It inspects 50 roots plus one look-ahead per page,
  handles at most four pages per collection per run, persists an independent
  cursor, and recursively deletes eligible dated roots and subcollections.
- `cleanupExpiredData`: daily at 04:00 Vienna time, 540 seconds, 512 MiB. For
  each marker/guard collection it processes pages of 500, at most 20 pages per
  run. Activity deletion re-reads the mutable expiry in a transaction so a
  concurrently refreshed marker is preserved.

Fixed `today`, `seven_days`, and `thirty_days` roots are never removed by the
aggregate cleanup. Invalid or non-date root IDs are also preserved for manual
inspection instead of being deleted heuristically.

## Rollups and user-stat materialization

`rollupAnalyticsPeriods` and `rollupUserAnalyticsStats` run hourly in
`europe-west3`, with one instance, concurrency of one, a 540-second timeout,
and 512 MiB memory.

Content rollups:

- calculate all period IDs once from one Vienna anchor;
- retain the top 20 items independently for news, events, and organizations;
- retain at most 50 region rows;
- retain at most 50 nested region/top-content items in each detail rollup;
- scan detail children in document-ID order with pages of 100 and at most five
  concurrent source reads; one bounded k-way stream produces Today/7/30-day
  detail values without loading a daily subcollection or catalog in full;
- tag each written detail child with a unique rollup generation, remove stale
  destination children in pages of 100, and publish the parent `updatedAt` only
  after every page and cleanup succeeds. Page writes, stale cleanup and final
  publication transactionally verify that the runner still owns the parent
  generation, so even an accidental overlapping invocation cannot overwrite or
  delete a newer generation. An interrupted run leaves the previous parent
  freshness visible and the next serialized run self-corrects the incomplete
  generation. For seven/thirty-day detail reads, iOS first reads the completed
  parent marker and then accepts a child only when its period and generation
  match; a missing child is confirmed against the parent a second time. An
  in-progress or mixed generation fails closed with a localized retry state
  instead of exposing partial totals or caching a transient empty result.

User materialization is a bounded, deterministic full scan:

- user profiles are ordered by document ID and processed in pages of 250;
- activity documents are fetched only for the current user page, in exact-read
  batches of 100, with at most three such batches for a full page;
- the 7/30-day arrays and membership sets are calculated once per run;
- registration and deletion ledgers are processed in document-ID pages of 250;
- counts are accumulated incrementally instead of loading whole collections;
- v1 migration baselines own lifecycle counts at or before their inclusive
  `coveredThrough` deployment boundary. A current profile's immutable
  `createdAt` fallback and immutable ledger events are considered only when
  strictly later than that boundary; a matching post-boundary ledger marker
  removes the fallback. Equality is therefore counted exactly once. The
  cross-scan fallback map is capped at 100,000 recent profiles, and exceeding
  the cap fails the run before publishing instead of risking an out-of-memory
  partial result;
- v1 dated `deletedAccounts` values were cumulative rather than daily. Cutover
  captures a 31st predecessor, rejects a missing/decreasing cumulative series,
  and stores adjacent deltas so Today/7/30 do not multiply one historical
  deletion across every later day;
- active totals exclude restricted/deactivated users, while total, status, and
  profile-region totals describe the complete current account collection.

The scan is memory-bounded but remains `O(number of users + lifecycle events)`.
Its separate paginated reads are not a Firestore point-in-time snapshot. An
account changed during a run can appear in the next hourly result; the next full
run self-corrects this normal eventual-consistency edge.

Registration/deletion triggers use opaque, deterministic IDs derived from the
CloudEvent ID and have retries enabled. Registration records also carry an
opaque user key for fallback deduplication. User deletion removes the matching
activity document.

## Owner read model, partial data, and freshness

The owner repository loads daily stats as the required base source. Top
content, region stats, and user stats are independent recovering sources:

- a failed optional source is logged and represented as unavailable instead of
  discarding usable dashboard data;
- missing top content is reported as partial only when current views are
  positive;
- missing regions are reported as partial only when active regions are
  positive;
- missing or structurally incomplete user stats are always reported as partial;
- keyed maps are preferred over stale ranked arrays when the map has usable
  values;
- legacy scalar active-region values are retained as a lower-bound fallback,
  while modern daily region keys are unioned across the period.

`OwnerAnalyticsSnapshot.generatedAt` is the oldest available source timestamp
among current daily data, top content, regions, and user stats. This conservative
choice prevents a fresh source from hiding a stale one. A missing timestamp is
shown as unavailable rather than fabricated.

Dashboard and detail view models cache each period for 60 seconds. If a refresh
fails after content was loaded, the existing data remains visible with a stale
data banner and Retry action. Errors, cache entries, and load generations are
period-scoped, so a late response cannot overwrite a newly selected period.

## Hot-document capacity and monitoring

### Current limit

Every accepted view transaction updates the same dated
`analyticsTopContent/{ViennaDay}` document. Every accepted event also updates the
same dated `analyticsDailyStats/{ViennaDay}` document, and views update the same
dated region document. These are intentional simple-schema hot documents.
`itemsByKey` in the dated top-content document is not capped; only the derived
ranked read model is capped. A popular individual content/detail or organization
document can become a second hotspot.

Firestore does not promise one universal safe write rate for a contended
document; the practical limit depends on transaction latency, indexes, and
workload. The following values are UkrainianCommunity operational guardrails,
not Firebase service-limit claims:

| Signal | Yellow: plan/enable sharding | Red: stop scale-up and shard before release |
| --- | --- | --- |
| Accepted view rate into one Vienna-day top document | 30/min averaged over 5 minutes | 60/min averaged over 5 minutes |
| `trackAnalyticsEvent` p95 latency | Above 1.5 s for 15 minutes | Above 2.5 s for 10 minutes |
| `ABORTED` + `DEADLINE_EXCEEDED` + `RESOURCE_EXHAUSTED` | At least 0.5% of calls for 15 minutes | At least 1% for 10 minutes |
| Dated top-content estimated payload | 700 KiB or 5,000 unique keys | 850 KiB, regardless of key count |
| User materialization duration | Above 300 s | Above 450 s or any timeout |

The document-size thresholds intentionally leave headroom below Firestore's
hard document limit and for Firestore encoding overhead.

### What to monitor

Before production traffic, create Cloud Monitoring dashboards and alerts for:

1. callable request count, p50/p95/p99 latency, and result/error code;
2. Firestore request latency and `ABORTED`, `DEADLINE_EXCEEDED`, and
   `RESOURCE_EXHAUSTED` responses;
3. the five-minute delta of `analyticsDailyStats/{today}.metrics.totalViews` as
   accepted-view throughput;
4. daily top-content unique-key count and an encoded-size estimate;
5. hourly rollup success, duration, timeout, and freshness lag;
6. retention deleted/failed counts and a cleanup cursor that stops advancing;
7. App Check valid/invalid/unverified request ratios.

The current code exposes function/platform errors and aggregate timestamps but
does not yet emit a structured accepted-event rate, materialization page count,
or encoded document-size metric. Until those metrics are automated, calculate
view throughput from consecutive daily-counter samples and inspect the dated
top-content document at least weekly. Crossing a yellow threshold makes this
instrumentation and sharding a release gate, not optional cleanup.

### Sharding plan

Preserve the existing owner read schema and move only the write model:

1. Add a versioned, server-only analytics write configuration with a fixed shard
   count for each Vienna day. Never change the count mid-day.
2. Write daily totals to deterministic counter shards selected from the receipt
   digest.
3. Replace the top-content map with per-content counter shards, for example
   `analyticsTopContentDaily/{day}/items/{contentKey}/shards/{shard}`. Resolve
   metadata from canonical content during rollup, so the hot path increments
   only a counter and neither one viral item nor a large catalog grows one map.
4. Apply the same per-entity counter-shard pattern to viral content and
   organization detail documents; region shards can be keyed by normalized
   region plus counter shard.
5. Keep the idempotency receipt and selected shard write in the same transaction.
6. Have the hourly compactor sum shards and publish the existing dated/fixed
   read models atomically by generation. iOS then needs no schema change.
7. Start v2 at a Vienna day boundary. During verification, make the compactor
   understand both v1 and v2 sources; do not keep dual-writing to the v1 hot
   document.
8. Reconcile v1 versus v2 totals for at least one full 30-day window before
   removing the compatibility reader.

Choose the next power-of-two shard count at or above
`peak accepted writes per second / 0.25`, with 16 as the initial minimum. The
0.25 writes/second target is an internal headroom objective and must be adjusted
from observed production latency and contention, not treated as a Firebase
guarantee.

## Release and deployment gates

### Repository gate

- Run `python3 scripts/validate_release_configuration.py` on the exact commit.
- Run Functions lint/build, the full unit suite, all Firestore/Storage emulator
  rules suites, and the production dependency audit.
- Run iOS Debug and Release builds, unit tests, targeted owner-analytics UI
  tests, light/dark mode, Dynamic Type, VoiceOver, and Vienna DST tests.
- Confirm the signed archive does not contain Google/Firebase Analytics and
  inspect its generated privacy report.
- Record the commit, SDK/Xcode version, test output, known risks, and rollback
  point. Do not deploy from a dirty or different worktree.

### Firebase deploy gate

- Obtain explicit deployment authorization.
- Verify the selected Firebase project twice; the repository production alias
  currently points to `ukrainiancommunity-dbd5f`.
- Back up/export production data under the operating procedure.
- Deploy the reviewed Functions, Firestore Rules/indexes, and Storage Rules from
  the same commit. Keep `ENFORCE_ANALYTICS_APP_CHECK=false` for the first staged
  client rollout.
- Verify the function region, runtime identity, permissions, schedules,
  timeout/memory settings, and monitoring alerts in the Firebase/Google Cloud
  consoles. Repository configuration alone does not prove deployed state.
- Run the hourly rollups and both cleanup jobs against non-destructive test data;
  confirm retries, cursor progress, freshness timestamps, and owner-only reads.
- Before production enablement, run a staged end-to-end callable matrix with a
  real token-capable client: consent off/on, verified/unverified and restricted
  accounts, valid/invalid canonical targets and proof documents, duplicate
  delivery/idempotency, rate limiting, App Check observation, and the resulting
  daily/detail aggregates. Unit and Rules emulator coverage does not replace
  this remaining pre-production verification.
- Execute `Docs/AnalyticsSchemaV2Cutover.md` before enabling v2. The transition
  must archive and digest the existing lifetime detail, use a zero-traffic
  Vienna day, freeze account creation/deletion, retain exact deployment-time and
  commit evidence, install the bounded lifecycle baseline, and pass read-only
  verification after v2 rematerialization. Neither a normal Functions deploy
  nor a typed `--maintenance=confirmed` value is sufficient evidence.
- Historical interaction events that were never collected cannot be
  reconstructed. Lifetime v1 detail remains in the cutover archive and is not
  presented as a v2 daily period.

### App Check gate

The client obtains an App Check token for the callable, but the callable
parameter defaults to no enforcement. Follow `Docs/AppCheckRollout.md` and
`functions/APP_CHECK_RELEASE_GATE.md`:

1. register App Attest and verify DeviceCheck fallback;
2. register only controlled simulator/CI debug tokens;
3. release the token-capable client with enforcement off;
4. observe valid production traffic for a normal usage cycle;
5. verify TestFlight with enforcement;
6. set `ENFORCE_ANALYTICS_APP_CHECK=true`, monitor errors, and retain the
   parameter rollback procedure.

### Privacy and App Store gate

- The public policy and App Store Connect answers must describe product
  interaction analytics as opt-in and account-linked while deduplicating, not
  anonymous.
- State clearly that aggregate region is based on published content and not
  device location.
- Keep operational all-account statistics distinct from consented interaction
  analytics.
- Reconcile the public policy, in-app text, `Docs/AppStorePrivacyInventory.md`,
  the signed archive privacy report, and current Firebase SDK disclosures.
- Obtain the required Austrian/EU legal review before submission.
- Record the approved lawful basis for optional owner analytics. If it is
  consent, deploy and verify versioned server-side consent receipts and callable
  enforcement before enabling collection; the current device-local UUID is not
  sufficient release evidence.

### Production smoke test

Using disposable verified accounts and approved test content:

1. Confirm fresh install/account consent is off and no event is queued.
2. Opt in, record a view, and confirm one dated aggregate increment.
3. Repeat the same event for the same content/day and confirm `tracked=false`
   with no second increment.
4. Create a supported operational action, verify the proof document, and confirm
   one action increment. Confirm a missing/mismatched proof is rejected.
5. Test offline queue persistence, retry, app restart, 48-hour expiry, queue cap,
   and that a transient failure does not block a newer entry.
6. Test account A opt-in, logout, account B login, opt-out, and rapid auth
   transitions; no old-session event may be delivered under a new session.
7. Verify Today/7/30 around Vienna midnight and both DST changes.
8. Verify an owner can read aggregates and a normal authenticated account,
   guest, and direct client write cannot.
9. Verify partial-source, stale refresh, empty, search, and detail drill-down UI.
10. Confirm freshness is within the hourly rollup SLO and all monitoring signals
    remain below yellow thresholds.

## Incident response

- **Legitimate requests rejected after App Check enforcement:** disable the
  affected enforcement/parameter first, preserve data, then investigate tokens.
- **Callable contention or latency threshold crossed:** stop promotional
  scale-up, retain receipt/aggregate data, reduce avoidable traffic, and execute
  the sharding plan. Do not weaken Auth, proof, or idempotency checks.
- **Rollup stale or failed:** leave the last good read model visible, investigate
  scheduler/function logs, rerun only after confirming one active instance and
  the correct Vienna anchor.
- **Retention backlog:** inspect per-collection cursor and failure logs. Increase
  a bounded per-run budget only after measuring runtime; never issue a broad
  recursive delete against an unresolved path.
- **Suspected cross-account delivery:** disable the analytics callable, preserve
  local/server evidence, verify consent generation tests, and treat it as a
  privacy incident. Do not delete evidence before the incident owner approves.

## Code sources of truth

- iOS consent and dispatch: `UkrainianCommunity/Services/Analytics/FirstPartyAnalyticsService.swift`
- iOS outbox and delivery fence: `UkrainianCommunity/Services/Analytics/AnalyticsAggregationOutbox.swift`
- consent storage: `UkrainianCommunity/Services/Analytics/AnalyticsConsentService.swift`
- callable and rollups: `functions/src/analytics/trackAnalyticsEvent.ts`
- Vienna date contract: `functions/src/analytics/analyticsDate.ts` and
  `UkrainianCommunity/Repositories/Analytics/AnalyticsFirestoreSchema.swift`
- user scan/window contract: `functions/src/analytics/analyticsUserActivity.ts`
- detail rollups: `functions/src/analytics/analyticsDetailRollup.ts`
- retention: `functions/src/retention/dataRetention.ts` and
  `functions/src/analytics/cleanupAnalyticsAggregates.ts`
- owner read model: `UkrainianCommunity/Repositories/Analytics/FirestoreOwnerAnalyticsRepository.swift`
- access control: `Firebase/firestore.rules`
- gated fix for action undo-before-delivery: `Docs/AnalyticsActionProofPlan.md`
  (design/pure validation only until its temporary Firestore data flow is
  explicitly approved and implemented)
- production schema transition: `Docs/AnalyticsSchemaV2Cutover.md`
