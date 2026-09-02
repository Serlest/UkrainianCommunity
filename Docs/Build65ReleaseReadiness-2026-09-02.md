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

## Remaining gates (do not infer completion from authorization)

1. Commit/push and verify the remote revision.
2. Deploy only the two new callables; verify ACTIVE, existing functions and Rules
   unchanged, and unauthenticated access denied.
3. Archive/upload build 65, verify Apple processing and select the new candidate.
4. Installed candidate: draft news/event publication; exact request navigation;
   hide/unhide one organization without changing a sibling or author permissions;
   accepted/rejected comment behavior. Preserve the current MFA session.
5. Reproduce and assess the logged navigation warning during the real scenarios.
   Do not change navigation based on the warning string alone.
6. Final operator release decision; no submission on behalf of the user yet.

Production read-back, upload logs and installation proof are kept in the ignored
`outputs/release-1.0.1-2026-09-02/` release evidence directory, not committed.
