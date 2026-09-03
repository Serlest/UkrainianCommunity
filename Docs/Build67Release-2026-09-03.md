# UAC 1.0.2 (67): organization compatibility and release verification

Scope: finish the confirmed organization-edit and CI failures, commit/push the
isolated release package, create a new build, and submit only after release gates
pass. Android, unverified-account cleanup, content automation and Storage changes
remain separate; they are not deployment inputs for this package.

## Confirmed causes and changes

- Build 66 already stopped rewriting protected organization submission/review
  metadata on ordinary profile edits. This prevents Firestore Timestamp precision
  loss from turning a legitimate edit into an unauthorized metadata change.
- A second independent issue: gallery callables add server-owned `photoCount`, but
  the organization structural validator rejected that field on subsequent edits.
  The narrow Rules patch accepts an existing nonnegative integer counter. Clients
  still cannot create, modify or delete it; owner/admin/status/submission metadata
  restrictions remain intact. Only this Firestore Rules patch may be deployed.
- GitHub run 33800430924 compiled Debug and Release successfully, but four unit
  tests failed. They deliberately suspended a simulated SDK request while racing
  a real 20-second deadline; under concurrent CI load the deadline won before the
  test could finish its controlled scenario. Tests now inject a cancellable manual
  clock. Production retains its 20-second continuous clock, with a separate test
  proving that the real deadline still expires an unresponsive read. Parallel
  execution and failure assertions are not disabled.
- The synthetic UI owner fixture lacked a real second-factor claim and therefore
  correctly hit the MFA gate. A Debug/Simulator-only auth dependency now models
  both authenticated and missing-factor sessions, using the real security policy.
  It cannot write to Firebase and is not compiled into a device/Release build.
- The inbox test expected a child identifier overwritten by SwiftUI's full-screen
  shell. The captured accessibility hierarchy showed the inbox and its visible
  German Back button. The test now checks that the inbox opens, Back is hittable,
  the inbox disappears, and the original tab returns. No navigation assertion is
  skipped and no production navigation behavior was changed.

## Evidence

- Production read-back before changes: Firestore and Storage Rules exactly match
  the committed build-65/66 baseline. The inspected europe-west3 Functions have
  no September 3 deployment or Android-specific function. Local Android changes
  therefore do not establish a production change.
- Red reproduction: the baseline Rules reject an authorized owner profile edit
  after a gallery counter of 1 is present.
- Final isolated Firestore/Storage suite: **161/161**, zero failures/skips.
  Coverage includes counters 0/1/30, owner and organization-admin edits, denied
  counter/ownership/moderation forgery, invalid data, and unauthorized users.
- Functions baseline: lint passed; **327 unit tests passed**, 39 integration tests
  intentionally skipped by this unit-only command. No Functions deploy is included.
- Focused Swift tests: **32/32** passed, including manual-clock races and both
  synthetic MFA states.
- UI checks passed for organization details, real news-editor preview, and denial
  of protected tools without the second factor. The corrected combined
  creation/inbox scenario and final full unit run are recorded separately below
  when complete; an earlier failed run is retained, not represented as green.
- Local static checks: repository structure, 2669 DE/UK localization entries,
  property lists and build-67 release configuration passed.
- Final build-67 local run: **386 unit tests + 1 combined creation/inbox UI test
  passed**, zero failures/skips, 190.9 seconds including preparation. Result:
  `test_sim_2026-09-03T20-50-25-357Z_pid10267_ecf7366e.xcresult`.
  Together with the three focused UI passes above, all four selected UI scenarios
  have passing evidence. The real production-clock deadline test also passed.

Evidence directory: `outputs/release-1.0.2-build67-2026-09-03/` (ignored by Git).
Server tests use a frozen baseline snapshot plus only the photoCount patch,
not the Android-modified working-tree Rules.

## Gates still requiring explicit final evidence

Preparation and local tests are not a successful GitHub run, deployment, signed
archive, upload, or App Review submission. Record each result independently.
The App Store Connect browser session expired during preflight; the user was
asked to sign in. Published App Privacy must be checked in the authenticated UI
before public submission. Historical manifest warnings are not silently removed.
Synthetic UI tests are not proof of a real Firebase/MFA session or a physical
accepted/rejected-comment test. TestFlight may be prepared without claiming those
public-release gates are complete.
