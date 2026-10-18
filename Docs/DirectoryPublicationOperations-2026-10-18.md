# UAC Directory publication operations

Status: live publication enabled by the user's direct instruction on 18 October 2026. This instruction supersedes the shadow-only rollout and four-week waiting period in the initial plan. Source verification, bilingual substantive review, revision protection, audit history and read-back remain mandatory.

## Scope

- Firebase `directoryCategories` is the authoritative catalog. Read the current payload and revision before preparing each publication.
- Find useful information missing from the catalog as well as changes to existing information. Use competent official public authorities and directly opened documents.
- Publish contact/link corrections, new sections, corrections of one existing section, or new topics in existing visible groups. New categories/navigation changes remain coordinated with UAC main.
- The publishing Codex agent reviews both languages, applicability, dates, exceptions and statement evidence. No further user approval is required for routine verified publications. Hold unresolved factual/source conflicts.
- Legal, benefit, residence, health and deadline material requires a substantive check of the governing primary source and practical scope; its category alone is not a reason to defer it indefinitely.

## Publication path

Use the IAM-protected `publishDirectoryAutomation` endpoint at `https://publishdirectoryautomation-2kiasqpopq-ey.a.run.app`. The caller identity is `uac-directory-automation@ukrainiancommunity-dbd5f.iam.gserviceaccount.com`; the local script obtains an ID token through the keyless IAM Credentials API. Do not make raw Admin writes to category documents.

Two gates are enabled: runtime `DIRECTORY_AUTOMATION_PUBLISH_ENABLED=true`, and `appConfig/directoryAutomation` with `policyVersion=directory-v1`, `allowLowRiskAutoPublish=true` and `allowVerifiedContentPublish=true`.

The manifest has a stable UUID `idempotencyKey` and `candidate`. Candidate fields and the precise review shape are defined in `functions/src/directory/directoryAutomationPolicy.ts`. For content use `changeClass=verified-content` and one operation:

- `add-section`, `field=section`, `newValue=sectionId`;
- `replace-section`, same stable ID/order, `field=section`;
- `add-topic`, `field=topic`, `newValue=topicId`, existing visible group.

Pin `previousPayloadSHA256`, `expectedRevision` and exact `nextPayload`. Content review must pin the next payload SHA256 and include recent review time, both-language check, applicability, no unresolved source conflict and bilingual statements mapped to source fragments. Each new/replaced section must cite the checked URL. The current content path uses one directly checked official page per operation; unsupported multi-source changes must be split into independently supported blocks or implemented and tested before use.

The server validates the entire payload, re-fetches all evidence fragments, rejects edits outside the declared target and optional single source addition, and atomically records revision/history/receipt/latest-additions state. A source page containing a fragment does not establish semantic correctness by itself; the publishing agent is responsible for the substantive claim review.

From `functions/`:

```sh
node scripts/publishDirectoryAutomation.mjs --candidate MANIFEST --url https://publishdirectoryautomation-2kiasqpopq-ey.a.run.app
node scripts/publishDirectoryAutomation.mjs --candidate MANIFEST --url https://publishdirectoryautomation-2kiasqpopq-ey.a.run.app --apply
```

Apply repeats preflight and performs production payload/revision/receipt read-back. Preserve the exact manifest/key after an uncertain outcome; reconcile the receipt before changing it. A concurrent edit requires a fresh baseline and review. Corrections are new versions; never delete history.

## Latest additions and reporting

New topics produce one feed item; initial sections are not duplicated. A new section in an existing topic produces one item. Existing section/contact corrections do not bump the feed. Verify the public `getDirectoryRecentAdditions` projection after additions.

Each morning/evening run saves an immutable report of directly opened sources, coverage limits, decisions, publication receipts/revisions and read-back. Zero publication is valid when nothing useful passes checks. Keep partial searches explicit and rotate the source registry rather than claiming all sources were checked.

## First live publication

On 18 October 2026 the block `housing/tenant-rights/subtenant-rights` was published from the Austrian Ministry of Justice page `https://www.oesterreich.gv.at/de/themen/bauen_und_wohnen/wohnen/3/2/Seite.210219`. Housing revision changed from 1 to 2. Anonymous catalog read returned the exact bilingual section; public latest additions returned exactly one corresponding item. Artifacts: `/Users/serlest/.codex/uac-content-automation/artifacts/directory-v1/runs/2026-10-18-activation/`.
