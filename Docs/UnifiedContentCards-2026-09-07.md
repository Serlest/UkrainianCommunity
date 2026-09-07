# Unified content cards — 2026-09-07

## Baseline and implementation

The screenshot's footer was `NewsTopicLink` in commit `7cbad8f`, subsequently
included in `codex/user-announcements-20260907`. The older checkout on
`integration/local-product-progress` did not contain it. This package starts at
`9bcf038` on branch `codex/unified-content-cards-20260907` in
`/Users/serlest/Developer/UACUnifiedCards-20260907`.

`ContentFeedCard` now provides the shared thumbnail, type badge, title, preview,
publisher or organization metadata, and event date. `ContentCardMetadataFooter`
provides the category on the left and geographic scope on the right, outside
the main card surface. Both adapt to accessibility text sizes. Long categories
wrap instead of colliding with the region. Publisher text expands at accessibility
sizes. A missing geographic value no longer implies nationwide coverage.

## Coverage

| Surface | Implementation | Verification |
| --- | --- | --- |
| Home mixed feed and filtered news | Shared card + separate footer | UI navigation and news topic filtering passed |
| Events, upcoming and past | Shared card | UI navigation passed; schedule tests passed |
| Organization directory | Shared card | UI navigation passed |
| News list | Shared card through NewsCard | Compiled; same source adapter/render tests |
| Saved news/events and saved/subscribed organizations | Shared card | Compiled; model adapters checked; individual saved-screen journey not rerun |
| Organization news/event activity, compact and full | Shared card | Compiled; source metadata/destination adapter tests passed |
| Related news | Shared card with recommendation reason retained | Compiled; individual recommendation journey not rerun |
| News/event editor preview | Shared card, including local UIImage preview input | Compiled; actual image-picker journey not rerun |

Management panels, planning receipts, system logs, banners and full detail pages
are separate UI types, not public content-list cards. Their specialized controls
remain separate. Existing navigation destinations, swipe actions, permissions,
pinned indicators and recommendation reasons remain attached at their original
call sites. No Firestore, Functions, public content, release configuration or
Android changes are included.

News topic taps on Home retain the existing independent server-backed filter
operation. This package adds category information for events/organizations; it
does not add new category-filter actions on their footers. Their existing filter
controls remain available.

Event adapters retain category, next occurrence, all-day state, registration
accessibility text and multi-day endpoint formatting. Organization activity now
carries the same display adapter instead of dropping category/geographic data.

## Validation

- Final build: passed, no compiler warnings reported.
- Final unit/render run: 15 passed, 0 failed, 0 skipped.
  Includes ContentFeedCardTests, NewsBrowseTests, EventSchedulePresentationTests
  and ContentFeedCardRenderingTests.
- UI run: 2 scenarios passed. Category tap → news filtering → detail → back;
  Home/Events/Organizations detail/back routes in Ukrainian dark, German light,
  and Ukrainian accessibility XXXL (nine screen captures).
- Twelve standalone card renders: all three content types in Ukrainian/German,
  standard and accessibility5, including a deliberately long finance category.
  These were used to inspect complete cards: the full-screen XXXL screenshots
  mostly showed the existing large header/banner and were insufficient on their own.
- `git diff --check`: passed.
- Mock data/placeholder thumbnails were used; no production content was created.
- Physical-device and TestFlight verification have not been performed.

Evidence (local Xcode result bundles):
- `~/Library/Developer/XcodeBuildMCP/workspaces/new-chat-4-00a68fe9c00b/result-bundles/test_sim_2026-09-07T19-27-19-641Z_pid35240_3b04e3ca.xcresult`
  (11 unit tests + 2 UI tests; before the final accessibility publisher-line expansion)
- `~/Library/Developer/XcodeBuildMCP/workspaces/new-chat-4-00a68fe9c00b/result-bundles/test_sim_2026-09-07T19-33-34-501Z_pid35240_4783c214.xcresult`
  (final 15 unit/render tests)

Exported screenshots: `output/unified-cards-qa/`.
Complete final renders: `output/unified-final-renders/`.
