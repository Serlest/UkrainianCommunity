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

This is startup proof only. It is not authenticated cloud acceptance: the active
Firebase CLI account receives HTTP 403 for the staging app/config APIs, and an
unauthenticated Firestore REST read correctly receives 403. No staging deployment,
fixture write, account creation or configuration change was made.

### Play preparation

- Updated the listing and conservative Data Safety draft for 1.0.3 (72), including
  announcements, acknowledgement/action receipts, FCM installation challenge and
  translation behavior.
- Created and visually checked the exact-size, no-alpha store icon and feature
  graphic under `Android/release/play/`.
- Prepared bilingual cross-platform privacy/terms wording as an approval-only
  document; published iOS legal versions remain unchanged.

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
2. Restore sufficient Firebase access or an authenticated browser session for the
   staging project; register the App Check debug token only in staging and run
   Auth/Firestore/Functions/Storage/FCM acceptance.
3. Connect and authorize a physical Android device for Play Integrity, background,
   notification, biometric, TOTP, email-link, Storage and OEM checks.
4. Approve the bilingual cross-platform legal candidate and its immutable version;
   only then perform a scoped Firestore/Hosting publication with hash/read-back and
   iOS regression verification.
5. Complete or confirm the Google Play developer account, reviewer accounts,
   declarations, testing track and upload decisions.

## Updated readiness

- Functional parity against iOS build 72: **95%**.
- Release engineering readiness: **84%**.

The increase from 80% reflects production-flavor/R8/lintVital compilation, 16 KiB
native alignment proof, staging cold-start proof and prepared Play graphics/legal
materials. Signing identity, authenticated cloud/device acceptance, legal approval
and Play Console remain blocking; therefore this is still not a releasable build.
