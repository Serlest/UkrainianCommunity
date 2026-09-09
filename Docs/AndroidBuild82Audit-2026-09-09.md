# Android 1.1 (82): iOS 82 alignment, UI repair and internal-test candidate

Reference iOS: `4f4ab98` (1.1 / 82). Android release lineage: `47aa343` (1.1 / 80, Google Play Internal testing).

## Scope and safety boundary

The Android 80 release lineage was merged into the current iOS 82 line before the Android 82 changes. Product edits are confined to `Android/**`; this document and the Android status index are the only non-product additions. No iOS, Firebase Functions, Firestore/Storage Rules, production document, tester membership, open/closed track or public release was changed.

The app continues to use the existing shared Firebase project and shared production collections. Production access during this pass was read-only. Emulator app data was cleared only on owned AVDs.

## Implemented changes

- Identity: `versionName 1.1`, `versionCode 82`.
- Cold-load banner: when asynchronously loaded banners first become available while the user is still at the top, the list reveals item 0. The app no longer retains the filter row above the newly inserted banner. Deliberate deep scrolling is not interrupted.
- Organization media: Firebase Storage HTTPS URLs with an explicit default `:443` port are accepted. Organization cards use the same tolerant fallback order as iOS (`logo -> image -> cover`); detail hero uses `cover -> image -> logo`.
- Compact layout: home/list/category filter surfaces and the bottom navigation were reduced visually while Material semantic touch targets remain at least 48dp. Extra bottom content clearance prevents feed content from meeting the navigation bar.
- Unit coverage was added for banner reveal policy, explicit-port media policy and organization image fallback order.

## Root-cause evidence

- The banner existed in the loaded data but was inserted before the stable keyed filter item. Compose retained the filter's scroll position, leaving the new banner above the viewport.
- Production organization records that showed placeholders used the same Firebase Storage bucket as working records but encoded URLs with `https://firebasestorage.googleapis.com:443/...`. The Android allowlist accepted only an unspecified port (`-1`). Read-only Firestore inspection and signed production runtime on API 37 reproduced this distinction.

## Verification

### PASS

- JVM: 116 result XML files, 1,934 tests, 0 failures/errors/skips.
- `assembleLocalDebug` and `lintLocalDebug`: PASS; lint 0 errors, 78 warnings, 1 hint.
- API 37 targeted affected UI: 16/16 PASS.
- API 26 / Android 8 compatibility target: 36/36 PASS at 200% system font.
- API 26 isolated follow-up for the sole full-suite timeout: 1/1 PASS.
- Signed production build: `assembleProductionRelease` and `bundleProductionRelease` PASS, including R8 and lintVital.
- Signed Build 82 production APK on API 37 against read-only production data: banner visible on cold home load; previously blank organization card artwork loads; organization detail artwork loads; all four bottom navigation destinations are visible and feed clearance is retained.

### Historical FAIL / environment-sensitive runs retained

- API 37 component run at 100% font: 293/299 passed. Four tests required the documented 200% font setup; two IME checks timed out.
- API 37 at 200% font: 294/299 passed. All five remaining failures were soft-keyboard visibility timeouts on the AVD and remained after enabling the emulator keyboard setting. Product behavior is not claimed PASS from those five checks.
- API 26 full component run: 298/299 passed; the sole status-confirmation timeout passed immediately as an isolated 1/1 rerun. This establishes no reproducible product failure but is not relabeled as a green 299/299 run.

### NOT VERIFIED

- Physical user-device installation/runtime, TalkBack and real hardware keyboard/IME behavior.
- Positive real TOTP owner/admin workflows and destructive production writes.
- Full screen-by-screen iOS 82 visual parity; this pass targeted the reported launch/banner, media and density defects.
- Google-Play-installed Build 82 runtime until a tester installs the published artifact.
- Previously documented parity gaps such as complete activity-history recovery, DSA action workflows and legal-document editing remain open unless separately verified.

## Production artifacts

- AAB SHA-256: `e3b2836a55f73927d0c38ef5a1a6a496ecdc89d56f7ebc70ca05f44d3b89ca6f`
- APK SHA-256: `b4eb415e40758a26cc1ece001cf65eb3fbbd38fe68f6f5aa7c2b6b2f026da66d`
- Output directory: `/Users/serlest/Documents/Codex/2026-09-09/82-82/artifacts`

## Google Play Internal testing — 2026-09-09

- Google Play accepted version 82 and immediately published release **1.1 (82) – Internal** to the existing internal track `4701365572505552935`.
- Final Console read-back: track **Aktiv**, latest release **1.1 (82) – Internal**, **Für interne Tester verfügbar**, published 9 Sept. 21:53 (Console display).
- Device support compared with Build 80: 0 phones, tablets, TV, Auto, Chromebook or Android XR devices removed.
- The only warning is the same nonblocking native-debug-symbol recommendation; ReTrace mapping is attached to the bundle.
- Tester link: https://play.google.com/apps/internaltest/4701365572505552935
- Existing tester membership was unchanged. No open/closed test, production/public release, iOS/backend deployment or production-data write was performed.
- Receipt: `/Users/serlest/Documents/Codex/2026-09-09/82-82/build82-play-internal-receipt.json`.

Play-installed runtime on a physical tester device remains NOT VERIFIED until a tester downloads and exercises this published artifact.
