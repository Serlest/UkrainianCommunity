# System log diagnostics — 2026-09-07

## Incident evidence (Europe/Vienna)

Read-only checks of production Firestore `systemLogs`, Cloud Run logs for
`getblockedorganizations`, and the deployed function source archive.

- 07:41:09: app 1.0.2, `com.firebase.functions` code 4. The original network
  cause and request duration were not recorded. Requests at 07:42:27 and
  07:42:40 completed with HTTP 200 in approximately 108 ms and 98 ms.
- 10:30:38: app 1.0.3, `NSURLErrorDomain` code -1200 (TLS connection failure).
  No nested CFNetwork/SSL details were persisted. The precise transport cause
  cannot be reconstructed from the saved event.
- 17:35:59: app 1.0.3, `com.firebase.functions` code 9. Matching server request
  at 17:35:57 returned HTTP 400 in 57 ms, with an iPad user agent. Auth and
  App Check verification passed. The deployed callable checks privileged TOTP
  authentication; that guard throws `failed-precondition`. This supports the
  MFA diagnosis. The historical client log does not retain the server message
  or session claims, so those cannot be independently recovered from it.

The client-reported OS version and HTTP user agent differ for the last event;
user-agent device attribution is server evidence, not a recovered hardware ID.
At the initial read: 71 request records, 70 HTTP 200 and one HTTP 400, no 5xx.
This does not count failed attempts that never reached Cloud Run.

## Changes

- Explicit MFA classification only when both Firebase domain/code and the
  deployed server's exact TOTP message match. Other preconditions remain
  distinct and are never guessed to be MFA failures.
- Explicit TLS, certificate validity/trust, DNS, host connection and cancellation
  classifications. Existing timeout/offline/connection-loss classifications remain.
- Up to five NSError levels retain domain/code and numeric CF stream domain/code.
  Arbitrary descriptions, userInfo, URLs, credentials and response bodies are
  not copied into diagnostics.
- All callable failures record elapsed milliseconds, configured timeout and
  app build number. Existing log detail UI and export already expose metadata.
- Organization block/unblock UI explains MFA, TLS, network and timeout failures
  in Ukrainian and German; failed operations retain their existing state semantics.

Firebase SDK `Functions.processedError` replaces URL timeout errors with
`FunctionsError(.deadlineExceeded)` without retaining NSUnderlyingErrorKey.
The added timing fields improve future evidence but cannot restore details
that the SDK itself discards. Nor can structured diagnostics guarantee an exact
cause if the OS provides none.

## Validation

Simulator build passed. Targeted tests: 26 passed, 0 failed, 0 skipped.
- SystemTechnicalErrorClassifierTests, UserBlockingContractTests,
  SystemLogsViewModelTests: 18 passed.
- OrganizationSafetyRoutingTests: 8 passed using the same built test products.
- Localization validation: 2,694 entries passed (de/uk).
- `git diff --check`: passed.

Evidence directory:
`~/Library/Developer/XcodeBuildMCP/workspaces/new-chat-4-00a68fe9c00b/result-bundles/`
- `test_sim_2026-09-07T17-14-56-205Z_pid16726_588d74d0.xcresult`
- `test_sim_2026-09-07T17-17-06-165Z_pid16726_798c0ccb.xcresult`

This verifies local classification and regression behavior, not a reproduction
of today's physical-device TLS failure or a deployed release.
No production changes, release upload or device installation were performed.
