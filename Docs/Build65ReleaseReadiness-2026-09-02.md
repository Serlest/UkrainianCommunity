# Build 65: scoped release-candidate verification

Version: 1.0.1 (65). No App Review submission or public release is authorized.

## Included changes

- Fractional-second callable response parsing and idempotent publication retry for
  Content Planning news/events.
- Organization submission notifications route to the exact review request.
- Personal organization hiding and undo, isolated from owner/user blocking,
  permissions, memberships, management and sibling organizations.
- Previously authorized Privacy Policy 2026.12 in the app, matching the published
  website and legal documents. No MFA logic change.

## Verified before deployment

- TypeScript compilation/lint and staged App Check policy validation passed.
- Nine targeted backend/emulator cases passed, no skips; 29 targeted Swift unit
  tests and the organization hide/undo UI test passed. Twelve final routing/error
  tests and the final Simulator build passed. Detailed result bundles are linked
  in the two fix reports; these are not physical-device evidence.
- Build 65 release configuration, property lists, DE/UK localization (2665 entries)
  and legal document structure passed. Existing public-release gates remain open.
- Production snapshot 2026-09-02T18:31:19Z: 112 existing functions ACTIVE, 114 local
  endpoints expected; only `getBlockedOrganizations` and `setOrganizationBlocked`
  missing. Deployed Firestore and Storage Rules exactly match local files.

## Completed deployment and upload

- Code commit `c42a1345c4af950e2213afa0a3e716609766da59` pushed and verified on
  `origin/integration/local-product-progress`.
- Scoped Firebase dry-run and deployment succeeded. Both new functions ACTIVE;
  114/114 expected functions now present. Read-back at 18:39:15 UTC confirmed all
  112 existing function update times/runtime/service identities unchanged and the
  same Firestore/Storage Rules release IDs and content hashes. The first verifier's
  order-sensitive JSON hash was replaced with deployment-identity checks after
  proving Google returns event filters in different orders on repeated reads.
  Original pre-deploy and diagnostic snapshots were preserved.
- Live authenticated checks used the existing unprivileged App Review test
  account, not the operator's iPhone session. Block/list/repeat/unblock succeeded;
  one same-owner sibling, both organization documents, account/role fields and
  personal user-block records stayed unchanged. Original block state restored.
  Unauthenticated requests were denied; caller-supplied actor IDs were rejected.
- Logs at 18:43:29 UTC: six successful HTTP 200 calls, three expected negative
  requests (400/401), zero server 5xx and zero ERROR entries. This short probe is
  not a 24-hour observation window.
- Release archive succeeded at 18:38 UTC. Signed 1.0.1 (65), exempt-encryption
  flag false, bundled legal JSON hash matches source. App binary/dSYM UUIDs match.
  Export/upload succeeded at 18:40:57 UTC. Firebase/gRPC binary SDKs still produce
  missing-dSYM upload warnings; the app's own symbols are present. No claim of a
  warning-free dependency archive.
- Apple build ID `54c8e0be-f576-44fa-82c2-e348e04bba82`: VALID,
  APP_STORE_ELIGIBLE, internal IN_BETA_TESTING. DE/UK What to Test updated. Existing
  internal group has access to all builds. External Beta Review was not submitted.
- Candidate selection verified at 18:45:40 UTC: 1.0.1 attaches build 65 and is
  PREPARE_FOR_SUBMISSION. Apple changed the earlier DEVELOPER_REJECTED state when
  the replacement build was selected; no review or release submission occurred.
- Authenticated App Privacy UI reread around 18:55 UTC: 14 declared collected-data
  types, including account-linked Product Interaction/User ID for App Functionality.
  The personal organization-hiding preference is covered by those existing
  operational disclosures; no questionnaire write was made. All 30 archive
  privacy manifests match build 64 exactly. This is technical verification, not an
  independent legal conclusion. Evidence: `build65-privacy-readback.md`.
- Metadata read-back at 18:46:41 UTC: 24 COMPLETE screenshots, six for each of
  DE/UK x iPhone/iPad; updated build reference in review notes; MANUAL release.
- Two additional Simulator navigation tests passed, zero failures/skips (125s
  including build, 79s test execution): feed refresh/detail/back for all three
  feeds and Profile -> Inbox. NavigationRequestObserver warning did not appear
  in these scenarios. Result bundle:
  `test_sim_2026-09-02T18-40-49-947Z_pid1645_a180a459.xcresult`.

## Remaining gates (do not infer completion from authorization)

1. GitHub workflow `33667890597`: Firebase/static jobs and Debug/Release builds
   passed, but test compilation failed on Xcode 26.3: two dynamic `Comment(...)`
   assertion diagnostics collided with the application's `Comment` model. Local
   Xcode 26.6 had compiled them. The test-only correction retains publication
   assertions and explicitly checks `editor.errorMessage == nil`, avoiding the
   ambiguous macro argument. The app binary/backend are unchanged; build 65 does
   not need replacement for a test-only compilation fix. A 55-second full local unit
   run then passed 367/368 tests and exposed one old assertion still expecting
   privacy 2026.11. That assertion now expects the already-published 2026.12;
   bundled-document parity checks remain enabled. No product code changed.
   Final local verification passed 368/368 unit tests, zero failures/skips, in
   54 seconds: `test_sim_2026-09-02T18-52-42-326Z_pid1645_96e4c575.xcresult`.
   Follow-up CI `33670117429` completed on commit `78aab364`: 366/368 tests passed,
   two failed, zero skipped. Compilation succeeded. The failing scenarios were
   `EventRegistrationRaceTests/commentLoadUpdateAndDeleteResolveCurrentEventAndCommentIDs()`
   (empty comments after the controlled read) and
   `PullToRefreshTests/presenceCoalescesPollAndPullAndPublishesBeforeBothFinish()`
   (nil presence snapshot). Both exercise the production 20-second read deadline
   with deliberately suspended mock responses; reported durations were 51/52s.
   Runner contention/deadline expiry is a hypothesis, not a proven root cause.
   The downloaded result bundle is preserved as `build65-ci-followup-xcresult`.
   No retries, skipped assertions, production timeout changes or workflow changes
   were used to turn this result green. The failed CI gate remains open.
   The two exact scenarios then passed unchanged on the Mac, zero skips, taking
   5ms and 3ms respectively (29s runner session), in
   `test_sim_2026-09-02T19-11-26-258Z_pid1645_8a7bc307.xcresult`.
   An earlier focused selector omitted the Swift Testing `()` suffix and
   discovered zero tests; it is not counted as successful test evidence.
   This test/docs-only diff did not select Firebase, Rules, Release or UI lanes;
   their earlier passing code-commit checks are separate evidence.
2. Installed candidate: draft news/event publication; exact request navigation;
   hide/unhide one organization without changing a sibling or author permissions;
   accepted/rejected comment behavior. Preserve the current MFA session.
3. Reproduce and assess the logged navigation warning during the real scenarios.
   Do not change navigation based on the warning string alone.
4. Final operator release/content-rights decision; no submission on behalf of the
   user yet. App Privacy UI was reread for build 65; independent legal review is
   not claimed.

Physical-device boundary: the connected iPhone reported installed build 65 at
19:02:31 UTC. Mac screen-control access was unavailable. The operator agreed to
perform the remaining actions, but installation alone is not a completed
installed-build test. No forced sign-out or MFA re-enrollment was performed.
Scoped production logs from 19:00 to 19:11:49 UTC show two successful
`getBlockedOrganizations` requests, no 5xx/ERROR entries and no requests to the
publication begin/finalize/fail functions in that window. This is evidence of
successful preference reads, not proof that the manual scenarios were completed.

Production read-back, upload logs and installation proof are kept in the ignored
`outputs/release-1.0.1-2026-09-02/` release evidence directory, not committed.
