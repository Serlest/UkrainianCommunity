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

## Verification receipts

| Area | Result | Evidence level |
| --- | --- | --- |
| Android unit suite | **1913/1913 PASS**, 0 failures/errors/skips | local JVM |
| Android compile/assemble/lint | **PASS** | local build/static |
| Affected UI, normal font | **16/16 PASS** on API 37 | local emulator |
| Affected UI, 200% font | **14/14 PASS** on API 37 | local emulator |
| Functions unit suite | **476 tests, 0 failures** (400 pass, 76 emulator/opt-in skips) | local Node |
| Announcement concurrency integration | **6/6 PASS**, including both new Android races | isolated Firestore emulator |
| Firestore index validator | **PASS**, 74 unique composite indexes | local/static |
| Current iOS build-79 configuration/localization | **PASS**, 2804 localization entries checked | read-only current iOS worktree |
| Signed production APK smoke | install/update and cold start **PASS** in 451 ms; process alive; current public content rendered; no UAC fatal/App Check/Firebase exception in captured log | API 37, production backend, guest |
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
  `a75c2d902b0dbd74132ea47ab51da2aad7fc6d9f3ed1aa31c81f83f153a8eeff`
- APK:
  `outputs/android-build79/app-production-release-build79-UPLOAD-SIGNED.apk`
- APK SHA-256:
  `29fc19e49fb79aae1fc1dc981bb9d8c79b5d8e1583592201080b52aba4a0fcea`

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

Evidence is stored in `outputs/android-build79-audit/` and
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
