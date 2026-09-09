# UAC 1.1 (80) — Integration and release checkpoint

Base: `fd58131` (iOS 1.0.3 build 79). Branch: `codex/uac-1.1-build80`.

## Authorized sequence

Implement confirmed outstanding audit defects, with up to six workers and exclusive shared-file ownership. Do not run individual builds or tests during implementation. After all packages are reconciled, run one consolidated verification phase, fix any failures, commit and push, deploy required backend changes, archive and upload internal-only TestFlight 1.1 (80). Android and public release follow the user's acceptance later.

## Coordinator integration

- All iOS target version settings: 1.1 (80).
- Legal notifications preserve the requested document kind, including organization rules.
- Feedback notifications route to the exact authorized ticket; guests receive unavailable state.
- Feedback composer clears on every principal change.
- Narrow Rules branch permits the owning verified active user to acknowledge only unreadForUser true to false.
- Missing banner target reports unavailable.
- Failed popup receipt prevents navigation/dismissal until retry.
- Organization deletion copy explains cascade.
- Feedback bulk clearing reads back retained DSA cases rather than emptying the UI; embedded DSA rows show retention protection.
- Account deletion copy distinguishes unknown server result from confirmed deletion with unfinished local sign-out. Failed local sign-out now removes the authenticated profile from UI state. The deletion callable uses a 330-second client deadline for its existing 300-second server deadline (SDK default is 70 seconds).

Package-specific changes and deferred validations are recorded in `Fix80-N-handoff.md`.

## Verified compatibility metadata (read-only)

App Store Connect currently lists public builds 53 (1.0), 65 (1.0.1), 68 (1.0.2); newest TestFlight is 79 (1.0.3), VALID. API access succeeded; no external group configured. Diagnostics callable routing was introduced in ef6c0f7 at build26 and is present in release53 source b3b8541 and audit68 source f28a50c. Thus package32 direct diagnostics create is closed in Rules; other audit/moderation/security writes remain unchanged.

Public legal pointers: terms2026.10 (202610), privacy2026.13 (202613), organizationRules2026.10 (202610). Existing pointers omit contentHash; all three version documents contain contentHash and complete DE/UK locale hash/content fields. Keep optional pointer hash compatibility and exact dual-format version-hash validation. No public document was changed.

## Consolidated verification gate

1. Compile backend and run meaningful unit/contract tests; validate changed Rules and destructive/concurrent workflows against disposable Firebase emulator data.
2. Build the integrated production iOS source and run app tests covering touched domains. Update obsolete expectations only when the new contract is intentional.
3. Run targeted functional journeys with result read-back and reopen/retry: feedback duplicates/unread/deep links, blocked targets, partial settings/deletion, organization decisions, legal draft conflict and banner state. Keep real legal publication, real accounts, and real payment actions outside test fixtures.
4. Check representative small-screen and accessibility layouts for reachable actions; avoid another broad scrolling audit.
5. Review final diff and exact release configuration, then commit/push and deploy affected backend/Rules with verification.
6. Archive/upload internal-only 1.1 (80), verify archive version, Apple processing, internal availability and What to Test. A build alone is not runtime proof.

Status: all 30 implementation packages are integrated (two further audit sections covered by shared packages). Consolidated verification passed. Source commits 2302211 and 98851ae pushed. Backend deployment and TestFlight release verified.

## Verification results, 2026-09-09

- Functions TypeScript compilation and App Check policy validation: passed. Existing unit run: 399 passed, 75 emulator-dependent tests skipped.
- Rules: initial run 165/175 passed. Nine Storage failures were caused by launching the emulator under a different project ID from the Storage cross-service fixture; the remaining failure expected the intentionally retired direct diagnostics write. Correct project and revised diagnostics rejection expectation: all 36 affected tests passed. Unaffected 139 tests passed in the first run.
- New registration Rules tests: 3 passed, covering atomic exact receipts, forged/incomplete receipts, immutable receipt update and older user-only bootstrap compatibility.
- Functions emulator integration: 72 passed, 11 project-specific tests skipped. Includes new Build80 concurrent moderation, replay/conflict, deleted-target unblock, protected feedback clearing, and active report deduplication scenarios. Callable handlers run with synthetic auth context; this alone is not SDK transport proof.
- Account deletion fault injection: reproduced deletion of canonical-only DSA feedback, fixed the missing canonical-case lookup, then passed the Auth-failure/resume test with real local Firestore/Auth/Storage. User root and consent state are removed; retained DSA message evidence survives; Auth deletion resumes and records completion.
- iOS app tests: 447 passed, 0 failed, 4 emulator/device-specific tests skipped. Compile integration failures were corrected before execution (async expression, Firebase error enum, shadowed error property and missing sort returns).
- Functional UI: five action journeys passed (AppLock, guest Profile, notification read/delete/navigation, organization block/undo, user detail failed-refresh/retry). SDK transport: two new journeys passed against local Auth/Functions/Firestore: moderation receipt replay/stale decision/role isolation/deleted-target unblock, and exact mirrored published legal documents through strict server/hash validation. Small-screen accessibility recheck passed on 375×667 after fixing a scrolling-away notification close button (six UI journeys passed total). Physical-device notification delivery, biometric/passcode hardware and final manual TestFlight acceptance remain separate.

- Dependency-aware backend scope is recorded in `Fix80-backend-deploy.json`: 28 functions and Firestore Rules. The unrelated `cleanupUnverifiedAccounts` schedule exists in base79 source but is absent from the live project and will not be newly activated by this rollout.

## Deployment verification

- 28 Functions deployed successfully and read back ACTIVE; all 28 source hashes changed, including one newly created reviewContentModeration endpoint.
- Public unauthenticated moderation request returns the expected 401 UNAUTHENTICATED without accessing user data.
- Rules API returned 503 after applying the release. Read-back confirmed the exact tested source is active: SHA-256 709707df9f0140b5e09cbc38a1cd8be8ac872bdb616c29fa6fdef9bf8f441034. No duplicate activation was needed after reconciliation.
- Release archive succeeded: bundle at.serlest.UkrainianCommunity, version 1.1, build80, non-exempt encryption false; signature verification passed.
- API-based distribution signing lacks permission; the existing signed-in Xcode account successfully uploaded the same archive.

- Xcode-account upload succeeded (`Uploaded package is processing`, `Upload succeeded`, `EXPORT SUCCEEDED`). Apple warned about absent vendor dSYMs for FirebaseFirestoreInternal, absl, grpc, grpcpp and openssl_grpc; these are also absent from the downloaded SDK artifacts. The application dSYM is present in the archive.

- Final Apple read-back: build 57128c3a-0eb2-44a6-aa1e-e70f7453900a, version1.1/build80, VALID, not expired, internal IN_BETA_TESTING, external NOT_APPLICABLE. DE and UK What to Test localizations are present.
