# Android parity with iOS 107 checkpoint

The Android working branch starts from the current UAC `main` source and restores the exact Android product tree used for Google Play Internal build 86. It is a development baseline for bringing Android to the product behavior of iOS 1.2 build 107. No new Android release has been built or uploaded.

## Source baseline

- Working branch: `codex/android-parity-1.2-107` in `/Users/serlest/Developer/UAC-Android-1.2-Parity107`.
- Shared iOS, Firebase, Functions, legal and website baseline: `main` at `b088ff2f013e9f42ffcdbf51163f8659869474a1`. The iOS source matches `release/1.2-107` at `1332693087fa6257855560097fb58520c0664910`; only two news coordination scripts differ under `functions/`.
- Android source baseline: the peeled `android-1.1-build86-play-internal` tag at `cda63d6e03b95bacbff405c5539f7fd8acc75989`. Before subsequent edits, `git diff` against this commit under `Android/` reported zero paths.
- Google Play Internal build 86 remains the latest confirmed Android release. Its version is `1.1`, code `86`, package `at.serlest.ukrainiancommunity`. The version has not yet been increased in this branch.

The old Android tree in `main` identified itself as `0.1-local` with version code `1`. Restoring the tagged Android tree preserves its production, staging and local build variants, signing and Play assets, push implementation and Build 86 functionality. The existing Build 86 checkout and the main working tree were not edited.

## Changes reconciled from main

The two Android source commits made after the Build 86 source were applied on top of the restored tree:

1. `5f4843a` adds `inProgress` and `done` feedback statuses, their localized labels and inbox grouping. Its existing status test was carried over.
2. `9364603` requires acknowledgement when the published Terms or Privacy version differs from the account receipt, even when an older `requiresAcceptance` flag is false. Its legal regression test was carried over.

The first full JVM run found two outdated test fixtures. The saved-news fixture used a fixed 8 September publication time inside a rolling 30-day filter; it now uses the current publication time for this membership test. The account deletion race test expected a new login to be fully ready without accepted legal versions; its specific synthetic account now has receipts for both current documents. Production logic was unchanged by these fixture corrections.

## Verification

- `:app:assembleLocalDebug`: passed.
- `:app:testLocalDebugUnitTest`: 1,951 tests in 119 suites, zero failures, errors or skips after fixture correction.
- `:app:lintLocalDebug`: passed.
- `git diff --check` and staged diff whitespace checks: passed.

These results establish local compilation and unit behavior only. They do not establish compatibility with live production Firebase, visual parity with iOS 107, physical Android behavior or a new Play release.

## Next package

Capture and inspect matching iOS 107 and Android baseline screens and scenarios: required sign-in, News, Events, Organizations, Directory, Profile and owner tools. Record each route's data source, access rule, action result, error and empty state. Check Ukrainian and German, light and dark themes, 100% and 200% font, compact and wide devices, then prioritize the observed gaps before implementing the new Android flows.
