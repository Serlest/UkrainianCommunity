# Legal evidence: implementation verification, 2026-10-23

## Scope

Owner Profile → agreements and legal confirmations. Backend/rules authority and old request formats retained. No receipt or user profile was edited by this task.

## Changes

- Mutable profile acceptance summaries no longer appear as duplicate immutable receipts. Unmatched profile evidence is explicitly labeled as a profile snapshot; minimum-age registration evidence remains separate.
- Account search uses continuation cursors bound to the normalized query; results beyond the first 50 are reachable without scanning and counting every matching account before returning a page.
- History format 2 merges paged legal receipts, analytics grants/withdrawals and profile fallbacks in descending timestamp order. Precise per-stream cursors handle ties and null grant/withdrawal dates. Filters limit queried streams. Text search scans bounded pages; the UI clearly offers continuation when a page has no matches.
- Compact account card, collapsible provenance, recorded confirmation summary, explicit states for current/earlier versions, consent grant/withdrawal and missing evidence.
- Recorded document reader loads the exact stored version from the server, validates stored translations and hashes, and rejects a mismatched receipt hash. Missing versions are never substituted with the current or bundled document. Legacy evidence without a hash is explicitly disclosed.
- Full JSON export is prepared only on request and includes all pages independently of the visible history filter. Rendering no longer repeatedly encodes the full export.
- Account identity changes clear/dismiss the detail and reader; late requests and cross-query cursors cannot overwrite current results.

## Tests and observation

Artifacts: `build/legal-evidence-audit-20261023/` (local, ignored).

- `EvidenceFinal.xcresult`: 24 iOS unit/UI tests passed, zero failures or skips. Includes paging, search continuation, exact-version/hash rejection, full export despite filtering, owner navigation, filter changes, exact recorded document opening, Ukrainian light appearance and German dark appearance with accessibility text.
- `EvidencePolished.xcresult`: both UI scenarios passed again after removing the repeated document heading and moving locale/app/source chips into technical details. Final screenshots inspected.
- `server-final.log`: 9 tests passed, zero failures or skips. Includes legacy format, 501-record history, precise cursor after deleted anchor, 61 matching accounts, deduplication, mixed chronology, null date progression, query/filter binding, permissions and analytics consent lifecycle.
- Localization, repository structure, composite-index and App Check policy validators passed; `git diff --check` clean.
- Final simulator screenshots exported and inspected. UI data are isolated fixtures, not production identities.

## Production read-back

- Four new composite indexes READY; actual read-only Firestore queries with their equality/order contracts succeed.
- `getLegalEvidencePage`, `listLegalEvidenceAccounts`, `getLegalEvidenceForUser`, `listLegalEvidence`: ACTIVE, Cloud Run Ready, intended revision receives 100% traffic, on-deploy runtime policy retained. Deployed compiled module hashes match this source build. Actual callable requests without user credentials return the expected UNAUTHENTICATED response.
- Read-only metadata audit: all 153 legal acceptance receipts reference 32 existing published version/hash combinations; stored root hashes match receipts and both translations are present.
- Authenticated application behavior was exercised in the emulator; no production owner sign-in was fabricated and no real confirmation/notification was created for testing.
- Firebase's index deployment wrapper twice received 503 from the unrelated Rules test service. Only the four specified indexes were created via the Firestore API, followed by READY/query read-back; no rules were changed.

## Delivery boundary

Backend and indexes deployed. UI changes require the next iOS build. TestFlight 1.2.1 (115) was not replaced. Legacy server formats remain supported for the installed app.
