# Organization notifications and personal blocking — 2026-09-02

Status: prepared for build 65. The user authorized commit/push, deployment of only
the two new block callables, upload and installed-build verification. Deployment
and App Store processing are separate gates, recorded after read-back. No Rules
change, MFA change or App Review/public release is authorized by this package.

## Confirmed causes

- The server already includes the submitted organization ID in its notification.
  Both inbox navigation and push navigation discarded that review destination and
  sent submission notices to the recipient's own organizations.
- The organization menu constructed a `UserBlockTarget` from the organization's
  owner ID. It really blocked the person, not the selected organization.
- The management hub used the public catalog as its management source. Applying
  personal catalog hiding there could remove a management entry without actually
  changing permissions. Saved content and subscriptions also bypassed the public
  visibility policy when reading and merging records.

## Local changes

- Inbox and push use one organization-request destination resolver. Submission
  notices open the exact request for authorized owner/admin reviewers. An older
  notice without an ID opens the review queue, not My Organizations. Applicant
  approval/revision/rejection destinations retain their existing meaning.
- Targeted review reads one organization by ID, without the queue's 100-document
  limit. Deleted/not accessible and network states use the existing Firebase error
  mapper. Losing review permission closes the request. Already reviewed requests
  are shown without approval/rejection actions.
- Organization hiding has its own model, coordinator and private storage:
  `users/{authenticatedUserID}/blockedOrganizations/{organizationID}`. The two new
  authenticated callables are `getBlockedOrganizations` and `setOrganizationBlocked`.
  Client input cannot select another user. Writes are transactional/idempotent;
  unblocking also works after organization deletion. Maximum 500 entries/account.
- Firestore and Storage Rules are unchanged. Direct client access to these private
  records stays denied. Existing verified/active-account and privileged-session
  checks remain in force. The callables use the current staged App Check policy;
  this package does not change enforcement or IAM.
- Public organization/news/event visibility uses the organization ID independently
  from author blocking. Saved content/subscriptions use the same policy and cannot
  reinsert hidden content into the shared feeds. Bookmarks/subscriptions are not
  deleted. Undo is available in Profile settings. Per-account local cache preserves
  the last verified hiding preference during network failure; late responses from
  a different session are ignored.
- The management hub uses the existing authoring repository and permission checks,
  separate from catalog visibility. No organization, role, membership or account
  permission is mutated by blocking. Other organizations and the owner's personal
  profile/comments remain unaffected.
- Existing account deletion recursively deletes the user's private subcollections,
  including these new preferences. Existing user blocks are not automatically
  reclassified: their original intent cannot safely be inferred.
- This is personal content hiding, not administrative suspension, unsubscribe,
  registration cancellation, or a new push-notification muting policy.

## Evidence

- TypeScript build/lint: passed.
- Demo Firestore emulator: 9/9 checks passed, none skipped. Includes concurrent
  blocking, same-owner sibling isolation, unchanged roles, account/auth rejection,
  deleted-organization unblock, and direct-client denial with unchanged Rules.
- iPhone 17 Pro Max Simulator: 29 targeted unit tests and one UI test passed in
  95 seconds. UI exercised organization menu, confirmation, settings and unblock.
  Unit checks also include the earlier draft-publication wire-format regression.
- Result: `test_sim_2026-09-02T18-12-07-863Z_pid1645_e5c438d8.xcresult`
  under `~/Library/Developer/XcodeBuildMCP/workspaces/first-update-856190e26dd4/result-bundles/`.
- DE/UK localization validation: 2665 catalog entries passed. `git diff --check`
  passed. Confirmation/settings screenshots were visually inspected.
- Final request-error handling: 12/12 targeted routing/visibility and Firebase read
  error-mapping checks passed in 38 seconds, no failures/skips. Result:
  `test_sim_2026-09-02T18-14-11-488Z_pid1645_e5985794.xcresult` in the same directory.
- The blocking coordinator is supplied outside all root presentation modifiers so
  nested sheets inherit it as well as the tab navigation stacks.
- Final Simulator build after that presentation-scope change passed in 33 seconds,
  without reported build warnings/errors: `build_sim_2026-09-02T18-16-13-385Z_pid1645_88f78493.log`.
- Initial iPad UI attempt was not a pass: the old helper expected an iPhone-style
  tab bar, and the owner fixture reached the real MFA gate. The block test now uses
  the adaptive helper and passed on iPhone. No MFA bypass was added. The attempted
  owner UI fixture/test was removed, not silently marked green. Exact notification
  routing/loading is unit-verified; end-to-end owner UI remains to verify using a
  valid protected session.
- Xcode recorded an iOS hosting/reparenting runtime warning during the passing UI
  run. The flow completed, with inspected screenshots; this is not evidence of a
  warning-free runtime or physical-device verification.

## Remaining release steps

1. Commit this scoped package alongside the publication response fix and the
   separately authorized published Privacy Policy 2026.12; preserve content assets.
2. Production preflight, deploy only the two new block
   callables, and read back their readiness. No Rules change is required.
3. Verify block/list/unblock using an authorized test account and two organizations
   belonging to the same owner. Verify organization and role documents unchanged.
4. Build/upload the next candidate only after backend availability. On a valid
   owner/admin session, verify inbox/push opens the exact submitted request and
   that review, creation and editing still work. No public release is claimed here.
