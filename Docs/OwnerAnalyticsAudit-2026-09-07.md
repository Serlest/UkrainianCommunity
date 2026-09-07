# Owner analytics audit — 2026-09-07

## Confirmed defects and corrections

The user screenshot showed uneven metric cards, vertically displaced icons and
values, and ellipsized comparison text. All icon containers were already 30×30;
the visible displacement came from vertically centered, independently sized
adaptive-grid cells. The primary value also used a different font size.

- Analytics-only layout measures intrinsic content at the available column width
  and gives each card the maximum height in its row, aligned at the top.
- Uniform title2 number typography, unchanged SF Symbol aspect ratios and 30×30
  base icon backgrounds; no stretching of icons. All six analytics icon badges
  now scale their containers with Dynamic Type so enlarged symbols stay inside.
- Metric titles and comparisons no longer have a two-line truncation limit.
  Percent and direction are separate from the secondary comparison caption.
  VoiceOver retains the full comparison sentence.
- One column for accessibility text sizes or compact vertical size class.
- The same card layout is applied to content and organization detail screens.
- At accessibility sizes, analytics introduction moves into scrolling content;
  the previous fixed subtitle consumed most of the viewport. The shared profile
  shell has an opt-in flag, default false, so other profile screens retain their
  existing layout.

## Audit matrix

| Area | Evidence / result |
| --- | --- |
| Today, 7/30 days, date boundaries | PASS: Swift contract tests, Vienna timezone/DST and immutable read anchor inspected; UI 7-day news details and 30-day organization journey |
| Search, empty result, clear | PASS: Swift search contract and main/organization UI tests |
| Sorting, content/region metric semantics | PASS: Swift tests for stable ties, region signals, localized category labels |
| Late responses, refresh failure, cache expiry | PASS: main and detail view-model race/stale-cache tests; last good data retained with explicit warning |
| Partial/missing data, lifecycle coverage | PASS: repository contract tests; partial-source banners and coverage labels reviewed; no assertion that legacy history is complete |
| Detail navigation | PASS: news detail and organization detail/search UI journeys |
| Charts | PASS: 7-day chart UI presence; date selection normalization and Vienna day labels tested; individual drag/VoiceOver gestures not exercised |
| Owner-only access | PASS: UI route gate inspected; emulator allows only active owner aggregate reads; denies admin/user/guest and client aggregate writes |
| Backend aggregation, consent and delivery | PASS: 75 server tests, no failures/skips, including analytics access Rules |
| Visual geometry | PASS: light/dark Ukrainian UI asserts equal row top/width/height; screenshots reviewed |
| Large text | PASS: maximum Ukrainian text, scrolling intro, one-column metrics; final icon-container correction rechecked below |
| Live data | PASS: read-only 11 aggregate documents, including today/yesterday and all period top-content/region/user summaries |
| Physical iPhone, iPad, VoiceOver operation | NOT VERIFIED in this audit; simulator results do not prove these |

## Production screenshot arithmetic

Read at 2026-09-07T18:24:34Z. Today: 7 total views = 3 news + 3 event +
1 organization; 5 active region keys. Yesterday: 31 = 13 + 8 + 10; 5 regions.
The displayed deltas are correct: -77.4%, -76.9%, -62.5%, -90%; regions unchanged.
Today compares the current partial calendar day with the entire previous day.

Today's view/top-content/region documents last changed at 15:32:49Z. The
freshness label therefore correctly shows an older data timestamp; it does not
mean the refresh button failed. Seven-/thirty-day rollups were updated around
18:01Z. This checks stored aggregate consistency, not independently observed
physical-device events or all historical raw data.

No production writes, deployments, account creation, or content mutations.

## Validation artifacts

All paths under output/announcements/:
- analytics-audit-ios.log: 57 tests / 3 suites PASS; 3 UI tests PASS.
- analytics-organization-ui.log: 30-day organization journey PASS.
- analytics-audit-server.log: 75 PASS, 0 FAIL, 0 SKIP.
- analytics-live-audit.json: sanitized read-only aggregate evidence.
- analytics-screenshots/: initial geometry/detail/large-text screenshots.
- analytics-final-ui.log: final visual checks after compact delta and scrolling intro.

Local corrections only. Uploaded TestFlight build 75 is unchanged.

## Final visual follow-up

Final light/dark row geometry and maximum-text UI tests passed again after the
compact delta caption and scrolling introduction changes. Screenshots in
analytics-final-screenshots/ were inspected. This exposed an additional large-text
defect: SF Symbols scaled but their fixed 30/34-point backgrounds did not. A shared
ScaledMetric badge now keeps symbols and backgrounds proportional at all six
metric/region/user/detail call sites. Final evidence: analytics-scaled-icons-final-ui.log (PASS). An initial compile
rejected the property-wrapper declaration without a default value; corrected
before the successful final run. Final compiler warnings/errors: zero.
The exported large-text screenshot was inspected and confirms the icon stays
inside its scaled background: analytics-scaled-icons-screenshots/.
