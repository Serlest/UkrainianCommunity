# Counter aggregation transition-state runbook

## Purpose and invariant

`functions/src/counters/aggregation.ts` maintains public counters from Firestore
create/delete events. Firestore/Eventarc delivery is at least once and delivery
order is not guaranteed, so a raw `+1` or `-1` per invocation is unsafe.

Every source document now has one server-only transition document in
`counterAggregationSourceStates`. Its document ID is the lowercase SHA-256 of
the normalized Firestore source path (leading/trailing `/` removed). A target
counter changes only for an accepted `inactive -> active` or
`active -> inactive` transition. The transition state and target counter are
written in the same Firestore transaction, and the target value is clamped to
zero or greater.

All counter triggers use `retry: true`. Transient Firestore/configuration
failures therefore propagate and retry. Permanent state-schema, hash, event
identity, or target-tuple invariant violations are transactionally acknowledged
to `counterAggregationDeadLetters` and return success, preventing an unbounded
poison-event loop.

Events are ordered by the full RFC3339 CloudEvent occurrence time (`event.time`),
stored and compared as explicit integer seconds plus nanoseconds. The companion
Firestore `Timestamp` is operational metadata only: Firestore persists timestamp
values at microsecond precision, so it is not the ordering authority. No
millisecond or microsecond truncation is allowed in the explicit tuple.
`event.id` establishes exact identity only;
it is never a semantic tie breaker. The same full timestamp and ID is a retry,
while the same full timestamp with another ID is an invariant conflict that is
quarantined for reconciliation. Reuse of an ID with another timestamp is also
an identity conflict and is quarantined rather than reordered.

An exact duplicate or any event older than the stored timestamp is ignored. A
delete observed before an older create writes an inactive tombstone and the
delayed create is then ignored. Its normal delta is zero because an unknown
source has no proven contribution. A server-managed registration is the narrow
exception: `counterManagedAtomically == true` proves its callable already added
the contribution, so a newer non-callable cleanup delete subtracts it even when
the create trigger state has not arrived. Tombstones are part of the correctness
boundary and must not be expired.

## Covered sources and targets

| Source path | Active event | Inactive event | Target |
| --- | --- | --- | --- |
| `likes/{likeId}` with `newsId` | create | delete | `news/{newsId}.likeCount` |
| `likes/{likeId}` with `eventId` | create | delete | `events/{eventId}.likeCount` |
| `likes/{likeId}` with `organizationId` | create | delete | `organizations/{organizationId}.likeCount` |
| `likes/{likeId}` with `subscribedOrganizationId` | create | delete | `organizations/{organizationId}.subscriberCount` |
| `registrations/{registrationId}` | create | delete | `events/{eventId}.registeredCount` |
| `news/{newsId}/comments/{commentId}` | create | delete | `news/{newsId}.commentCount` |
| `events/{eventId}/comments/{commentId}` | create | delete | `events/{eventId}.commentCount` |
| `users/{uid}/newsViews/{newsId}` | create | none | `news/{newsId}.viewCount` |
| `users/{uid}/eventViews/{eventId}` | create | none | `events/{eventId}.viewCount` |

View counts are lifetime-deduplicated. Admin cleanup can remove a view marker,
but its transition state remains active, so recreating the same source path
does not count a second view.

Event registration callables already update membership and `registeredCount`
atomically. Their existing guards remain authoritative:

- a create with `counterManagedAtomically == true` advances transition state
  without adding to the counter;
- a delete whose `eventRegistrationCounterOperations` record is an
  `unregister` advances transition state without subtracting again;
- a direct server cleanup delete of a server-managed registration bootstraps its
  proven existing contribution and subtracts exactly once, even if that delete
  event arrives before the registration's create event;
- legacy/non-callable registration transitions still change the counter.

## State document contract

Each `counterAggregationSourceStates/{sha256Path}` document is written only by
the Admin SDK and contains:

- `schemaVersion` (`2`);
- `sourcePathHash` (the clear source path is deliberately not retained);
- `targetCollection`, `targetDocumentId`, and `counterField`;
- `isActive`;
- `lastEventId`, `lastEventTimeSeconds`, and `lastEventTimeNanoseconds` as the
  authoritative order, plus a Firestore `lastEventTime` for operations;
- `counterContributionApplied`, which distinguishes an active source whose
  target was missing from a contribution actually present in the public count;
- whether the accepted transition was `counterManagedAtomically`;
- server `updatedAt`.

Firestore rules explicitly deny every client read and write to this collection.
The target tuple is immutable for a given hashed source path. A later event that
maps the path to another target fails instead of moving or corrupting a count.
The hash is still pseudonymous operational data and must not be exported to
client analytics or logs.

If an accepted active event finds no target, the state keeps its event order but
sets `counterContributionApplied = false` and `targetMissingAt`. An exact retry
of that event safely materializes the missing `+1` if the same target now exists;
otherwise bounded reconciliation reports it as a release blocker. The operator
does not guess or silently rewrite transition history; recovery requires the
exact event retry or a reviewed targeted transaction against the authoritative
source. A delete never subtracts a contribution that was not recorded.

`counterAggregationBaselines` is a second server-only collection used for
the first lifetime-view migration and later reconciliation. Its document ID is
the lowercase SHA-256 of `collection/documentId#viewCount`. Every immutable
schema-v2 baseline document contains the target tuple, `legacyCount`,
`cutoverTimeSeconds`, `cutoverTimeNanoseconds`, an operational `cutoverAt`,
`sourceViewCountAtCutover`, `activeMarkerCountAtCutover`, and server creation
metadata. Client access is explicitly denied. Baselines and transition tombstones
have no TTL. The migration writer uses a create precondition; on restart it
verifies an identical existing baseline and never replaces it. A later-created
target may receive a zero legacy baseline only when its canonical `createdAt`
proves it was created after the recorded cutover.

`counterAggregationDeadLetters` is also server-only. Its deterministic ID is
the SHA-256 of `sourcePathHash + NUL + eventId`; it records the opaque event
identity, explicit seconds/nanoseconds, operational timestamp, incoming state,
target tuple, permanent reason, and quarantine timestamp. It contains no clear
source path. Runtime writes `resolutionStatus = unresolved`; a repeat of the
same quarantined event reopens that deterministic record without erasing prior
resolution evidence. A reviewed resolution sets `resolutionStatus = resolved`
and supplies a Firestore `resolvedAt`, non-empty `resolvedBy`,
`resolutionReason`, and `resolutionTicket`. Resolved records remain as evidence
and do not block the gate. Missing, incomplete, or malformed resolution evidence
is unresolved operational work and blocks release.

## Executable migration and reconciliation gate

The supported operator is `functions/scripts/reconcileCounterAggregation.mjs`,
exposed as `npm run counters:reconcile`. It is dry-run by default, pages every
source/target/state query in document-ID order, caps in-memory target cardinality,
persists resumable cursors, and exits non-zero while any mismatch remains. It
rejects malformed polymorphic likes, invalid source tuples, missing targets,
newer/conflicting state, negative lifetime baselines, invalid public counters,
and unresolved dead letters.

From `functions/`, first run a dry preflight with a recorded full-precision UTC
cutover and a new checkpoint file:

```sh
npm run counters:reconcile -- \
  --project=PROJECT_ID \
  --cutover-at=2026-08-24T10:00:00.123456789Z \
  --checkpoint-file=/restricted/path/counter-preflight.json
```

An apply run additionally requires an exact project confirmation, confirmed
maintenance, operator, change ticket, and report path. The cutover must already
be in the past; the CLI rejects a future ordering barrier:

```sh
npm run counters:reconcile -- \
  --project=PROJECT_ID \
  --confirm-project=PROJECT_ID \
  --cutover-at=2026-08-24T10:00:00.123456789Z \
  --checkpoint-file=/restricted/path/counter-apply.json \
  --report-file=/restricted/path/counter-apply-report.json \
  --maintenance=confirmed \
  --operator=OPERATOR_ID \
  --ticket=CHANGE_TICKET \
  --apply
```

Pass `--resume` only for the same project, mode, cutover, generation, page size,
cardinality limit, and apply/dry-run intent; the script rejects a mismatched checkpoint.
Partial scans resume from their persisted cursor. A completed dry-run phase is
always discarded and rescanned before it can become new release evidence; this
also makes recovery safe if the process stopped between its configuration checks.
The checkpoint binds every audit phase to the Firestore configuration revision.
A changed revision resets a dry-run scan and makes an apply resume fail closed;
the latter requires a new checkpoint and a fresh preflight. Start/end revisions
must also match, so a disable/enable flip during a run blocks its report.
Checkpoint files are mode `0600`, may temporarily contain collection-group path
cursors (including a user ID), and are automatically removed after a clean run.
The checkpoint and report must use different canonical paths; the operator rejects
aliases through symbolic links and case aliases on case-insensitive filesystems,
so checkpoint cleanup can never delete the release report.
Restrict and remove a failed/stale checkpoint within 24 hours. The JSON report
contains operator/change-ticket attribution and a stable SHA-256 integrity
digest; attach it to the signed release/change record rather than treating the
digest itself as an identity signature.

After deployment/enabling, compare live non-view sources and contributing state,
and compare lifetime views as immutable baseline plus contributing view state:

```sh
npm run counters:reconcile -- \
  --project=PROJECT_ID \
  --cutover-at=2026-08-24T10:00:00.123456789Z \
  --mode=reconcile \
  --checkpoint-file=/restricted/path/counter-reconcile.json
```

Public `--mode=reconcile` evidence is valid only while
`appRuntimeConfig/counterAggregation.enabled == true`; the operator checks the
flag before and after the scan and fails if it is disabled or flips mid-run.
Pre-enable verification is already part of bootstrap apply and cannot be
substituted for the required post-enable clean runs.

Use apply in reconcile mode only during confirmed maintenance and with the same
confirmation/operator/report arguments. It transactionally repairs public
counter mismatches and can create a zero baseline only for a target whose
canonical timestamp proves post-cutover creation. It never repairs malformed
state or a conflicting immutable baseline automatically.

## Mandatory first rollout

Do not enable the state-aware triggers against existing counters without a
backfill and reconciliation. With no state, the safe default is inactive; a
delete of an already-counted legacy source would otherwise write an inactive
tombstone without decrementing the old contribution.

Bootstrap scans the entire transition-state collection in addition to probing
the state for every live source. The counts must match exactly. Any orphan or
extra state from a partial/previous rollout is a blocker requiring a reviewed
manual migration plan; otherwise a retained view contribution could be counted
again inside the newly captured lifetime baseline.

Use this sequence in staging first, then production:

1. Confirm the existing event backlog is drained and there are no repeating
   counter-trigger failures. Choose and record a UTC cutover timestamp `T`.
2. Put the affected write paths in maintenance/read-only mode, or otherwise
   guarantee that the authoritative source snapshot and reconciliation use one
   stable cutover. Set `appRuntimeConfig/counterAggregation.enabled` to false
   while preparing the state. This flag stops aggregation; it does not stop
   source writes by itself.
3. Before changing any counter, capture each news/event `viewCount` at `T`.
   This is the only available total for historical views whose account-owned
   marker was already deleted. Keep the capture as release evidence.
4. Run the executable bootstrap operator, which enumerates every currently active source listed above. For each
   exact normalized path, create its hashed state document as active, with
   the explicit event-time tuple equal to `T`, a documented backfill generation,
   the correct target metadata, and `counterContributionApplied = true`. A
   registration state copies its source `counterManagedAtomically` flag; other
   source kinds set that field to false. A restarted job may replace only a
   state at the same backfill generation; it
   must never overwrite a transition newer than `T`. Do not increment counters
   as part of this state backfill.
5. For likes, subscriptions, registrations, and comments, recompute each target
   directly from the authoritative live source snapshot and replace the public
   count. Clamp results to zero or greater. A registration document counts once;
   its atomic-operation record is a dedupe guard, not another registration.
6. Do **not** replace `viewCount` with the number of live view markers. For every
   news/event target calculate
   `legacyCount = captured viewCount at T - active marker states at T`. A negative
   result, or any non-integer/negative input, is a migration blocker. Write one immutable
   `counterAggregationBaselines` document using the target hash contract above,
   and leave the captured public `viewCount` unchanged. From this point, the
   reconciled lifetime total is `legacyCount + count(contributing view states)`.
   This preserves views whose marker disappeared during earlier account cleanup.
7. Retain the clean, digest-stamped apply report. Compare every non-view counter with contributing state grouped by target.
   Compare every view counter with its immutable baseline plus contributing view
   state. Investigate every mismatch; do not use an undocumented global offset
   to hide drift.
8. Deploy Firestore rules containing explicit denies for all internal counter
   state, baseline, and dead-letter collections, then deploy the
   state-aware functions.
9. Enable `appRuntimeConfig/counterAggregation.enabled`, restore writes, and run
   the same reconciliation comparisons after the event queue is quiet.

If writes cannot be paused, the current operator must not be applied. A safe
two-watermark path needs executable change capture/replay: record a start
watermark, backfill paginated snapshots, replay source changes after that
watermark into transition state, reconcile at a second watermark, and enable
only after the two views converge. That replay implementation is not present,
so the CLI deliberately rejects `--two-watermark`; inability to enter
maintenance remains a release blocker. A best-effort live scan is not a gate.

Deleted legacy paths cannot be discovered from the current live collections.
Therefore the pre-cutover backlog must be drained before `T`; if that cannot be
proven, keep aggregation disabled for the maximum retained delivery/retry
window, reconcile again, and only then enable the new triggers.

## Reconciliation procedure

The reconciliation job/script must be bounded and restartable:

- page each top-level or collection-group query by document ID with a fixed
  page size and persisted cursor;
- calculate non-view counts from source documents, never from the current
  counter; calculate post-cutover lifetime views only as immutable legacy
  baseline plus contributing transition states, never from live markers alone;
- checkpoint the cutover/watermark, pages scanned, source totals, target totals,
  invalid source records, and corrections applied;
- reject malformed polymorphic likes (none or more than one target field)
  instead of guessing;
- for every authoritative live source, recompute its path hash and report an
  active `counterContributionApplied = false` state as a blocker; the general
  apply mode repairs public counters, not ambiguous transition history;
- update target documents transactionally or in bounded batches and verify a
  second read after completion;
- retain a signed operational report with before/after counts and mismatch
  details.

Reconcile these independent dimensions: news/event/organization likes,
organization subscriptions, event registrations, news/event comments, and
lifetime-unique news/event view paths. A missing target with any live source is
a blocker. The one expected exception is a deleted news/event target whose view
markers were also deleted: retained contributing view states are lifetime
tombstones and are reported as retired, not treated as counter drift. Content
document IDs are therefore permanent identities and must never be reused after
deletion; reuse would inherit the old immutable view baseline and tombstones.
An accepted active source with a missing target retains transition order with
`counterContributionApplied = false`; it must not decrement later unless a
contribution was actually recorded. Silently attaching a source path to another
target is not allowed.

## Monitoring and incident response

Alert on transaction errors, malformed or inconsistent state hashes, target
tuple changes, malformed source target fields, a counter below zero, missing
view baselines, any unresolved dead letter, active non-contributing states whose
target now exists, and reconciliation mismatch. Sample or aggregate routine
duplicate/older-event ignores; do not emit a user-linked log line for every
successful event.

For each dead letter, compare the authoritative source, stored state, and target.
Correct data through a reviewed bounded reconciliation transaction, then set
`resolutionStatus = resolved` and record `resolvedAt`, `resolvedBy`,
`resolutionReason`, and `resolutionTicket` on the retained record. Never replay
a quarantined event blindly. Runtime sets the status back to `unresolved` if the
same poison event recurs; an increasing queue or recurrence after remediation is
an incident.

After deployment, run the executable reconcile mode daily until seven consecutive
clean runs, then at least weekly and before every release. Any non-zero mismatch
is a release blocker until explained and corrected from authoritative sources.

For rollback, disable `counterAggregation` first. Preserve both internal counter
collections and operation guards, reconcile counters, and only then deploy a
replacement. Never delete or TTL transition tombstones or view baselines as a
rollback step: doing so reopens duplicate/out-of-order corruption or discards
the only retained bridge to pre-cutover lifetime views.
