# Fix80-24 handoff — Feedback operation reconciliation

## Result

Implemented in the shared Build 80 checkout from base `fd58131`. Existing package 10 pagination, unread, message retry, session isolation, exact-ticket routing and initial feedback submission changes were preserved. No commit, push, deployment, build, test, Simulator run, linter or dependency installation was performed.

## Changed files owned by package 24

- `UkrainianCommunity/Repositories/RepositoryProtocols.swift`
- `UkrainianCommunity/Repositories/MockFeedbackRepository.swift`
- `UkrainianCommunity/Repositories/MockRepositoryStore.swift`
- feedback section only in `UkrainianCommunity/Services/Auth/UserProfileService.swift`
- `UkrainianCommunity/ViewModels/FeedbackInboxViewModel.swift`
- `UkrainianCommunity/ViewModels/MyFeedbackViewModel.swift`
- the close-action call site only in `UkrainianCommunity/Views/Profile/FeedbackViews.swift`

`UserProfileService.swift`, the view models, protocol, mock files and `FeedbackViews.swift` also contain concurrent Build 80 edits. Integrate by hunk and do not attribute their whole-file diffs to package 24.

## Idempotent operation contract

- User messages, owner replies and close-system messages now share `FeedbackOperationAttempt`: a stable operation/message ID plus exact feedback ID, kind, text, actor ID, actor display name and creation time.
- Each view model retains unresolved attempts in `PendingFeedbackOperationBuffer`, keyed by operation kind and feedback ID and capped at eight entries.
- A retry with the same actor and payload reuses the same ID and timestamp. Editing the payload replaces that pending intent.
- A confirmed success removes the attempt. A later intentional message with identical text therefore receives a new ID and is not collapsed into the previous successful operation.
- Auth/session reset clears the pending buffer so one principal cannot inherit another principal's operation.

## Firestore reconciliation

- `FirestoreFeedbackRepository.performFeedbackOperation` first verifies the current authenticated UID against the attempt actor.
- A Firestore transaction reads the exact message document. If it already exists, success is returned only when every stored operation field matches, including actor, role, text, system flag and timestamp.
- If the document does not exist, the same transaction creates it with the stable ID and updates the parent summary/status.
- This makes a retry after a lost commit response a read-only authorized reconciliation instead of a second random message creation.
- Existing Firestore Rules already authorize the exact message read only to the feedback owner or feedback managers; no Rules or localization dependency was added.

## Mock and DSA integration

- The mock store applies the same stable-ID reconciliation and rejects a same-ID/different-payload collision.
- Mock single deletion rejects embedded DSA feedback.
- Mock clear removes ordinary feedback and messages while preserving embedded DSA feedback and its messages, matching package 21's client-visible contract.
- Source review confirms the package 21 backend protects both embedded and canonical DSA cases, bulk clear counts only actual deletions, and retention is the explicit allowed DSA deletion path.
- `FeedbackInboxViewModel.clearInbox` still performs backend readback instead of assuming an empty list; the owner UI still replaces embedded-DSA trash with the retention lock.

## Verification boundary

- Reviewed the owned diffs and searched all Swift call sites for the removed random-ID send/close APIs.
- `RecordingFeedbackRepository` remains source-compatible through the protocol's explicit failing default for the new mutation operation; the two product repositories provide concrete implementations.
- Build, tests, Simulator, runtime Firestore, lint, commit, push, deployment, TestFlight and release readiness remain NOT VERIFIED by package instruction.
