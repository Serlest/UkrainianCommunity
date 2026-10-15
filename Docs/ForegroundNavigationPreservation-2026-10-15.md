# Preserve screens when returning from the background

## Cause and change

`AppStartupGate` previously replaced `ContentView` with loading, legal-review or
connection-failure screens whenever legal verification became pending. Removing
that view destroyed its selected tab, navigation stacks, scroll state and sheet
state. A short background interruption could trigger this after the periodic
verification interval or a legal-listener error.

The authenticated content is now mounted after initial verification and retained
for that account. A single scene-owned `AppAccessShield` covers the content and
its sheets while legal access is blocked or the device lock is active. It also
disables interaction and accessibility on the source window. Account changes
still discard the former account's content hierarchy. The production legal
verification interval remains 15 minutes; only local UI fixtures override it.

Pending notification routes wait until access is ready. Legal updates still
require reading and accepting the current documents, and a connection error
continues to block access until verification succeeds.

## Verification

On UAC Test iPhone 17 Pro, iOS 26.5 Simulator:

- Build succeeded without warnings or errors.
- `ForegroundNavigationUITests`: 5/5 passed. Actual background/foreground
  transitions cover news/event details and reading position, settings position
  after an offline/retry flow, a presented editor draft hidden by verification,
  and mandatory privacy review/acceptance before returning to the same news.
- `LegalComplianceMonitorRaceTests`: 11/11 passed, including account switching,
  stale acceptance responses, new legal versions and brief-background reads.
- Existing device-lock UI scenarios: 3/3 passed, including failed unlock over an
  inbox, the one-minute grace period, and a Ukrainian large-text editor draft.
  LocalAuthentication is scripted in these tests; this is not real Face ID proof.

Final focused result bundle:
`test_sim_2026-10-15T15-39-50-908Z_pid99809_05598223.xcresult` (16 passed).
The three existing lock tests passed in the earlier combined run, whose log is
`test_sim_2026-10-15T15-30-18-167Z_pid99809_fe08f405.log`; its MCP call timed out,
but the completed Xcode log records all three results.

This source fix needs a new installed iOS build. TestFlight build 107 and the
public App Store release were not changed as part of this fix.
