# Android 85 — profile and management corrections

Baseline: Internal 84, commit `7f97056`. The user's device report is the acceptance input;
the previous source/component review was insufficient to establish populated nested-page quality.
Android only; iOS/backend/Rules unchanged.

## Confirmed causes and corrections

- Recent history rejected iOS `organizationID` metadata (string/null), failing the whole page.
  Accept validated optional metadata, preserve it on writes and version checks; target/content
  visibility and blocked-item rules stay authoritative. No cloud data rewrite.
- Account and managed organization/banner cards had URLs but no image renderer. Added actual
  images and placeholders. Existing alternate avatar filenames are no longer hidden.
- Two independent back controls existed in embedded destinations. `UacBackButton` suppresses
  the local duplicate while the host toolbar dispatches the same native back handling. Nested
  analytics/log details and unsaved editor protections retain local handling.
- Management is now denied at the route boundary, not just by missing menu links. Announcement
  management was visible but inert for admins; now owner-only. Repository/server guards remain.
- Analytics timeout was handled as ordinary coroutine cancellation, leaving loading active.
  Timeout now becomes a retriable offline failure; actual cancellation is not swallowed.
- Donation settings required fields which iOS treats as optional. Missing fields now receive
  existing defaults, while raw-source compare-and-set still detects concurrent changes.
- External HTTPS banner URLs were accepted by content contracts but rejected by image loading.
  Added banner-only opt-in with public DNS validation, no redirects/cookies/auth/proxy, byte/time
  bounds. Normal avatar/content storage policy is unchanged; local flavor has no external network.
- Log metrics/filters and analytics period controls wrap; log filters have an explicit expandable
  entry instead of multiple horizontally hidden rows.

## Verification

Final JVM regression: 1950 tests / 119 suites, zero failure/error/skip, including personal
appeal-route exemption; own DSA review is not an administrative tool. Local APK/test APK and lint PASS.

PASS: 32 component scenarios at 100%, including real local-Storage JPEG fetch/decode in avatar,
organization, request and banner preview; each unique fixture deleted and GET404 verified.
Initial three image assertions incorrectly expected a network bitmap tag on a bundled vector;
tests were replaced with actual HTTP image fixtures, not weakened to accept a placeholder.

PASS: system night mode change followed by system-theme reaction, manual light/dark override,
activity recreation/persistence, guest direct management routes denied (3 integration tests).
PASS: real Main history bookmark/read/delete/logout, native photo picker/upload/private-public
profile readback, 14 profile destinations in de/light and uk/dark (3 integration tests).
Populated analytics and logs captured in both languages/themes; single toolbar back, detail and
list return verified. Empty analytics action heading removed after screenshot review.

PASS: 52 component scenarios at 200%, extending the 32 to managed-user/moderation/organization/banner
states and role loss/denial. Full profile traversal passed again at 200% after the final route policy.
Avatar, organization and banner image tests now verify actual downloaded bitmaps, not only URL/slot
presence. Temporary local image fixtures are removed exactly; no production account/data writes.
AVD font and keyboard settings restored to their previous values.

## Signed release and Internal publication — PASS

Source commit: `9584da6`. Production release build PASS; APK signing verification PASS.
Package `at.serlest.ukrainiancommunity`, version `1.1 (85)`, minimum API 26, target API 36.
Archived AAB SHA256: `0de11a123b8526dacfbd8615fed8056d8dbf70ec3a7e5c97581b099cb3638096`.
Archived APK SHA256: `eee9f02bfcf34c076af816338b605e04b05f11e9d9cc2ded3771c82df3df8476`.

Google Play read-back at 2026-09-10 06:32 UTC: `Aktiv`, latest `1.1 (85) – Internal`,
`Für interne Tester verfügbar`, published 10 September 08:31 Vienna. Review reports no lost
supported devices and one nonblocking native-debug-symbol warning. No production/open/closed
track or tester-list changes. Internal acceptance is not public review approval or device proof.
Test link: https://play.google.com/apps/internaltest/4701365572505552935
Artifacts, test logs, screenshots and `build85-play-internal-receipt.json` are archived in
`/Users/serlest/Documents/Codex/2026-09-09/82-82/artifacts/android-build85/`.

No physical-device or complete live-cloud functional parity claim. Destructive management operations
must not be tested against users' real production records.
