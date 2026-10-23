# Legal documents: implementation verification, 2026-10-23

## Delivered source

- Independent loading of all three documents; one failure does not expose fallback text as editable authoritative content or hide the other cards.
- Incomplete drafts retain integrity and can be saved, reopened and explicitly discarded. Published versions remain immutable. Concurrent writes and lost save acknowledgements are checked against authoritative data.
- Persistent editor labels, safe close choices, pinned save and action menu, privacy acknowledgement wording, preview, active document reader, paginated published history and line comparison.
- German/Ukrainian translation in both directions, bounded provider batches and preserved Markdown/link/code structure. Limits and actual provider input remain subject to existing quota checks.
- Durable legal-publication delivery cursor: at most 100 accounts per event, stable notification IDs, retry-safe progression, skip superseded publications. Existing inbox/push routing retained.

## Automated and visual evidence

Artifacts: `build/legal-documents-audit-20261023/` (local, ignored).

- `LegalComplete.xcresult`: 26 iOS unit/UI tests passed, zero failures/skips. Includes owner draft save/reopen, close without saving, explicit draft deletion, German dark mode with accessibility text, account-switch races, offline/legal gating and notification routing.
- `LegalPartialSummary.xcresult`: 5 affected unit/UI tests passed after the final partial-summary fix; explicitly saves only the German summary, leaves, reopens and confirms preservation before discarding.
- `server-final-tests.log`: 20 server/rules/translation tests passed, zero failures/skips.
- `fanout-tests-v2.log`: 103-account emulator delivery/retry/supersession test passed.
- Live Google Translate sample preserved protected Markdown markers.
- Localization, repository, composite-index and App Check policy validators passed.
- Deployed analytics compatibility/release configuration validation passed for existing build 115.
- Screenshots exported from the passing UI suite and inspected, including Ukrainian/light and German/dark/accessibility text.

## Production read-back

- `translateContent`, `notifyLegalDocumentsUpdatedOnPublish`, `deliverLegalPublicationBatch`: ACTIVE, Cloud Run Ready, intended revision receives 100% traffic, on-deploy runtime update policy retained; deployed relevant source hashes match local build.
- Eventarc document paths, locations and retry policies verified.
- Active Firestore rules match local source; owner can delete draft versions only.
- No new legal text published, no synthetic notification or user created in production.

## Delivery boundary

Backend and rules deployed. New iOS interface is source-only until the next requested build; TestFlight 1.2.1 (115) was not replaced by this task. Emulator delivery validates fanout and inbox writes; this task did not send a real publication push to a physical device.
