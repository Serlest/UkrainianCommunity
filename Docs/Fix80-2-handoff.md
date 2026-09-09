# Build 80 package 2 — shared shell/layout handoff

## Scope

Changed only `UkrainianCommunity/Components/ScreenChromeComponents.swift`.

## Confirmed causes addressed

- `PushedScreenShell` kept its Dynamic Type-scaled title/subtitle outside the only vertical `ScrollView`. At Accessibility XXXL the fixed header could consume all remaining height, producing a 0–14 pt content viewport in the audited admin/pushed screens.
- `EditorScreenShell` already moved its header into the scroll content at accessibility sizes. That earlier fix was preserved. Its optional bottom action was still a `ZStack` overlay, so it could cover fields/status content and did not reserve keyboard/safe-area space.

## Product changes

- At accessibility Dynamic Type sizes, `PushedScreenShell` now places the complete header and screen content in one vertical scroll flow. Standard Dynamic Type keeps the existing fixed header behavior.
- The pushed/admin scroll viewport receives flexible height and layout priority, preventing a large sibling header from collapsing it.
- The editor scroll viewport receives the same explicit flexible-height priority.
- Non-empty optional editor bottom actions now use `safeAreaInset(edge: .bottom)` instead of an overlay. The scroll viewport therefore reserves their height and the action follows the keyboard safe area; `EmptyView` does not introduce spacing.

`AdminScreenShell` inherits the pushed-shell correction. Font scaling, title/subtitle text, feature content, role logic, validation, persistence and individual screens were not changed.

## Already fixed / deliberately not duplicated

- Existing accessibility-size relocation of `EditorScreenShell` header into its scroll flow was already present at `fd58131` and remains intact.
- Existing adaptive vertical action/header composition remains intact.
- Individual row clipping, oversized `TextEditor` behavior, feature-specific tab-bar overlap and Profile editor validation are outside this package.

## Coordinator dependencies

No localization keys, copy changes, project-file edits or new API dependencies are required.

The coordinator should validate after all packages merge:

1. `PushedScreenShell` users from sections 11/15/18/27/31/32 at standard and AX XXXL, including 375×667.
2. `AdminScreenShell` list/action reachability after repeated swipes.
3. `EditorScreenShell` users from sections 02/03/10/30 with keyboard shown and persistent bottom actions.
4. Standard Dynamic Type screenshots to catch unintended header scrolling or spacing changes.
5. Empty `BottomActionContent` adds no visible inset; external screen-owned `safeAreaInset` remains compatible.

No build, tests, lint, Simulator, dependency install, commit or push was performed in this package, per coordinator instruction.
