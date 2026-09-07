# Build 75 integration — 2026-09-07

The user requested build 75 after build 74 had already uploaded, to include
completed changes from the task “Проверь сегодняшние ошибки”.

## Included source

Commit `094d6e6` integrates the exact eight tracked-file changes from the original
working copy, plus the new classifier tests and two incident reports. The four
new localization entries were merged by key, preserving the news and editor
translations already present in this release worktree.

- Home news topic/date/order/personal filters and search compatibility from build 74.
- Structured network/callable diagnostics and localized MFA/network failure hints.
- Archive/delete controls for incomplete unpublished planning drafts, retaining
  confirmation dialogs and server authorization/lifecycle checks.

The original working copy and its uncommitted edits remain unchanged.
No additional production data, Functions or Rules changes are needed.

## Validation

- Full Swift regression: **441 tests in 46 suites PASS** on combined build 75.
- The first runner launch failed with Simulator Busy before tests started. After
  booting the simulator and waiting for boot completion, the same built test
  products passed; no application code changes were needed for this retry.
- Final combined-build UI regression: **2/2 PASS**, German topic/type/reset and
  Ukrainian period/topic/detail/cancel navigation. Evidence: build75-ui.log.
- All seven repository validators passed. The legal validator also reports
  existing public-release gates; this upload does not claim those gates closed.
- Earlier news-specific UI scenarios, 175 Rules tests and 40 live read-only query
  combinations are documented in NewsBrowseFilters-2026-09-07.md.
- Physical-device acceptance remains separate and has not been performed here.

Evidence: output/announcements/build75-tests-retry.log,
build75-validators.log, archive75.log and export75.log.

## Release

Archive `/tmp/UAC-news-browse-75.xcarchive` succeeded with zero compiler warnings
and errors. Strict code signature and app dSYM UUID matching passed. Version
1.0.3, build 75, non-exempt encryption false. Source commit: `094d6e6`.

Upload succeeded. Export reports five existing symbol warnings for the embedded
FirebaseFirestoreInternal, absl, grpc, grpcpp and openssl_grpc framework stubs.
Each has zero defined symbols; UAC app dSYM is present. No fabricated symbols or
symbol-upload suppression were introduced. This is not a zero-warning export.

Apple verification at 2026-09-07T17:40:34Z: **VALID / IN_BETA_TESTING**.
Build ID: `90efa509-aafc-4426-bd9b-008f50281315`.
uk/de-DE What to Test written and exact readback verified. Evidence:
output/announcements/testflight75-apple.json. Build 75 supersedes 74.
No App Review submission or public release.
