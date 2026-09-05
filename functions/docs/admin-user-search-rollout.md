# Admin user search: UAC 1.0.3 implementation and deferred index rollout

## Included in 1.0.3

Both `searchManagedUsers` and the search branch of `listLegalEvidenceAccounts`
consume one Firestore projection stream. They inspect every document, retain only
up to the requested limit (100), and return the exact full match count. A stream
error rejects the call rather than returning partial results. Legal search uses
stable top-K insertion, preserving descending timestamp order and document-ID
order for ties. Management search retains document-ID order. Existing predicates,
field sets, response shapes and pagination contracts are unchanged, including
legal punctuation-only queries matching all accounts.

Memory retained across documents is O(limit), plus SDK stream buffers and the
current document. Reads remain **O(N)** per request. Legal selection is O(N*K)
with K <= 100; management selection is O(N). This is a bounded-memory repair,
not a claim that production read cost or large-dataset timeout risk is solved.
There are no early limits, stale caches, new background jobs or external services.

Authentication still runs before the query: management uses the verified/active
helper with its existing conditional privileged TOTP requirement, followed by
`assertCanManageUsers`; legal retains its legacy verified/active helper and owner
check. That legacy helper does not add TOTP; this package does not change its
existing contract. App Check options and all Rules remain unchanged.

## Prepared, deliberately incomplete index package

`adminUserSearch.ts` also contains a native Firestore candidate implementation.
All production call sites use its default **incomplete** readiness gate, which
always scans the complete projection. No request argument, config document or
environment variable can turn on indexing in this release. The explicit `ready`
argument is exercised only by the future verification fixtures; production use
requires a separately reviewed writer/Rules integration change.

`users/{uid}.adminSearchGramsV1` stores unique normalized 1-, 2- and 3-code-point
substrings from UID and all management-search fields. Normalization matches the
existing Ukrainian lowercase, NFKD, mark removal and punctuation splitting.
For any query, a gram from the longest token is a necessary condition. An
`array-contains-any` query selects that gram OR the overflow sentinel; the original
predicate then verifies EVERY candidate, including multi-token AND semantics.
Legal uses the broader index only for candidates and still checks its narrower
identity fields. Queries that normalize empty use the full fallback.

The index caps at 4,000 short grams per profile. Oversized profiles receive only
`!overflow-v1`, ensuring they remain candidates for every query rather than losing
matches. This stays below Firestore's 40,000 index-entry limit for this field;
other fields and total document/index size still need measurement before rollout.
Single-field array indexing must be enabled. No composite index is expected for
this array membership plus document-ID ordering; prove the exact deployed query
in a nonproduction project before activation. Worst-case candidates remain N for
common/one-letter queries and overflow documents; there is no universal O(1)
substring search or exact count promise.

Embedding the index in the user document avoids a second identity store and
makes profile deletion remove its index atomically. The derived grams are not
anonymized data; existing readers of a user document would also see these grams.

## Activation prerequisites — a separate, not implemented package

1. Inventory all create/update/import/admin/restore paths for UID and the six
   source fields, including direct iOS and any other clients. Keep the gate
   incomplete throughout this work. Do not silently break older clients.
2. Route searchable-field mutations through trusted synchronous writers. In the
   same transaction/write as the new profile, derive and replace (not merge)
   `adminSearchGramsV1` from the complete post-write profile. Partial patches must
   read/merge the current profile inside that transaction. Non-searchable changes
   may preserve the index. Deletes remove the whole profile as today.
3. Coordinate Rules to prevent clients changing searchable fields without this
   trusted protocol and prevent forging/removing grams. Current Rules are NOT
   claimed to enforce this. Do not deploy the migration before reviewing whether
   new fields affect current client key allowlists or trigger behavior.
4. Only after all writers enforce the protocol, run the separate backfill below,
   then independently verify full coverage and fresh rename/create/delete
   behavior. A clean backfill alone cannot establish readiness.
5. Run candidate-vs-full parity checks on representative Unicode, email, UID,
   short/multi-token and overflow queries, preserving exact counts/order. Verify
   authorization/MFA denials occur before reads; measure read cost/latency.
6. Only after these proofs, a separate reviewed code change may supply `ready`
   at the two call sites. If any prerequisite is lost, restore `incomplete` BEFORE
   permitting legacy writes. Rollback needs no data removal or destructive work.

An asynchronous on-write trigger is intentionally absent: its lag/reordering can
hide a newly created or renamed match. Reading candidate profiles again cannot
recover a user excluded by stale grams. A ready flag alone cannot fix that.

## Prepared migration — NOT RUN

After a build in the authorized verification phase, from `functions/`:

```
node scripts/backfillAdminUserSearch.mjs --project=NONPRODUCTION_PROJECT
node scripts/backfillAdminUserSearch.mjs --project=NONPRODUCTION_PROJECT --apply --confirm-project=NONPRODUCTION_PROJECT
node scripts/backfillAdminUserSearch.mjs --project=NONPRODUCTION_PROJECT
```

Default mode only reads, reports counts without personal data, and exits 2 if any
index differs. Apply requires explicit matching project confirmation, streams all
profiles and re-reads each changed profile in a transaction before updating only
the derived field. Concurrent deletions are skipped. Reruns are idempotent. There
is no automatic ready transition, even after a clean scan. Process failure may
leave partial backfill; keep incomplete and rerun. Source fields are untouched.
Production execution requires the coordinator's separate rollout authorization.

## Verification to run centrally, not executed by this task

- Build/typecheck and full existing Functions unit suite.
- New `adminUserSearch.test.ts` tests late matches beyond 1,000 rows, full counts,
  top-K/ties, interrupted streams, Unicode/multi-token superset, overflow and rename.
- Isolated Firestore emulator project `demo-uac-admin-search`, with matching
  GCLOUD_PROJECT and localhost FIRESTORE_EMULATOR_HOST: run compiled
  `adminUserSearch.integration.test.js`. It verifies incomplete fallback with
  absent/stale indexes, rename/delete, and prepared ready-path parity.
- Existing user-permission/TOTP tests; callable checks for unauthenticated,
  unverified, inactive, member, admin and owner identities, including management
  TOTP-required without/with second factor. Legal legacy behavior must stay intact.
- No index/migration activation is required to ship the bounded-memory fallback.

## Official references consulted 2026-09-05

- [Firestore queries](https://firebase.google.com/docs/firestore/query-data/queries)
- [Firestore limits](https://firebase.google.com/docs/firestore/quotas)
- [Node Firestore Query stream](https://cloud.google.com/nodejs/docs/reference/firestore/latest/firestore/query)
