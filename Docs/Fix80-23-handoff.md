# Fix80-23 — Moderation handoff

## Scope

Source-only fixes for the remaining M23 moderation findings on the shared Build 80 checkout. The package preserves the existing Fix80-17/18 block-list work, Fix80-21 DSA retention/account-deletion protections, Fix80-22 organization-review transaction work, and Fix80-24 feedback operation idempotency.

## Implemented

- Authenticated content reports now deduplicate only identical, still-active reports from the same reporter and target. The fingerprint includes the normalized reason, illegal-content explanation, legal basis, and evidence. Changed evidence creates a new case, and a completed/stale mapped case also creates a new case. A duplicate increments occurrence counts and refreshes the active case retention deadline.
- News and event approval/rejection now use the new `reviewContentModeration` callable. The callable requires the exact loaded `updatedAt` revision and a stable operation ID, checks `pendingReview` inside the transaction, and persists a short-lived receipt. A same-operation retry returns the committed result; changed payloads and stale revisions fail closed.
- DSA case decisions, appeal submissions, and appeal decisions accept optional operation IDs and expected revisions for compatibility with older clients. Build 80 retains a stable operation ID until a confirmed response and sends the exact revision loaded from the feedback document.
- DSA decisions verify any required content removal/restriction inside the same transaction as the case decision. Same-operation retries do not create another decision, notification, statement, or audit entry.
- Post-commit DSA notification/audit failures and content-moderation audit failures are logged as diagnostics without turning a committed decision into a client failure.
- The feedback inbox exposes DSA decision actions only to the app owner, matching the callable authorization. The unsupported `restricted` choice was removed from the decision sheet; the server value remains accepted for compatibility with existing callers that first apply a real restriction.
- Scheduled retention cleanup now removes expired `contentModerationOperations` and `contentReportDeduplication` documents.

## Files owned by this package

- `functions/src/safety/contentModeration.ts` (new)
- `functions/src/safety/contentReports.ts`
- `functions/src/safety/dsaCases.ts`
- `functions/src/index.ts`
- `functions/src/retention/dataRetention.ts` (narrow additions beside Fix80-21 changes)
- `UkrainianCommunity/Services/Firebase/CloudFunctionsClient.swift`
- `UkrainianCommunity/Repositories/RepositoryProtocols.swift`
- `UkrainianCommunity/Repositories/Firebase/FirestoreNewsRepository.swift`
- `UkrainianCommunity/Repositories/Firebase/FirestoreEventRepository.swift`
- `UkrainianCommunity/ViewModels/FeedbackInboxViewModel.swift`
- `UkrainianCommunity/ViewModels/MyFeedbackViewModel.swift`
- `UkrainianCommunity/Views/Profile/ModerationToolsView.swift`
- `UkrainianCommunity/Views/Profile/FeedbackViews.swift`

These files contain unrelated shared-tree changes from other Fix80 packages; integrate the Fix80-23 hunks rather than replacing whole files.

## Deployment dependency

The Build 80 iOS moderation queue depends on deploying the new `reviewContentModeration` callable. The changed callable implementations that must accompany it are `submitContentReport`, `decideDsaCase`, `submitDsaAppeal`, and `decideDsaAppeal`. `cleanupExpiredData` must be deployed for expiry cleanup of the two new service collections. Existing callable names and required legacy request fields remain compatible; the new DSA request fields are optional.

## Boundaries

- No Firestore Rules changes.
- No MFA or App Check expansion.
- No public portal retention or policy change.
- No Android changes.
- No localization keys or project-file changes from this package.
- No build, tests, Simulator, linters, dependency installation, commit, push, or deployment were run, per coordinator instruction.

## Coordinator verification

Review the combined diff, then run the repository's normal Functions type/lint checks and iOS build after all shared packages settle. Runtime scenarios should cover identical active-report retry, changed-evidence new report, completed-case new report, concurrent news/event decisions, lost-response same-operation retry, stale revision rejection, owner versus app-admin DSA controls, DSA decision retry, appeal-submission retry, and appeal-decision retry.
