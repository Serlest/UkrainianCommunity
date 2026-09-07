# TestFlight 1.0.3 (78)

Source: `c003caa` (user-management fixes), with the build number advanced to 78.
The original news/event/organization card styles from build 77 are preserved.
No backend deployment or public App Store release is part of this build.

User requested a new build; existing release scope covers internal `Beta Tester`
and external `Tester Serlest EXT` testing groups.

Validation: release configuration and Ukrainian/German localization checks
passed. The preceding user-management audit includes 29 passing selected iOS
tests, two passing detail-refresh UI scenarios, a passing regression scenario
for horizontal drag/search failure/recovery, and 16 passing backend unit tests.
See `UserManagementAudit-2026-09-07.md` for the actual coverage and limitations.

Artifacts: `output/release78/archive-upload.log`,
`build/UkrainianCommunity-78.xcarchive`.
Export configuration allows external testing and keeps build number 78 fixed.

Apple inventory before upload: build 77 VALID; build 75 still
WAITING_FOR_BETA_REVIEW. No existing build was expired or withdrawn.

## Archive and upload

Archive succeeded. Archived app identity is `at.serlest.UkrainianCommunity`,
1.0.3 (78), with `ITSAppUsesNonExemptEncryption=false`. Strict deep signature
verification passed and the app executable UUID matches its dSYM.
Evidence: `output/release78/archive-check.json`.

API-key export encountered the existing Cloud Signing permission issue.
Fallback through the signed-in Xcode account succeeded, reporting
`Uploaded package is processing`, `Upload succeeded`, and `EXPORT SUCCEEDED`.
Upload completed at 23:55 Europe/Vienna on 7 September 2026.

Five third-party dSYM warnings remain: FirebaseFirestoreInternal, absl, grpc,
grpcpp and openssl_grpc. Each archived binary reports zero defined symbol
lines via `nm -U` (exit 0). The app's own dSYM is present and matches.
Evidence: `output/release78/framework-symbol-check.json`.

## Apple read-back (8 September, Europe/Vienna)

Build ID `70068233-b37f-4e71-b0f2-b34850d51c6f`, build 78, processing `VALID`,
audience `APP_STORE_ELIGIBLE`, internal state `IN_BETA_TESTING`.
Both `Beta Tester` and `Tester Serlest EXT` group build lists contain build 78.
What to Test text in `uk` and `de-DE` matched on read-back; auto-notification is
enabled. Evidence: `output/release78/apple-state.json`.

External state is `READY_FOR_BETA_SUBMISSION`, not external availability.
The review submission returned 422 `ENTITY_UNPROCESSABLE.ANOTHER_BUILD_IN_REVIEW`:
Apple requires the existing review in this version train to finish first.
Current inventory confirms build 75 remains `WAITING_FOR_BETA_REVIEW`.
No earlier build was expired, withdrawn, or removed from testing groups.
