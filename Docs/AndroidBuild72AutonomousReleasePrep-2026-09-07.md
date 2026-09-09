# Android build 72 autonomous release preparation

Date: 2026-09-07 (Europe/Vienna)

Scope: continue from commit `2e0ee59` without changing iOS source, Firestore Rules,
production data/configuration, TestFlight or any public release.

## Completed autonomously

### Permanent upload-key release candidate

- Reused the existing permanent upload keystore outside the repository; no new or
  replacement signing identity was created.
- The keystore and Firebase build values are read from macOS Keychain by
  `Android/scripts/build-production-aab-keychain.sh`; secrets are not written to
  Gradle properties, source files, artifacts or logs.
- A fresh R8/lintVital production AAB passed signing verification with upload
  certificate SHA-256
  `C7:F9:7B:B4:BE:68:C8:5E:AD:95:A6:7D:29:35:67:08:87:4C:36:97:A6:EA:69:45:3F:78:37:D8:3F:7F:EF:BE`.
- Upload candidate:
  `outputs/android-build72/app-production-release-build72-UPLOAD-SIGNED.aab`;
  SHA-256
  `8c954eb820a97982dfd6bfddf64c9e02b12c2742e839491f54290c0eca6aad38`.
- Manifest read-back remains package `at.serlest.ukrainiancommunity`, version code
  `72`, version name `1.0.3`, min SDK 26 and target SDK 36.
- The matching signed/minified release APK installed and cold-started on the API 37
  Play AVD in 400 ms. The process remained alive and loaded current public
  production news, events and organizations.
- That smoke exposed a release-facing offline message that incorrectly mentioned a
  local emulator. Android now uses neutral German/Ukrainian user copy, protected by
  two focused tests; the full unit suite passed `1909/1909` with zero failures,
  errors or skips. A repeated release smoke contained no emulator wording and no
  fatal process signal.
- Eight localized 1080 x 1920 RGB JPEG screenshot candidates (four German, four
  Ukrainian) were captured from the signed production release under
  `Android/release/play/screenshots/` and visually inspected.

### Production-flavor build proof

- `bundleProductionRelease` completed with R8, resource shrinking and lintVital.
- Merged manifest: package `at.serlest.ukrainiancommunity`, version code `72`,
  version name `1.0.3`, min SDK 26, target SDK 36.
- All eight bundled native-library/ABI combinations have ELF `LOAD` alignment
  `2**14` (16 KiB).
- AAB SHA-256:
  `7efad10499e67fd38fc5b8837ffb7a48f986f00934d99be9afcdc775fa3b7cba`.
- Local evidence path:
  `outputs/android-build72/app-production-release-build72-EPHEMERAL-SIGNATURE.aab`.

The build used the previously generated production Firebase values only inside the
Gradle process and a two-day throwaway RSA certificate named `UAC Build
Verification`. It did not use, alter or replace the real upload keystore. The
artifact is deliberately quarantined and **must never be uploaded**.

### Staging build and smoke

- `assembleStagingDebug` passed from the previously generated configuration for the
  separate `uac-android-test-20260903` project.
- APK identity: `at.serlest.ukrainiancommunity.staging`, version `1.0.3-staging`
  (72); SHA-256
  `15bafdecec668cbd57d61ebb10f66e52dd347ff203e5bc6fc89660e7882aa400`.
- Installed beside the local package on the API 37 AVD; cold start completed in
  1.465 s, process stayed alive and the captured home screen was visually sound.
- Captured log contained no fatal exception, Firebase exception, App Check error or
  explicit permission-denied line.

This is startup proof only. Firebase CLI project/app access was subsequently
restored through the authorized Google account; an unauthenticated Firestore REST
read still correctly receives 403. No staging deployment, fixture write, account
creation or production configuration change was made.

### Physical Firebase Test Lab smoke

- Matrix `matrix-1cmv8cyvsf0fl` ran the exact staging APK on a physical Samsung
  Galaxy A35 (`a35x`), Android 15 / API 35, German locale, portrait.
- The dedicated read-only `StagingPhysicalSmokeTest` passed 1/1 in 3.278 s. It
  launched the real `MainActivity`, verified package
  `at.serlest.ukrainiancommunity.staging`, verified Firebase project
  `uac-android-test-20260903`, and found Home, Events, Organizations, Profile and
  Settings in the rendered shell.
- Raw evidence was retained under
  `outputs/android-build72/testlab/matrix-1cmv8cyvsf0fl/`; the cloud result page is
  tied to Firebase matrix `4660116178651670227`.
- The initial matrix deliberately exposed the next gate: its generated App Check
  token was not registered, so token exchange returned HTTP 403
  `App attestation failed` even though the shell test passed.
- The test was hardened with Firebase's CI `DebugAppCheckTestHelper` and a
  staging-only dependency. Matrix `matrix-2bdsgms123cgc` then failed because the
  helper registrar was confined to the test APK; this was a diagnosed harness
  packaging failure, not an application crash.
- After moving the registrar to the staging application only and aligning its
  AndroidX Test runtime, the same hardened check passed locally and on the physical
  A35 in matrix `matrix-2xludxv1o4xoj` (Firebase execution
  `5110753193396570288`): 1/1 passed in 3.383 s.
- The final log contains zero UAC fatal-process signals and zero App Check exchange,
  attestation, token-fetch or retry failures. APK SHA-256 values were
  `ea93c4b3cd5ef8b74b037b847d7d9c3f2a91f6423faa4d6c94d56b587280830f`
  (app) and
  `db928a7424b1784ad0afc6ba7f6be00ee152bfc51e21a508f543b57701117dbd`
  (test).

This upgrades physical startup/navigation and staging App Check token exchange to
passed. It still does not claim authenticated Auth/Firestore/Functions/Storage/FCM
acceptance, Play Integrity from a Play-installed release, or interactive OEM proof.
The registered debug secret was supplied only as a transient test-runner argument;
it was not printed, stored in an artifact or committed.

### Play preparation

- Updated the listing and conservative Data Safety draft for 1.0.3 (72), including
  announcements, acknowledgement/action receipts, FCM installation challenge and
  translation behavior.
- Created and visually checked the exact-size, no-alpha store icon and feature
  graphic under `Android/release/play/`.
- Prepared bilingual cross-platform privacy/terms wording as an approval-only
  document; published iOS legal versions remain unchanged.

### iOS-priority regression guard

- The diff from the iOS build 72 base commit `5b0ba56` contains no Swift,
  Xcode-project or iOS application-path changes.
- On the `iPhone 17 Pro` simulator (iOS 26.4.1), all eight selected
  `AnnouncementTests` and `ContentTranslationTests` unit checks passed.
- All three selected UI flows passed: owner bilingual announcement creation,
  guest announcement popup/history, and the real news editor translation/preview.
- The two `.xcresult` summaries report 8/8 unit and 3/3 UI tests passed, with no
  failure, skip or expected failure.

This is targeted regression evidence for the iOS features shared with Android. It
does not replace the already separate TestFlight, physical-iPhone or App Review
evidence levels, and no iOS source or release state was changed.

### Live public-page read-back

| URL | Result | Release meaning |
| --- | --- | --- |
| `/privacy` | HTTP 200, version 2026.13, explicitly iOS-only | BLOCKED for Android |
| `/delete-account` | HTTP 404 | BLOCKED for Play submission |
| `/support` | HTTP 200, live wording still iOS-only | BLOCKED until scoped deploy/read-back |
| `/report-illegal-content` | HTTP 200 | Available; submission behavior still needs final acceptance |

The repository support/deletion source already contains cross-platform wording;
the difference is deployment state. No Hosting deployment was attempted.

## Remaining gates requiring owner access or approval

1. Use the staging Firebase access and the proven staging-only App Check
   CI path to run authenticated Auth/Firestore/Functions/Storage/FCM acceptance.
2. Complete Play internal distribution and interactive device checks for Play
   Integrity, background notification, biometric, TOTP, email-link, Storage and
   corporate/OEM behavior. Test Lab has proven physical startup and App Check only.
3. Approve the bilingual cross-platform legal candidate and its immutable version;
   only then perform a scoped Firestore/Hosting publication with hash/read-back and
   iOS regression verification.
4. Wait for Google to approve the newly submitted personal-account identity
   verification, then confirm the contact phone and any remaining real-device task.
5. Create the Play app, complete reviewer accounts/declarations, and start the
   required closed test with at least 12 continuously opted-in testers for 14 days.
6. Reconfirm that every photo visible in the screenshot candidates has explicit
   store-marketing reuse rights; replace uncertain captures before upload.

## Updated readiness

- Functional parity against iOS build 72: **95%**.
- Release engineering readiness: **91%**.

The increase reflects the permanent-key signed AAB, reproducible Keychain-backed
build, minified production runtime smoke, corrected release copy, full unit rerun
and localized screenshot candidates. Authenticated cloud workflows, interactive
Play/OEM acceptance, legal approval, screenshot rights review, Play verification
and the mandatory closed-testing period remain blocking; therefore this is still
not a publicly releasable build.
