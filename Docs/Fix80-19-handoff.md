# Fix80-19 handoff — Legal reader and acceptance (sections 19 + 20)

## Scope and Build 79 comparison

- Baseline: `fd58131` (Build 79).
- Package 30 already implemented legal pointer/target/version/hash consistency, draft conflict protection, publication invariants, and management state reconciliation. This package preserves those changes and does not reimplement them.
- The remaining source-proven defects were:
  1. Markdown tables in the Privacy Policy were rendered as raw pipe-delimited paragraphs.
  2. Mandatory acceptance loaded through the repository method that can return a bundled fallback and cleared the gate on read failure.
  3. Registration displayed static version constants, then created a user document claiming acceptance without an immutable initial acceptance receipt.
  4. Package 30's management reads and uncertain-publication read-back used default Firestore reads, so cached snapshots could be mistaken for authoritative server state.
  5. The legal seed script removed the controlled version/publication/effective-date line from the document body and used a canonical document-hash input different from the repository validator.

The retained user UID in immutable acceptance evidence was not treated as a defect. No public legal wording was edited or published. Android remains deferred.

## Implemented behavior

### Reader and table rendering

- `LegalMarkdownRenderer` recognizes a Markdown table only when a header, a valid delimiter row, and at least one equal-width data row are present.
- Compact tables use a SwiftUI grid. When the grid does not fit, the same data becomes stacked header/value groups, so long German/Ukrainian cells and accessibility text sizes do not require horizontal clipping.
- Each compact data row receives a header-associated accessibility label. Inline Markdown continues to work in headers and cells.
- Malformed pipe text remains an ordinary paragraph rather than being silently discarded.
- Bundled legal documents now retain the existing source metadata line, including the effective date. The seed script will retain and hash that same line for future controlled publications. No existing remote document was modified or republished.
- The coordinator-owned `organizationRules` reader kind in `LegalViews.swift` is preserved.

### Authoritative reads and hash compatibility

- `LegalDocumentRepository` now exposes `fetchAuthoritativeActiveDocument`.
- The public reader path keeps normal Firestore cache behavior and its explicit bundled fallback/error notice.
- Management active-document reads, draft queries, mandatory acceptance checks, registration checks, uncertain publication reconciliation, and uncertain registration reconciliation explicitly use `source: .server`.
- Hashed documents must have a document hash and every locale hash. Locale hashes are recomputed from normalized Markdown.
- The document hash is accepted only when it matches one of two known canonical inputs:
  - current: locale, trimmed title, normalized Markdown, locale hash;
  - legacy seed: the same fields plus `contentText` before the locale hash.
- A mismatch against both formats is rejected. New seed output uses the current format. There is no shape-only success path for a missing or partial hash set.

### Mandatory acceptance

- Terms and Privacy are fetched from the authoritative server path.
- If either read fails or validation fails, the compliance modal remains blocking with the existing load-error text and a Retry action.
- The unavailable state contains no documents and therefore cannot execute an acceptance write.
- Retry repeats the authoritative check. Decline/sign-out behavior and partial successful reacceptance handling remain unchanged.

### Registration and initial receipts

- Registration loads authoritative active Terms and Privacy documents before enabling their consent toggles or account creation.
- The version labels and document links use those exact in-memory documents; opening a link cannot silently refetch different text.
- A document-version change resets both consent toggles.
- The registration draft carries the displayed versions and validated document hashes instead of the Build 79 constants.
- `users/{uid}` and deterministic Terms/Privacy entries in `legalAcceptanceLogs` are created in one Firestore batch. A partial profile/receipt result is impossible.
- Each receipt contains UID, type, displayed active version, server acceptance time, app version, app locale, validated document hash, and `ios` platform.
- A lost batch response counts as success only after an exact server read-back finds the profile and both matching receipts.

### Firestore Rules and compatibility

- The existing Build 79/Android `safeUserCreate` contract is unchanged, so older clients may still create only their user document.
- The new receipt permission is additive and create-only. It requires:
  - the authenticated UID and deterministic receipt ID;
  - exact fields/types, `request.time`, iOS platform, and a DE/UK locale;
  - a user document that did not exist before the request and is created in the same batch;
  - both Terms and Privacy receipts in that same batch with matching server timestamps;
  - matching accepted versions/timestamps in the new user document;
  - the referenced active, published legal pointer/version and exact SHA-256 document hash.
- Client updates/deletes of receipts remain denied. A later standalone client write cannot manufacture an initial receipt.
- Package 7 dependency was merged exactly: `recentViewFields` and `safeRecentViewWrite` now accept an optional string/null `organizationID`, while legacy rows remain valid.

## Files and shared ownership

- `UkrainianCommunity/Components/LegalMarkdownRenderer.swift`
- `UkrainianCommunity/Repositories/RepositoryProtocols.swift`
- `UkrainianCommunity/Repositories/Firebase/FirestoreLegalDocumentRepository.swift` (extends package 30)
- `UkrainianCommunity/Resources/LegalDocuments.json`
- `functions/scripts/seedLegalDocuments.mjs`
- `UkrainianCommunity/Services/Auth/LegalComplianceMonitorService.swift`
- `UkrainianCommunity/Views/Profile/LegalComplianceView.swift`
- `UkrainianCommunity/Services/Auth/AuthService.swift` (only the registration draft hash fields; package 16 verification notice and package 21 deletion recovery preserved)
- `UkrainianCommunity/Services/Auth/UserProfileService.swift` (registration batch/read-back only; package 21 deletion journal preserved)
- `UkrainianCommunity/Views/Profile/AuthViews.swift` (registration/consent only; package 16 verification UI and package 21 completion message preserved)
- `Firebase/firestore.rules` (package 30 legal rules preserved; package 7 optional `organizationID` dependency included)

`LegalViews.swift`, `AppStrings.swift`, `Localizable.xcstrings`, routing, and the Xcode project were not edited by this package.

## Localization keys

No UK/DE/EN key was added or changed. The implementation reuses:

| Key | UK | DE | EN source fallback |
| --- | --- | --- | --- |
| `action.retry` | Спробувати ще раз | Erneut versuchen | Спробувати ще раз |
| `legal_compliance.error.load_failed` | Не вдалося перевірити актуальні юридичні документи. | Die aktuellen rechtlichen Dokumente konnten gerade nicht geprüft werden. | Unable to check the current legal documents right now. |
| `auth.consent.accept_terms` | Я приймаю Умови користування | Ich akzeptiere die Nutzungsbedingungen | I accept the Terms of Use |
| `auth.consent.accept_privacy` | Я прочитав(-ла) Політику конфіденційності | Ich habe die Datenschutzerklärung gelesen | I have read the Privacy Policy |
| `auth.consent.review_terms` | Прочитати умови користування | Nutzungsbedingungen lesen | Read Terms of Use |
| `auth.consent.review_privacy` | Прочитати політику конфіденційності | Datenschutz lesen | Read Privacy Policy |
| `auth.consent.current_terms_version` | Версія умов користування %@ | Version der Nutzungsbedingungen %@ | Terms version %@ |
| `auth.consent.current_privacy_version` | Версія політики конфіденційності %@ | Datenschutz-Version %@ | Privacy version %@ |

## Required unified verification scenarios

1. Open Terms and Privacy online in DE and UK. Confirm the title, version, metadata/effective-date line, body, and server publication date are coherent.
2. Open the Privacy Policy table in regular width. Confirm three aligned columns, inline formatting, and complete rows.
3. Repeat the table at Accessibility XXXL and a narrow width. Confirm stacked header/value groups, full wrapping, scroll to the last row, and no horizontal clipping.
4. With VoiceOver, confirm compact table rows announce each header with its cell value and stacked rows retain understandable reading order.
5. Open Terms/Privacy with no server and no cache. Confirm the full bundled document, version/effective-date metadata, offline notice, and Retry remain visible.
6. Supply a pointer/target mismatch, locale-hash mismatch, current canonical document-hash mismatch, and legacy canonical document-hash mismatch. Each must be rejected; a valid current hash and a valid legacy-seed hash must load.
7. Open legal management offline or with cache only. Confirm it fails instead of presenting cached state as current.
8. Simulate a lost publish response with only cached matching data. It must remain failed. Repeat with matching server pointer/version/hash; reconciliation may succeed.
9. For an authenticated user already on current versions, confirm no compliance gate.
10. Publish a newer acceptance-required Terms version in a test backend. Confirm the exact server document appears in the blocking gate and acceptance records that version.
11. Make either mandatory document server read fail. Confirm the modal stays blocking, shows Retry, and cannot accept an empty/fallback requirement.
12. Restore the server and retry. Confirm the requirement is reevaluated and normal acceptance or dismissal follows.
13. Open registration online. Confirm consent toggles and submit remain unavailable until authoritative Terms and Privacy load.
14. Confirm registration version labels and both document links show the same versions/text/hashes later submitted.
15. Change an active legal pointer after registration loaded but before submit. Confirm Rules reject the atomic batch and no user/receipt subset is created.
16. Complete registration. Confirm one user document plus exactly two deterministic initial receipts, with matching UID, type, version, server time, locale, platform, app version, and hashes.
17. Attempt a user-create batch with only one receipt, a later standalone receipt, a wrong hash/version/type/ID, or client update/delete. Confirm denial.
18. Use the unchanged Build 79/Android user-create payload without receipts. Confirm registration compatibility remains allowed.
19. Simulate a lost registration-batch response. Matching server profile plus both receipts is success; cache-only, partial, or mismatched read-back remains failure.
20. Recheck package 16 pending/email-sent verification states and package 21 account-deletion local recovery after the shared Auth files are integrated.
21. Recheck package 7 recent views: new optional `organizationID` string/null writes pass, and old rows without the field remain readable/writable under the prior identity rules.

## Verification boundary

- Implementation and scoped diffs were read manually.
- Per package instruction, no tests, build, Simulator, linter, dependency install, commit, push, deployment, public legal publication, or Android work was performed.
- Runtime, test-cloud, deployed Rules, production data, device behavior, and release readiness remain NOT VERIFIED until the coordinator's unified validation.
