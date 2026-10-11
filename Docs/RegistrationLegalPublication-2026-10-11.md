# Registration legal publication, 11 October 2026

The operator approved the bilingual registration wording for the iOS account
flow. Source commit `26826af` contains Terms 2026.11, Privacy 2026.15,
the iOS offline bundle, generated website pages, and analytics consent
compatibility for 2026.12 through 2026.15.

## Production read-back

- Firebase Functions: `updateAnalyticsConsent` and
  `updateAnalyticsConsentV2` deployed successfully in `europe-west3`.
- Firestore: Terms 2026.11 and Privacy 2026.15 were created and their active
  pointers changed in one four-write commit. Both languages were read back
  by content hash; 26 existing legal documents were preserved.
- Hosting: live release `1791724011957000`, version
  `e9fa6eb79f2f1852`, changed only `/terms/index.html` and
  `/privacy/index.html`. The other 15 files kept their live hashes.
- Public HTML SHA-256: Terms
  `40731bf69c5c3a33042082e111d991eb460dbf7430eb68373782fc239d8c1a1f`;
  Privacy
  `b654566543b00b4e8b21436e189401f519f35b47532017da6a4a329ac3e7f8be`.

The first Hosting run stopped after finalization because the new version's
metadata omitted `fileCount`. Read-only inspection confirmed the candidate
was finalized with the exact 17-file plan and that the previous release was
still live. The same candidate was then released once and verified; no second
candidate or upload was created.

## Checks and distribution boundary

The iOS Debug Simulator build, TypeScript lint/build, focused analytics
consent tests, legal source validation, bundle check, Firestore read-back,
and Hosting read-back passed. A current signed archive, App Store privacy
questionnaire read-back, TestFlight upload, and public App Store release were
not part of this publication. The public iOS binary may therefore still
expose its older guest flow until a new build is distributed.
