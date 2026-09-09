# Fix80-30 — Legal document management handoff

## Scope and baseline

- Shared integration checkout: `/Users/serlest/Developer/UAC-1.1-Build80`
- Requested base: `fd58131`
- Source audit reconciled: `30-audit.md` from the frozen `f28a50c` audit snapshot
- No legal document was published and no consent, inbox, push, production, or cloud mutation was performed.

## Files changed

- `UkrainianCommunity/Models/Legal/LegalDocument.swift`
- `UkrainianCommunity/Views/Profile/LegalDocumentManagementView.swift`
- `UkrainianCommunity/Repositories/Firebase/FirestoreLegalDocumentRepository.swift`
- `Firebase/firestore.rules` — legal-document helpers and matches only
- `Docs/Fix80-30-handoff.md`

## Fixed in this package

- **D30-01 uncertain publication result:** a failed transaction response now triggers authoritative pointer/version read-back. The app treats the operation as successful only when the exact version, number, published status, and normalized content hash are active.
- **D30-03 stale and racing management refreshes:** cards cannot be opened while a refresh is pending, only the latest generation may publish results, and an error clears the old snapshot so no stale cards remain editable.
- **D30-04 silent draft overwrite:** draft writes run in a transaction and carry `baseContentHash`. An update succeeds only when the hash observed by the editor still matches the current draft hash.
- **D30-05 dirty Back:** the legal editor uses the shared pushed-screen back action. A dirty draft is saved before dismissal; a failed save keeps the editor open and shows the existing save error copy.
- **D30-06 pointer/publication invariants:** the client validates pointer identity/status, target identity/status, version-number progression, exact supersession, draft-to-published transition, and pointer/version agreement. Staged Rules require a pointer to resolve to a matching published target and constrain draft updates/publication transitions.
- **D30-07 multiple draft ambiguity:** management requests up to two drafts and fails closed if more than one exists instead of choosing an arbitrary document.
- Version generation now derives the next identifier from the authoritative numeric version where possible, and client writes reject inconsistent `YYYY.minor` / numeric-version pairs.
- The shared Firestore reader now rejects contradictory pointer/target type, status, version, number, acceptance, locale, and hash metadata. It still accepts older published records that consistently omit optional legacy metadata or all hash fields; public fallback behavior is unchanged.
- Existing published documents remain readable and immutable. Rules do not recompute SHA-256; they validate SHA-256 shape and graph metadata, while the app computes canonical hashes.

## Already fixed outside this package

- **D30-13 AXXXL layout:** the shared `PushedScreenShell` currently places its header inside the vertical scroll area at accessibility text sizes. This file was owned by another worker and was not edited here.

## Stored field and dependency notes

- New Firestore version field: `baseContentHash` (`null` for a new draft; the previously observed content hash for draft updates and publication).
- `LegalDocument` now decodes the existing `supersedesVersion` field so a loaded draft retains its publication base.
- `CryptoKit` is imported by the legal model for the same normalized SHA-256 calculation used by the repository.
- No repository protocol signature, localization key, public legal copy, or external API dependency changed.

## Remaining work and validation boundary

- `Firebase/firestore.rules` is staged source only and still requires the normal Rules validation and deployment workflow.
- Firestore Rules cannot enforce query-wide uniqueness of draft documents. The client now detects two or more and blocks management; a callable or canonical draft document ID would be needed for server-enforced single-draft uniqueness.
- D30-02 notification routing, D30-08 effective date, D30-09 immutable history UI, D30-10 fan-out disclosure, D30-11 empty-locale preview explanation, D30-12 Android parity, and the owner MFA/email-remediation gap remain outside this ownership package.
- For the follow-on 19/20 reader and acceptance work, this package covers only Firestore pointer/target metadata and stored-hash consistency. Mandatory acceptance, registration remote-version/fallback behavior, and initial receipt logic still require their own review.
- Build, tests, Simulator, Rules lint/emulator, dependency operations, commit, push, deploy, and production reads/writes were intentionally not run per the coordinator instruction. Review in this package is source/diff inspection only.
- Runtime follow-up still needs save conflict, failed refresh, overlapping refresh, dirty Back success/failure, multiple drafts, uncertain transaction read-back, DE/UK, accessibility/VoiceOver, and disposable Rules negative cases. Actual legal publication remains prohibited for validation.

## Release note

Do not present this package as runtime-, cloud-, or release-verified. Merge it with the shared shell and route work, validate against a disposable Firebase environment, then deploy Rules before relying on the server-side invariants.
