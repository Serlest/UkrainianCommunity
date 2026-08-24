# Immutable analytics action proofs — gated implementation plan

Status: implemented end-to-end on 2026-08-24; production rollout remains gated by the schema-v2
cutover and deployment evidence. The product owner approved the temporary privacy-minimized proof.

## Problem being closed

The current compatibility check reads the mutable operational document for a like, bookmark,
follow, or registration when the analytics outbox eventually delivers. If the user legitimately
undoes the feature action first, the analytics signal can no longer be verified and is lost. The
analytics state must not keep the feature selected merely to preserve delivery.

## Privacy-minimized proof contract

For each opted-in positive action, the client reserves a random UUID before the feature mutation.
The proof contains only:

- `proofId`: random, single-use UUID;
- `eventName` and `contentId`: the positive action identity;
- `actorBinding`: SHA-256 of `actor`, UID, and the random proof ID;
- `sessionBinding`: SHA-256 of `session`, consent UUID, and proof ID;
- server `createdAt` and an `expiresAt` no later than 48 hours later.

The raw UID and consent UUID are not stored in the proof. Bindings are
different for every proof and cannot be joined across actions without already knowing the account
and random proof ID. The collection remains client unreadable.

## Atomic creation

For direct Firestore feature creates, one batch/transaction creates both the operational document
and `analyticsActionProofs/{proofId}`. Rules must require:

1. a verified active authenticated user;
2. an exact proof schema and exact random document ID;
3. `createdAt == request.time`, with `expiresAt` in the bounded 47–48 hour window;
4. a correct per-proof actor binding and matching event/content values;
5. `!exists(operationalPath)` plus `getAfter(operationalPath)` matching the newly created like,
   bookmark, or follow document;
6. create only; all client reads, updates, and deletes denied.

When analytics is disabled, no capture exists and the operational feature write continues alone.

Event registration remains server authoritative. `registerForEvent` accepts an optional capture
and creates the proof in its existing transaction only when the registration plan has
`didChange == true`. Unregister never creates a proof.

## Delivery transaction

`trackAnalyticsEvent` accepts the optional opaque binding for action events. Its transaction must:

1. derive an opaque proof-receipt ID from `proofId` and read that receipt first;
2. if an exact receipt already exists, return `tracked: false` without requiring the consumed or
   expired proof;
3. otherwise read and validate the immutable proof against auth UID, event, content, actor binding,
   and session binding;
4. use **only proof `createdAt`** as the authoritative Vienna analytics day — never compare or
   substitute the client `occurredAtMilliseconds` at a midnight boundary;
5. read the existing daily deduplication receipt and activity marker;
6. atomically create the proof receipt, delete the proof, and either increment aggregates or return
   `tracked: false` when the daily receipt already exists.

Both receipt kinds expire after 48 hours. A mismatched existing receipt is rejected, not treated as
a duplicate.

## Safe rollout order

1. Deploy Rules that understand atomic proof creation while preserving feature-only writes.
2. Deploy Functions that accept both immutable proof bindings and the current mutable operational
   proof path during the compatibility phase.
3. Release the capture-enabled iOS client and verify staged undo-before-delivery scenarios.
4. After the minimum supported client version has adopted immutable proofs, remove the legacy
   compatibility path and monitor failed-precondition rates.
5. Remove the mutable compatibility path in a later backend release.

Never release the client before compatible Rules and Functions.

## Required verification before enabling

- Pure TypeScript: exact parsing, principal/session mismatch, bounded lifetime, opaque IDs, and
  proof-receipt matching.
- Rules emulator: all six direct action types; standalone/mismatched/extra-field proofs denied;
  proof read/update/delete denied; feature-only opt-out writes succeed.
- Functions emulator: accepted action, undo before delivery, duplicate retry after proof deletion,
  same-day deduplication, midnight server-time day, expired proof, and mismatches.
- iOS unit tests: no capture while opted out/unverified, stale session rejected, atomic capture passed
  before mutation, and only the matching capture enters the outbox.
- Staging: two real devices/accounts, offline outbox retry, rapid undo, sign-out/opt-out races, and
  retention cleanup evidence after the configured TTL.

The server helper and tests live in `functions/src/analytics/analyticsActionProof.ts` and
`functions/src/analytics/analyticsActionProof.test.ts`; iOS capture and atomic feature mutations
live under `Services/Analytics` and the Firebase repositories.
