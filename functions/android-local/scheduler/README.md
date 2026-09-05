# Target-scoped Android scheduler proof

Status: **local boundary13/13 PASS3.367s and actual target worker20/20 PASS6.030s**, root-executed on2026-09-03. Worker final checks required zero blocked attempts, zero cron calls, one disabled schedule registration, unchanged sentinel and all105 exact cleanup/read-back operations. No run/handoff marker remains. Logs are `android-scoped-scheduler-boundary-fixed.log` and `android-scoped-scheduler-worker.log` in the Android task outputs. This is separate from Android O06-B's proven scheduled-create UI/Rules/receipt flow. It imports the existing compiled `publishScheduledCandidate` implementation. It neither deploys nor starts emulators, a schedule, maintenance, background triggers, the full scheduled collection processor, or the publication cycle.

## Fixed local boundary

- Exact project: `demo-uac-android-scheduler`; exact endpoint: `127.0.0.1:8098`. This is **not** shared Android `demo-uac-android` on8088. Root owns the existing isolated listener and must inspect it before execution.
- Before any Admin/application import: validate opt-in/project/host/metadata settings; deny nonlocal sockets, other ports, TLS/HTTPS, DNS resolution, metadata, UDP/Unix/fd sockets, child processes and worker threads. Fetch has `redirect:error`; outgoing destinations are independently socket-checked.
- A clean allowlisted environment drops HOME, credentials, proxies and loaders. An ephemeral in-memory certificate has only the emulator `owner` token; no key file, ADC, dotenv or Cloud authority is used.
- Auth, Storage and Messaging provide throw-only handles. `onSchedule` registers a disabled stub; invoking it throws. Additional Admin apps/credentials and unreviewed Functions imports throw. Existing business code, `HttpsError`, transactions and Firestore SDK are real.
- A fixed registry contains21 cases ×5 paths =105 possible documents (user, organization, target, duplicate, lease). No discovery can expand it. Guarded WriteBatch methods enforce the exact database instance/path on direct and transaction writes; bulkWriter/recursiveDelete are denied. This guards the reviewed SDK code path, **not arbitrary hostile JavaScript or raw private RPC calls**.
- The default `linkedPlanningDraft` collection-group query is retained (unique content ID, limit10), as are actual News sourceURL/limit10 and Event startDate/limit20 duplicate queries. They are read-only and confined to this separate demo database. The reviewed worker writes no counters/log documents for these ordinary candidates. An unexpected planning-linked write fails because no planning path is registered.

## Registry and recovery

`run.local` is an exclusive0600, file+directory-fsynced, read-back manifest with synthetic paths/UUID/project, runnerPID, workerPID and prepared/active phase. No body, contact, token or credentials are stored. Both `*.local` files are gitignored. Existing/partial manifests are never overwritten by a new run.

The child durably binds its PID before Admin initialization. Worker execution uses Node's explicit [no-isolation test mode](https://nodejs.org/download/release/v22.17.0/docs/api/test.html), so there is one tracked test child rather than an untracked test grandchild. The runner has a10min deadline; boundary/cleanup children have4min. An interrupted ownership/phase handoff leaves `handoff.local` and fails closed for manual inspection. Do not delete either marker to get a “clean” run.

Before any remote mutation, all105 registered paths are read and required absent; only then is `active` durably committed. If this preflight fails, cleanup may only verify absence, never delete pre-existing content. A random UUID is not treated as permission to remove a collision. After activation, finite paths are owned even if a process dies midway through seeding.

Normal cleanup deletes every exact registered path and reads it back absent. One failure does not skip later targets; aggregate cleanup failures and the manifest remain visible. A successful run removes the marker only after all absences are confirmed. The synthetic due sentinel must stay unchanged before cleanup. Interrupted-run `--cleanup` refuses while either recorded runner or workerPID is alive; PID reuse conservatively blocks rather than guesses.

`--cleanup` runs only one explicit root-owned recovery at a time. If ownership handoff is incomplete, inspect the two immutable candidate manifests and process state manually; this harness does not guess which side is authoritative. A prepared-phase collision likewise requires explicit investigation, not blind deletion. Cleanup is not a recursive database clear.

## Commands (root review required before first execution)

Use an exact inspected Node22+ executable. Existing dependency libraries and compiled `functions/lib` must be present; the runner refuses stale compiled timestamps for the four reviewed application modules. A scoped Functions compile, if needed, is a separate parent-owned step. No dependency installation or remote service calls are part of these commands.

From the repository, with a known safe PATH (the examples use `node` already resolved by the host shell):

```sh
env -i PATH="$PATH" UAC_SCHEDULER_LOCAL=1 GCLOUD_PROJECT=demo-uac-android-scheduler FIRESTORE_EMULATOR_HOST=127.0.0.1:8098 METADATA_SERVER_DETECTION=none node functions/android-local/scheduler/run.cjs --boundary
```

Boundary tests need **no port listener** and create no database fixtures. They use independent child processes to test guard ordering, outbound entry points, exact targets, services, disabled cron, finite mutation paths, and cleanup fault behavior. They do not import the guard into the parent runner (which must be allowed to spawn that one child).

Only after boundary PASS, root inspects its existing isolated Firestore listener/project and runs:

```sh
env -i PATH="$PATH" UAC_SCHEDULER_LOCAL=1 GCLOUD_PROJECT=demo-uac-android-scheduler FIRESTORE_EMULATOR_HOST=127.0.0.1:8098 METADATA_SERVER_DETECTION=none node functions/android-local/scheduler/run.cjs --worker
```

Only after the old worker/runner are confirmed absent, an interrupted **complete** manifest can be reconciled with:

```sh
env -i PATH="$PATH" UAC_SCHEDULER_LOCAL=1 GCLOUD_PROJECT=demo-uac-android-scheduler FIRESTORE_EMULATOR_HOST=127.0.0.1:8098 METADATA_SERVER_DETECTION=none node functions/android-local/scheduler/run.cjs --cleanup
```

No listener is started or stopped here; no Rules, indexes, shared environment or project settings are changed. Each new worker run requires the previous manifest safely reconciled, then uses a new UUID.

## Test scope

20 actual-worker tests cover future skip, due News/Event, exact timestamp behavior, Austria review, fresh organization owner/admin/moderator, role loss/restriction/missing or unapproved organization, News/Event duplicates, concurrent same-ID claims, live/expired lease, date/role changes after claim, lookup exception, replacement lease, and candidate deletion. Existing `planningDraftLookup` is used only for deterministic after-claim pauses/faults; ordinary cases retain the real lookup. A separate due sentinel proves no full-cycle processing happened.

13 boundary tests exercise negative environment/early import, URL/socket/process/service entry points, redirects, schedule disablement, finite paths and per-item cleanup/read-back fault behavior. All13 and all20 worker tests passed with0 failures, cancellations or skips. Initial validation failures are retained in separate logs: NODE_OPTIONS-versus-CLI capability detection was corrected to an exact harmless CLI probe; early inherited socket construction was moved behind explicit constructor/connect guards rather than relaxing its negative assertion.

Success means local existing-worker/transaction behavior against synthetic fixtures only. It does **not** establish Cloud Scheduler/IAM delivery, publication latency, FCM/background trigger behavior, billing, deployed Rules, privileged TOTP, linked owner planning receipts or exactly-once client creation. The pre-existing Android create TOCTOU and lost-receipt-after-scheduler-transform conflict remain separate documented limits.
