# History of my actions — 2026-10-23

## Scope

Profile → `Історія моїх дій` / `Verlauf meiner Aktionen` records personal saves/removals, organization follows/unfollows and event registrations/cancellations. It remains separate from recently viewed content and optional analytics. Likes/comments are not advertised as part of this history.

## Changes

- Search by action, title and snapshot subtitle; content filters, saved-action filter and date/name sorting retained. The screen explicitly explains the latest-100 limit and the separate recently-viewed section.
- Empty filter/search results no longer claim the entire history is empty. Errors remain visible with an empty filter. Error text refers to history rather than news.
- Accessibility sizes use a type menu and vertical cards. Full action labels wrap; small decorative action badges keep a fixed size while the readable action text scales. Search submits/dismisses the keyboard explicitly.
- The selected filter/search survives detail navigation. Account switches dismiss pending confirmations and reset local controls.
- Removing a saved news/event/organization from the Saved screen and unfollowing from Subscriptions now records an action after successful completion. The operation's account ID is captured before the request and passed to the recorder. Failed or stale-account requests do not record actions.
- Backend history entries stay immutable. Recording uses a transaction: create a missing stable ID, or acknowledge an existing ID with matching action/target without writing. This fixes retry after a lost acknowledgement without changing deployed rules or duplicating/moving an existing entry.
- Per-account writes, retries and destructive actions share an ordered queue. Reads and local destructive actions cannot overlap. Successful writes are published and merged with pending refresh results. Late signals for deleted/cleared items are suppressed.
- Pending delivery is persisted in private app settings per account, bounded to the latest 100 entries. It survives app restart and is retried when history is opened/refreshed. Successful delivery/deletion removes it; clearing preserves actions created after confirmation.
- Confirmed account deletion purges undelivered local history entries for that UID before completing local account cleanup.
- New records preserve the action occurrence timestamp rather than using the later retry/delivery time. The existing rules accept this timestamp without schema changes.
- Clear removes history only, in pages of 400 older than the confirmation cutoff. Confirmation text explicitly states that saved content, follows and registrations remain unchanged.

## Evidence

- `build/activity-history-20261023/ActivityUnit.xcresult`: initial 9 state/ordering tests passed. Two initial closure-isolation warnings were corrected with explicit MainActor closure types.
- `build/activity-history-20261023/ActivityVerified.xcresult`: 53 tests passed with no failures/skips/warnings. Includes the Ukrainian/light and German/dark/accessibility UI journey, plus action emission from Saved/Subscriptions and failure handling.
- `functions/smoke-tests/activityHistoryRules.test.mjs`: passed against a demo Firestore emulator. Initial create + same-ID retry leaves one entry with unchanged timestamp; conflicting targets are rejected; raw updates and another account's writes/reads remain denied. A 100-row query and clearing 501 entries in bounded batches were verified while newer entries survived.
- Screenshots exported under `build/activity-history-20261023/screens` were visually reviewed in both languages.

- `build/activity-history-20261023/ActivityFinal.xcresult`: 55 tests passed, with no failures/skips/warnings; includes restart persistence, stale-account removal suppression and the complete two-language UI journey.
- `build/activity-history-20261023/ActivityFinalUnit.xcresult`: final 10 history tests passed after the action-timestamp and badge adjustments. `rules-final.log` confirms the same-ID retry preserves the original occurrence timestamp under the existing rules.
- Final compile (`build_sim_2026-10-23T16-21-40-144Z_pid52586_b23daaac.log`) succeeded after integrating account-deletion cleanup. It reports two existing Swift 6 migration warnings in unchanged `SystemLogDeliveryQueue.swift:52` and `DirectoryEditorAccessStore.swift:50`; no warning comes from the changed history code.
- Active production rules were read back through the existing Firebase CLI session: `projects/ukrainiancommunity-dbd5f/rulesets/2bac9d14-b5ca-4756-b95d-a4d7cffc246c`. The actual `safeActivityLogWrite` permits the unchanged fields and a timestamp for `createdAt`, confirming the new client occurrence timestamp is compatible. Evidence: `build/activity-history-20261023/live-rule.json`. The gcloud identity initially returned 403; no permissions were changed.

## Delivery boundary

This is an iOS source change. The existing `users/{uid}/activityLog/{id}` schema and Firestore access rules are preserved. No server/rules deployment or App Store/TestFlight upload is part of this change. Rules checks use a demo emulator and UI checks use isolated fixtures; production accounts were not modified. The installed binary receives these improvements with a new build.
