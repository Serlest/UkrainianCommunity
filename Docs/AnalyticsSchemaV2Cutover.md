# Analytics schema v2 production cutover

Last reviewed: 2026-08-24

This is a fail-closed operating procedure for the existing v1 analytics data.
It does not authorize a Firebase deployment. Run it only from the reviewed,
clean release commit and retain every JSON report with the change record.

## Why a cutover is mandatory

Production currently contains v1 fixed-period documents and lifetime detail
documents. The v2 backend writes dated sources and derives Today/7/30 read
models with different semantics. Deploying v2 directly could label lifetime
detail as Today, mix old and new counters, or publish a partial owner dashboard.

The cutover therefore keeps `analyticsSchemaState/current` non-complete until
the old data has been captured and the exact v2 deployment has drained. While
the state is not `complete`, the v2 callable, rollups, and aggregate cleanup
stop. Firestore Rules deny every client access to the state, archives, and
lifecycle baselines.

## Preserved data and boundary semantics

- Every captured root and lifetime detail document is copied into
  `analyticsSchemaCutoverArchives/{generation}` and covered by a stable SHA-256
  digest. Lifetime detail is archive-only; it is never relabelled as Today.
- The cutover day must have zero views and actions. Prepare and finalize compare
  the lifetime-detail digest and reject any cutover-day daily/top/region signal.
- Thirty-one dated user-stat documents are captured: the 30-day window plus one
  predecessor. v1 copied a cumulative deleted-account total into each dated
  document, so the migration first proves the sequence never decreases and
  converts adjacent cumulative values into true per-day deletion increments.
  Missing, malformed, or decreasing source data stops the cutover. Thirty
  normalized documents then become migration baselines. For each day,
  registration history is the maximum of the final legacy count and current
  profiles whose immutable `createdAt` is at or before the deployment boundary.
  Deleted-account history comes from the final legacy dated count.
- Each baseline stores the same inclusive `coveredThrough` timestamp. A
  registration/deletion ledger event at or before that timestamp belongs only
  to the baseline; an event strictly after it belongs only to the ledger.
  Profile fallback uses the same strict boundary and the registration ledger's
  timestamp comes from the profile's immutable `createdAt`, not delivery time.

This partition prevents double counting and gaps for accounts that remain
observable. A transient account created and deleted before the new registration
trigger is active cannot be reconstructed from historical Firestore state.
Consequently account creation and physical account deletion must be frozen from
before prepare until finalize. `--maintenance=confirmed` is an operator
attestation, not a technical lock; without independently retained maintenance
evidence the production release remains blocked.

## Preconditions

1. Select a low/zero-traffic Vienna calendar day and a unique generation ID.
2. Export/back up the affected production collections.
3. Freeze new account creation and physical account deletion, and pause any
   administrative process that can change them. Record start/end evidence.
4. Stop supported clients or otherwise guarantee no v1 analytics views/actions
   during the window. The script verifies data quiescence but does not create it.
5. Confirm the Firebase project ID twice and record operator, ticket, release
   commit, Firebase CLI output, and UTC/Vienna timestamps.
6. Run the full repository, Functions, Rules, migration-integration, and release
   validators on the exact clean commit.

Production commands below intentionally require explicit values. Never copy a
sample generation, commit, project, or timestamp without resolving it first.

## 1. Prepare and close the v2 gate

First run without `--apply` and inspect the report. Then run the same arguments
with `--apply`, exact project confirmation, operator, ticket, maintenance
attestation, and a protected report path:

```sh
npm run analytics:cutover -- \
  --phase=prepare \
  --project=PROJECT_ID \
  --generation=GENERATION_ID \
  --operator=OPERATOR \
  --ticket=CHANGE_TICKET \
  --maintenance=confirmed \
  --confirm-project=PROJECT_ID \
  --report-file=EVIDENCE_PATH/prepare.json \
  --apply
```

The result must say `stateAfterPhase: prepared`. If the legacy Today top or
region document has not rolled to the same Vienna day, stop. Do not repair or
delete production data by hand.

## 2. Deploy one exact v2 commit

Deploy the reviewed Functions and Firestore Rules from the recorded commit.
Record the real deployment-completion time and prove that all of these handlers
are ACTIVE at that revision before using it as `DEPLOYED_AT`:

- `trackAnalyticsEvent`;
- `trackRegisteredUserAnalyticsAggregate`;
- `trackDeletedUserAnalyticsAggregate`;
- `rollupAnalyticsPeriods`;
- `rollupUserAnalyticsStats`;
- `cleanupAnalyticsAggregates`.

The migration CLI validates format, ordering, same-day execution, and commit
equality during verification. It cannot independently prove that a typed
timestamp is the actual Cloud Functions activation time, so deployment output
and function revision evidence are mandatory.

Wait at least ten minutes after deployment completion. This drains already
running v1 invocations; increasing the drain is safe, reducing it below 60
seconds is rejected.

## 3. Finalize

Run a dry run first, then apply:

```sh
npm run analytics:cutover -- \
  --phase=finalize \
  --project=PROJECT_ID \
  --generation=GENERATION_ID \
  --deployed-at=DEPLOYED_AT_RFC3339 \
  --deployed-commit=EXACT_GIT_COMMIT \
  --operator=OPERATOR \
  --ticket=CHANGE_TICKET \
  --maintenance=confirmed \
  --confirm-project=PROJECT_ID \
  --report-file=EVIDENCE_PATH/finalize.json \
  --apply
```

Prepare, deployment completion, and finalize must all be in the same Vienna
calendar day. Finalize fails when the day is not quiescent, lifetime detail
changed, the drain is incomplete, or the state/generation changed. A successful
finalize archives lifetime detail, publishes authoritative empty v2 dated
top/region sources for the zero-traffic day, installs the lifecycle baselines,
removes incompatible fixed v1 user read models, and changes the gate to
`complete`.

Only after successful finalize may account and analytics traffic resume.

## 4. Materialize and verify

Wait for or deliberately invoke the reviewed v2 rollups. Verification is
read-only:

```sh
npm run analytics:cutover -- \
  --phase=verify \
  --project=PROJECT_ID \
  --generation=GENERATION_ID \
  --deployed-commit=EXACT_GIT_COMMIT
```

Release requires `releaseGatePassed: true` and an empty `issues` array. Verify
recomputes prepare/final archive digests, lifecycle-baseline archive/live
digests, exact commit identity, and freshness of every fixed v2 read model after
`completedAt`. Retain this report; a green result is necessary but does not
replace staging, device, privacy, App Check, or legal gates.

## Abort and rollback

Before finalize, abort a matching prepared generation with a meaningful reason:

```sh
npm run analytics:cutover -- \
  --phase=abort \
  --project=PROJECT_ID \
  --generation=GENERATION_ID \
  --reason=REASON_AT_LEAST_8_CHARACTERS \
  --operator=OPERATOR \
  --ticket=CHANGE_TICKET \
  --confirm-project=PROJECT_ID \
  --report-file=EVIDENCE_PATH/abort.json \
  --apply
```

`aborted` remains a closed v2 gate. Either start a new reviewed prepare or roll
Functions back to the recorded v1 commit as one change; do not manually mark
the state complete. After finalize, do not use abort. Preserve archives and
reports, stop analytics collection if needed, diagnose, and perform a reviewed
forward repair or full backend rollback. No migration command deploys or
deletes production Functions by itself.

## Local evidence command

Before any production window, the exact commit must pass:

```sh
XDG_CONFIG_HOME=/private/tmp/uc-firebase-audit-config \
  npm run test:analytics-cutover:integration
```

The emulator scenario proves aborted-generation recovery, the closed gate,
quiescence rejection, full lifetime archive, cumulative-deletion normalization,
inclusive/exclusive lifecycle composition through the real user materializer,
incompatible-read-model removal, rematerialization requirement, archive-tamper
detection, and final digest verification.
