# Fix80-1 — Profile root reconciliation

Date: 2026-09-09  
Baseline: `fd58131d2c7c7c5f50b5d354473b91d271990565`

## Scope completed

- `ProfileBadge` keeps the existing two-line limit at standard Dynamic Type sizes and removes the limit at accessibility sizes, preventing the confirmed owner-role truncation.
- Owner feedback and pending-organization counters now publish explicit idle, loading, loaded, and failed states.
- A failed initial fetch no longer marks the counter as loaded. Realtime listener errors also publish failure and allow a later retry.
- Profile rows show progress while the counter loads, a numeric badge for a positive loaded count, and an error indicator when loading fails.
- The platform operations section exposes a localized retry action when either service counter fails. Its navigation rows remain available.
- `profile.guest.card` moved from the container to the welcome title, so it no longer overrides the existing `profile.guest.signIn` and `profile.guest.createAccount` identifiers.

## Files changed

- `UkrainianCommunity/Views/Profile/ProfileHeaderSection.swift`
- `UkrainianCommunity/Views/Profile/ProfileModuleComponents.swift`
- `UkrainianCommunity/Views/Profile/ProfileOwnerVisibilityViewModel.swift`
- `UkrainianCommunity/Views/Profile/ProfileViews.swift`
- `Docs/Fix80-1-handoff.md`

## Shared-file safety

The existing shared `ProfileViews.swift` changes for feedback detail routes, auth draft reset, and Saved Content repository injection were preserved.

## Verification

- Source reconciliation against Build 79 baseline: PASS.
- Patch whitespace validation (`git diff --check`) for the scoped files: PASS.
- Build, tests, linters, Simulator, and device validation: NOT RUN by coordinator instruction.

## Remaining validation

- Re-run the owner profile in Ukrainian, dark mode, and an accessibility Dynamic Type size to confirm the full role text renders.
- Re-run guest accessibility automation to confirm all three identifiers resolve independently.
- Exercise feedback and organization counter failures to confirm the error badges and retry action recover to loaded values.
