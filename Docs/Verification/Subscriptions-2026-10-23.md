# Profile subscriptions — 2026-10-23

## Implementation

- Added a session-bound SubscriptionsViewModel. Account changes clear records, cursor, errors and pending state; old reads/removals cannot modify another session.
- List reads server-authoritative pages of 20 canonical organization_follow markers, clamped to 1–50 with one-record lookahead. Query excludes ordinary likes and retains the existing ownership filter. Cards do not request likes/bookmarks. Pages merge by organization ID; errors retain the current page and cursor.
- Explicit partial-data notice: search and sorting apply to loaded records, not an unscanned full collection.
- Date sorting and labels use the subscription marker timestamp. Organization creation dates are no longer substituted. Repository fallback without a known subscription timestamp returns nil.
- Search uses localized organization names. Available rows support contextual unsubscribe with confirmation; unavailable/blocked rows remain removable rather than vanishing. Existing detail navigation is retained.
- Shared organization cards retain their general-feed presence and unrelated interaction state. Successful unsubscription reconciles membership in place. Pending shared membership changes are not treated as final; an in-flight read does not overwrite a newer shared membership state.
- Refresh and removal are mutually exclusive. Shared membership publications remove confirmed unsubscribed entries from this list.

## Verification

Artifacts: build/subscriptions-audit-20261023/ (ignored).

- SubscriptionsVerified.xcresult: final combined run passed all 43 cases (42 unit and the two-language UI journey), zero failures/skips.
- SubscriptionsLogic.xcresult: 42 unit cases passed, no failures/skips. Includes 20→25 records without duplicates, general-feed preservation, unsubscribe reconciliation, account reset and old-response isolation.
- UI test testSubscriptionsSearchOpenAndUnsubscribe passed in Ukrainian light and German dark/accessibility modes: search/no matches, clear search, open/return, context menu, confirmation and disappearing entry. Screenshots inspected.
- rules-verified.log: one emulator integration test passed, no skips, validating first/next prefix pages, exclusion of ordinary likes and rejection of another user's query. Initial fixture failures were corrected by seeding current legal acceptance on fixture users; production rules were unchanged.
- production-query.json: the actual Firestore service accepted first-page and cursor query shapes using an intentionally unmatched user filter. No production writes or real-user unsubscribe were performed.
- Repository structure, Ukrainian/German localization and diff checks passed.

## Delivery

No schema/rules/backend deployment or store upload. Current installed binary is unchanged; client improvements ship with the next iOS build. Production membership remains in the existing likes collection with canonical organization_follow identifiers.
