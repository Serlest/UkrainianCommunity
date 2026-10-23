# Project support settings: verification, 2026-10-23

## Scope and changes

Owner Profile → project support settings. Public support card still uses appConfig/donation; document schema and owner-only write authority retained.

- Normalized HTTPS domain validation, explicit 443 normalization, IDN conversion to ASCII, no credentials/IP/bare hosts/nonstandard ports. URL 2048, title 120, message 2000, button 80; enabled support requires complete Ukrainian and German text.
- Transaction compares an exact source revision derived from all stored fields and nanosecond timestamps. A stale draft cannot overwrite another device. Writes are not wrapped in a cancellation timeout. Authoritative read-back confirms persistence; lost acknowledgements are accepted only when content and author match. Unconfirmed writes require reload.
- Server-authoritative listener updates the public configuration; cached/local pending writes are excluded. Late reads cannot overwrite newer state. Listener lifetime is owned by the view model.
- Pinned Save, visible validation messages, freeze while saving, unsaved-change dialog with Save and Close, conflict notice and explicit reload/discard confirmation. Account identity changes dismiss the editor.
- Separate preview and editing language, visibility status, noninteractive card preview, explicit link check, field labels/counts/errors, translation in both directions using the existing owner-authorized callable and quotas.

## Verification

Local artifacts: build/donation-improvements-20261023/ (ignored).

- DonationSDK.xcresult: 9 passed, zero failures/skips. Includes actual Swift Firestore SDK transaction/read-back, stale-write rejection and realtime delivery against isolated demo emulator, plus view model failures/retry/conflict/stale reads and validation.
- DonationFinal.xcresult: save/reopen and German dark/accessibility UI scenarios passed. Interrupted integration run was superseded by DonationSDK; translation scenario rerun separately after making its scroll/tap positioning deterministic.
- DonationTranslationUI.xcresult: complete de→uk preview/apply/save/reopen scenario passed, zero failures/skips. Total final scoped evidence: 12 iOS tests and 6 server/rules tests passed. Ukrainian light and German dark/accessibility screenshots inspected.
- rules-final.log: 3 rule tests passed, zero skipped. Owner allowed, admin/user denied, public reads retained, malformed links and overflow rejected, boundaries accepted, enabled translations complete, server timestamp required.
- translation-final.log: 3 tests passed, zero skipped, including owner donation de→uk and outsider rejection. Provider stub checks language routing; it does not assess real machine translation quality.
- TypeScript build, repository/localization/App Check validation and git diff --check passed.
- First integration attempts exposed invalid fake Firebase key and emulator TLS configuration; fixed in test setup. No production credentials or payment transaction used.

## Deployment and compatibility

- Rules published through official Rules API after CLI preliminary test endpoint returned 503. Active rules read-back exactly matches local source: rules-readback.json.
- translateContent deployed; Cloud Run Ready, intended revision receives 100% traffic, onDeployUpdatePolicy preserved, compiled translation source hashes match; unauthenticated real callable returns UNAUTHENTICATED. See server-verification.json and callable-readback.json.
- Read-only production donation snapshot matches audit baseline in every recorded field. isEnabled remains false and existing PayPal URL unchanged.
- No App Store/TestFlight upload. Current binary remains 1.2.1 (115); editor and realtime client improvements require the next iOS build. Existing installed writer uses the retained schema/serverTimestamp and valid current payload.
- No production owner save or payment flow was exercised. Rules/SDK integration and mock UI persistence are separate evidence.
