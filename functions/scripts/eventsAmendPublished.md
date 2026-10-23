# Supported Events amendments — 23 October 2026

The human explicitly authorized autonomous correction of published Events on 23 October. The supported maintenance command is:

`node /Users/serlest/Developer/UkrainianCommunity/functions/scripts/eventsAmendPublished.mjs <config.json> [--apply]`

It uses the authenticated Firestore SDK conditional update of an existing exact ID. It never creates, deletes or performs a direct REST patch. All edits retain organization/author, region, media, original identity and counters. Dry-run and apply use immutable saved files; apply refuses changed baselines, evidence or plans. A fresh exact same-ID read-back and receipt are mandatory.

## Regional procedure

1. Open the exact existing document, save `{id,data}` as baseline, and verify direct official facts. Preserve original reports/manifests/receipts. Save source snapshots and a new amendment request with `id`, `kind`, `reason`, at least three substantive `verificationNotes`, `evidence` (absolute saved paths) and `changes` (allowlisted event fields only). Put all three root text fields in sync with Ukrainian localization whenever changing copy. Keep full German text.
2. Set config `requestPath`, `baselinePath`, unused `planPath` and `receiptPath`; run the command without `--apply`. Review exact old/new values, factual evidence, pricing and Europe/Vienna conversions. Never write a guessed date or price.
3. Acquire only the shared publication mutex via `policies/events-v3/runtime.py publication-acquire --run-id <amendment-run> --thread-id <your-thread-id>`. Do not acquire a work lock for prepared amendments. Bind config `runId`, `threadId`, `generation` to this returned owner. Never impersonate another region, remove foreign locks or interrupt an active chat. If busy, retain the request and resume after release.
4. Run the same command with `--apply` within ten minutes of dry-run. A precondition conflict requires a fresh baseline and review, never retry blindly. Do not rerun a successful amendment. If the write may have committed without a receipt, exact-read the same ID and reconcile before another attempt; no create fallback.
5. Verify receipt `updated=true,allVerified=true`, both complete texts and every changed field. Update only current coordination issue state, link the new receipt, and release the owned publication lock. Sending an assignment or obtaining a lock is not completion.

## Supported corrections

Text, dates/occurrences, structured/legacy price, external action and participation may be amended. Preserve occurrence IDs and historical dates; merge only the same programme at the same venue, after targeted duplicate checks. Root startDate is earliest occurrence and root endDate latest end. Explicitly cancelled single sessions use occurrence.status=cancelled while later scheduled sessions remain intact.

Sold out is not cancellation: explain UK/DE, remove external registration invitation, use participationMode=none and requiresRegistration=false. Preserve the scheduled event.

Postponement without a new date: archive the old live listing with clear UK/DE postponement text, close ticket invitation, preserve old date only as historical evidence. Do not invent a postponed enum unsupported by clients, set cancelled, or invent a new date. A confirmed duplicate is archived only after verifying the retained original approved ID (`kind=duplicate,keepId=...`). Never delete/recreate.

Unknown price remains pricing.kind=unspecified with explicit bilingual note, never free or an invented amount. The schema still requires numeric legacy price; Android currently falls back to that legacy zero even for explicit unspecified. This client display defect cannot be repaired by inventing a price or violating the supported schema. Track it separately as requiring client delivery, rather than claiming the display is fixed.

The coordinator keeps ordinary heartbeat monitoring lock-free and routes prepared amendments to regions. A direct human maintenance turn authorizing actual updates may use its own named Events maintenance run and publication mutex only, as on 23 October. No new event publications, News changes or app/release changes are implied.
