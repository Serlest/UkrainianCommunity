# Fix80-6 — Followed organizations handoff

Date: 2026-09-09  
Base: `fd58131d2c7c7c5f50b5d354473b91d271990565`  
Scope owner: organization-subscription block only.

## Problems addressed

1. A user could not revoke a subscription after its organization became non-public or was deleted because `unsubscribeOrganization` first read the target document.
2. Explicit pull-to-refresh reused the five-minute in-memory subscription-ID cache, so a change from another device could remain invisible.

The previously suspected stale row after unsubscribe/back is not part of this fix. The earlier frozen-baseline audit runtime rejected that hypothesis; no Build 80 runtime was run during implementation.

## Implementation

- Added `OrganizationRepository.fetchOrganizationSubscriptions(forceRefresh:)` returning marker-backed `SavedContentRecord<Organization>` values. Its default implementation preserves compatibility for mock and alternate repositories; the existing `fetchSubscribedOrganizations()` API remains available.
- `FirestoreOrganizationRepository` now joins the user's existing `likes` subscription markers with only approved, publicly readable organization documents. A missing or non-public target produces a record with `content == nil`; no hidden target fields are read or returned.
- Explicit refresh bypasses both `SessionDataCache` and Firestore's local query cache by requesting the marker and approved-target queries with `source: .server`. Initial/task reloads retain the existing session-cache behavior.
- `unsubscribeOrganization` deletes the user's canonical subscription marker directly. It no longer reads the organization or the marker first, so deletion also works for a hidden or deleted target under the existing owner-delete Rules.
- `FollowedOrganizationsView` renders resolved organizations with the existing card/navigation. Unresolved markers render a generic unavailable card, reveal no organization data, and offer a destructive confirmation followed by direct marker removal.
- Resolved organizations excluded by the user's local visibility policy remain hidden; they are not converted into unavailable cards.
- Failed unavailable-marker removal keeps the row and uses the existing inline subscription error path.

## Localization coordination

Coordinator added and the subscription card uses:

- `AppStrings.Profile.unavailableSubscriptionTitle`
- `AppStrings.Profile.unavailableSubscriptionMessage`
- `AppStrings.Profile.removeUnavailableSubscription`

The corresponding `Localizable.xcstrings` entries contain EN, UK and DE values. AppStrings and localization remain coordinator-owned.

## Files and owned hunks

- `UkrainianCommunity/Views/Profile/ProfileSavedContentView.swift`: only `FollowedOrganizationsView` plus its private unavailable-subscription card.
- `UkrainianCommunity/Repositories/Firebase/FirestoreOrganizationRepository.swift`: only subscription fetch/join, direct unsubscribe, and subscription-marker fetch helper. Existing saved-marker work and organization-review hunks are preserved.
- `UkrainianCommunity/Repositories/RepositoryProtocols.swift`: one subscription-record API declaration and its compatibility default. Existing saved-content APIs are preserved.

## Verification boundary

Per coordination instruction, verification was limited to reading the implementation and final diff. No build, tests, Simulator, emulator, linter, dependency installation, commit, push or deployment was run.

Runtime and integration checks still required:

1. Existing approved subscription displays and opens normally.
2. Approved target becomes pending/rejected or is deleted: generic row appears without target fields; confirmation removes the marker.
3. Failed marker delete leaves the generic row and displays a localized error.
4. A second client changes subscriptions; pull-to-refresh reads server state immediately.
5. Initial navigation retains expected cached behavior and the previously passing unsubscribe/back flow remains unchanged.

