# Fix80-8 handoff — Activity History

## Scope and baseline

- Repository: `/Users/serlest/Developer/UAC-1.1-Build80`.
- Baseline/HEAD at start: `fd58131d2c7c7c5f50b5d354473b91d271990565` (Build 79).
- Edited only:
  - `UkrainianCommunity/Services/ActivityLogService.swift`
  - `UkrainianCommunity/Views/Profile/ProfileActivityHistoryView.swift`
  - `functions/src/content/contentDeletion.ts`
  - this handoff.
- Shared `AppStrings.swift` and `Localizable.xcstrings` hunk was supplied by the coordinator. Firestore Rules remain owned by section 19 and were not edited here.
- No product build, test, Simulator, lint, install, commit, push, deployment, or production access was performed, as required.

## Covered findings

### Account-bound repository operations and late-result isolation

Every Activity History repository method now takes an explicit `userID` and rejects the operation unless it still matches the Firebase Auth principal. Fetch, record, delete, and clear no longer resolve a potentially changed principal inside an asynchronous operation.

`ActivityLogViewModel` now has separate session and refresh generations. A sign-out/account switch clears rows, errors, loading/clearing/deleting state, and invalidates late refresh results. Delete and clear results are applied only to the session that started them. Starting a mutation invalidates a concurrent refresh so stale rows cannot overwrite a completed deletion.

Opening the destination for an already-loaded account performs a fresh read. This closes the reproducible stale-screen path where an action completed after the first load and reopening History reused `hasLoaded` without fetching again.

### Recording failure and explicit reconciliation

The previous recorder used detached `Task { try? ... }`, which silently discarded failures. It now:

1. captures the initiating Firebase UID;
2. keeps the item under its stable UUID in an account-keyed, process-local pending store;
3. writes only while the same UID is current;
4. removes the pending item only after the repository confirms the write;
5. retries pending items when Activity History is explicitly opened/refreshed;
6. leaves a failed item queued and exposes the reconciliation error through the History error state.

This avoids automatic duplicate records because retries reuse the same document ID. Pending state is intentionally process-local; cold-launch persistence was not added without runtime proof that it is required. Firestore's own offline queue remains the durable transport for writes accepted by the SDK.

New iOS history writes use `FieldValue.serverTimestamp()`. Firestore Rules remain backward-compatible with Build 79 and Android client timestamps; the coordinator explicitly declined an equality-to-`request.time` rule for this release.

### Large clear and existing cap maintenance

- Clear now deletes in repeated batches of 400, avoiding the Firestore 500-operation batch limit.
- Existing best-effort count cap remains 100. Maintenance now reads at most 400, deletes every row after the newest 100, and repeats until no stale tail remains. This fixes the former permanent tail beyond the first 150 without changing the product's retention target or schema.
- The maintenance throttle remains once per account/day and pruning failure remains secondary to the successful user action.

### Filters, disclosure, and accessibility

- Added a dedicated News filter alongside All, Events, Organizations, and Saved.
- When exactly 100 rows are loaded, the screen displays the shared localized bounded-window notice.
- Each trash button now announces `Delete: <item title>`, so VoiceOver users can distinguish rows.

### Organization deletion lifecycle

Organization deletion now removes direct organization entries from both `users/*/recentViews` and `users/*/activityLog`, filtered by `itemType/targetType == organization`. This runs for both owner deletion and discard of an unpublished request. News and event history cleanup remains handled by the existing content deletion policies.

The historical snapshot itself is not classified as a privacy leak. No snapshot fields were erased, no `organizationID` field was added to Activity History, and no visibility/block schema change was made.

## Already fixed or intentionally unchanged

- Build80 already contained the `AppTestHost.isUnitTesting` guard before activity recorder repository initialization; retained.
- Account deletion already recursively deletes `users/{uid}` and its Activity History subcollection; unchanged.
- News/event deletion already removes matching Activity History references; unchanged.
- Recent Views section 7 independently added its account guards and optional `organizationID`; no code was copied into Activity History.
- Sorting implementation and confirmations were already present.
- Activity history remains independent of optional analytics consent.
- No rule hardening for action/target pairs was included. Valid producer pairs are:
  - news: `savedNews`, `unsavedNews`;
  - event: `registeredForEvent`, `canceledEventRegistration`, `savedEvent`, `unsavedEvent`;
  - organization: `followedOrganization`, `unfollowedOrganization`, `savedOrganization`, `unsavedOrganization`.
  The coordinator classified this as optional hardening of a user's own history, not a Fix80 blocker.

## Shared localization supplied by coordinator

Key: `profile.activity_history.limit_notice`

- EN: `Showing your latest 100 activities.`
- DE: `Die letzten 100 Aktivitäten werden angezeigt.`
- UK: `Показано 100 останніх дій.`

Accessor: `AppStrings.Profile.activityHistoryLimitNotice`.

The News filter reuses the existing localized `AppStrings.News.title`; the item-specific delete label composes existing localized `AppStrings.Action.delete` with the stored title.

## Unified verification scenarios

These are required integration checks after all Fix80 hunks are merged. They were not run in this slot.

1. **Record and reopen:** for a verified user, perform each of the ten supported actions, reopen History, and verify one row per changed action with the correct target type and server timestamp.
2. **Failed record reconciliation:** inject one record failure after the primary action succeeds; open History, verify a visible error; restore transport and explicitly refresh; verify exactly one row with the original stable ID.
3. **Account switch during record:** start user A's delayed record, switch to B, then complete the delay. Verify no A row is written/read under B and no late A result changes B's UI.
4. **Account switch during fetch/delete/clear:** delay each repository call, switch accounts, complete it, and verify all late results are ignored and operation indicators reset.
5. **Reopen freshness:** load History, perform another action, leave and reopen the destination, and verify the new row without killing the app.
6. **Filters:** seed mixed target/action rows and verify exact counts and IDs for All, News, Events, Organizations, and Saved.
7. **Bounded window:** seed 101+ rows; verify only the newest 100 display and the localized limit notice is visible in EN/DE/UK.
8. **Single delete:** cancel leaves the row; confirm removes only that row; failure preserves it and surfaces an error.
9. **Large clear:** seed at least 501 rows in the local Firestore emulator; confirm clear and read back zero documents. Inject a later-batch failure and verify the screen reports failure rather than claiming empty.
10. **Cap maintenance:** seed more than 400 rows, allow one maintenance run, and verify exactly the newest 100 remain, including removal of the former tail beyond row 150.
11. **Organization lifecycle:** create organization-target recent/history rows plus same-ID rows of another type, delete/discard the organization, and verify only organization-typed references are removed.
12. **Accessibility:** inspect VoiceOver labels for multiple trash buttons and verify each contains its corresponding item title.
13. **Compatibility:** confirm Build79/Android client-timestamp activity documents remain readable and allowed by unchanged Rules while new iOS writes resolve to server timestamps.

## Remaining risks and dependencies

- The pending recorder queue is process-local. A forced termination between a rejected write and opening History loses the retry item; no disk schema was introduced without direct runtime evidence.
- Clear is chunked but not atomic. A later-batch failure can leave a partially cleared server collection; the UI correctly retains its pre-operation rows and shows an error until refresh.
- The server timestamp and changed repository protocol require integration compilation after coordinator-owned shared hunks land.
- `functions/src/content/contentDeletion.ts` needs the existing content deletion integration suite extended by the integrator for organization-typed references.
- Firestore Rules pair validation is optional and deferred to section 19; it is not required for this functional fix.
- The second section 08 audit runtime stopped after environment setup and supplies no behavioral validation for these changes.

