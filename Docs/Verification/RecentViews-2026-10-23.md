# Recently viewed — 2026-10-23

## Scope and data flow

Profile → Recently viewed → news, events and organizations. Successful detail loads record a private snapshot in `users/{uid}/recentViews/{type}_{contentID}`. Reopening an item updates its timestamp rather than creating a duplicate. Guests do not record history. This remains a personal history feature, separate from optional analytics.

The repository now receives an explicit account ID for every operation and verifies it against Firebase Auth. Pending responses cannot populate or delete local rows belonging to a different account. Existing document IDs, fields and access rules are unchanged; older installed versions remain compatible.

## Changes

- Search over saved titles and subtitles; existing type filters and date/name sorting retained.
- Explain that the screen contains the last 30 items. Local recording updates obey the same limit as remote reads.
- Empty history, no matches and loading failures use distinct states. Errors remain visible when a selected filter has no matches. German and Ukrainian strings are in `RecentViews.xcstrings`.
- Accessibility text sizes use a menu for the content-type filter instead of a horizontally clipped chip row.
- Account changes dismiss pending confirmations and reset filters/search. Returning from a detail preserves the selected filter and search.
- History reads no longer load/refresh the three general content feeds. Detail destinations still resolve current content by ID and apply normal availability/visibility rules.
- Reads and destructive actions cannot overlap. New successfully recorded views are merged into a pending read, rather than overwritten by an older snapshot. Late signals for cleared/deleted views are suppressed.
- Clear and retention process bounded pages of 400 documents; transactions reread timestamps before deleting so a concurrently refreshed view survives. Retention continues to be best effort and throttled, not an extra read after every open.
- Cancelled events also enter personal history, without incrementing their normal public view counter.
- Content deleted from a news/event detail opened through history is also removed from this account's history.

## Verification

- `RecentUnit.xcresult`: 8 history tests passed.
- `RecentVerified.xcresult`: 50 unit tests plus one UI journey passed, no failures or skips. The UI journey covers Ukrainian/light and German/dark/accessibility text; search/no results, opening all three content types, individual deletion, clearing and confirmation dialogs.
- `functions/smoke-tests/recentHistoryRules.test.mjs`: passed against the Firestore emulator. Verified own-account writes/reads, rejection of another account and invalid IDs, retention of 30 out of 836 records through multiple deletion pages, and preservation of a concurrent newer view.
- UI screenshots exported to `build/recent-history-20261023/screens`; visual review found clipped large-text chips, addressed by the accessibility filter menu.

- Final source/UI verification: `RecentFinalJourney.xcresult` passed after the accessibility menu and keyboard-submit improvements. This strengthened journey explicitly switches filters, verifies the filter survives a detail round trip, verifies the search screen leaves the accessibility tree when each detail opens, and repeats removal/clear in both languages.
- Final screenshots in `build/recent-history-20261023/final-screens` were visually inspected; accessibility filter and sort controls are no longer clipped.
- An intermediate expanded UI run (`RecentAccessibleUI.xcresult`) failed because the automation's coordinate tap to dismiss the keyboard opened the header clear-history dialog. The test now submits the search field using Return, and the field explicitly releases focus on submission. The final run above is green.

## Delivery boundary

Changes are iOS source only. No rules/schema/function deployment or store upload is required for these changes. UI tests use isolated mock content; rule tests use a demo emulator project, not production user records. Deleted/unavailable content from other devices is resolved by the existing detail's unavailable state; the list does not query each content document merely to display history snapshots.
