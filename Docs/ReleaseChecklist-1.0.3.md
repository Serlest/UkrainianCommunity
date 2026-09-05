# UAC 1.0.3 (69) — release checklist

Prepared 2026-09-05, implementation phase. No tests, validators, builds, archive,
upload, deployment or Apple mutation were performed by the release task.
Starting checkpoint: `120a60212c12a3451332c18fdfdcbe3a0b6f8df9`.
Static reading found six version/build pairs at 1.0.2 (68); all are now 1.0.3 (69).
This reserves a local candidate number; it does not establish availability in Apple.

## Baseline and current evidence

[Build 68](Build68Release-2026-09-04.md) records production read-back, signed
archive, TestFlight VALID, review submission and MANUAL publication. The September
5 baseline audit still recorded WAITING_FOR_REVIEW and published 1.0.1 (65).
These are dated facts; leave the current application unchanged and refresh its
state before any future authorized submission. Earlier build 64/65 reports remain
historical evidence, including their App Privacy and SDK manifest inventories.
No baseline pass is automatically a build 69 pass.

Current App Privacy attempt: the available Codex browser navigated to
`https://appstoreconnect.apple.com/apps` on September 5 and returned
`/login?targetUrl=%2Fapps&authResult=FAILED`. Current answers could not be read.
The old `production-release/asc.cjs` helper was inspected: it authenticates REST
API requests using an existing key; API-key access is not an authenticated browser
questionnaire or evidence of its answers. No credentials, questionnaire answers
or metadata were entered or changed. Coordinator owns the login-dependent follow-up.

## Gates and closure evidence

`Legal/legal-manifest.json` links [ReleaseGates-1.0.3.json](ReleaseGates-1.0.3.json).
The two legacy free-text blockers retain final operator/rights confirmation and
installed final-build accepted/rejected comment smoke. Old draft-64 wording was
superseded by the documented build-68 submission, not silently marked passed.
Structured gates additionally retain App Privacy, privacy publication, candidate
validation, archive/TestFlight, device coverage, content and authorization.

Set a gate to `passed` only after reviewing evidence for this candidate: include
commit/build, date, tester or approver, result and a durable evidence reference.
An evidence reference is a declaration for review, not automatic verification of
its contents. Missing gates, stale candidate fields, open/blocked gates and passed
gates without evidence fail strict mode. Do not empty the blocker list for a green
command. Resolve duplicate free-text blockers alongside their structured gate.

Strict `--release` means readiness for public publication, not permission to start
verification or create an otherwise authorized test archive. It is expected to
fail while archive/device/authorization gates remain open. Run ordinary structural
checks during central verification and record strict failures as open release gates;
do not bypass or weaken them. No validation command belongs in implementation phase.

## Central verification plan (coordinator only after implementation)

1. Merge task commits, preserving privacy-owned manifest document fields; record the
   integrated commit. Run release configuration, legal structure, bundled/website
   consistency checks, then strict legal mode to enumerate remaining gates.
2. Complete full iOS unit tests with explicit runner termination and result counts;
   run affected UI scenarios and exact timestamp cursor integration. Complete the
   reviewed Functions and iOS production-variant Rules checks. Android stays excluded.
3. Verify accepted and rejected comments on the installed final candidate. Retain
   result/build/account role; server probes from August/September alone do not close it.
4. Confirm the privacy owner's 90-second heartbeat / 180-second lease correction,
   document versions, consent/evidence compatibility and bilingual generated copies.
   Future authorized publication requires locale hashes and website/Firestore read-back.
5. Compare the candidate signed archive privacy report, SDK disclosures, inventory,
   public policy and authenticated App Privacy answers, including account-linked
   administrative presence, independent optional analytics and SDK diagnostics.
   Record all categories, purposes, linkage and tracking; resolve mismatches separately.
6. Before an authorized archive/upload, refresh Apple's build inventory to confirm 69
   is unused, then check signing, entitlements, release configuration, privacy report,
   export compliance and exact source digest. Record Firebase SDK dSYM warnings;
   build 68's five warnings have no evidence of resolution. Upload/TestFlight/review
   and public release each need their own evidence and authorization.
7. Verify four approved German event translations after separately authorized content
   publication/read-back. Preserve rights/provenance confirmation and candidate media
   review for UK/DE iPhone/iPad; 24 accepted build-68 images are historical evidence.

## Physical and operational proof still required

| Scenario | Evidence to retain |
| --- | --- |
| APNs | Physical iPhone/OS/build, permission states, foreground/background delivery and tap, account-switch/sign-out cleanup; no debug-provider inference |
| Face ID / passcode | Enable/disable, successful and failed biometric authentication, fallback/cancel, app background/foreground and account switch |
| App Attest | Physical attestation and protected operation with valid token; no simulator debug-token substitution; review invalid/unverified traffic before enforcement decisions |
| Privileged TOTP/recovery | Authenticator app handoff, cancel/retry, backup administrator recovery without locking out the sole owner; preserve current enforcement |
| iOS 17 | Install/startup/auth/content/media path on the minimum supported OS; report unavailable device/OS coverage explicitly |
| Accessibility | Manual VoiceOver focus/labels/actions, maximum Dynamic Type, contrast/dark mode and iPad layout with candidate identifiers |
| Performance | Representative scroll/editor startup/memory observations on device; do not infer battery or latency from build success |
| Recovery | Coordinator's isolated restore drill with backup ID, target isolation and cleanup proof; ready backups alone do not prove restoration |

Storage App Check was ENFORCED at baseline; Firestore/Auth were monitoring.
Organization/photo commands and cleanup remained off/shadow. This checklist does
not authorize enabling them or changing production. Use the existing rollout and
rollback evidence; do not deploy neighboring Android changes.

Release decision remains blocked pending evidence and the coordinator/operator's
separate decision. This preparation neither cancels build 68 nor submits build 69.
