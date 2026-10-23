# Saved content improvements — 2026-10-23

## Changes

- Saved content no longer deletes cards from shared news/event/organization feeds. Existing shared cards keep their interaction data; bookmark reconciliation respects changes made while a read was in flight.
- Refresh and direct removal are mutually exclusive. Pending removal completion cannot be invalidated by a concurrent refresh; account changes clear all pending state and cursors.
- Added server-backed pages of 20 markers per content kind, with bounded repository limits, document-ID cursors and lookahead. Partial pages never populate the complete session bookmark cache. Existing all-record repository methods retain their contracts for other callers.
- Search, sort and counters explicitly refer to loaded records while pages remain. Each category keeps its continuation on failure. Loaded records merge by ID without duplicates. Search uses localized matching on titles.
- Available cards support removal through the context menu. Unavailable records retain the explicit removal button. Recorded save date is shown separately from publication/event dates.
- Saved event rows use the shared multi-occurrence schedule formatter and display cancellation. Errors describe saved content rather than news; raw Firebase read failures use the common error mapper.
- Reconciliation uses ID dictionaries instead of repeated linear searches. Ukrainian/German additions use a separate string catalog.

## Verification and boundaries

Artifacts: `build/saved-content-audit-20261023/` (ignored).

- SavedFinal.xcresult: 41 checks passed, zero failures/skips. Final Ukrainian/light and German/dark/accessibility screenshots inspected. Paging-rules.log: 1 integration test passed, zero skipped, covering all three bookmark kinds.
- Regression tests added for preserving a general-feed card, 20→25 saved records without duplicates, account reset, and refresh during a suspended removal.
- UI journey uses isolated mock data: search for no match, clear search, open and return, remove from context menu; Ukrainian light and German dark/accessibility settings.
- New emulator rule test checks first/next document-ID pages and denies another account for all three bookmark subcollections.
- Repository/localization validation and diff whitespace checks pass.
- Production schema, rules and callable contracts are unchanged; no deployment, live user mutation or store upload was performed. New client behavior requires the next iOS build. Partial lists are not claimed to be globally sorted or fully searched until remaining pages are loaded.
