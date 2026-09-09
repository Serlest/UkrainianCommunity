# Fix80 package 21 — Account deletion and DSA backend

## Result

Implementation is staged locally on `codex/uac-1.1-build80` from Build 79 (`fd58131`). No commit, push, deployment, build, test, Simulator run, linter, or dependency installation was performed.

## Changed files owned by package 21

- `functions/src/users/accountDeletion.ts`
- `functions/src/users/accountDeletionPolicy.ts`
- `functions/src/users/accountDeletionPolicy.test.ts`
- `functions/src/feedback/feedbackManagement.ts`
- `functions/src/retention/dataRetention.ts`
- `UkrainianCommunity/Services/Auth/UserProfileService.swift`
- `UkrainianCommunity/Services/Auth/AuthService.swift`
- `UkrainianCommunity/Services/Auth/AppLockService.swift`
- `UkrainianCommunity/Services/Analytics/AnalyticsConsentService.swift`
- `UkrainianCommunity/ViewModels/ProfileViewModel.swift`
- `UkrainianCommunity/Views/Profile/AuthViews.swift`

These Swift files also contain concurrent edits from other Build 80 packages. Integrate by hunk; do not attribute the whole-file diff to package 21.

## Fixed

### DSA retention versus feedback deletion

- Owner deletion and bulk inbox clearing now preserve a feedback record when it has an embedded `dsaCase` or a canonical `dsaCases/{feedbackId}` record.
- A direct attempt to delete protected DSA feedback returns `failed-precondition`.
- Bulk clearing pages by document ID and counts only records actually deleted. Protected DSA records no longer cause an infinite first-page loop and do not consume the 10,000-deletion cap.
- Scheduled DSA expiry cleanup is the explicit path allowed to delete the feedback mirror. Closed-feedback retention reports the actual deletion count after protected records are skipped.

### Idempotent account-deletion reconciliation

- `deleteOwnAccount` records an Admin-only, SHA-256-keyed operation receipt with `started`, `privateData`, `references`, `userRoot`, `authIdentity`, and `completed` stages.
- The receipt stores no UID, email, display name, or copied profile values. It expires after seven days and scheduled retention removes it.
- A retry can continue after the Firestore user root is gone. Re-running each stage is idempotent, and `auth/user-not-found` is accepted after the identity stage.
- A completed receipt returns success on a repeated authenticated call.
- Failure to write the final receipt after Auth deletion is logged but does not turn an already completed destructive operation into a retryable client error.
- Active `analyticsConsentStates/{uid}` is deleted. Legal-acceptance and analytics-delivery receipts remain under their existing retention policies.

### Personal-reference cleanup

Added anonymization for retained references in:

- DSA decision, appeal decision, previous decision, and previous appeal actors;
- feedback DSA decision mirrors;
- per-user DSA statement decision copies;
- feedback reply and latest-message actors;
- user status updater references.

Retained logs also redact `ownerReply` and `lastMessageText` when they contain the deleting user's known personal values.

### iOS completion and local residue

- The client writes a hashed local deletion journal before calling the backend, marks server confirmation, and clears the marker only after local sign-out completes.
- Session restore and interactive sign-in resume a pending backend operation before loading a missing profile. A server-confirmed operation skips an unnecessary retry and proceeds directly to local cleanup.
- Successful deletion removes per-account analytics consent/version keys and App Lock enabled/grace keys.
- Post-deletion sign-out failure is no longer silently treated as success. The local journal remains for the next launch/sign-in reconciliation.
- Concurrent delete submission no longer returns a false success, and generic backend failure no longer uses the inaccurate existing text saying the account was definitely not deleted.

## Already correct before this package

- End users were already prohibited from deleting their own feedback records through `clearMyFeedback` and `deleteMyFeedback`.
- Client and callable already enforced a recent-authentication window.
- Platform-owner and organization-owner deletion guards already existed.
- Canonical DSA cases already carried `expiresAt`, and scheduled retention already removed expired canonical cases and related statements.
- The account-deletion UI already had a destructive confirmation flow.

## Coordinator-owned follow-ups

No localization or `AppStrings.swift` files were edited. The coordinator should add and wire localized Ukrainian/German copy for:

1. Account deletion completed on the server but local sign-out still needs recovery; avoid saying the account was not deleted.
2. A pending deletion that needs sign-in again to resume.
3. Direct deletion of DSA feedback being unavailable until regulatory retention expires.
4. Bulk feedback clearing deleting ordinary feedback while retaining DSA cases until expiry.

The present direct-delete callable exposes DSA protection as `failed-precondition`; the existing iOS repository/view-model mapping may otherwise show a generic failure.

An in-flow recent-login/MFA challenge is still not implemented. The current app tells the user to sign in again, and a pending operation can resume after that sign-in. Building an embedded reauthentication flow requires shared auth UI and localized copy outside package 21 ownership.

A narrow unresolved edge remains when the callable response is lost after Firebase Auth identity deletion while the local journal is still `pending`: the Functions SDK may be unable to authenticate the receipt read. The server-side deletion itself has completed; fully deterministic client reconciliation of that state would require a separately authorized proof endpoint or another non-UID recovery token design.

## Verification status

- Source review: completed for the package-owned backend and Swift hunks, including producer-field checks for DSA mirrors and retained actor references.
- Tests/build/runtime/deployment: NOT VERIFIED by instruction.
- Release readiness: NOT VERIFIED. Backend remains staged and undeployed.
