# Restored card style — 2026-09-07

User explicitly rejected both visual iterations and requested the state before
news/event/organization cards were unified, additionally removing the blue news
category link and the new metadata footers everywhere.

Baseline: `9bcf038` (parent of `b86c786`). Reverted UI packages `b86c786`,
`a526214`, and `3af14ce` in reverse chronological order. Preserved the build 76
release metadata and earlier diagnostic/content-planning fixes. No TestFlight
upload, server deployment or production content changes.

The application source now matches `9bcf038` except removal of `NewsTopicLink`,
its two Home call sites and the unused callback. The normal top topic menu and
query filtering remain. Separate original Home, event, organization, saved and
related-content card implementations are restored, including event calendars.
Original theme, spacing, banners, article/profile/settings layouts are restored.

Simulator build succeeded. Manually inspected Home and Events: original date
badges are visible and the added below-card category/region footers are absent.
Evidence: `output/restored-style/home.jpg` and `events.jpg`.

Updated the existing Ukrainian news-browse UI test to choose a category through
the retained top menu, assert the removed blue link is absent, and exercise
article navigation and date filters.

Validation result: the updated UI scenario passed (1 passed, 0 failed).
