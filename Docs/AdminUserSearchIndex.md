# Managed user search index

## Contract and compatibility

`searchManagedUsers` still accepts `{query, limit}` and returns `{userIds, totalMatches}`.
`listLegalEvidenceAccounts` keeps its owner-only scope, newest-first ordering and response format.
No iOS/Android update, profile write protocol change, new registration field or Rules change is required.

The server-owned `users.adminSearchGramsV1` array contains normalized 1–3-character tokens from UID,
name, display name, email, Telegram name, city and federal state. A single indexed candidate query
is followed by the existing exact all-token substring predicate. Legal evidence still matches only
its original fields. All matches are counted; only up to 100 results are retained. Unicode folding,
ID ordering, punctuation and overflow profiles preserve existing semantics.

A search reads matching candidates, not every user. Common short queries can still match many
accounts: exact totals necessarily inspect those matches. This is not constant-cost full-text search.
No external search service or permanently warm instance is introduced.

## Maintenance and consistency

`maintainAdminUserSearchIndex` receives `users/{userId}` writes, including old app profile updates,
registrations, server-side email changes and administrative edits. It reads the **current** profile
inside a transaction and changes only the derived array. Duplicate/delayed events cannot restore
old data. Deletions are never recreated. Its own valid index-only events and unrelated changes do
not write again. Firestore Rules already prevent clients (including app owner/admin) from editing
or removing the index and from accessing `internalSearchState`.

**Consistency is eventual:** between a source write and delivery of its Firestore event, a new name
or newly registered user may not yet match an indexed search. No bounded event-delivery latency is
promised. Deleted documents are immediately absent because the query reads the users collection
itself. A former name cannot produce a false match because exact matching uses current source data.
This is an explicit compatibility choice for existing clients, whose writes cannot atomically produce
server-normalized grams. It must not be described as synchronous/atomic profile-plus-index maintenance.

The event has retries enabled. On maintenance failure it disables indexed reads before rethrowing;
subsequent searches use the complete original scan. It does not automatically re-enable an unverified
index. Database-wide outages can prevent both the update and switch write; the event still retries.

## Controlled activation / rollback

All commands run from repository root after `npm --prefix functions run build`.
Use normal ADC, or `--gcloud` for the locally signed-in gcloud account. No access token is written to disk.
Only `demo-*` project IDs are accepted with an emulator. Writes require an exact project confirmation.

1. Deploy only `maintainAdminUserSearchIndex`, `searchManagedUsers`, `listLegalEvidenceAccounts`.
2. Verify the writer is ACTIVE, the document filter is correct and retries are enabled.
3. Backfill current source documents transactionally (does not set readiness):

```sh
node functions/scripts/backfillAdminUserSearch.mjs --project=ukrainiancommunity-dbd5f --gcloud --apply --confirm-project=ukrainiancommunity-dbd5f
```

4. Run a **separate** activation pass. It refuses mismatched indexes, compares full and indexed query
results, verifies the deployed event writer, and refuses a concurrent change of the control document:

```sh
node functions/scripts/backfillAdminUserSearch.mjs --project=ukrainiancommunity-dbd5f --gcloud --activate --confirm-project=ukrainiancommunity-dbd5f
```

5. Read-only recheck: same command without `--activate` and without `--confirm-project`.
6. Immediate rollback, without redeploying or changing application builds:

```sh
node functions/scripts/backfillAdminUserSearch.mjs --project=ukrainiancommunity-dbd5f --gcloud --disable --confirm-project=ukrainiancommunity-dbd5f
```

The readiness document is `internalSearchState/usersV1`, requiring `ready: true` and `version: 1`.
Absent/disabled/unsupported-version state uses the original full scan. It is never client-controlled.
Do not delete the writer while this switch is enabled. Repair failures, backfill and verify before
re-enabling. Backfill is also a safe one-off repair after privileged/manual profile imports.

## Verification

- Pure matcher tests: normalization, multiple tokens, UID, overflow, legal-field restrictions,
  full totals past the response limit and failure propagation.
- Firestore emulator: 1,500 profiles, exact full/index result parity and selective candidate count;
  rename/delete, duplicate events, current-state transactions, source field preservation and switch rollback.
- Actual callable handlers: owner/admin access, denied ordinary/blocked/unaccepted/anonymous users,
  original response contract and owner-only legal evidence.
- Existing-app Rules test: the existing updateData profile payload succeeds with the index present;
  direct index/state tampering is denied, and existing registration/email-verification tests still pass.
- Migration integration: refuses premature activation, repairs, verifies, activates, and rolls back
  without changing any source profile field.

These checks do not substitute for a signed-in physical-device App Store end-to-end test.

## Production verification — 2026-10-20

- Targeted deployment completed; all three functions ACTIVE. Only the two intended existing
  functions changed; one new index-maintenance function was added. Existing URLs/service accounts
  remained unchanged. Other function metadata was unchanged after normalizing event-filter order.
- Live Firestore Rules exactly matched tested source, SHA-256
  `952da3747bcd89acb50fe480d39c41498b869c50e34cc79db39ada8ed5dbe123`; no Rules deployment performed.
- 32/32 profiles backfilled. Separate activation pass: zero mismatches, 32 full-vs-index query
  comparisons passed. Private readiness switch read back as enabled.
- Before activation, deleting only one disposable derived-index field exercised the actual deployed
  event pipeline: the correct index was restored in 2,189 ms. No source fields changed. This observed
  delivery time is a point-in-time check, not a latency guarantee.
- All 32 full source-document hashes, excluding only the derived index, were unchanged afterwards;
  no account was added or removed for testing.
- Live Firestore Query Explain for a selective UID query: full scan 32 document reads versus indexed
  query 1 document read; both returned the intended candidate after exact filtering.
- Both callable endpoints rejected anonymous requests with HTTP 401 / UNAUTHENTICATED.
- 34 targeted tests passed with no skips; TypeScript build/lint and diff checks passed.
- No ERROR-level Cloud Run entries for the three functions in the immediate post-deployment window.
- No iOS/Android binary, TestFlight build or public release was changed. Physical-device authenticated
  App Store E2E was not performed; compatibility evidence is the original callable contract, actual
  deployed query path, unchanged Rules and emulator execution of the legacy profile-write payload.
