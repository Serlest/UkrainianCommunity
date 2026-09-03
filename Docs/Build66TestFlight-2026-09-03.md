# UAC 1.0.2 (66): TestFlight package

Scope: user authorized a new TestFlight build, scoped commit/push and tests. No App Review submission, public release, Firebase deployment or automatic account deletion is part of this package.

## Included

- Optional DE/UK App Store update prompt: published compatible version only, fixed UAC store URL, Later until the next opening, no blocking offline, authentication/editor presentation takes priority. An installed build 65 cannot show this new mechanism until it receives a newer client. Details: `AppUpdatePrompt-2026-09-03.md`.
- Organization profile edits no longer rewrite protected submission/review metadata. This avoids precision loss in the Firestore Timestamp → Date → Timestamp round trip. Request creation and resubmission keep their separate contract; ownership/roles are not changed. Covered by `OrganizationFirestoreWriteContractTests`.
- Shared native region menu on Home, Events and Organizations, matching other themed filter controls; common ordering, selected state and synchronized nationwide/land selection.
- Production German text correction for Ukrainian Community was separately authorized and read back before this build. It was a three-field content change, not a client or Rules deployment. Details: `OrganizationLocalizationAudit-2026-09-03.md`.

Existing Android, server retention, content-publisher and Rules edits remain separate in the working tree. They are not included or deployed by this iOS package.

## Preflight and local tests

- Apple read-only preflight: app/bundle identity verified; latest upload 65 VALID, public 1.0.1 READY_FOR_SALE. Next package: 1.0.2 (66). Existing internal group has access to all builds; no external Beta Review is requested.
- Full local iOS unit tests: **383/383**, zero failures/skips, 39.9 seconds including preparation. Result: `test_sim_2026-09-03T19-57-59-400Z_pid10267_6c174dc4.xcresult` under the XcodeBuildMCP result-bundles directory.
- DE/UK localization: 2669 entries passed. Property lists, release configuration, content-category contract, repository structure, index uniqueness and bundled legal-source parity passed. Change classifier: 15/15.
- Legal structure validation passed with existing public-release warnings. No legal clearance or automatic closing of the manifest's historical warnings is claimed.
- Production Firestore Rules match the committed baseline exactly (SHA-256 `64f4ae8d8f4b9289778a26f99c967a40722bb408022cc93c2d61c06be12fe8bd`). The read used a per-request quota-project header after Google rejected the initial SDK request without it; no permissions/API/settings were changed.
- Initial four-case UI run: update prompt and organization details passed; quick creation and region controls were inaccessible behind the required MFA screen. Evidence shows the old synthetic app-owner fixture has no Firebase/TOTP session, rather than a missing control. Production MFA was not bypassed or changed. Public region testing now uses a guest; the privileged quick-creation scenario remains an explicit fixture/physical-verification gap.
- Final region UI check passed on a guest session: all three catalogs, DE/light and UK/dark, selection synchronization and reset to nationwide coverage. **1/1**, no skipped assertions; 112.7 seconds test execution, 136.8 seconds including preparation. Result: `test_sim_2026-09-03T20-03-56-070Z_pid10267_44f78389.xcresult`. This closes the region check, not the separate privileged-fixture gap.

## Remaining checks and evidence boundary

- Signed archive, upload processing and current GitHub workflow are recorded in the local evidence folder `outputs/release-1.0.2-build66-2026-09-03/` as each finishes. Their preparation is not completion.
- Physical TestFlight checks remain: edit the real organization, verify region-menu appearance, ensure editor/Face ID priority and the real App Store handoff when an update offer is available. Do not force sign-out or MFA reenrollment to perform unrelated checks.
- Existing privileged UI tests need a correctly modeled MFA-authenticated fixture; the old owner shortcut is not proof of a signed-in protected session. This does not justify weakening production security.
- TestFlight availability is not a public App Store release or release-readiness approval. No production records are created or deleted by these synthetic local tests.
