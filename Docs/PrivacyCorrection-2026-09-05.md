# Privacy 2026.13 — local correction package for UAC 1.0.3

Status: prepared locally, not published or tested. Source checkpoint:
`120a60212c12a3451332c18fdfdcbe3a0b6f8df9`. This document records a proposed
publication package, not production evidence or App Store approval.

## Scope and versions

Section 18 of the German and Ukrainian notice now describes the existing
90-second client heartbeat and 180-second server online lease. The display is
approximate and may update later; the text no longer promises an exact visible
disconnect deadline or attributes today's interval to historical build 32.

Source evidence read in this worktree:
- `UserPresenceService.swift`: default interval `.seconds(90)`; local response
  expiry uses the server timestamp and caps remaining lifetime at 180 seconds.
- `functions/src/users/userPresence.ts`: `presenceLeaseMs = 180_000`; response
  uses active session timestamps plus the lease. No runtime presence code changed.
- `ManagedUserPresenceView.swift`: foreground detail refresh every 30 seconds.
- The coordinator's baseline audit separately reports 180 seconds in deployed
  source packages. This task has not independently reread production.

Privacy becomes 2026.13, superseding 2026.12. The proposed effective date is
2026-09-05. If publication is later, reconcile the date in both source headers and
the privacy manifest definition, then regenerate the website. Do not backdate a
publication report. Terms and organization rules remain 2026.10.

The previous canonical 2026.12 files were copied without editing into
`Legal/history/privacy-2026.12.{de,uk}.md`; the old drafts and the actual
2026-09-02 publication report remain intact. Existing Firestore versions and
acceptance logs must not be replaced with corrected text under an old version ID.

`Legal/legal-manifest.json` retains the existing `published` serialization status
required by the bundle generator. The generated bundle likewise uses the existing
published-document schema. These are the intended release payload, not evidence
that 2026.13 is live. The current public website and Firestore were not modified.
Release must retain a pending-publication gate until read-back proves alignment.

## Acceptance, consent and manifests

- `privacy.requiresAcceptance` stays false. The compliance monitor filters on
  this flag, so this notice correction adds no mandatory acceptance prompt.
  Existing user confirmations and legal/age evidence are not migrated or erased.
- `AuthService.currentPrivacyVersion` and the bundle become 2026.13. New
  registration evidence and new optional analytics choices use that version.
- `AnalyticsConsentService` retains the ID, language and original versions for
  an existing choice. Only withdrawal followed by a new choice creates a new ID
  and records today's version. The disclosure remains `2026-08-25.1` and purpose
  remains `owner-aggregate-analytics-v1`; presence is separate from this consent.
- The server mutation parser now accepts explicit 2026.12 and 2026.13 with the
  unchanged disclosure. Historical receipt compatibility retains every old pair
  and adds 2026.13. Receipt persistence itself is unchanged: an existing receipt
  is not relabeled on resynchronization. Legacy app-version inference remains
  unchanged; a versionless 1.0.3 grant is intentionally not guessed.
- `PrivacyInfo.xcprivacy` is unchanged. It already declares linked Product
  Interaction for App Functionality (and optional Analytics), without tracking.
  Correcting timing adds no data category, purpose, SDK or required-reason API.
  The release task owns archive manifest comparison and live App Privacy answers.

## Required coordination and publication order

1. Coordinator merges the package and runs the common verification phase first.
   The release task owns `unresolvedReleaseBlocks`, strict validator changes and
   App Privacy account checks. Only the privacy definition in the shared legal
   manifest was changed here; preserve it when merging release's block updates.
2. Before the new client ships, publish compatible server code for
   `updateAnalyticsConsent`, `updateAnalyticsConsentV2` **and `trackAnalyticsEvent`**.
   The last function embeds the receipt-version compatibility check. Updating
   only consent writes would create 2026.13 receipts that the old event reader
   rejects. Confirm all deployed callers of that helper in the integration tree.
   The old parser rejects 2026.13; the client treats invalid-argument as a rejected
   opt-in. This ordering is necessary to preserve the choice on first sync.
3. Publish only a new immutable `legalDocuments/privacy/versions/2026.13` and
   switch its active pointer from the reread prior version using atomic
   create/update-time preconditions. Preserve prior versions, logs and unrelated
   legal documents. Do not use the generic seed script with `--force`: it writes
   all legal kinds and can overwrite existing version evidence.
4. Coordinate the generated website publication with the Firestore change and
   verify both locales, version metadata, titles, content and hashes against the
   intended bundle. Keep the app release gated during any mismatch window.
5. Read back old 2026.12 version content and unrelated legal pointers unchanged;
   record publication time, effective date, commit, approver, locale hashes and
   exact deployed functions. Only then clear the pending-publication gate and
   distribute a build containing the matching fallback.

No publication script was executed and no backend data was migrated. The
existing generic seed tool is not a safe production rollout mechanism for this
narrow change; the coordinator must use a scoped preconditioned publication.

## Verification to run in the shared phase

Nothing below was run in this task. Only source reading, local editing,
Markdown-to-resource generation and diff inspection were performed.

- `python3 scripts/validate_legal_documents.py`, then `--release` with the release
  task's updated gates; `python3 scripts/generate_bundled_legal.py --check`.
  Check that generation changes only the privacy website and privacy bundle item.
- Build Functions and run analytics consent unit tests, including explicit old
  and new versions, malformed/missing pairs, historical version preservation
  and rejection of inferred versionless 1.0.3 grants.
- In a local `demo-*` Firestore emulator, run
  `lib/analytics/privacyConsent.integration.test.js` and the existing
  `lib/analytics/accessReliability.integration.test.js`. The added case checks
  immutable receipt evidence, withdrawal, fresh 2026.13 choice and stale grant
  rejection. Follow with the existing analytics delivery tests.
- iOS unit: `AccessReliabilityTests` (includes a stored 2026.12 choice surviving
  service recreation and a fresh choice receiving 2026.13), legal document and
  compliance monitor tests, analytics delivery/account-switch tests.
- Shared iOS build/UI: both languages online/offline legal reader; no privacy
  acceptance gate; retained old opt-in and fresh opt-in; withdrawal/re-enable;
  account switch. Verify actual delivery after server receipt authorization.
- During separately authorized external work: read back the website, Firestore
  and deployed compatibility before release; App Privacy/physical-device gates
  remain with the release task. None are claimed complete here.
