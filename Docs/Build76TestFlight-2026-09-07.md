# TestFlight 1.0.3 (76) — 2026-09-07

## Source and scope

Built from `b86c786` on `codex/unified-content-cards-20260907`, with the project
build number advanced from 75 to 76. Includes shared news/event/organization
cards and metadata footers, accessibility layouts, the category-menu button
appearance fix and analytics-card layout changes. Previous diagnostic and
incomplete planning-draft fixes remain included.

User requested distribution to both existing internal and external TestFlight
groups. This is not an App Store public-release submission.

## Validation and archive

Card validation is documented in UnifiedContentCards-2026-09-07.md: final
15 unit/render tests and two UI scenarios passed. Physical-device acceptance
remains unverified.

Release archive succeeded with zero compiler warnings. Archived bundle is
`at.serlest.UkrainianCommunity`, version 1.0.3, build 76; non-exempt encryption
is false. Strict deep signature verification passed, and the app executable's
UUID matches its dSYM.

Archive: `build/UkrainianCommunity-76.xcarchive`.
Export configuration permits external testing (`testFlightInternalTestingOnly=false`).
The API-key export encountered a Cloud Signing permission error; the release
script's fallback using the existing Xcode account uploaded successfully.

Export reported five missing-symbol warnings for FirebaseFirestoreInternal,
absl, grpc, grpcpp and openssl_grpc. Each archived framework executable contains
zero defined symbols (`nm -U`, all commands exited 0). The app dSYM is present
and verified. The successful upload does not imply a warning-free export.

Evidence: `output/release76/archive-upload.log`, `inventory.json`, `notes.json`
and final `apple-state.json` (local, untracked output).

## Apple read-back and remaining external gate

Verified at 2026-09-07T19:48:31Z:

- Build ID `3707862c-6129-4df4-8efe-b7ffe9c5e3ab`: `VALID`,
  audience `APP_STORE_ELIGIBLE`.
- Internal group `Beta Tester`: assigned; `IN_BETA_TESTING`.
- External group `Tester Serlest EXT`: assigned; `READY_FOR_BETA_SUBMISSION`.
- Ukrainian and German What to Test text exactly matched after read-back.
- Auto-notification enabled.

Submission of build 76 to Beta App Review returned
`422 ENTITY_UNPROCESSABLE.ANOTHER_BUILD_IN_REVIEW`: build 75 is still
`WAITING_FOR_REVIEW`, submitted at 2026-09-07T19:06:46Z. The attempt to replace
that pending submission with build 76 could not proceed: the API rejected
DELETE of betaAppReviewSubmissions with 403 (only CREATE/GET allowed).
The old submission was **not** cancelled and neither build was expired.
The available App Store Connect browser was signed out, so a UI replacement
could not be inspected without user sign-in. External testing of 76 is not
available yet. It requires either completion of the previous review and a new
submission, or a supported replacement through a signed-in Apple interface.
