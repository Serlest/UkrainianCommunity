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

## Scoped publisher added during coordinator validation

`scripts/publish_privacy_2026_13.py` is the narrow Firestore publisher. It uses
Python's standard library and the existing external `control.py` authentication
helper. No SDK installation, server ports or simulator are needed. Project and
`(default)` database are fixed to `ukrainiancommunity-dbd5f`; there is no project,
version or force override.

Default execution is read-only against Firestore and creates a new local JSON
review plan. It reads the three legal pointers and **all** their version documents
with pagination. The plan contains only hashes/technical metadata, never tokens,
actor identities, or full policy bodies. No acceptance or analytics collections
are read or written. Existing plan files are never overwritten.

Commands below are relative to the coordinator's integrated checkout. First run
read-only dry-run; inspect the saved plan and the source/website/bundle diff:

```sh
python3 scripts/publish_privacy_2026_13.py --plan work/privacy-2026.13-plan.json
```

The helper defaults to the read-only authentication module supplied by the
coordinator at
`/Users/serlest/Documents/Codex/2026-09-04/new-chat/production-release/control.py`.
`--control PATH` supports a relocated copy with the same request API and fixed
project. Authentication is performed by that helper; credentials are never saved
in the plan. Do not commit private authentication helpers or generated plans.

Only the coordinator, after common verification and publication authorization,
should execute the explicit apply command:

```sh
python3 scripts/publish_privacy_2026_13.py --apply --plan work/privacy-2026.13-plan.json
```

Before sending a write it regenerates and compares the complete plan: locale
source hashes, privacy bundle, generated website, manifest privacy definition,
active pointer update time and every historical document fingerprint. Source
header dates must match the manifest. The effective date must be today's date in
Vienna at apply time. If dates or inputs change, reconcile and create a new plan
at a new path. This is preparation, not automatic date adjustment or permission.

There is exactly one atomic Firestore commit containing two writes:

1. Create `legalDocuments/privacy/versions/2026.13` with `exists: false`, full
   bilingual text and content hashes, supersedesVersion 2026.12, false acceptance,
   and server publication/creation/update timestamps.
2. Update only the named privacy pointer fields with its reviewed `updateTime`
   precondition. An update mask preserves any unrelated pointer fields.

After the attempt it makes one read-back pass, verifies both locale hashes and
version/pointer payloads, and compares every prior version and the other legal
pointers with the plan. This verifies preservation of 2026.12 and earlier privacy
versions, as well as terms/organization versions. There are no other write paths.
A concurrent unrelated legal change causes verification to fail, not an automatic
rollback or a claim that the publisher caused that change.

A lost commit response never causes a write retry. If the one read-back proves
success, the result explicitly says `verified-after-uncertain-response`. Otherwise
it exits with publication unconfirmed. Use the **same** plan for read-only recovery:

```sh
python3 scripts/publish_privacy_2026_13.py --verify --plan work/privacy-2026.13-plan.json
```

Do not rerun apply to resolve ambiguity. An existing 2026.13 is never overwritten.
Keep the plan and the successful output (including publishedAt and DE/UK hashes)
with release evidence. No website upload, Function deploy, Apple change or consent
migration is included; their existing coordination gates still apply.

Validation performed here, limited to this publisher:

- 10 offline tests passed using in-memory Firestore responses. Cases cover the
  default CLI's lack of writes, create/CAS envelope, stale plans, existing target,
  project/input mismatch, date guard, preservation, locale tampering, CAS conflict
  and lost response recovery. Command:
  `python3 -m unittest discover -s scripts -p test_publish_privacy_2026_13.py -v`.
- Read-only production schema inspection and a live **dry-run only** succeeded.
  Active privacy was 2026.12, target 2026.13 absent; 26 legal documents were
  fingerprinted. New locale hashes: DE
  `e131a66168ffc0d0c514314fc3461a0dfd449359f50587e4ed7360f81e26b9b9`, UK
  `43b729625d0f7fae044460f247a156954d99f6e1efa58e23fe1c7e2ce3bf734c`.
- No production commit/apply, deploy, simulator or server process was executed.
  Offline fake transport tests do not prove production write permission or
  successful publication. The coordinator must create a fresh review plan in the
  integrated checkout before applying; the task's dry-run plan is local evidence.
