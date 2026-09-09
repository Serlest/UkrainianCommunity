# Fix80 package 18 — Blocked users

## Result

Implementation is staged locally on Build 80 from `fd58131`. No build, test, Simulator, linter, dependency installation, commit, push, deployment, TestFlight, or release action was run.

## Why this package was needed

The Build 80 source still had four package-specific failure modes:

1. `setUserBlocked(..., false)` read and validated the target account before deleting the caller-owned relationship. A deleted or deactivated target therefore became impossible to unblock.
2. iOS queried by `blockedAt` and used `compactMap`. Missing or malformed denormalized fields could remove an existing relationship from `blockedUserIDs` and reveal blocked content.
3. `UserBlockingCoordinator` applied load and mutation completions after account changes and accepted an uncertain write error without authoritative readback.
4. The blocked-user row kept a two-line horizontal layout at accessibility text sizes.

The concurrent shared-shell change in `ScreenChromeComponents.swift` already moves large accessibility headers into the vertical scroll view. Package 18 preserved that implementation and did not edit the shared shell.

## Changed files owned by package 18

- `functions/src/safety/userBlocks.ts`
- `UkrainianCommunity/Services/Firebase/CloudUserBlockingRepository.swift`
- `UkrainianCommunity/Components/UserBlockingPresentation.swift`
- `UkrainianCommunity/Views/Profile/BlockedUsersView.swift`
- `Docs/Fix80-18-handoff.md`

No shared AuthService, AuthState, UserProfileService, ProfileViewModel, CloudFunctionsClient, Firestore Rules, localization, AppStrings, routing, project, or package-21 file was edited.

## Implemented behavior

### Deleted or deactivated target no longer blocks unblock

The callable now handles `isBlocked == false` before reading the target profile. It transactionally reads and deletes only `users/{actor}/blockedUsers/{target}` and returns an idempotent unblock receipt. Existing display data is used when available; the target ID is the neutral fallback. Target existence and active-state validation remain mandatory when creating a block.

This preserves caller authentication, self-target rejection, App Check behavior, MFA policy, private document ownership, and package-21 account-deletion behavior.

### Relationship reads remain effective with legacy or malformed display fields

The Firestore document ID is now authoritative for `targetUserId`. Reads explicitly use Firestore `.server`, so mutation reconciliation cannot be falsely confirmed from offline cache. The query no longer orders server-side by optional `blockedAt`, so a legacy record without that field is still returned. Missing display name falls back to the target ID; missing timestamps receive deterministic fallbacks; malformed avatar text is ignored. Sorting happens after every relationship has been materialized.

The previous `compactMap` path is gone, so missing denormalized fields cannot silently remove a block from the visibility policy.

### Session isolation, bounded reads, and write reconciliation

`UserBlockingCoordinator` now:

- increments a session generation whenever the configured account changes;
- synchronously clears private list, errors, loading, pending confirmation, and mutation state on account change;
- rejects late load, mutation, and reconciliation completions from an older account;
- invalidates an older load before a mutation and serializes mutations so readback cannot race a second write;
- bounds Firestore reads with the existing `RefreshRequest` 20-second read deadline;
- does not wrap writes in a synthetic client timeout, because a timed-out write may already have committed;
- after an SDK network/deadline, malformed response, or unknown write result, performs a bounded authoritative list read;
- treats the operation as successful only when readback matches the requested relationship state;
- otherwise publishes the authoritative list when available and retains an honest localized error.

### Refresh and accessibility

`BlockedUsersView` now exposes pull-to-refresh through the existing scroll view. At accessibility Dynamic Type sizes, each row places avatar and unrestricted name above a separate unblock action. At normal sizes the compact horizontal row and two-line name remain.

The shared `PushedScreenShell` change already makes the entire header and content vertically reachable at accessibility sizes; package 18 relies on that existing change instead of duplicating it.

## Coordinator dependency

`UkrainianCommunity/Views/ContentView.swift` is owned concurrently by package 17/coordinator. Package 18 did not edit it. Package 17 has added:

```swift
Task {
    await organizationBlockingCoordinator.reload()
    await userBlockingCoordinator.reload()
}
```

inside the existing `UIApplication.willEnterForegroundNotification` handler. This closes the automatic cross-device foreground-refresh dependency; pull-to-refresh remains available on the list itself.

## UK / DE / EN keys

No new localization keys are required. Package 18 reuses existing keys and did not change their translations:

| Key | EN default | DE | UK |
|---|---|---|---|
| `safety.block.error.network` | The change could not be saved. Check your connection and try again. | Die Änderung konnte nicht gespeichert werden. Prüfen Sie Ihre Verbindung und versuchen Sie es erneut. | Не вдалося зберегти зміну. Перевірте з’єднання та спробуйте ще раз. |
| `safety.block.error.unknown` | The change could not be saved right now. Try again later. | Die Änderung kann derzeit nicht gespeichert werden. Versuchen Sie es später erneut. | Зараз не вдалося зберегти зміну. Спробуйте пізніше. |
| `safety.blocked_users.title` | Blocked users | Blockierte Benutzer | Заблоковані користувачі |
| `safety.blocked_users.unblock.confirm.title` | Unblock this user? | Diesen Benutzer entsperren? | Розблокувати цього користувача? |
| `safety.blocked_users.unblock.confirm.message` | %@ will appear in your feeds and comments again. | %@ wird wieder in Ihren Feeds und Kommentaren angezeigt. | %@ знову з’являтиметься у ваших стрічках і коментарях. |

The backend no longer introduces the English literal `Community member` for new block receipts; it uses the stable target ID when profile display data is absent.

## Scenarios for the single common test run

### Backend / emulator

1. Active actor blocks an active target; relationship and receipt contain the target ID and profile data.
2. Delete target after blocking; unblock succeeds and removes the relationship.
3. Mark target deactivated after blocking; unblock succeeds and removes the relationship.
4. Repeat unblock after relationship deletion; response is successful and idempotent.
5. Creating a block for missing/deactivated target still returns `not-found`.
6. Self-block, forged actor field, unauthenticated actor, restricted actor, and privileged actor without required MFA remain rejected.
7. Missing target display name stores/returns target ID, with no English fallback.

### iOS repository / coordinator

8. Server relationship missing `displayName`, `blockedAt`, `updatedAt`, or valid avatar remains in `blockedUserIDs` using safe fallbacks; a conflicting offline cache cannot satisfy the read.
9. A delayed fetch for account A completes after configure B/guest and cannot publish A data or errors.
10. A delayed mutation for A completes after configure B/guest and cannot publish A receipt or errors.
11. Firestore read exceeding 20 seconds ends in the localized load error and keeps any already-confirmed same-session list.
12. Callable reports deadline/network after commit; readback matches desired state, list updates, and no false failure remains.
13. Callable reports deadline/network before commit; readback shows old state, list stays authoritative, and localized network error remains.
14. Reconciliation read also fails; previous confirmed list remains and localized error remains.
15. Concurrent second mutation is rejected while reconciliation for the first is in flight.
16. Pull-to-refresh reloads the authoritative list; foreground reload is checked after the package-17 ContentView hunk lands.

### iOS UI / accessibility

17. UK and DE, light and dark: empty, populated, load error/retry, search/no-results, confirmation, successful unblock, failed/reconciled unblock.
18. AX XXXL and smallest supported iPhone: title, intro, long user name, and unblock action are vertically reachable; name is not truncated at accessibility sizes.
19. Normal Dynamic Type preserves the compact two-line row.
20. VoiceOver reads the name and unblock button separately in stable order; decorative avatar is skipped.
21. During mutation the target unblock action is disabled and a second mutation cannot start.

## Deliberately unchanged product decision

The earlier audit also found that personal blocks are respected by comment-added notifications but not uniformly by every actor-driven moderation or staff notification. This package does not suppress additional notification classes because required moderation/security messages need an explicit product policy. No notification file was changed.

## Verification boundary

Only source and diff review were performed, as instructed. The package is not build-, test-, runtime-, emulator-, device-, deployment-, or release-verified until the coordinator runs the single common test after all Fix80 packages are integrated.
