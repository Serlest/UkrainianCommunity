# Privacy Policy 2026.12 publication

Operator authorization: the user explicitly instructed publication of the current policy on 2026-09-02 and subsequently requested a new build containing it, to be selected in the App Store 1.0.1 draft. No App Review submission or public app release was authorized. MFA changes were explicitly excluded; the operator reported a successful manual MFA check.

## Published scope

- Canonical German and Ukrainian policy: `Legal/privacy.de.md`, `Legal/privacy.uk.md`, effective 2026-09-02.
- Website: https://ukrainiancommunity-dbd5f.web.app/privacy.
- Firestore: new immutable `legalDocuments/privacy/versions/2026.12`, active pointer switched from 2026.11 using an atomic commit with update-time/create preconditions.
- Offline bundle and `AuthService.currentPrivacyVersion`: 2026.12.
- Archive 1.0.1 (64): both locale hashes verified against the bundle. Terms and organization rules remain 2026.10. Privacy `requiresAcceptance` remains false; no new login or MFA enrollment requirement is introduced.
- Prior policy 2026.11 and unrelated legal documents were preserved and read back unchanged.
- The website URL renderer also excludes sentence-ending punctuation from link targets; this repairs the privacy-provider link and an existing Ukrainian reporting link without changing the legal wording.

## Technical evidence

Read-back at 2026-09-02T16:54:04Z matched website bytes, Firestore text and bundled locale hashes:

| Locale | SHA-256 of policy Markdown |
| --- | --- |
| de | `5f6e46a0aed1f4e273782049c13d534fecc8dfe0912a8964ebbeb3c9e859dea2` |
| uk | `df741f8c77ae765d2b41ac7ca5a10b5296cf68829abb2e6e867b624520e73364` |

The signed archive contains 30 privacy manifests, 14 distinct collected-data categories and no tracking declaration. App Store Connect's existing published answers were checked against those categories during this release preparation. Firestore recovery and backup settings were read back (7-day PITR, daily 14 days, weekly 98 days); Storage soft delete was read back as 604800 seconds. Content-planning receipts use six calendar months, deleted inbox records 30 days. Cleanup is asynchronous and is described as such.

Local evidence: `outputs/release-1.0.1-2026-09-02/privacy-publication-readback.json`, `build64-archive-proof.json`, `backend-readback.json`. These generated/private release artifacts are not committed.

Provider documentation checked: [Firebase privacy and retention](https://firebase.google.com/support/privacy), [Firebase iOS TOTP](https://firebase.google.com/docs/auth/ios/totp-mfa).

This records operator approval and technical verification, not an independent legal opinion or a certification of compliance. The recommendation for qualified Austrian legal review remains. Other unverified release gates must not be closed by this publication record.
