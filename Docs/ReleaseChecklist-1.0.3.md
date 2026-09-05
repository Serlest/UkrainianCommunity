# UAC 1.0.3 (69) — release evidence and remaining gates

Updated 2026-09-05 from coordinator evidence after shared verification and scoped
external work. Integration snapshot: `21126fea721952a00730a79554b4c6074fd06611`.
This document update ran no new tests/builds and made no external changes.
The verification task owns the final independent audit and ratings.

## Confirmed within scope

[Sanitized evidence](ReleaseEvidence-1.0.3.json) retains results, limitations and
SHA-256 references to the shared source artifacts. [Structured gates](ReleaseGates-1.0.3.json)
are the current readiness record; dated implementation notes below other reports
must not override these results.

| Area | Evidence and scope |
| --- | --- |
| iOS unit | 414 passed, 0 failed; two actual SDK scenarios excluded from this general run and each passed separately |
| UI | 50 unique tests, 53 executions, 0 failures/skips; Simulator |
| Actual SDK | Timestamp cursor and Auth/content/media/account lifecycle each 1/1 passed against isolated local emulators; not production/device proof |
| Server | Unit 392 passed (67 integration skips in unit command), separate integrations 74/74, common Rules 172/172 and iOS-adapted Rules 169/169; lint/build passed, dependency audit 0 findings |
| Release Simulator | Build passed; bundle 1.0.3 (69), minimum iOS 17.0; 30 privacy manifests / 14 categories, all manifests identical to retained archive 68; not a signed device archive |
| Privacy Functions | updateAnalyticsConsent, updateAnalyticsConsentV2 and trackAnalyticsEvent deployment/source/settings read-back verified; global App Check unchanged; no authenticated production canary claimed |
| Privacy Firestore | 2026.13 active, DE/UK hashes verified, 25 documents preserved; immutable version/pointer publication completed |
| Privacy Hosting | Live version/HTML hash verified, DE/UK present, 14 unrelated files unchanged; local `published` serialization was not used as live proof |
| Legal package | Coordinator's existing structural and bundled-source read-back checks passed; App Privacy questionnaire remains separate |
| Content | Three German event translations published/read back; unrelated fields unchanged. One event remains held |
| Restore | Isolated database restore completed; sampled 23 documents/five collections, anonymous 403; deletion completed, exact GET 404, source/PITR/protection/backup unchanged. Not full-database comparison or Storage restore |

Static Git reading at 21126fe found no app-source/project/plist differences from
`0172860dbfa0f61aef9626eb1b825d4a25436632`, and no Functions runtime/package
changes from `0681aa0540a8557a57f8c49f9f295bc5266784f2`. The older source-map
artifact names 53bb1ad; this equivalence was refreshed without rerunning tests.
Later changes to app/server code require their own verification; matching code
is not a claim that every later deployment has completed.

Management deployment read-back now confirms both search Functions. All 116
Functions outside the five privacy/search updates are unchanged after normalizing
unordered event-filter order (16 ordering-only differences); total 121 and global
App Check unchanged. No authenticated production canary is claimed; search still
performs O(N) reads. Canonical cursor fixture cleanup records 61 documents complete.

## Open gates

- **Candidate visual assessment:** Hackathon feed shows 11–12 September while detail
  shows 11 September in coordinator review. UI owner is tracing the cause read-only.
  Candidate validation is reopened pending that assessment; prior passing tests
  remain recorded. Cause/regression/resolution are not assumed.

- **App Privacy:** available browser reached Apple login (`authResult=FAILED`).
  Current questionnaire answers must be compared with signed candidate SDK report,
  account-linked presence, optional analytics and published 2026.13. No answers changed.
- **Archive/TestFlight:** exact signed device archive, signing/entitlements/privacy
  report, upload and TestFlight smoke remain unproved. Build68's five SDK dSYM
  warnings remain historical unresolved limitations, not fixed by Simulator success.
- **Physical device and iOS 17:** APNs permission/delivery/tap/account-switch cleanup;
  Face ID success/failure/cancel/passcode fallback; App Attest attestation; privileged
  TOTP authenticator handoff and backup-admin recovery; minimum-OS installation and
  critical paths. Simulator iOS 26.5 and declared minimum 17 do not prove iOS 17 runtime.
  Retain manual VoiceOver/Dynamic Type/iPad and device performance coverage limits.
- **Content/rights:** resolve the held fourth event and retain final operator
  content/image-rights confirmation. Three verified translations do not prove all rights.
- **Final live comments:** accepted/rejected comments in installed final candidate
  against intended live backend. Local UI/SDK and older server probes do not close it.

## Authorization and publication boundary

The user authorized completion of the agreed 1.0.3 plan and scoped external changes
after verification. There is no missing general-authorization blocker. Public
App Store publication is outside this task and is not being performed. Recording
`release-authorization=passed` means the current work scope is authorized; it is
not permission or evidence for a public release. Do not cancel or publish the
existing 1.0.2 (68) application as a side effect of this preparation.

Historical [build 68 evidence](Build68Release-2026-09-04.md) records
VALID / WAITING_FOR_REVIEW / MANUAL; baseline published 1.0.1 (65) is separate.
Refresh Apple status before future authorized upload/submission; no current
questionnaire or final archive proof is inferred from those dated states.

## Gate operation and next handoff

`Legal/legal-manifest.json` keeps held-content/rights and final-live-comment blockers.
Privacy-owned document/version/history keys are unchanged by this release update.
The published 2026.13 proof closes `privacy-publication`; local code results remain recorded but
`candidate-validation` awaits the visual date assessment. Scoped authorization,
management deployment and isolated restore are recorded passed.
App Privacy, archive/device, held-content/rights, comments and candidate visual assessment
remain open. Do not clear them for a green strict command.

Evidence references must be reviewed, not merely exist. Strict `--release` remains
a publication-readiness check and is expected to fail for genuine remaining gates.
It is not a reason to repeat the entire passing suite or block authorized independent
work. This doc-only update does not rerun validators. Coordinator/verification will
refresh strict output and complete the final audit after the remaining UI assessment.
