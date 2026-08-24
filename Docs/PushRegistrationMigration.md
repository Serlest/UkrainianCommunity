# Firebase Messaging FID migration

Last audited: 2026-08-24

Firebase Messaging 12.18 deprecates the registration-token client API in favor of Firebase
Installation ID (FID) registration. The repository uses a staged, backward-compatible contract so
supported older app versions continue receiving push notifications during the transition.
The Swift package requirement and resolved dependency are both fixed to the audited 12.18.0
baseline; release validation fails if either changes before the FID behavior is re-audited.

## Stored contract

Push registrations remain in `users/{uid}/notificationPushTokens/{registrationId}`. The historical
`token` field is retained as the identifier field until legacy clients are retired:

- `registrationType: "fid"` means `token` contains a Firebase Installation ID.
- `registrationType: "token"` means `token` contains a legacy FCM registration token.
- a missing `registrationType` is interpreted as `"token"` for compatibility with older clients.

New iOS builds always write `registrationType: "fid"`. Firestore Rules accept only `fid`, `token`,
or the missing legacy value, require explicit FIDs to match the 22-character URL-safe format, and
keep registration documents unreadable by clients. The backend repeats the format validation so a
malformed historical or Admin-written FID cannot poison a multicast batch; it skips and removes
that unusable document without touching valid legacy registrations.

## Delivery behavior

Cloud Functions parse and deduplicate both registration generations, split mixed targets into
Firebase Admin batches of at most 500, and send tokens before FIDs as required by the Admin SDK
response ordering. Only permanent identifier failures (`invalid-registration-token` and
`registration-token-not-registered`) remove a stored registration. Transient delivery failures do
not delete it. A cleanup failure is logged without converting a successfully attempted push into a
failed business operation.

An upgraded installation can temporarily own both its old token document and its new FID document.
Firebase Messaging 12.18 treats a legacy iOS token as belonging to a FID when that token starts with
the exact 22-character FID. The backend uses only this strict, SDK-defined prefix relationship; it
never guesses from device name, app version or document age. When a valid FID and its prefixed legacy
token coexist, the backend sends once through the FID. It removes the superseded token document only
after that FID send succeeds. A failed FID send preserves the legacy document, and an unrelated,
empty, malformed or short FID never suppresses or deletes another registration.

This correlation is intentionally tied to the Firebase Apple SDK 12.18 token-freshness invariant
and must be re-audited whenever Firebase Messaging is upgraded. If the identifier format changes,
the conservative behavior is to keep and send unmatched registrations rather than infer ownership;
that can expose a duplicate during migration, but it cannot silently delete another device's route.

The new client enables `FirebaseMessagingInstallationIdEnabled`, assigns the APNs token manually
because Firebase app-delegate proxying is disabled, calls `Messaging.register`, and receives the FID
through `messaging(_:didReceiveRegistration:)`. Sign-out also resolves the current FID directly
through Firebase Installations, so cleanup does not depend on an APNs token or the Messaging delegate
having fired first. Before Firebase Auth is cleared, an App-Check-protected callable synchronously
deletes that FID and only legacy tokens with the exact FID prefix. Cleanup failure blocks sign-out;
the next attempt retries it. The callable uses prefix-bounded Firestore queries in pages of 250, so
the cleanup remains within batch limits without scanning or deleting another installation's route.
Notification preferences are not changed globally, and registrations belonging to other
installations remain intact. CI runs this pagination/isolation path against the Firestore emulator;
it is not merely a skipped branch of the unit-test suite.

## Required rollout order

1. Deploy the dual-read Cloud Functions, the authenticated/App-Check-protected registration-cleanup
   callable, and compatible Firestore Rules first.
2. Verify mixed token/FID delivery in a non-production Firebase project.
3. Release the FID-enabled iOS build.
4. Observe delivery errors and permanent-registration cleanup while supported legacy builds remain.
5. Remove token compatibility only after the minimum supported app version can no longer write
   legacy documents and production contains no active legacy registrations.

Reversing steps 1 and 3 can stop push delivery for the new client. Repository tests prove schema,
classification, batching, ownership and compile-time API compatibility; real APNs/FCM delivery,
entitlements and production credentials still require a physical-device/TestFlight smoke test.
The production rollout gate is a staging test with two physical devices: upgrade one device from a
legacy build and confirm it receives exactly one notification and its old document is cleaned only
after success; keep the second device on the legacy build and confirm its token remains and still
receives. Do not ship the FID-enabled build until this mixed-version scenario passes with production-
equivalent APNs entitlements and Firebase configuration.
