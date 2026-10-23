# Profile notification inbox — 2026-10-23

## Changes

- The global live head remains bounded to 50 records (+1 lookahead); loading history uses an exact timestamp/document-ID cursor instead of replacing the listener with a growing limit.
- Page boundaries are computed from raw documents, including soft-deletion tombstones. Empty visible pages retain an explicit load-more action.
- Unread history has its own server query (`isRead == false`, creation date descending, document ID descending), independent of the latest read messages. Archived/deleted records never qualify as unread locally.
- Archive is a separate filter. Archive marks read; restore returns a read record to the inbox; marking an archived record unread restores it. Legacy unread/archive combinations use consistent visual states.
- Error/retry controls sit outside the empty-list branches. Row and detail deletion use confirmation. Account changes dismiss pending destructive confirmation and details.
- Mutation locking and request/session generations reject repeat writes and stale refresh/page results. A live-head update cannot unlock a pending history request. Deletion tombstones and a clear cutoff prevent late reads from restoring removed rows; newly arriving messages survive clear.
- Bulk read/clear reads and writes at most 450 documents per batch. Only records created before the operation cutoff are changed.
- Ukrainian/German labels use a dedicated string table. Controls use the adaptive foreground accent for dark-mode contrast; large text keeps controls and titles reachable.

## Verification

- Simulator compilation passed. Two previously existing unrelated Swift concurrency warnings remain in SystemLogDeliveryQueue.swift and DirectoryEditorAccessStore.swift on a clean recompilation.
- `InboxPaginationFinal.xcresult`: **25 inbox model tests passed** on the final source, including equal-timestamp boundaries and a complete live-head replacement without history gaps.
- `InboxVisualVerified.xcresult`: the full two-language UI journey passed again after the adaptive contrast correction; exported screenshots were visually inspected.
- `InboxVerified.xcresult`: **28 tests passed** (23 inbox model tests, 3 legal-routing tests, 2 system-log-routing tests). Regression coverage includes deleted head pages, older unread messages, legacy archives, repeat writes, late refreshes, live-head/page overlap, account switching, failed page retry and newly arriving messages during clear.
- `InboxFinal.xcresult`: 21 inbox tests and the Ukrainian/German archive/restore/unread/detail/delete-cancellation UI journey passed. German UI uses dark mode and accessibility text size.
- `InboxFixesUI.xcresult`: the existing profile/bell/detail navigation test passed. The first new UI journey exposed a missing string-table lookup; that issue was fixed before the successful final journey.
- Firestore emulator `notificationInboxRules.test.mjs`: **2 tests passed**. The real query shape crosses 50 deleted documents and independently finds older unread records; recipient mutations are accepted, content edits and access to another inbox are rejected. Firestore timestamps are tested at supported microsecond precision.
- Localization, localization-table validator tests, repository structure, composite-index validation and diff whitespace checks passed.

Local evidence: `build/notification-inbox-audit-20261023/` (ignored build artifacts, xcresult bundles, UI screenshots and emulator log).

## Production compatibility

Only an additive composite index was created in production:

`projects/ukrainiancommunity-dbd5f/databases/(default)/collectionGroups/notificationInbox/indexes/CICAgJi0v5MK`

Fields: `isRead ASC`, `createdAt DESC`, implicit `__name__ DESC`. Read-back confirmed **READY**. Authenticated REST queries matching both the live head and unread page returned successfully against an existing private inbox (zero documents in the sampled inbox; no content was printed or changed). The index contract is also enforced by `validate_firestore_indexes.py`.

No rules, Cloud Functions, user content or existing store binary were changed. Client UI changes require a new iOS build. Actual APNs delivery to a physical iPhone was not retested in this change; existing server delivery handlers and routing contracts were preserved.
