# Android 1.2 (112) — compact Directory recent preview

## Scope
- Existing UacCard surface, colors and rounded corners; a single card containing three compact title-only rows, separators and chevrons.
- Titles use maxLines1 and ellipsis. Merged accessibility semantics retain the complete text (verified), without a duplicated content description.
- Minimum48dp row and Show More targets; minimum height only, no fixed maximum height. No metadata, description or refresh in the home preview. Full feed keeps existing metadata and pagination.
- Show More retains loaded-count/hasMore logic introduced111. No placeholder banner restored.

## Targeted verification
- Four targeted UI tests PASS,13.823seconds. Compact preview testedUK/DE xlight/dark, one-line actual text layout/ellipsis/full semantics,48dp targets, real bundled article reader/back, full feed fourth item/article/back, one source fetch across round trip, plus111 pagination/empty/banner-error regression.
- Screenshots compact112-{uk,de}-{light,dark}.png are isolated UI harness with fixture titles. Back button at top is test-only navigation; not a new product button.
- Real reader source remains bundled in this local test; no production database writes.
- No full audit rerun;111 banner regression remains applicable since banner code is unchanged.

Visual review is required before signed archive/upload; delivery receipts to follow.
