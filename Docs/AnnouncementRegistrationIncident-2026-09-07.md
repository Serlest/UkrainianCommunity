# Announcement registration incident — 7 September 2026

## Diagnosis

Production Cloud Run request logs show one HTTP 500 for registerAnnouncementDevice at
10:47:02.471931 UTC (12:47 Vienna), revision registerannouncementdevice-00001-foj.
The corresponding exception is Firestore NOT_FOUND: No document to update in
announcementDevices. App Check and Authentication verification both passed.

The verified-registration fast path read the document and then updated it outside a
transaction. A concurrent deletion between those operations reproduces the same error.
The logs do not establish which deletion caller won the race. Subsequent requests at
10:47:03 and 10:47:20 returned 200; that recovery did not remove the race.

## Fix and verification

Registration reads and writes now share a Firestore transaction, including the
verified refresh, initial challenge creation, rate limit and account binding.
The push challenge is sent outside the transaction and only if its record still
exists with the matching challenge and account.

Two regression scenarios fail on the previous implementation:
- verified refresh versus disable reproduces NOT_FOUND;
- four simultaneous initial registrations send four challenges instead of one.

After the fix, all 7 announcement integration checks pass against the Firestore
emulator, including 20 iterations of refresh versus disable. Backend unit run:
399 passed, 0 failed, 75 skipped (integration suites require their emulator setup).
TypeScript build and lint pass. No iOS source or build number changes are required.

Artifacts: output/announcements/registration-race-before.log,
registration-race-after.log, registration-unit.log, registration-deploy.log.

## Storage

Live metric at 11:10 UTC: 311,818,638 bytes (297.37 MiB), below the configured
768 MiB warning and 1 GiB threshold. The supplied recovered email describes an
older incident beginning 31 August, not a new storage failure.

Both Storage policies had stale documentation/subjects referring to 256/512 MiB.
Only those text fields were corrected to 768 MiB / 1 GiB. Thresholds, enforcement,
notification channels and bucket contents were unchanged.

## Production completion

The scoped Firebase deployment completed successfully. Cloud Functions read-back:
ACTIVE, revision registerannouncementdevice-00002-zuq, update time
2026-09-07T11:22:20.657967817Z (13:22 Vienna).
A request without App Check still returns HTTP 401 / UNAUTHENTICATED.

No further Cloud Run HTTP 5xx was observed in the queried logs after the original
incident. A successful authenticated physical-device registration on the new
revision has not yet been observed; emulator regression and active deployment
must not be described as that device proof.
