# Release and security checklist

Use this checklist for the first release after the security and privacy hardening work. A merged pull request means the repository is prepared; it does not mean Firebase configuration, backend code, rules, indexes, legal documents or App Store metadata have been deployed.

## Current candidate — 2026-09-05, after shared verification

1.0.3 (69): code verification and privacy 2026.13 publication/read-back are recorded
in [the current checklist](ReleaseChecklist-1.0.3.md),
[structured gates](ReleaseGates-1.0.3.json) and
[sanitized evidence](ReleaseEvidence-1.0.3.json). These supersede the August and
implementation-phase status notes. General checkboxes below are reusable procedures,
not a current list of unperformed deployments.

414 unit tests, 50 unique UI tests and two separate actual SDK scenarios passed;
local server/Rules checks passed. Three privacy Functions, Firestore 2026.13 and
Hosting live hashes were verified; three German translations and isolated restore
cleanup have proof. Management deployment now has verified read-back. Candidate validation is reopened
pending UI-owner assessment of the Hackathon feed/detail date discrepancy. Exact app/server code equivalence was read at integration 21126fe.

App Privacy login, signed archive/TestFlight, physical device/iOS 17, one held event
and final rights confirmation, and final live comments remain open. The user has
authorized the agreed external work; no missing general authorization is a blocker.
Public App Store release remains outside this task. Strict gates remain closed for
actual evidence gaps. Qualified legal review stays a recommendation; these technical
checks do not provide a legal opinion.

## Repository gate

Run `python3 scripts/validate_release_configuration.py` and `python3 scripts/validate_legal_documents.py --release` on the exact release commit. The first automated preflight checks build-number consistency, export-compliance metadata, privacy-manifest semantics, absence of the Google/Firebase Analytics product and the App Check client configuration. The second blocks publication while legal identity, bilingual document synchronization, DSA pages or retention decisions remain unresolved. Neither replaces the signed archive or its privacy report.

- [ ] All required GitHub checks pass on the exact release commit.
- [ ] iOS Debug build, Swift unit tests and UI tests pass on a supported simulator.
- [ ] Firebase Functions lint/build and all emulator rules tests pass.
- [ ] Production dependency audit is reviewed; no unaccepted high/critical finding remains.
- [ ] Xcode archive succeeds with the distribution signing identity and production entitlements.
- [ ] The archive privacy report contains the app manifest and expected SDK manifests.

## Firebase deployment gate

- [ ] Confirm the intended Firebase project with `firebase use` and a second human-readable project-ID check.
- [ ] Back up or export production data according to the operating procedure.
- [ ] Inventory existing canonical IDs before deploying the collision guards: no news ID may begin with `event_` or `organization_`, and no organization ID may begin with `follow_`; migrate any exception before clients create new likes/follows.
- [ ] Treat deleted news/event document IDs as permanently retired; never recreate content with the same ID, because immutable lifetime-view baselines and transition tombstones intentionally survive deletion.
- [ ] Before enabling state-aware public counter triggers, run the bounded `npm run counters:reconcile` bootstrap/apply gate from `Docs/CounterAggregationRunbook.md`; retain its clean digest-stamped report with the signed change record, complete the transition-state backfill and immutable lifetime-view baseline, and prove the pre-cutover event backlog is drained.
- [ ] Verify the counter reconciliation reports no recoverable missing-target contribution and `counterAggregationDeadLetters` has no unresolved record.
- [ ] Run the removed-feature inventory and deactivate every legacy featured banner before deploying the restrictive Rules.
- [ ] Deploy the reviewed Functions, Firestore rules/indexes and Storage rules from the release commit.
- [ ] Before enabling analytics schema v2, execute `Docs/AnalyticsSchemaV2Cutover.md` on a zero-traffic Vienna day: retain prepare/finalize/verify reports, exact commit and function activation evidence, freeze account create/delete through finalize, preserve the digest-covered lifetime archive, and require `releaseGatePassed: true`. A typed maintenance flag alone is not evidence.
- [ ] For the Firebase Messaging FID migration, deploy the dual token/FID Functions and compatible Rules before releasing the FID-enabled iOS client; follow `Docs/PushRegistrationMigration.md` and retain staging delivery evidence.
- [ ] Verify callable account deletion and scheduled retention jobs in production logs with non-destructive test accounts/data.
- [ ] Confirm scheduled retention policy, region, time zone, runtime identity, permissions, monitoring and alerting.
- [ ] Confirm the agreed retention period remains six months after content completion, subject to legally required exceptions.
- [ ] Deploy and verify the 1,095-day `auditLogs` cleanup and six-month cleanup of closed feedback/report conversations, including the required feedback index.
- [ ] Before deploying Rules that reject `canManageGuide`, confirm no supported older build still sends the field during registration or stage a temporary `false`-only compatibility rule.

## App Check rollout gate

- [ ] Register the iOS app for App Check in Firebase and configure App Attest.
- [ ] Use only registered debug tokens for local development; never ship a debug provider or token in Release.
- [ ] Release the App Check-enabled client while enforcement remains off.
- [ ] Observe App Check metrics long enough to cover the supported app population and critical operations.
- [ ] Investigate invalid/unverified traffic and only then set `ENFORCE_ANALYTICS_APP_CHECK=true` and enable enforcement service by service.
- [ ] Prepare an emergency rollback/disable procedure before enforcement.

## Privacy and legal gate

- [ ] Identify the legal controller/operator, postal address and working privacy contact for Austria/EU disclosure.
- [ ] Record whether the operator follows the recommendation for qualified Austrian/EU counsel review of policy, terms, retention and lawful bases. Repository text is not legal advice.
- [ ] Complete the operator imprint and Media Act disclosure, and verify the user and authority contact points required by the Digital Services Act.
- [ ] Verify the public notice-and-action mechanism, statement of reasons and internal appeal workflow against `Legal/notice-and-action.*.md`.
- [ ] Reconcile every affected surface in `Docs/LegalChangeMatrix.md`; retain the resulting version, hash, deployment and approval evidence.
- [ ] Record the approved lawful basis for optional owner analytics. The technical consent path now persists a versioned server-owned receipt (purpose/policy version, grant/withdrawal timestamps and disclosed copy) and enforces the exact current grant in the callable; legal/controller approval remains required.
- [x] Obtain explicit data-flow approval and complete `Docs/AnalyticsActionProofPlan.md`. One-time immutable proofs now preserve an opted-in positive action even when the operational feature is undone before delayed analytics delivery.
- [ ] Update the public privacy policy to distinguish account-linked operational feature records created when a feature is used (including lifetime view deduplication/public counters, likes, bookmarks, follows and registrations) from optional first-party daily aggregate signals controlled by analytics consent. Also cover Firebase services, Firebase Installation IDs and legacy push registration tokens during migration, device name, App Check/App Attest, user uploads/interactions, moderation/security logs, deletion and retention.
- [ ] Version and publish the approved legal documents; require renewed acceptance when the approved change is material.
- [ ] Ensure the in-app fallback text, Firestore-published text and public policy URL are identical in substance and language coverage.
- [ ] Complete App Store Connect privacy answers from `Docs/AppStorePrivacyInventory.md` and the archive privacy report.

## Functional release gate

- [ ] Test registration, email verification, login, password reset and logout.
- [ ] Test guest and authenticated permissions plus owner/admin/organization role boundaries.
- [ ] Test create/read/update/delete flows for content, uploads, comments, reports and feedback.
- [ ] Test push registration, mixed legacy-token/FID delivery, opt-out, permanent-registration cleanup and immediate sign-out before the first Messaging callback on physical devices. Confirm cleanup failure blocks Auth sign-out and a retry succeeds.
- [ ] Confirm the signed app does not embed Google/Firebase Analytics; test optional first-party aggregate analytics disabled on a fresh install, then explicit opt-in and opt-out for a verified account.
- [ ] Confirm the analytics switch is unavailable for guests and anonymous/unverified accounts and becomes available after verification.
- [ ] With optional analytics disabled, verify that requested account features still create their disclosed operational records and work correctly: lifetime news/event view deduplication and public counters, likes, bookmarks, organization follows and event registrations. Verify the switch explains that these App Functionality records are outside its scope.
- [ ] Test account A opt-in → logout/account B login: B remains opted out, A's queued events are not attributed to B, and opt-out prevents in-flight or delayed delivery.
- [ ] Test offline analytics delivery, bounded backoff, 48-hour expiry, app restart, and recovery without blocking newer eligible events.
- [ ] Test the owner dashboard for Today/7/30 days across a Vienna midnight and daylight-saving boundary, including zero-current/positive-previous data, stale refresh, search-empty and detail drill-down states.
- [ ] Verify owner-only reads and server-only writes for every analytics aggregate/detail collection in the Firestore emulator.
- [ ] Verify the deletion and registration triggers retry idempotently and the 72-hour receipt/60-day activity-marker analytics cleanup drains more than one batch without deleting a refreshed activity marker.
- [ ] Test in-app account deletion end to end with a disposable account and verify backend cleanup.
- [ ] Test splash/startup, offline/poor-network behavior, localization, accessibility and dark mode.
- [ ] Complete TestFlight smoke testing on at least one current physical iPhone before production submission.

## Release evidence

Record the Git commit, Xcode/SDK version, Firebase project ID, deploy timestamps, CI run links, archive privacy report, TestFlight build, tester/date, known risks, approver and rollback point. Do not mark the release ready while any unchecked item can affect security, privacy, legal compliance or data loss.
