# Fix80-05 — Saved content handoff

## Scope and baseline

- Working tree: `/Users/serlest/Developer/UAC-1.1-Build80`
- Base/HEAD at start: `fd58131d2c7c7c5f50b5d354473b91d271990565`
- Implemented only Saved content and its repository reads. The Followed organizations section in `ProfileSavedContentView.swift` was preserved.
- No build, tests, Simulator, formatter, linter, dependency installation, commit, push or deployment was run, per delegation.

## Implemented behavior

1. `SavedContentView` now owns a dedicated session-bound `SavedContentViewModel`. It holds the three saved snapshots, partial-load error, loading state, removal state and a generation guard for late auth/session responses.
2. Successful unbookmark from a news/event/organization detail is reconciled only after the corresponding optimistic mutation leaves its pending set. A failed write that rolls back to bookmarked therefore keeps the row. Returning to Saved also executes a fresh repository read.
3. Saved repositories now return one `SavedContentRecord` per private bookmark marker. Each record contains only marker ID, optional marker `createdAt`, and optional approved/readable content.
4. A deleted, unpublished, blocked or otherwise hidden target becomes a generic unavailable card. The card exposes only its content kind and shared unavailable copy; it never renders the hidden target's fields. The owner can delete that bookmark marker directly, with write failure surfaced inline.
5. Newest/oldest sorting now uses bookmark `createdAt`. Legacy markers or non-Firestore repository implementations without a bookmark timestamp use `nil`, sort after dated records, and receive the stable prefixed-ID tie break. No bookmark migration is hidden in this change.
6. The existing `RefreshRequest` 20-second read deadline remains around all three Saved reads. Writes are not placed behind a timeout because their result would be ambiguous.
7. `ProfileView` passes its existing repository instances into `SavedContentView`, so production, mocks and alternate containers use the same dependencies as detail screens.
8. Saved news, event and organization cards lift their fixed line limits at accessibility Dynamic Type sizes. The shared organization card used by Followed organizations was not changed.

## Files and shared dependencies

- `UkrainianCommunity/Views/Profile/ProfileSavedContentView.swift`
  - Saved block, private Saved card types and Saved-only organization card.
  - The existing `FollowedOrganizationsView` block was not edited.
- `UkrainianCommunity/Views/Profile/ProfileViews.swift`
  - Narrow `.savedContent` destination hunk only: passes the three existing repositories.
  - Preserve concurrent feedback routes and auth draft-reset work when integrating.
- `UkrainianCommunity/Repositories/RepositoryProtocols.swift`
  - Additive `SavedContentRecord` plus `fetchSavedNews`, `fetchSavedEvents`, `fetchSavedOrganizations` requirements and backward-compatible default implementations.
  - This is shared with Fix80-24 feedback API work; integrate the Saved hunks without replacing other protocol edits.
- `UkrainianCommunity/Repositories/Firebase/FirestoreNewsRepository.swift`
  - Reads news bookmark marker IDs and `createdAt`, resolves only approved organization news, retains unresolved markers.
- `UkrainianCommunity/Repositories/Firebase/FirestoreEventRepository.swift`
  - Equivalent event behavior.
- `UkrainianCommunity/Repositories/Firebase/FirestoreOrganizationRepository.swift`
  - Equivalent organization behavior. This file also contains unrelated concurrent organization-review changes; preserve them.

No Saved repository implementation was found in `UserProfileService.swift`; that file was not changed.

## Localization

No new keys are required. The unavailable card reuses:

- `AppStrings.DetailState.unavailableTitle`
- `AppStrings.DetailState.unavailableMessage`
- `AppStrings.Organizations.removeBookmark`
- existing localized News/Events/Organizations section titles

`AppStrings.swift` and `Localizable.xcstrings` were not edited.

## Read-only verification performed

- Re-read the actual Build79 Saved flow and all three Firestore bookmark implementations.
- Read the final diff and ran whitespace/conflict-marker checks only.
- Confirmed delimiter counts are balanced in the touched Swift sources.
- Confirmed the generic default protocol implementations keep existing mocks conforming without source migration.

This is implementation evidence only. Compilation, runtime behavior, Rules behavior and visual/accessibility behavior remain unverified until the coordinator's integration pass.

## Required integration checks

1. Build after all concurrent `RepositoryProtocols.swift`, `ProfileViews.swift` and `FirestoreOrganizationRepository.swift` changes are integrated.
2. Unit-test Saved VM with three successful branches, one partial failure, all failures, 20-second deadline, late A→B completion and failed unavailable-marker removal.
3. Runtime: open Saved → detail → successful unbookmark → Back; row/count must disappear. Repeat news/event/organization and a failed-write rollback.
4. Emulator: retain markers while deleting or unpublishing targets; Saved must show generic unavailable rows, reveal no target data and allow owner removal.
5. Verify newest/oldest with content dates deliberately opposite to bookmark `createdAt`, plus missing/legacy timestamps and stable ID ties.
6. Repeat UK/DE, light/dark, small width and Accessibility XXXL with actual VoiceOver.

## Material limits

- The unavailable state cannot distinguish deleted from unpublished, permission-hidden, blocked or malformed content, by design; exposing that distinction could leak moderation or existence details.
- Bookmark markers created before `createdAt` became reliable remain sortable only by stable ID after all timestamped records.
- The current generic error copy is shared with Saved loading. If product wants action-specific unavailable-bookmark removal copy, coordinator can add dedicated UK/DE/EN keys later.
