# TestFlight 1.0.3 (77) — 2026-09-07

Source: `9cc0f66`, with build number advanced to 77. Restores the original
pre-unification card designs from `9bcf038`, including event calendar badges,
and removes the below-card news topic link and added metadata footers. Both
visual-refinement iterations are excluded. Earlier diagnostics and incomplete
content-planning fixes remain. See RestoredCardStyle-2026-09-07.md.

User requested a build; existing authorization covers the internal Beta Tester
and external Tester Serlest EXT groups. This is not a public App Store release.

Validation before packaging: Simulator build passed; Ukrainian news topic-menu,
article-navigation and date-filter UI scenario passed. Source matches the
pre-unification baseline except the requested news-footer removal. Repository
release configuration validation passed for build 77. Physical device
acceptance remains unverified.

Archive/export evidence: `output/release77/archive-upload.log`.
Archive: `build/UkrainianCommunity-77.xcarchive`.
Export configuration permits external testing.

## Archive and upload

Archive succeeded. Archived app: `at.serlest.UkrainianCommunity`, 1.0.3 (77),
non-exempt encryption false. Strict deep signature validation passed, and the
app executable UUID matches its dSYM. API-key export could not use Cloud
Signing; fallback through the existing Xcode account succeeded. Export reported
`Uploaded package is processing`, `Upload succeeded`, and `EXPORT SUCCEEDED`.

Five third-party framework dSYM warnings remain: FirebaseFirestoreInternal,
absl, grpc, grpcpp, openssl_grpc. Each archived framework has zero defined
symbol lines (`nm -U`, exit 0). The app's own dSYM is present and matches.
Evidence: `archive-check.json` and `framework-symbol-check.json` in release77
output. This was a successful upload with warnings, not a warning-free export.

## Apple read-back

Build 77: `VALID`, audience `APP_STORE_ELIGIBLE`, internal `IN_BETA_TESTING`.
Both Beta Tester and Tester Serlest EXT group build lists contain build 77.
Ukrainian (`uk`) and German (`de-DE`) What to Test texts matched on read-back.
Auto-notification enabled. Evidence: `output/release77/apple-state.json`.

External state is `READY_FOR_BETA_SUBMISSION`, not external availability.
Beta App Review submission returned 422
`ENTITY_UNPROCESSABLE.ANOTHER_BUILD_IN_REVIEW`. Fresh inventory confirms build
75 is still `WAITING_FOR_BETA_REVIEW`. Apple requires completion of that review
before accepting this submission. No prior build was expired or cancelled.
