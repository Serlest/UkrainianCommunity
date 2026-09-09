# Android Build 84 — complete visual hierarchy pass

Baseline: `85b05e4`, Google Play Internal Build 83. Scope: Android UI, navigation and test code.
User feedback: missing Events/Organizations banners, inconsistent profile icons, hidden logout,
unclear hierarchy, unfinished nested pages. Public release remains subject to the user's device review.

## Changes

- Restore targeted banners on Events and Organizations list roots; details remain content-focused.
- Logout is a full-width, labeled action in the first signed-in account card.
- All profile navigation rows have semantic icons. Personal collections, communication, activity,
  settings and privileged administration are grouped.
- Security and privacy/app-lock settings are separate destinations. Mandatory MFA/legal remediation
  remains available before the account becomes ready. Guest authentication screens omit signed-in menus.
- Privileged tools now have their own administration hub rather than extending the personal menu.
- Account/settings screens use a quiet solid theme background; security omits the repeated identity card.
- A shared wrapping section heading is used across nested destinations.
- Remove repeated horizontal/system insets inside the account host. Retain bottom scroll clearance.
- Add compact search/filter/location icons, place event facts before long descriptions, fit organization logos.
- Wrap long action rows and label switches; distinguish destructive and secondary actions.
- Replace stale development/test-server copy with user-facing explanations where the feature is live.

## Screen inventory reviewed in source

| Area | Hierarchy reviewed |
| --- | --- |
| Browse | Home, News, Events, Organizations; search, filters, region, details, links, galleries |
| Account | Guest, login, registration, recovery, legal acceptance, MFA challenge/setup, logout |
| Personal | Profile edit/avatar/region/save, saved items, subscriptions, history/recent items |
| Settings | Security, app lock, analytics consent, language/theme, legal readers |
| Communication | Inbox, filters, message detail, preferences, popup, feedback/create/replies/context |
| Safety | Blocked accounts/organizations, report form, account status, deletion/confirmation/MFA |
| Events | Registrations, participation/cancellation, reminders, attendees, comments/moderation |
| Organizations | My organizations/applications, form, editor, management, team, subscribers |
| Publishing | Authoring list/editor/preview/recovery, cover picker, lifecycle actions, gallery/captions |
| Administration | Users/status/roles, moderation/preview/decision, organization review, legal evidence |
| Owner tools | Banner list/editor, planning/draft/detail, donation settings, announcements/audience/preview |
| Diagnostics | Logs/filter/detail/actions, analytics overview/period/detail/metrics/regions |

Source review is not a claim that every server-dependent state has been exercised on a physical device.
Existing DSA appeal read-only limitations and recovery/uncertain-operation safeguards are preserved.

## Verification and publication

JVM unit tests: 1934 passed, zero failures/errors/skips. Local APK and instrumentation APK built.
Initial full component run: 277/282 passed; one title semantics defect was corrected by merging the
heading descendants, while four scenarios require the documented 200% OS font / docked keyboard
configuration. Initial profile navigation passed all actions and
captured both locales but failed test-only cleanup due to an invalid fixture prefix. That prefix was
fixed, the exact orphan synthetic Auth/user/public-profile records were removed and absence checked;
the corrected profile/security/privacy scenario then passed with cleanup.

Corrected 200% component run: 278/282 passed; the remaining four native keyboard checks were blocked
by Gboard's visible "Try out your stylus" onboarding overlay (captured in `keyboard-during.png`).
The emulator-only handwriting setting was disabled and Gboard restarted without clearing its data.
Both affected classes then passed 21/21, including all four checks. The aggregate component coverage
therefore has a passing result for all 282 distinct scenarios; this is not represented as a single
uninterrupted all-green run. The setting is an Android test environment control documented in
[AOSP](https://android.googlesource.com/platform/frameworks/base/+/d98974c1f5c4081d03b01f7e6a5d0d3115ce0c55%5E1..d98974c1f5c4081d03b01f7e6a5d0d3115ce0c55/).

Expanded real-MainActivity profile traversal passed at 100% and 200% OS font: all 14 normal profile
destinations in German/light and Ukrainian/dark, return navigation with identity preserved, visible
logout and actual logout. The disposable local account was cleaned after each run. 72 profile PNGs
cover both scales. Main visual/chrome and legal-reference journeys passed at both scales (2 tests
each). A final 100% navigation run passed 11/11 including those 2 main tests, browse filters,
organization team/photos/news, guest login/legal navigation and personal-route return behavior.
Local Android lint passed after the final source changes. Key profile, privacy, editor, inbox,
organization, event-list and event-detail captures were visually inspected; synthetic content and
emulator-only account/legal fixtures are not production content or physical-device proof.

Production APK/AAB build and release lint passed. APK signature verified; AAB JAR verification
returned success with the usual self-signed upload-certificate/no-timestamp and ZIP entry-order
warnings. Google Play accepted the bundle and its signing identity.

Published to Google Play **Internal testing only** on 2026-09-09 at 23:53 Europe/Vienna.
Read-back at 21:54 UTC: `Aktiv`, `Neuester Release: 1.1 (84) – Internal`,
`Für interne Tester verfügbar`, one version code. No production/open/closed track or tester-list
changes. Device support unchanged from 83. Play has one non-blocking native debug-symbol warning;
the R8 mapping file is attached. Play review is not completed and no public release is claimed.

- Package: `at.serlest.ukrainiancommunity`; version name `1.1`, code `84`, min SDK 26, target SDK 36.
- AAB SHA-256: `59b7725573f3dcc82e2bcb311f31a25db98cc8b6629b5f97cf39f3b2081fcfd1`.
- APK SHA-256: `2095142e901d34ee1d7bd7bfa90b77b3603616c7aa14933d8d85c1e8702f8c7b`.
- Upload certificate SHA-256: `c7f97bb4be68c85ead95a67d29356708874c3697a6ea69453f7837d83f7fefbe`.
- Test link: https://play.google.com/apps/internaltest/4701365572505552935

iOS, server code and database/security rules are unchanged. Production Firebase/signing configuration
uses the existing release path; no database migration/deployment was performed. Physical-device
installation, role-specific live data, TalkBack and full production-function parity remain separate
device/release gates. Next step: user's Play-installed Build 84 visual and navigation acceptance.
AVD font scale and keyboard settings were restored after the tests.
Evidence files are stored in the task workspace under `artifacts/android-build84/`.
