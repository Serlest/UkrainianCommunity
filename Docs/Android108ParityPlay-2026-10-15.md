# Android 1.2 (108): parity and Internal release evidence

## Scope

- Existing package: `at.serlest.ukrainiancommunity`; existing Play Internal track only.
- Shared production Firebase project: `ukrainiancommunity-dbd5f`. No separate production user store.
- Android parity changes: directory editor identity and failure states, guarded grant/revoke, DE/UK directory translation with preview, actionable editor validation, and removal of redundant navigation arrows.
- Shared callable `translateContent` and `cleanupExpiredPasskeyChallenges` were synchronized with iOS source, built, tested and deployed separately in commit `f537c47`.

## Verification before Play upload

- Production release build with R8 and vital lint: successful.
- AAB SHA-256: `04d06377b21a8522c69448cb5476082d5658d4d188dc7d3600f98c59dbdfb6ec`.
- APK inspection: package `at.serlest.ukrainiancommunity`, versionCode `108`, versionName `1.2`, minSdk `26`, targetSdk `36`.
- Upload signing certificate SHA-256: `C7:F9:7B:B4:BE:68:C8:5E:AD:95:A6:7D:29:35:67:08:87:4C:36:97:A6:EA:69:45:3F:78:37:D8:3F:7F:EF:BE` (matches build 107).
- Local JVM tests: 1,998 passed, 0 failures/errors; Android lint passed.
- Android API 37 emulator: 8 directory/editor/translation UI tests passed, 0 failures.
- Isolated staging Firebase end-to-end test: reader denied; owner signed in with TOTP and granted access; editor published; revision/history read-back matched; owner revoked; editor was denied afterward. Temporary Auth users, category and App Check debug token removed.

## Remaining hands-on checks

- Physical Android installation through Play Internal, with real account sign-in, Apple/Google login as applicable, passkey, notifications, Support and Directory navigation. The available Samsung blocks USB debugging by organization policy, so no USB-based physical-device run was possible.
- Compare the Play-installed 108 build visually with iOS 107 on the user's device, especially screen density, banners and text fit. Simulator screenshots and automated UI checks are evidence for the tested layouts, not a claim that every physical-device state is perfect.

## Play read-back

- Uploaded the signed AAB to the pre-existing Internal track and published `1.2 (108) – Internal` on 15 October 2026 at 19:37 Vienna time.
- Play Console read-back: track active, latest release `1.2 (108) – Internal`, status `Für interne Tester verfügbar`. No bundles from 107 were included, and the supported-device counts did not decrease.
- Tester enrollment link shown by Play: <https://play.google.com/apps/internaltest/4701365572505552935>.
- Play review showed one non-blocking warning: native debug symbols were not uploaded for third-party native code. The Java/Kotlin ReTrace mapping is attached to bundle 108.
- UI evidence: `Docs/evidence/play-internal-108-2026-10-15.png`.
