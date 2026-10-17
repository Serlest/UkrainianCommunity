# Android 108: region, banners and profile background

## Baseline and scope

- User confirmed the affected Play version is **1.2 (108)**. The previously verified Closed Alpha release is 108; this task does not upload another release.
- Authoritative checkout: `/Users/serlest/Developer/UAC-Android-1.2-Parity107`, branch `codex/android-parity-1.2-107`, starting commit `b2e34d1`. The checkout was clean before this task. Version metadata remains 1.2 (108).
- iOS `ContentView`, featured-banner model/repository/validation, and Directory root were read as references. No iOS source or production data changed.

## Established causes

1. **Every active production banner was rejected by Android.** Production has seven banner documents, five active. Every document includes `directory` in `visibleSections`. Android's public validator accepted only home/events/organizations, so the five active documents all failed validation, including banners requested for home. The exact production query returned five documents for each of the four sections. All five active image URLs returned HTTP 200 with `image/jpeg`.
2. **Profile region and public browsing region were disconnected.** The profile persists `selectedFederalState`; BrowseViewModel restored a separate `uac-local.region`/SavedStateHandle value. Profile loading/saving never synchronized that browse value. Therefore a Tirol profile could coexist indefinitely with a stale Kärnten filter shared by all public screens.
3. **Profile/settings explicitly disabled artwork.** BrowseScreen passed `plain = state.isAccountRoute || state.route == "settings"` to the existing UacPageBackground, producing the flat light/dark background observed by the user.

## Changes and data path

- Public banner validation now recognizes all four supported placements. The owner editor's FeaturedSection enum and DE/UK label include Directory, preserving that placement on edit/save. Other field/action validation remains enforced.
- Directory root loads and renders banners within its own LazyColumn; nested articles/editors do not gain a carousel. Arriving banners are revealed only near the top. The same lifecycle refresh and schedule filtering applies as on other public roots.
- Banner loading runs even when the primary feed fails. Its warnings/cache timestamp survive, cancellation remains cancellation, and unexpected optional-read failures produce UNKNOWN warnings.
- Confirmed profile state seeds the shared browse region for the current UID, including migration of the stale persisted value from 108. Profile-before-account ordering is handled by a pending synchronization. Account changes reset the manual-filter flag, including sign-out/sign-in to the same UID. Stale other-account values cannot be applied.
- As on iOS, an explicit public filter takes precedence over later same-session profile refreshes. A new account/session can seed its profile region again. Guests retain their own durable public region.
- MainActivity supplies the matching confirmed personal profile, falling back to the authenticated profile during bootstrap. A successful personal-profile save updates the observed personal state and therefore the browse region while no manual filter is active.
- News, events, organizations and Directory all consume BrowseState.region. Feed queries already include the selected federalState plus Austria-wide records. Feed/cache query identities include region; raw banner cache is section-based and is filtered again for the current region. Offline region filtering is covered by regression tests.
- Profile, personal-profile editor and settings now use the existing app artwork and theme overlay. The artwork is unchanged.

## Verification

- Production read-only snapshot and image checks: [sanitized evidence](evidence/android-banner-production-2026-10-17.json). No image download tokens or operator credentials are stored in that file.
- JVM suite: **2,005 tests, zero failures/errors/skips**. Includes production-shaped banner placements, region filtering through offline cache, editor publication payload, stale-108 preference migration, explicit manual filter, account switch/relogin, profile-before-account ordering, guest persistence, feed-error banner independence and Directory root-only loading.
- Final local debug app/test APK assembly, full JVM suite and Android lint all succeeded.
- Isolated emulator: `UAC_Step8_API37_Fresh`, API 37, `emulator-5586`. The pre-existing emulator-5582 was not used or changed.
- Pre-fix local 108 APK plus the regression harness reproduced missing banners, stale Kärnten and flat profile backgrounds. This is a local APK from the starting checkout, not a Play installation proof.
- Final UI journey passed: loaded banner images on home/events/organizations/Directory; Tirol/Kärnten switches include/exclude the Tirol banner; durable preference and recreated model agree; guest profile, personal-profile form and settings retain artwork in light/dark. The harness uses the actual BrowseScreen, GuestProfileContent and PersonalProfilePanel with isolated fixtures.
- A separate two-invocation test seeded Tirol through the actual MainActivity BrowseViewModel, force-stopped the app, then launched a fresh process and verified both app state and `uac-local.region` remained Tirol.
- Local image fixtures were removed and their absence checked by the test helper. No production Auth users, content or settings were created/changed.
- Visual comparison: [before/after](evidence/android-108-region-banner-profile-comparison.jpg). Full captures and test logs remain under `build/android-region-banner-proof/` and `/tmp/uac-region-*.log`.

## Limits and release boundary

- No physical Android run or new Play artifact was produced. Installed Play 108 still contains the defects until a corrected build is uploaded and distributed.
- Signed-in profile bootstrap/save is covered with isolated state/fixtures and the real UI/state wiring; this task did not perform a new live production login or edit a real profile.
- Production REST query/image reads prove current document shape and endpoint availability. They do not replace an authenticated Play-installed client/App Check test.
