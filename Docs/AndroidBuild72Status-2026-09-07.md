# Android parity with iOS 1.0.3 build 72

Date: 2026-09-07 (Europe/Vienna)

## Baseline and scope

- Branch: `codex/android-build72-20260907`.
- iOS baseline: commit `5b0ba56`, the recorded TestFlight build 72 translation release.
- Android baseline: commit `ea5ee8c`, the completed build 68 local release candidate.
- Android identity is now `versionName=1.0.3`, `versionCode=72`.
- Product changes are limited to `Android/` and the shared announcement Functions implementation. No iOS source, Firestore Rules, production configuration, campaign, TestFlight build, or public release was changed.

## Implemented build 72 parity

### User announcements

Android now implements the build 72 announcement contract rather than treating it as an iOS-only payload:

- authenticated and guest feed/history;
- priority popup, once-only and acknowledgement presentation modes;
- protected acknowledgement dialog with “later”, action and feedback paths;
- account and guest notification preference handling;
- FCM registration challenge, foreground delivery, killed-process inbox and notification-tap routing;
- owner list, editor, audience/group/region/user/platform selection, schedule, preview/audience count, save, test, publish, cancel and statistics;
- native Android date/time selection and adaptive action layout;
- platform-aware backend rollout, registration and delivery so iOS and Android can be enabled independently.

The local flavor does not initialize or register announcement FCM. This preserves the existing local-only safety boundary.

### Shared editor translation

The shared `translateContent` callable is wired into Android editors that already exist:

- news and events;
- organization basic information;
- organization extended information;
- featured banners;
- user announcements, in both language directions.

Translated values are shown for review before applying. Existing non-empty target fields require explicit replacement permission, stale drafts cannot be overwritten, and an empty source cannot erase target text.

Donation and legal-document editors do not currently exist on Android, so build 72 translation parity cannot be wired into those absent screens without implementing those product areas first.

## Verification completed

| Area | Result | Evidence level |
| --- | --- | --- |
| Android local debug APK and test APK | PASS | Gradle assemble completed |
| Android unit tests | 1907/1907 PASS, 0 failed/error/skipped, 110 XML suites | JVM/local |
| Backend unit tests | 400 PASS, 0 FAIL, 74 expected integration/opt-in skips, 474 total | Node/local |
| Announcement Firestore integration | 6/6 PASS | isolated Firestore emulator |
| Affected Compose UI matrix | 42/42 on API 37; 42/42 on API 26 after required compatibility arguments | local AVDs |
| Main visual/legal regression | 2/2 on API 37 at 100% font; 2/2 on API 26 at 200% font | local AVDs |
| Guest main journey | PASS on both AVDs | local AVDs |
| Stable-screen visual inspection | PASS for the tested home composition; initial API 26 cold-start capture was an animation/frame artifact and disappeared after stabilization | manual local inspection |
| Backend TypeScript build/lint and App Check validator | PASS; 65 callable sites, 0 audit vulnerabilities | local/static |
| Android lint | PASS with no new build-72 warning in the touched announcement/translation/Main paths | local/static |
| Production release/R8/lintVital compile | PASS with a quarantined throwaway signing certificate; package/version verified | local build engineering only |
| Native 16 KiB ELF alignment | PASS for all 8 packaged ABI/library combinations | local AAB inspection |
| Staging cold start | PASS on API 37; no fatal/Firebase/App Check error observed in the captured startup log | separate test-cloud package, unauthenticated |

The APK evidence is local-emulator evidence only. It does not prove physical-device FCM delivery, Play Integrity/App Check acceptance, OEM background behavior, or production deployment.

## Release gates still open

1. **Production backend deployment:** Android-aware Functions are only in this branch. Production remains untouched.
2. **Rollout flag:** the last recorded production configuration has `androidEnabled=false`. It must remain false until the deployed backend and a signed build pass staging/physical-device acceptance.
3. **Signed AAB:** a production-flavor AAB compiles, shrinks and passes lintVital, but it is deliberately signed by a quarantined throwaway certificate. The upload keystore exists locally while the four required `UAC_PRODUCTION_*` signing variables remain absent; no uploadable build 72 AAB can be produced or verified without those inputs.
4. **Cloud/device acceptance:** run signed staging/production-flavor checks for App Check/Play Integrity, authenticated callables, FCM challenge, foreground/background/killed-process delivery, notification permission and tap routing on at least one physical Android device.
5. **Android legal text:** the bundled terms are version 2026.10 and still scope themselves to the “iOS-App”. Legal approval and a versioned Android/cross-platform replacement are required; an automatic wording change would not be a valid legal approval.
6. **Google Play release data:** complete/read back Data safety, content rating, privacy/support links, testers/tracks and store-listing assets before upload/promotion.

## Readiness estimate against iOS build 72 = 100%

- **Implemented product/function parity: 95%.** The build 72 announcement and translation additions are present where equivalent Android screens exist; absent donation/legal editors and physical/cloud-only behavior account for the remaining gap.
- **Release readiness: 84%.** Local code, unit, backend-emulator, affected UI, production-flavor compilation, 16 KiB alignment, staging startup and Play graphics evidence is green, but upload signing, authenticated cloud/device acceptance, legal approval, Play Console and production deployment/read-back remain incomplete.

This branch is a verified local build 72 candidate, not yet a production-ready Google Play release.
