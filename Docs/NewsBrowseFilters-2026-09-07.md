# Home news filters — 7 September 2026

Implementation checkout: UACAnnouncements-20260907, codex/user-announcements-20260907.
Release target: iOS 1.0.3 (74). Android UI is not enabled by this change.

## Behavior

Selecting News shows Topic and Filters alongside the existing type/region controls.
The topic includes both the primary category and any additional category. Category
identifiers are unchanged; legacy news/event labels are presented as general news /
news about events. Every news row has a topic link and a national/state label.
Topic links select the News mode while retaining region and news filter choices.

The filter sheet uses EditorScreenShell and AppEditorSectionCard. Edits apply only
on Apply; Cancel leaves the current selection unchanged. It offers all time,
today, last 7/30 calendar days, custom inclusive dates, oldest/newest first and
all/saved/subscribed sources. Personal sources require an authenticated session.
The selected period, order and personal scope remain visible in the feed.

News-only choices remain local to Home and inactive outside News mode. Returning
restores them. Account changes clear private results and reset personal scope.
Details preserve the navigation stack; refreshes of an unchanged query retain
visible rows until a successful response. Different queries replace the old result.
Date/time in news details now uses publishedAt instead of draft creation time.

## Query and pagination contract

NewsBrowseQuery / NewsBrowseFilter are independent of SwiftUI views. Android can
use the same raw category/region values and Firestore query semantics without
changing stored documents or iOS-compatible backend contracts.

Public base query:
- sourceType == organization
- moderationStatus == approved
- optional (category == topic OR additionalCategories ARRAY_CONTAINS topic)
- optional (federalState == region OR regionScope == austria)
- optional publishedAt >= start and publishedAt < exclusiveEnd
- publishedAt, document ID ordered in the same chosen direction.

Bounds use Europe/Vienna calendar days, including daylight saving transitions.
Reference time is frozen per refresh so later pages share the same boundaries.
Cursors preserve exact Firestore timestamp components and document ID.

Topic, region, date and order are database query constraints, not filters over the
first loaded Home page. Text search and personal membership checks inspect each
server page. A load action scans up to four 15-row pages; if more remain but no
matches were found, the UI explicitly offers continued searching, not a false
terminal empty state. Matching subscriptions are read for the whole current user,
not only the organizations already loaded on Home. Publication data is never
modified by browsing. Blocked users/organizations retain the existing visibility
policy. Late responses are discarded after query/account changes.

18 composite-index variants cover category/additional-category/no-topic,
state/national/no-region and both directions. All existing indexes are retained.
The index validator now requires these query variants.

## Current data and verification

Read-only production category audit: 95 news documents, 60 with additional
categories; four use the legacy general-news category. No content migration needed.

All 18 new production indexes reached READY. Forty read-only production query
combinations (topic, region, direction and date boundary) matched independently
computed expected results. These reads establish index/query availability;
Firebase emulator tests separately establish guest access boundaries.

Local Rules regression: 175 passed, zero failed/skipped, including the new
anonymous OR-filter/date/cursor scenarios and denial of unpublished queries.
Full Swift regression: 432 tests / 45 suites passed before the final refresh
preservation test was added. Existing Home/event/organization navigation UI test
passed; German and Ukrainian news filter UI scenarios passed.
Final targeted results and release verification are appended after completion.

Evidence under output/announcements:
news-browse-regression.log, news-browse-final-tests.log,
news-browse-all-rules.log, news-browse-live-queries.json,
news-browse-indexes.json, news-browse-validators.log.

## Final local checks

- Final NewsBrowseTests: 7/7 PASS, including delayed responses, account clearing
  and retention of visible rows during a refresh of an unchanged query.
- Final German/Ukraine UI scenarios: 2/2 PASS after adopting the shared editor
  shell; Ukrainian scenario repeated successfully after dark-theme contrast fix.
- Final Firestore query regression: 2/2 PASS, including a document whose primary
  and additional topics both match (no duplicate across page boundaries).
- All seven repository validators PASS for build 73.
- Final screenshots: output/announcements/news-browse-contrast-screenshots and
  news-browse-final-screenshots. The filter sheet uses the semantic foreground
  accent on dark cards. Date range text uses the selected application locale.

The first archive attempt was intentionally interrupted before upload to include
the contrast correction. Release/Apple status is recorded below after completion.


## Final compatibility correction

Build 73 uploaded successfully and Apple marked it VALID. Before final delivery,
comparison with the previous Home search found that publisher, author, city and
the localized content-type title also needed to remain searchable. These fields
were added alongside the new body/tag search, with a dedicated regression test.
Build 74 is the final release target; build 73 is superseded by this correction.
No additional cloud or schema changes are involved.


## Build 74 Apple verification

1.0.3 (74) uploaded successfully and was verified VALID / IN_BETA_TESTING
at 2026-09-07T17:33:11Z; uk/de-DE notes were written and read back exactly.
Source: 66a15dd. Archive compilation: zero warnings/errors; strict signing and
app dSYM UUID verified. Export reported five existing vendor stub dSYM warnings
(FirebaseFirestoreInternal, absl, grpc, grpcpp, openssl_grpc); UAC app symbols
are present. Each affected embedded vendor stub has zero defined symbols.

After upload, the user requested build 75 to incorporate the completed diagnostic
and incomplete-planning-draft fixes from another task. Build 75 supersedes 74;
see Build75Integration-2026-09-07.md. No App Review/public release requested.
