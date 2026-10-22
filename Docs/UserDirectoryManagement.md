# User management directory (2026-10-22)

## Reads

The new iOS directory uses `manageUserDirectory`. Every request is bound to
`principalId` and requires a verified, active application owner/admin with the
current legal/MFA contract. Organization staff without a platform role cannot
use it. Existing `searchManagedUsers` and old application requests are unchanged.

- `list`: 40 users, an exact matching count and an opaque cursor bound to the
  actor, search, region, status/organization-role filter and sort order.
- The ordinary newest/oldest list uses an indexed Firestore page of 41 and an
  aggregate count; region queries have dedicated indexes. While an index is
  building, an authorized read falls back to a complete streamed query.
- Name ordering, substring matching and normalized legacy status/role filters
  are evaluated server-side with a bounded top-41 set. Exact totals still inspect
  all matching candidates. These paths are not constant-cost full-text search.
  Existing search grams narrow text candidates; no paid search service or warm
  instance is added.
- Organization role badges query organizations related to the returned user IDs,
  rather than loading every organization into the phone on each list refresh.
- `memberships` reads the selected user's canonical owner/admin/moderator links,
  including archived/draft organizations. Role precedence matches iOS.
- `organizations` searches authorized actionable organizations on demand, 30 per
  page. It is called only after expanding assignment controls. Draft/archive
  membership visibility does not make these entries assignment candidates.
- The user count remains the canonical `users` collection count used by analytics.
  Presence/last activity retains its existing 90-second heartbeat/180-second lease.

## Mutations and compatibility

Organization role requests now retain the exact organization timestamp revision
through `ManagedOrganization.asOrganization()`. Conflicts refresh both the
membership and current organization choice before another confirmation.

Status/global role mutations accept optional `operationId`, `principalId` and
`expectedRevision`. Revision is SHA-256 of canonical moderation state (global
role, account/block states, warning count, legacy blocked flag, ban expiry and
status/role timestamps); Swift and TypeScript share a pinned fixture hash.
Profile text edits do not invalidate moderation review. The iOS request journal
retains the original operation and suspension deadline across a network retry.

The transaction re-reads the initiator, target, legal documents and receipt,
then checks current activity, MFA/passkey epoch, role and administrator hierarchy.
The target mutation, audit and addressed notification remain atomic. Modern
replays return the saved response, reject changed fingerprints, and reject
subsequently changed target states. A delayed ban retry cannot revoke sessions
of an account restored afterwards. Revocation failure remains explicit and can
be retried without a duplicate inbox notification. Legacy requests remain
accepted and get the transaction-time authorization checks.

Receipts are private server-owned `adminMutationOperations` documents; existing
catch-all Firestore Rules deny all client reads/writes. `expiresAt` records the
retention boundary; no TTL policy is changed by this implementation.

## Evidence and delivery

- Demo emulator tests cover 137 accounts, more than 100 search matches,
  all-page filters/sorts, scoped cursors, 65 organization choices, archived/draft
  memberships, role precedence, modern/legacy mutation contracts, revoked actors,
  receipt replay/conflicts, session-revocation recovery and restored-account safety.
- iOS tests cover reviewed hashes/requests, exact organization revisions,
  pagination/deduplication, stale response/account rejection and lazy choices.
- Simulator UI checks cover Ukrainian/German, dark/light, enlarged text and
  opening/cancelling each account action. UI fixtures perform no real moderation.
- Production verification compares deployed handler/helper source, checks index
  readiness and actual chronological/region queries, and rechecks user search
  index parity. Production accounts are not modified to test moderation or push.
- Server deployment and source changes do not upload an iOS/TestFlight binary.
