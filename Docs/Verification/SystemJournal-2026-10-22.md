# System journal improvements — 2026-10-22

## Implemented source

- Owner/admin journal queries use principal-bound opaque cursors. Search and filters run across the retained journal, with at most 250 source candidates per server call, 100 returned rows, and eight automatic empty-page continuations. An older-page continuation remains visible when matches are sparse. Query changes cannot overwrite a new query's cursor or results.
- Source-derived Unicode-normalized text index, additive Firestore indexes, transactional maintenance, and a dry-run-first migration. Readiness stays disabled until a complete backfill and all ten production indexed query shapes are verified. Until then, queries use bounded scanning. Journal indexes cap at 2,000 grams with an overflow candidate marker, keeping ten composite indexes below Firestore per-document entry limits without losing matches.
- Redacted client log outbox persists up to 200 records for 48 hours. It retries with backoff and retains the original principal and event ID across restart. Anonymous errors cannot be assigned to a later account. Occurrence timestamps are canonicalized to milliseconds so a restart preserves the idempotency payload. Server diagnostic receipts prevent duplicate writes/quota consumption or resurrection of owner-deleted diagnostics after a lost acknowledgement. Non-diagnostic client audit writes preserve occurrence time in metadata and retain server-timestamp creation required by existing rules.
- Known failure stage/mode and a correlation ID are retained; missing historical causes are not invented. Deduplication is released if local enqueue fails.
- Readable wrapping status chips, action/impact/cause before identity and raw evidence, review controls after the explanation, collapsed technical evidence, foreground/midnight refresh, and explicit loaded-subset metrics.
- Owner inbox and central durable push for new warning/error/critical failures. Equivalent issues share one notice per fixed 15-minute window. The push contains fixed non-personal summaries; the selected journal record opens behind owner access checks. Old binaries retain their existing profile fallback action. Informational/successful/reviewed/older-than-24-hour records do not alert. Existing user push preference is respected.

## Verification

- iOS: 34 unit tests in seven suites pass; one UI test exercises four detail variants (Ukrainian/light, German/dark, analytics/banner). Build and UI tests pass. Screenshots inspected for wrapping and hierarchy.
- Server: 90 diagnostic, management, notification, retention and Firestore rules checks pass; the additional index-size guard also passes in the targeted 18-test rerun. Includes emulator Auth/Firestore, sparse search beyond 250 records, derived-index updates, principal/query/expiry cursor fencing, idempotent delivery, deleted-record replay protection, owner-only notice routing and simulated FCM delivery deduplication.
- Analytics regression: 80 tests pass.
- Node 22 production module bootstrap loads 362 exports in approximately 0.5 seconds (about 115 MiB RSS) locally.
- App Check policy validation and `git diff --check` pass.
- Production owner: notifications enabled; four Apple push registrations exist. Actual APNs display has not been tested by sending a synthetic production alert.

## Initial deployment boundary (historical; resolved below)

Ten additive Firestore journal search indexes reached READY. No journal source records were deleted or marked reviewed. The migration preview is read-only; activation must wait for a working deployed maintenance trigger.

The server rollout failed the Google Cloud Run container health check. Updated functions were NOT confirmed active and journal push delivery is NOT yet enabled in production. Do not describe these changes as deployed or delivered in TestFlight. Existing project-file and localization-catalog changes were preserved outside this commit.

## Initial production incident investigation (historical)

Four new Google Cloud emails represent two services, each crossing warning and critical thresholds: `recordbannermeasurement` and `aggregatenewsviewcounteroncreate`. Incident IDs: `0.oe4pugqw2exx`, `0.oe4pvo5kjmhh`, `0.oe4pvo5kjmhc`, `0.oe4pvo5kjmhl`.

Failures started around 2026-10-22 21:18 UTC, before the journal rollout around 21:30 UTC. HTTP 500 responses report that an instance could not start. Some monitoring thresholds later auto-resolved, but a non-mutating unauthenticated callable probe still returned platform HTML 500; auto-resolution is not recovery proof. Additional affected requests include organization access, consent update, passkey challenge cleanup and recent directory additions.

Fresh journal revision `listsystemlogs-00001-riz` reported `Internal error occurred while performing container health check`; image import and resource provisioning had succeeded. No application startup exception was available in the revision logs. Billing is enabled. Personalized Service Health was enabled/read; its reported Python remote Artifact Registry incident does not establish the cause of these Node.js failures. Missing old deployment images likewise do not establish a cause: Firebase documents that deployed functions retain their own image copy.

One targeted recovery deployment for the six affected existing handlers also failed its startup health checks. Current Cloud Run traffic still resolved to the previous ready revision; five subsequent non-mutating callable probes returned platform HTML 500. Function metadata reporting ACTIVE was therefore not accepted as recovery evidence. Explicit traffic-pin commands targeting the previous ready revisions also returned the same health-check failure. They must not be presented as a successful rollback. Traffic read-back still requires verification; the incident remains unresolved. Root cause remains unconfirmed. Preserve old ready traffic and avoid repeated blind redeployment or a paid always-on workaround.

## Original recovery checklist (completed below)

1. Establish that Cloud Run can start the original handlers and the pending/new journal containers; inspect exact revision startup logs and current Google Cloud health.
2. Deploy only `listSystemLogs`, `maintainSystemLogSearchIndex`, `notifySystemLogIssue`, `writeClientDiagnostic`, `deliverInboxNotificationPushOnCreate`, `cleanupExpiredData` (retry-enabled triggers are idempotent; CLI requires explicit `--force` acknowledgement).
3. Confirm all six functions ACTIVE and the two new Firestore triggers have retry enabled. Compare deployed source to this checkout.
4. Run `node functions/scripts/backfillSystemLogSearch.mjs --project=ukrainiancommunity-dbd5f` then `--apply` only after maintenance is ACTIVE. The script verifies every query shape before leaving the readiness switch enabled.
5. Read back indexed query results and production logs; inspect real owner inbox/push receipts without manufacturing a user error or changing read status.
6. An iOS build is a separate user-authorized delivery step. None was requested in this task.

Local evidence directory (gitignored): `build/system-logs-improved-20261022/`.

Final console verification also showed the existing news counter deployment health failure and completed traffic forwarding, with no spend-cap banner on the inspected Cloud Run pages. A sanitized support packet was prepared locally; it has not been sent without user authorization.


## Verified recovery — 2026-10-23, 00:14 Vienna

The incident was resolved without contacting Google support. A private ordinary Google hello container started; the real application reproduced the failure with automatic base-image composition, while the same source with `on-deploy` runtime packaging started and returned the expected application JSON response. This isolates the failing startup path without claiming to know Google's internal defect. See [runtime recovery](../CloudFunctionsRuntimeRecovery.md).

- All **161 production functions** are ACTIVE, use `onDeployUpdatePolicy`, and have Cloud Run Ready=True with 100% traffic on their intended revision. Temporary diagnostic resources were deleted.
- Existing runtime identities, feature environment values, secrets, memory/concurrency/instance limits and event trigger identities/types/retries were preserved. Twenty-four handlers now explicitly declare the previously implicit `FUNCTION_SIGNATURE_TYPE=http`; there were no other unexpected configuration changes.
- Eight representative callable probes returned application JSON 400/401 as appropriate, with no platform HTML 500. These are startup/authentication rejection checks, not authenticated end-to-end business tests.
- Genuine news and event counter deliveries on recovered revisions returned HTTP 204. A read of ERROR/5xx logs after 22:14:40 UTC contained zero new entries at the final check; this is a bounded observation, not a guarantee about future traffic.
- All six journal handlers are deployed. Both new Firestore/Eventarc triggers have the intended `systemLogs/{logId}` filter, retry enabled and their service account's invocation access. The callable journal endpoint is reachable through normal application authentication/App Check.
- Final journal deployment through Firebase CLI succeeded while preserving the pinned runtime policy. Source archives match the current compiled query, alerts, client diagnostics and push delivery handlers. The query/index helpers include the final 2,000-gram bound.
- Search backfill scanned the two retained source records and verified all ten production indexed query shapes before activating readiness. No records were deleted or marked reviewed by this work.
- Owner notifications remain enabled with four registered Apple devices. Server inbox/push routing is deployed; actual notification display on an installed iPhone has not been observed. No synthetic production error/push was manufactured for that purpose.
- Deployed analytics consent contract verification passes for `trackAnalyticsEvent`, `updateAnalyticsConsent` and `updateAnalyticsConsentV2`.
- CI run [39862308512](https://github.com/Serlest/UkrainianCommunity/actions/runs/39862308512) passed static checks, iOS build/unit tests, Firebase affected checks and Firebase/rules gates. The cutover integration fixture was corrected to stay away from Vienna midnight; its dedicated emulator rerun passed.
- Runtime security patches are now received during deployments. Restore automatic updates only after a separate real-source cold-start canary succeeds. The repository instructions retain this deployment requirement.

No TestFlight upload or public release was performed. The deployed backend is available to existing versions; the new iOS journal interface/deep link still requires a later user-authorized build.

Additional local evidence: `build/cloud-startup-investigation-20261022/final-readiness.json`, `final-callable-probes.json`, `recovered-counter-logs.json`, `final-source-verification.json`, `journal-final-backfill.log`, `deployed-analytics-contracts.log`, `post-recovery-errors.json`.
