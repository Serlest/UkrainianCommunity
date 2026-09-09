# Fix80-10 handoff — Feedback

## Implemented iOS API

- `MyFeedbackView(viewModel:currentUserID:initialFeedbackID:)` accepts an optional exact feedback ID.
- `FeedbackInboxView(repository:notificationInboxRepository:initialFeedbackID:)` accepts an optional exact feedback ID.
- Both views open the exact ticket after the authenticated first-page load. If it is outside that page, the view model uses `FeedbackRepository.fetchFeedback(id:)`; Firestore Security Rules remain the authorization boundary.
- Feedback pages use a `(createdAt, documentID)` cursor. My Feedback loads 50 per page; owner inbox loads 100 per page.
- Message pages load 100 per page and expose an in-sheet retry after a load failure.
- View models isolate cached/listener state by authenticated user/actor ID.
- `ProfileViewModel.submitFeedback` retains the same document ID and timestamps when the same failed/uncertain payload is retried, and clears the attempt on success or auth reset.

## Coordinator integration status

The coordinator integrated the notification feedback ID through dedicated `feedbackDetail` / `myFeedbackDetail` routes, added the guest guard, and clears the composer draft/type on every authenticated user-ID change. The localized `feedback.subtitle` now uses neutral sole-developer wording:

- DE: `Sende Feedback oder Fragen direkt an den Entwickler.`
- UK: `Надішліть відгук або запитання безпосередньо розробнику.`

No new localized keys are required. The UI reuses `AppStrings.Moderation.retry`, `AppStrings.Search.loadMoreContent`, and `AppStrings.Feedback.unread`.

## Backend integration status

The client calls `acknowledgeFeedbackReadByUser(id:userID:)` by updating only `unreadForUser` from `true` to `false`. The coordinator added `safeFeedbackUserReadAcknowledgement`, limited to this transition for the signed-in verified owner of the feedback document.

Owner acknowledgement (`unreadForOwner: true -> false`) already fits the owner management rule. Exact-ticket reads use the existing document read rule and do not bypass access checks.

## Verification boundary

Reviewed by reading the owned diffs only. Per package instruction, no build, test, Simulator, linter, dependency install, commit, push, deployment, TestFlight, or public release action was run.
