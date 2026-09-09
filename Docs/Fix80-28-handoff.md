# Fix 80 — Package 28 handoff

## Scope

iOS Owner Analytics and the Profile preferences analytics-consent switch. Baseline checked at `fd58131d2c7c7c5f50b5d354473b91d271990565`.

## Product changes

1. Daily aggregate coverage is now explicit.
   - A daily document counts as complete only when it exists, parses into nonempty analytics metrics, and has a valid `updatedAt`.
   - The repository compares the complete document IDs with every expected current and previous-period day.
   - Missing or malformed daily documents add `dailyStats` to `unavailableSources`, so the existing partial-data banner is shown instead of presenting the zero-filled range as complete.
   - Daily freshness now uses the oldest current-day timestamp and is excluded from freshness when the required window is incomplete.

2. Owner Analytics refreshes now require Firestore server reads.
   - Overview daily query, top-content, region, and user documents use `.server`.
   - Content and organization detail root, child, and generation-verification reads use `.server`.
   - Offline/cache-only refresh therefore reaches the existing ViewModel error path, which retains the last good snapshot and displays the stale/retry banner.

3. A permanent consent API rejection now updates the visible Profile switch.
   - `FirstPartyAnalyticsService` already clears local consent for `failedPrecondition`, `invalidArgument`, and `permissionDenied`, then emits a collection-change notification.
   - `ProfilePreferencesView` now consumes that stream for the active account and re-reads `isCollectionEnabled`, preventing the switch from remaining visually ON after the service has revoked the rejected local choice.

## Changed files

- `UkrainianCommunity/Models/Analytics/OwnerAnalyticsSnapshot.swift`
- `UkrainianCommunity/Repositories/Analytics/FirestoreOwnerAnalyticsRepository.swift`
- `UkrainianCommunity/ViewModels/Analytics/OwnerAnalyticsViewModel.swift`
- `UkrainianCommunity/Views/Profile/ProfileRootDestinationViews.swift`

## Coordinator-owned dependencies

- Required AppStrings/localization additions: none. The daily source currently uses the existing localized “Views” label in the partial-data list.
- Optional wording improvement: add `owner_analytics.source.daily_stats` with DE/UK translations and expose `AppStrings.OwnerAnalytics.sourceDailyStats`; then replace the existing `views` label for `.dailyStats`.
- Project-file changes: none.
- New package/API dependencies: none. Firestore `getDocument(source: .server)` and `getDocuments(source: .server)` are already used elsewhere in the target.

## Suggested coordinator validation

- Repository contract: complete 1/7/30 current plus previous windows do not mark daily unavailable; one missing document, malformed metrics, or missing `updatedAt` does.
- Emulator: cached successful overview followed by disabled Firestore network produces retained content plus stale/retry state.
- Consent UI: permanent callable denial clears the visible switch; transient network failure preserves the local choice while delivery remains suspended.
- Existing owner overview/detail happy paths and partial-source banner.

No build, tests, Simulator, dependency installation, commit, push, deployment, Android change, or production access was performed in this package, as required by the coordinator.
