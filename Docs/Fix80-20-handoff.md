# Fix80-20 handoff — Privacy reader cross-check

## Scope

Short source-only cross-check of the prior section 20 iOS Privacy findings against `Fix80-19-handoff.md`. Baseline remains `fd58131`; Android wording, public legal publication, Rules, Auth state/service/views, localization, routing, builds, tests, and Simulator work were outside this slot.

## Covered by package 19

- **D20-01 table rendering:** `LegalMarkdownRenderer` now parses valid equal-width Markdown tables, uses a compact grid when it fits, falls back to stacked header/value groups, retains inline Markdown, and supplies row/header accessibility context. Malformed pipe text remains a paragraph.
- **D20-02 remote version/body integrity:** the Firestore reader validates pointer/version consistency, every supplied locale hash, and the document hash against the current or known legacy canonical input before returning a remote document. A failed reader load shows the bundled document under its bundled version plus the existing offline/error notice.
- **D20-03 static registration authority:** registration loads authoritative server Terms and Privacy documents, binds links/labels/toggles to those instances, resets consent after a version change, and submits their versions and hashes.
- **D20-04 initial receipt:** user creation and deterministic Terms/Privacy receipts are one batch; the receipts contain server time, version, app version, app locale, platform, and validated document hash. Lost-response reconciliation uses server reads.
- **D20-05 effective metadata:** bundled generation and the seed script retain the controlled version/publication/effective-date line inside the hashed Markdown body.
- The shared `PushedScreenShell` integration now places accessibility-size headers inside the vertical scroll view, addressing the prior AX XXXL fixed-header reachability risk. Runtime proof remains coordinator-owned.

## Narrow remaining fix

`FirestoreLegalDocumentRepository.hasValidContentHashes` previously accepted a correctly hashed document with only one arbitrary locale, or with an empty title/Markdown. Registration receipts record `AppLanguage.stored`; such a document could display a fallback locale while the receipt recorded DE or UK.

The repository validator now requires:

- every locale supported by `AppLanguage` (currently `de` and `uk`);
- `defaultLocale` and any `canonicalLocale` to exist in the payload;
- non-empty normalized title and Markdown for every locale;
- the existing exact locale and dual canonical document hashes.

The coordinator's read-only production metadata is compatible: active Terms `2026.10`, Privacy `2026.13`, and Organization Rules `2026.10` version documents all contain `de` and `uk` payloads with title, Markdown, text, and locale/document hashes. Their pointer documents do not contain `contentHash`; this remains supported because validation reads the hash from the selected version document and does not require one on the pointer.

The registration hash chain preserves the stored version hash exactly. `hasValidContentHashes` recomputes current and legacy candidates only for comparison and returns the decoded document unchanged. `RegistrationLegalDocumentsViewModel` retains that document, the registration draft copies `termsDocument.contentHash` / `privacyDocument.contentHash`, and `UserProfileService` writes those same values to the deterministic receipts. A legacy-seed hash is therefore validated but is not replaced by the current recomputation.

Only `UkrainianCommunity/Repositories/Firebase/FirestoreLegalDocumentRepository.swift` was changed by slot 20.

## Dependencies and verification boundary

- Coordinator verification should retain package 19 scenarios for current/legacy document hashes and add missing-DE, missing-UK, unknown-only locale, missing default/canonical locale, empty title, and empty Markdown rejection cases.
- The existing registration/Rules scenarios must still prove atomic profile plus two receipts and Build 79 compatibility. Slot 20 did not edit `Firebase/firestore.rules`, `AuthState.swift`, `AuthService.swift`, `AuthViews.swift`, `UserProfileService.swift`, localization, project, or routing.
- Public Privacy wording, Android scope, remote publication, and production read-back remain deferred.
- Per instruction, no tests, build, Simulator, linter, install, commit, push, deploy, or publication was run.
