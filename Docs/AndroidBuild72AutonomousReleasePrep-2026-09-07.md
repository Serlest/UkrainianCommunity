# Android build 72 autonomous release preparation

Date: 2026-09-07 (Europe/Vienna)

Scope: continue from commit `2e0ee59` without changing iOS source, Firestore Rules,
production data/configuration, TestFlight or any public release.

## Completed autonomously

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

1. Make the real upload-key password/alias available through the four
   `UAC_PRODUCTION_*` signing inputs, then create a fresh AAB and verify its
   certificate against the retained upload-key fingerprint.
2. Use the restored staging Firebase access and the proven staging-only App Check
   CI path to run authenticated Auth/Firestore/Functions/Storage/FCM acceptance.
3. Complete Play internal distribution and interactive device checks for Play
   Integrity, background notification, biometric, TOTP, email-link, Storage and
   corporate/OEM behavior. Test Lab has proven physical startup and App Check only.
4. Approve the bilingual cross-platform legal candidate and its immutable version;
   only then perform a scoped Firestore/Hosting publication with hash/read-back and
   iOS regression verification.
5. Complete or confirm the Google Play developer account, reviewer accounts,
   declarations, testing track and upload decisions.

## Updated readiness

- Functional parity against iOS build 72: **95%**.
- Release engineering readiness: **87%**.

The increase from 80% reflects production-flavor/R8/lintVital compilation, 16 KiB
native alignment proof, emulator and physical Test Lab staging startup, positive
staging App Check token exchange, and prepared Play graphics/legal materials.
Signing identity, authenticated cloud workflows, interactive Play/OEM acceptance,
legal approval and Play Console remain blocking; therefore this is still not a
releasable build.
