# Legal and App Store change-control matrix

Use this matrix before merging any product or backend change and again before an App Store submission. A code change is not legally complete until every marked surface is reconciled.

## Single source and publication order

1. Confirm the implemented behavior, data fields, recipients, access rules and retention.
2. Update `Docs/AppStorePrivacyInventory.md` with code evidence.
3. Update the canonical German draft in `Legal/` and the Ukrainian translation in the same change.
4. Obtain operator approval and qualified Austrian/EU legal review for material changes.
5. Generate/update the public website, then verify both languages and all links.
6. Publish a new versioned Firestore legal document. Terms require renewed acceptance when material; the privacy notice itself is not “accepted,” while separate consent is versioned independently.
7. Update in-app fallback text/version so an offline or backend failure does not show contradictory rules.
8. Reconcile App Store Connect privacy labels, privacy URL, support URL, description and review notes.
9. Archive the exact release commit and compare the signed archive privacy report with the inventory and public policy.
10. Record version, hash, publication time, deploy commit and approver in the release evidence.

## What a change triggers

| Product or operational change | Privacy policy | Terms | App Store privacy | Other mandatory work |
| --- | --- | --- | --- | --- |
| New personal-data field or identifier | Categories, purpose, basis, retention, recipients | If user obligation or public visibility changes | Data type, linked/not linked, purpose | DTO/Rules/Storage schema, deletion/export, inventory |
| New SDK, API or processor | Processor, transfer, purpose, retention | If availability/external-service risk changes | SDK disclosures and data types | DPA, region, privacy manifest, archive report |
| Analytics, metrics, profiling or experiments | Exact signals, consent/basis, opt-out, retention | Explain material user-facing limitation | Analytics purpose and linkage | Consent copy/version, server receipt, deletion, tests |
| Push notification reason or provider | Tokens, content, basis, opt-out, retention | Delivery is non-guaranteed; service notices | Identifiers/other data if changed | APNs/FCM configuration, notification matrix |
| Organization, shop, specialist or paid offer | Controller roles, recipients, public data | Platform role, seller duties, prices/contracts | Usually no change unless new data/payment | Verification, required legal fields, complaints |
| Organization-creator rules or acceptance flow | Evidence fields, purpose, retention and access | Organization duties and relationship to general Terms | Other Data if evidence fields change | Versioned bilingual rules, server acceptance log, creation proof, Rules tests |
| Event registration or attendee features | Attendee fields, recipient organization, retention | Registration meaning, cancellation, organizer duties | User content/contact data as applicable | Access matrix, capacity and notification tests |
| Comments, reviews, reports or moderation | Public visibility, moderation evidence, retention | Prohibited content, decision, appeal | User content | DSA notice/action, statement of reasons, audit log |
| Role, ban, warning or account status | Access recipients, logs, retention | Enforcement grounds and appeal | Usually no data-type change | Rules/Functions matrix, notification and audit test |
| File/image upload or media metadata | Content, EXIF handling, storage/retention | Rights, licenses, third-party data | Photos/user content | Storage Rules, orphan cleanup, deletion cascade |
| Location, map or region behavior | Device vs manual location, precision, basis | Publisher accuracy duty | Precise/coarse location | Permission string, screenshot and device test |
| Payment, donation, subscription or advertising | Financial data, processors, profiling | Price, refund, seller, tax, ad rules | Purchases/financial/advertising data | StoreKit, consumer disclosures, tax/legal review |
| Account deletion/export | Deletion exceptions, backup periods, rights | Account consequences | Account deletion URL/behavior | Full cascade, evidence preservation, live test |
| Retention or backup change | Every affected duration/criterion | If content/account consequences change | Usually no | Scheduled job, TTL/index, restore and race tests |
| New country, language or target age | Controller/authority, child rule, transfers | local mandatory law, language, age/capacity | Territory/age rating | localization, local counsel, support capability |
| Website form, cookie, analytics or external media | Website data, cookie/storage, recipient | If service scope changes | Website data rarely, verify | consent banner if needed, CSP, form security |

## Required release comparison

The following six representations must say the same thing:

- implemented app/backend behavior;
- `Docs/AppStorePrivacyInventory.md`;
- `UkrainianCommunity/PrivacyInfo.xcprivacy` and embedded SDK manifests;
- `Legal/privacy.*.md` and the published privacy website;
- Firestore active legal documents and in-app fallback;
- App Store Connect privacy answers and URLs.

Any mismatch is a release blocker, even if the build and tests are green.

## Current unresolved blockers for version 2026.10

- Deploy and verify automatic deletion for separate `auditLogs`, closed support, feedback and report records.
- Public DSA-compliant notice-and-action flow and internal appeal/statement-of-reasons workflow.
- Austrian lawyer review of the final filled German text.

The operator identity is filled as Timofeev Philipp, a private non-commercial
hobby operator at Egger-Lienz-Straße 47, 6020 Innsbruck. Registration now
requires an explicit `14+` confirmation and stores its timestamp/version. Closed
support, feedback and report conversations use a six-month retention rule in the
scheduled cleanup implementation; these changes remain release-blocking until
the matching Functions, index and Rules are deployed and verified.

Organization creation now has a separate versioned German/Ukrainian rules
document. Creation is bound to an immutable server acceptance log and a private
30-day proof for the exact organization ID and name. A change to organization
fields, seller obligations, acceptance metadata or proof retention must update
the organization rules, privacy policy, inventory, Functions, Rules and tests in
the same change.
