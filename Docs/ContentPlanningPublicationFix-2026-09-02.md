# Content Planning publication response fix — 2026-09-02

## Confirmed cause

`beginOwnerContentDraftPublication` returns `expiresAt` and optional `existingScheduledAt` using JavaScript `Date.toISOString()`, including fractional seconds. The iOS repository used the default `ISO8601DateFormatter`, which rejected these values. The callable had already committed the publication lease, but the client threw `validationFailed` before invoking the news/event editor save operation.

Observed production calls returned HTTP 200 with valid authentication and App Check. Neither corresponding live news nor event existed. This was not an MFA, Rules or organization permission failure.

The old tests constructed leases with native `Date` values; they bypassed the broken wire-response conversion.

## Local changes

- Extract the exact callable response into `OwnerContentPublicationResponse`, used by the production repository and JSON regression tests.
- Accept fractional-second ISO 8601 timestamps, while preserving whole-second compatibility, for both lease and scheduled dates and stored planning payload strings.
- Keep response validation, additionally reject a mismatched draft and empty content/lease identifiers. Invalid dates and inconsistent existing-content state still fail closed.
- Preserve the original attempt ID after an ambiguous response so retry can reuse the server lease. Clear a previous error when retry uses a cached valid lease.
- Replace the incorrect DE/UK claim that the draft was not changed with an honest retry message.
- No backend, Rules, MFA, App Check, privacy or production content mutation.

## Verification

- Xcode Debug simulator test: 16 test methods passed, 0 failures, 0 skipped; parameterized cases cover news and events. Final run: 38.4 seconds.
- Covers actual callable-shaped JSON strings; first publication; existing scheduled/published content; malformed data; same-attempt retry after a lost response; cached lease reuse; ambiguous finalization retry.
- Both actual editor view models save to the local mock repository using the server-reserved ID, read the saved record back, and pass their real publication result to planning finalization. Test records are removed from the mock store. No production test articles or accounts were created.
- Final compiler run has no new actor-isolation warnings. Firebase emitted its generic pre-initialization logging notice; there were no test failures.
- DE/UK localization validation: passed (2,658 entries). `git diff --check`: passed.
- Result bundle: `/Users/serlest/Library/Developer/XcodeBuildMCP/workspaces/first-update-856190e26dd4/result-bundles/test_sim_2026-09-02T17-43-17-108Z_pid1645_ad3b48e6.xcresult`.

## Read-only production recovery

The existing scheduled recovery returned both failed attempts to `needsAttention`, without manual writes:

- News draft `b82059688ca18e49b94b5746a18864588768db41`: recovered at `2026-09-02T17:38:02.099Z`; reserved live news absent (404).
- Event draft `58d135a4dc1b2de8bb01afe723a1cea2e19d43aa`: recovered at `2026-09-02T17:40:01.549Z`; reserved live event absent (404).

## Release boundary

Build 64 does not contain this fix and is not release-ready. App Store read-back at `2026-09-02T17:34:07Z`: 1.0.1 (64) `DEVELOPER_REJECTED`; public 1.0 (53) `READY_FOR_SALE`. No App Store write occurred during this repair.

Committed/pushed in `c42a134`; build 65 is uploaded (VALID) and selected in the editable 1.0.1 candidate. No App Review submission. These local tests do not prove production image upload, Firebase write permissions or a physical-device end-to-end publication. Existing editorial/source uncertainties must still be reviewed before publishing the affected real content. See `Docs/Build65ReleaseReadiness-2026-09-02.md` for read-back evidence and the remaining installed-candidate check.
