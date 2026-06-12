# Firebase Read Policy

This policy locks the app-level read and cache contract for Firebase and Firestore data access. It exists to prevent repeated interaction-state reads from being reintroduced as new screens and features are added.

## SessionDataCache Contract

`SessionDataCache` is the single app-level source for authenticated interaction state:

- `likedNewsIDs`
- `bookmarkedNewsIDs`
- `likedEventIDs`
- `bookmarkedEventIDs`
- `registeredEventIDs`
- `likedOrganizationIDs`
- `subscribedOrganizationIDs`
- `bookmarkedOrganizationIDs`
- `publicProfiles`

Rules:

- Memory only. Do not persist this cache.
- Key all cached data by authenticated `userId`.
- TTL is 5 minutes.
- Reset on login, logout, and user change.
- Mutate cached state only after the matching Firebase write or transaction succeeds.
- Do not store guest interaction state in this cache.

## Repository Contract

Feed repositories must not reread full interaction collections directly when `SessionDataCache` can provide the same state.

Rules:

- News, Events, and Organizations repositories should resolve interaction IDs through `SessionDataCache`.
- Pagination must not reread full interaction sets.
- Detail and organization activity fetches should reuse `SessionDataCache` for interaction state.
- If a new interaction collection is introduced, add it to `SessionDataCache` before using it in feed/detail mapping.
- Repository methods may still read primary content documents and pages normally.

## Refresh Contract

`loadIfNeeded` and `refresh` have different meanings:

- `loadIfNeeded` should respect ViewModel cache and TTL.
- `refresh` intentionally bypasses list TTL.
- `.onAppear` and `.task` should call `loadIfNeeded`, not `refresh`.
- Pull-to-refresh may call `refresh`.
- Content-change notifications may call `refresh` only when the affected content type is relevant.

## Listener Contract

Realtime listeners must be explicit and bounded.

Rules:

- Use one listener per user/path/query.
- Store every listener.
- Remove every listener on user change, detail dismissal, reset, or deinit.
- Prefer `RealtimeListenerBag` where multiple keyed listeners can exist.
- Do not start a one-shot fetch for the same query after listener start unless the fallback is justified in code.

## Detail Contract

Detail screens should be narrow.

Rules:

- Use list memory first.
- Fetch detail data only when the item is missing or stale.
- Do not force-refresh parent lists from detail screens.
- Lazy-load heavy subsections such as comments, photos, team, related activity, and attendee lists.
- Detail activity fetches must reuse `SessionDataCache` for interaction state.

## Future Feature Checklist

Before adding a Firebase read, answer these questions:

- Is this data already in `SessionDataCache`?
- Is there a TTL?
- Is this ViewModel recreated by navigation, sheets, or tabs?
- Is this called from `init`, `.onAppear`, or `.task`?
- Does pull-to-refresh intentionally bypass TTL?
- Is this listener cleaned up?
- Is this a count that should use a maintained counter or Firestore count aggregation instead of `getDocuments().count`?
- Is this query repeated during pagination?
- Does this read depend on authenticated user state that should be reset on login, logout, or user change?

## Non-Goals

This policy does not require changing Firestore rules, Cloud Functions, navigation, UI layout, analytics, notification delivery, or moderation workflows.
