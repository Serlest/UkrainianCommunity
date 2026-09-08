# Android 1.0.3 build 79 — parity and release audit

Date: 2026-09-08 (Europe/Vienna)

## Exact baseline and scope

- Current Apple reference: iOS/TestFlight source `1.0.3 (79)`, commit `fd58131`.
- Android release identity: `versionName=1.0.3`, `versionCode=79`.
- iOS source and Xcode project were not changed. The current iOS worktree still passes
  release-configuration and DE/UK localization validation for build 79.
- No Firebase, Hosting, App Store Connect or Google Play deployment/upload was made.

## Build 79 parity implemented

### News

- Native Android filter sheet for period (all/today/7 days/30 days/custom), order
  (newest/oldest) and personal source (all/saved/subscribed organizations).
- Custom dates use inclusive Vienna calendar days with an exclusive server-query end,
  including DST boundaries.
- Topic matching covers canonical `topic`, legacy `category` and
  `additionalCategories`; search also covers author/publisher/organization labels.
- Personal source filters require a signed-in account, are refreshed from Firestore,
  fail closed, and reset when identity changes.
- Required Firestore composite indexes and their validator were synchronized with the
  iOS build-79 source. They remain local until an authorized deployment.

### Analytics and user management

- Owner analytics metric cards use adaptive one-column layout at large font/small
  width, equal-height rows otherwise, and keep percentage deltas separate from the
  comparison caption.
- Managed-user details now show fresh presence with explicit loading/error/refresh;
  stale successful state is retained during a failed refresh.
- City/region duplication and double Telegram `@` presentation were removed.
- Existing Android self/owner/action gates remain unchanged.

### Announcements/backend compatibility

- The Android platform-aware announcement registration now includes the atomic
  build-79 iOS race fix for concurrent refresh, disable, account replacement and
  challenge delivery.
- Android platform binding remains part of challenge confirmation and refresh.
- This shared Functions source was tested locally but not deployed.

### Release tooling

- The Keychain-backed release script now builds both the upload-key-signed AAB and a
  matching minified APK, so the install smoke tests the same source/version as the
  upload artifact.
- A direct staging Gradle build now fails fast when its Firebase identifiers are
  absent and points to the configuration-fetching script instead of producing an APK
  that crashes later with `CLOUD_APPLICATION_ID_MISSING`.
- The staging-only App Check CI helper is installed only while registered test
  instrumentation is active. A manually launched staging APK now remains alive for
  visual QA; its cloud calls remain fail-closed without the transient test secret.
- At large accessibility text, bottom navigation switches to its two-by-two native
  layout as soon as any label would wrap. This keeps the German `Organisationen`
  label intact; normal-text four-column navigation is unchanged.

## Verification receipts

| Area | Result | Evidence level |
| --- | --- | --- |
| Android unit suite | **1913/1913 PASS**, 0 failures/errors/skips | local JVM |
| Android compile/assemble/lint | **PASS** | local build/static |
| Affected UI, normal font | **16/16 PASS** on API 37 | local emulator |
| Affected UI, 200% font | **14/14 PASS** on API 37 | local emulator |
| Build-79 browse/filter regression, normal + 200% font | **6/6 + 6/6 PASS** on API 26 | exact local app/test APKs |
| Final large-text navigation/browse regression | **6/6 PASS** on API 37 at 200% | exact final local app/test APKs |
| Build-79 news filter fix at 200% font | **PASS** on API 26; full affected set remains **16/16** by 15 prior unchanged passes plus exact fixed-test rerun | exact local app/test APKs |
| Functions unit suite | **476 tests, 0 failures** (400 pass, 76 emulator/opt-in skips) | local Node |
| Announcement concurrency integration | **6/6 PASS**, including both new Android races | isolated Firestore emulator |
| Firestore index validator | **PASS**, 74 unique composite indexes | local/static |
| Current iOS build-79 configuration/localization | **PASS**, 2804 localization entries checked | read-only current iOS worktree |
| Signed production APK smoke | install/update and cold start **PASS** in 451 ms; process alive; current public content rendered; no UAC fatal/App Check/Firebase exception in captured log | API 37, production backend, guest |
| Final signed production APK compatibility smoke | install and cold start **PASS** in 493 ms; process alive; `1.0.3 (79)` read back; 200% navigation visually inspected | API 26, production backend, guest |
| Final staging standalone smoke | install and cold start **PASS** in 539 ms; process alive; `1.0.3-staging (79)` read back; former instrumentation-argument crash absent | API 26, staging, unauthenticated/fail-closed cloud |
| Upload-key-signed AAB | **PASS**, R8 + lintVital + signature | local release artifact |
| Native libraries | all 8 ABI/library combinations use `2**14` (16 KiB) LOAD alignment | local AAB inspection |

Signed release identity read-back:

- package: `at.serlest.ukrainiancommunity`
- version: `1.0.3 (79)`
- min/target SDK: `26 / 36`
- upload certificate SHA-256:
  `C7:F9:7B:B4:BE:68:C8:5E:AD:95:A6:7D:29:35:67:08:87:4C:36:97:A6:EA:69:45:3F:78:37:D8:3F:7F:EF:BE`
- AAB:
  `outputs/android-build79/app-production-release-build79-UPLOAD-SIGNED.aab`
- AAB SHA-256:
  `5835e55e6c719146e1e3ff3b3787feeb0a1b72854fe4db69aceba8c1cfc5d998`
- APK:
  `outputs/android-build79/app-production-release-build79-UPLOAD-SIGNED.apk`
- APK SHA-256:
  `99b7da9de8702e0e3df9872ebce1f136e84131c2c1ffcd6a6dfdd436c128176b`
- staging APK:
  `outputs/android-build79/app-staging-debug-build79.apk`
- staging APK SHA-256:
  `dec9cdc032f59cc6f239588b42156786c4000c4c155159a503c2cdff8d394435`

## Visual audit against iOS build 79

The current build-79 iOS captures and fresh Android API-37 captures were inspected.
Product hierarchy is aligned: brand header, optional hero/banner, primary filters,
content-type filters, cards, and four-item floating bottom navigation. Android keeps
native Material behavior for scrollable filter rows, modal bottom sheets and the date
range picker instead of copying iOS controls.

Fresh checks confirm:

- a banner, when present, sits between the header and filters;
- the new news filter control no longer expands/clips its full summary inside a chip;
  the short action and the readable summary are separate;
- the filter sheet fits normal width, scrolls to its actions, and disables personal
  sources for guests with an explanation;
- production Home renders real news/event cards without placeholder/demo wording;
- card hierarchy, spacing and bottom navigation are coherent with iOS while retaining
  Android touch targets and typography;
- analytics and user-management build-79 layouts are covered at normal and 200% font.
- on API 26 at 200% text, the final production navigation uses a readable two-by-two
  arrangement with complete labels instead of splitting `Organisationen` mid-word.
- the Play phone set was refreshed from the final signed production APK at normal
  text: four clean 1080 × 1920 captures in each of DE and UK. Third-party image
  marketing rights still require owner confirmation before upload.

Evidence is stored in `outputs/android-build79-audit/` (including
`production-home-api26-font200.png` and `api37-font200-navigation-grid.png`) and
`outputs/android-build79/production-home-api37.png`. This does not replace a physical
OEM/TalkBack/contrast matrix.

## Audit result and remaining gates

- **Functional parity against iOS build 79 = 97%.** The build-79 product deltas with
  Android equivalents are implemented. Remaining differences are physical/device or
  platform-service evidence, plus Android screens that have no direct iOS-equivalent
  implementation path without a separate product decision.
- **Local release-candidate readiness = 98%.** Source, tests, R8/lintVital, permanent
  upload signing, identity read-back and a production guest smoke are green.
- **Google Play release readiness = 92%.** This is intentionally lower because local
  success cannot prove Play-installed integrity, production cloud rollout or console
  completion.

Open release gates:

1. Deploy the synchronized indexes and Android-aware announcement Functions to staging,
   then verify exact read-back. Production rollout must remain disabled until acceptance.
2. Run authenticated staging/Play-internal checks on an unrestricted physical Android:
   Auth flows, privileged TOTP, App Check/Play Integrity, Storage/gallery, callables,
   account deletion, FCM foreground/background/killed-process delivery and tap routing.
3. Complete Play Console identity/app onboarding, declarations, reviewer access and the
   required testing track; the console currently controls these external gates.
4. Approve and publish cross-platform privacy/support/account-deletion wording and verify
   the public URLs. Do not silently replace the released iOS legal version.
5. Perform manual TalkBack, light/dark, DE/UK, signed-in/owner and OEM visual checks, plus
   final store-screenshot rights review.
6. Upload the exact AAB only after gates 1–5. Upload, internal-track creation and public
   promotion are separate actions and were not authorized by this audit.

## Release decision

The Android `1.0.3 (79)` code and signed artifacts are ready for the next controlled
staging/Play-internal gate. They are not yet evidence of a public Google Play release.
