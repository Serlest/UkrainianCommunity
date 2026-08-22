# Release and security checklist

Use this checklist for the first release after the security and privacy hardening work. A merged pull request means the repository is prepared; it does not mean Firebase configuration, backend code, rules, indexes, legal documents or App Store metadata have been deployed.

## Repository gate

- [ ] All required GitHub checks pass on the exact release commit.
- [ ] iOS Debug build, Swift unit tests and UI tests pass on a supported simulator.
- [ ] Firebase Functions lint/build and all emulator rules tests pass.
- [ ] Production dependency audit is reviewed; no unaccepted high/critical finding remains.
- [ ] Xcode archive succeeds with the distribution signing identity and production entitlements.
- [ ] The archive privacy report contains the app manifest and expected SDK manifests.

## Firebase deployment gate

- [ ] Confirm the intended Firebase project with `firebase use` and a second human-readable project-ID check.
- [ ] Back up or export production data according to the operating procedure.
- [ ] Run the removed-feature inventory and deactivate every legacy featured banner before deploying the restrictive Rules.
- [ ] Deploy the reviewed Functions, Firestore rules/indexes and Storage rules from the release commit.
- [ ] Verify callable account deletion and scheduled retention jobs in production logs with non-destructive test accounts/data.
- [ ] Confirm scheduled retention policy, region, time zone, runtime identity, permissions, monitoring and alerting.
- [ ] Confirm the agreed retention period remains six months after content completion, subject to legally required exceptions.
- [ ] Define and legally review an explicit `auditLogs` retention period; no automatic `auditLogs` cleanup exists yet.
- [ ] Before deploying Rules that reject `canManageGuide`, confirm no supported older build still sends the field during registration or stage a temporary `false`-only compatibility rule.

## App Check rollout gate

- [ ] Register the iOS app for App Check in Firebase and configure App Attest.
- [ ] Use only registered debug tokens for local development; never ship a debug provider or token in Release.
- [ ] Release the App Check-enabled client while enforcement remains off.
- [ ] Observe App Check metrics long enough to cover the supported app population and critical operations.
- [ ] Investigate invalid/unverified traffic and only then enable enforcement service by service.
- [ ] Prepare an emergency rollback/disable procedure before enforcement.

## Privacy and legal gate

- [ ] Identify the legal controller/operator, postal address and working privacy contact for Austria/EU disclosure.
- [ ] Have qualified Austrian/EU counsel review the privacy policy, terms, retention rules and lawful bases. Repository text is not legal advice.
- [ ] Update the public privacy policy to cover Firebase services, analytics consent, push tokens/device name, App Check/App Attest, user uploads/interactions, moderation/security logs, deletion and retention.
- [ ] Version and publish the approved legal documents; require renewed acceptance when the approved change is material.
- [ ] Ensure the in-app fallback text, Firestore-published text and public policy URL are identical in substance and language coverage.
- [ ] Complete App Store Connect privacy answers from `Docs/AppStorePrivacyInventory.md` and the archive privacy report.

## Functional release gate

- [ ] Test registration, email verification, login, password reset and logout.
- [ ] Test guest and authenticated permissions plus owner/admin/organization role boundaries.
- [ ] Test create/read/update/delete flows for content, uploads, comments, reports and feedback.
- [ ] Test push registration, delivery, opt-out and token cleanup.
- [ ] Test analytics disabled on fresh install, then explicit opt-in and opt-out.
- [ ] Test in-app account deletion end to end with a disposable account and verify backend cleanup.
- [ ] Test splash/startup, offline/poor-network behavior, localization, accessibility and dark mode.
- [ ] Complete TestFlight smoke testing on at least one current physical iPhone before production submission.

## Release evidence

Record the Git commit, Xcode/SDK version, Firebase project ID, deploy timestamps, CI run links, archive privacy report, TestFlight build, tester/date, known risks, approver and rollback point. Do not mark the release ready while any unchecked item can affect security, privacy, legal compliance or data loss.
