# Visual refinement — simulator preview, 2026-09-07

Baseline: `ada5f1f` (build 76), preserved in `UACUnifiedCards-20260907`.
Preview branch: `codex/visual-refinement-20260907`, separate worktree
`/Users/serlest/Developer/UACVisualRefinement-20260907`.

The user approved visual changes and asked to view them in Simulator instead
of creating a new TestFlight build. Marketing version and build number remain
unchanged. No archive, upload, external test distribution, Firebase mutation or
production content publication is part of this package.

## Changes

- Feed outer gutter remains 16pt, but the nested 10pt decorative plane is removed.
- Main thumbnail is 64pt; headlines have their full text-column width and up to
  three lines at normal sizes. News timestamps no longer occupy a side column.
- Footer height remains 44pt, with its duplicate 8pt vertical padding removed;
  body-to-footer spacing is 0 and item spacing is 8 (previous gap including
  metadata: 70pt; now 52pt for a single-line footer).
- The actual independent news-topic button has a 44pt label/hit region.
  Informational event/organization categories use a secondary text color.
- Home banner is 176pt; event/organization banners use the existing 146pt
  compact size. Standard filter controls retain at least a 44pt height.
- At accessibility sizes, banner text determines height; a stable single banner
  has explicit previous/next buttons instead of automatic rotation. Filters
  stack vertically, and decorative branding caps its type size.
- Shared screen background is a calm system grouped background with a faint
  branded tint. No image assets were deleted.
- Article body uses the primary text color and body font.
- Log metric labels use the full tile width. Analytics comparison explanations
  appear once per grid, while accessibility values retain the complete delta.
- The owner header removes its repetitive access-description paragraph; role,
  account status and the explicit access-level row remain.
- Root/pushed bottom spacing is 32pt and detail spacing 48pt. The editor retains
  116pt for its overlaid bottom action; keyboard/final-scroll checks are separate.

This is a reviewable visual iteration, not a claim that every item in the audit
or every role/device has been validated. Legal/security explanations are not
removed. Fixtures are used for Simulator viewing, so missing remote pictures
in screenshots are not production image-loading evidence.

## Validation

- Simulator build succeeded; 18 selected tests passed, zero failed/skipped.
- Includes card adapters/rendering, news query/filter navigation, event schedules,
  three-tab navigation across uk dark / de light / uk dark largest text, and
  analytics row alignment. The parametrized schedule test has two cases.
- Result: `test_sim_2026-09-07T20-17-43-896Z_pid35240_1bef3930.xcresult`
  in the XcodeBuildMCP workspace result-bundles directory.
- Manually inspected light Home, Events, Organizations, news detail and owner
  profile; inspected the dark Home test attachment. Largest-text banner
  displays complete text and changes from page 1 to page 2 using its arrow.
  Feed can scroll to its end at largest text.
- Test attachments and manual screenshots: `output/visual-preview/`.
- Still unverified: physical device, every role/form, keyboard interactions,
  live remote image loading and every detail page's final-scroll state.
- After tests, only indentation was cleaned in FeaturedBannerCarouselView.
