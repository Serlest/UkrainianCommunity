# Incomplete content planning draft — 2026-09-07

## Confirmed production state (read only)

The user confirmed the affected record:
`fd054066f897ff323b3d985d8b4e64b0ad49d882`,
“Street Food & Wine Festival у Шпітталі — час потребує уточнення”.

- kind: event; state: needsAttention; schemaVersion: 2.
- Created and updated 2026-09-07T11:45:20.167Z.
- payload.startDate is absent; payload.endDate and scheduledAt are null;
  publicationMode is now.
- Stored editorial reason: conflicting start times on Friday 18 September,
  11:00 versus 12:00; direct organizer confirmation required before publication.
- No published content link or publication lease was present.
- The read returned 97 planning records, with this the sole needsAttention/failed
  record. Today's queried planning mutation logs contained no non-200/error entry.

This is not an expired publication schedule. `makeEventDraft` requires startDate,
so this record produces eventDraft=nil and isEditableInPlanning=false.
The card previously also hid archive/delete behind isEditableInPlanning. Thus an
incomplete record had no cleanup controls despite the backend permitting these
operations for needsAttention records without linked content.

## Local correction

Separate `canDiscardInPlanning` (readyForReview, needsAttention, failed) from
editor payload availability. Use it to expose the archive/delete menu. Retain
existing confirmation dialogs and backend linked-content checks. Publishing,
scheduled and completed records do not gain unsupported discard controls.

No date was invented, and the real draft was neither published nor deleted.
Publication remains blocked until the editorial conflict is resolved and a valid
startDate is supplied. This change restores cleanup controls in the next app build.

## Validation

Simulator build passed. OwnerContentPlanningViewModelTests: 12 passed, 0 failed,
0 skipped, including incomplete-event archive/delete and all lifecycle-state
action gates. `git diff --check` passed.

Result bundle:
`~/Library/Developer/XcodeBuildMCP/workspaces/new-chat-4-00a68fe9c00b/result-bundles/test_sim_2026-09-07T17-23-00-547Z_pid16726_fbecd887.xcresult`.

These are local tests, not a physical-device or deployed-release verification.
