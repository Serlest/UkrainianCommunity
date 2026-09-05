# Android-only local Functions harness

This folder is not a production Functions source. Use only
`firebase.android-functions-local.json`, never add this folder to `firebase.json`.
No app credentials, production data, real emails or real FCM are needed.

From the repository root:

```sh
npm --prefix functions run build
node functions/android-local/run.cjs check
```

`start` instead of `check` keeps the emulators available for Android. Coordinate
ownership of ports with other tests first. Android reaches Functions at
`10.0.2.2:5008`, Auth at `:9098`, Firestore at `:8088`, Storage at `:9198`.
The host only listens on `127.0.0.1`; project ID is always `demo-uac-android`.
The launcher creates ignored `.env.local` from the checked-in non-secret
`.env.example`, and refuses an unexpected existing override. It uses a temporary
Firebase CLI configuration directory; no persisted signed-in CLI state is copied.

## Boundaries

- Before Admin initialization or application import: exact project/host validation,
  credential/proxy/loader-env rejection, outbound HTTP/TLS/DNS/socket restrictions.
- Admin's certificate credential is a new unregistered key generated only in
  process memory, not read from disk or persisted. It has no cloud authority.
  Emulator calls use the emulator-only `owner` token.
- Messaging is a deterministic in-memory fake. A successful diagnostic push here
  means only that the local handler called that fake, not that FCM accepted or
  displayed anything.
- Child processes, workers and UDP are blocked inside the application process.
  Four explicit localhost service ports are allowed. This is a Node-level
  accidental-egress guard, not an OS security sandbox for untrusted native code.
- Only existing callable endpoints are exported. Firestore/Auth/storage/scheduled
  background triggers and public HTTP handlers are deliberately not exported.
  Calls preserve their original auth, active account, role, TOTP and App Check
  options. The normal Firebase emulator still uses its synthetic token verification;
  this does not prove cloud attestation, password policy or TOTP enrollment.
- Firebase CLI supplies a non-existent demo RTDB placeholder in `FIREBASE_CONFIG`.
  The exact demo placeholder is tolerated but is never passed to Admin initialization.
  RTDB is not started and outbound RTDB access is blocked.

The known startup warning from `ENFORCE_ANALYTICS_APP_CHECK.value()` belongs to
the existing source; this harness does not change production analytics policy.
Its local value remains the existing false default, not cloud enforcement proof.

## Android callable client boundary

The Android demo app uses a deliberately local-only implementation of the
[documented callable protocol](https://firebase.google.com/docs/functions/callable-reference),
not the native Functions SDK. The tested Functions 22.1.1 dependency requires IID
and fetches an installation token even after `useEmulator`; the intentionally
invalid demo API key rejects this before the handler. Do not make that key valid,
initialize a default Firebase app, or add real FIS/IID credentials to bypass it.

`LocalFunctions` returns `LocalCallableClient` for the existing named Auth app.
It accepts only a reviewed callable allowlist at the fixed demo endpoint, attaches
that real emulator Auth user's ID token, and disables proxies, redirects and
automatic retries. Request/response sizes and nesting are bounded; transport
timeouts finish the actual task before the shared Auth mutation mutex releases.
Comment/report creation and legal acceptance (which appends an audit receipt)
become `UNCONFIRMED` if the connection/result is uncertain after body transmission.
No automatic re-send is allowed. No Messaging, IID, FIS or cloud App Check bypass
is initialized. Auth and Firestore are still the real Android SDKs.

This verifies Android Auth → local callable protocol → guarded handler → Firestore
Rules/read-back only. A release/staging native SDK gateway with real reviewed
configuration and attestation remains a separate requirement; do not label this
local result as native Functions SDK or cloud E2E proof.

## Verification

`check` runs a real Auth → callable → Firestore path, ownership/email/owner/TOTP
negative cases, Storage RPC read-back, fake push, six independent inbox records and
idempotent delivery receipts; then the Android fixture assertions, push Rules suite,
existing workflow/APNs/durable-delivery integration, and FID cleanup pagination.
Known synthetic fixture IDs only are used; no production import/export.

Port-free boundary and push unit checks (run after the build):

```sh
node --test functions/android-local/boundary.test.cjs
node --test functions/lib/notifications/androidPush.test.js functions/lib/notifications/pushRegistrations.test.js functions/lib/notifications/inboxPushDelivery.test.js functions/lib/notifications/pushRegistrationMutations.test.js
```

The source catalog intentionally detects changed Rules/push sources. Review that
diff and record the new contract separately; never regenerate the baseline just
to hide drift.

## Android push dependencies still required

The local backend now accepts `platform=android` through the same verified,
active, self-write, TOTP, identifier and timestamp gates as iOS. The existing
legacy token/FID schema and cleanup contract are preserved. Unknown platforms
are ignored by the sender without speculative cleanup.

Android registrations receive a separate Android message; iOS and missing-platform
legacy registrations retain their original message. Android localization keys are
`uac_` plus the iOS key with dots replaced by underscores. Client resources must be
integrated before real delivery: channel `uac_updates`, monochrome `ic_stat_uac`,
all UK/DE strings, and a data-only `type=inboxSync` handler with current `unreadCount`.
Use `export-push-resources.mjs /absolute/output/directory` to create review XML from
the actual iOS resource catalog; it fails on missing translations/collisions.

Visible messages have high delivery priority, private lockscreen visibility, the
current server unread count, a stable SHA-256 tag per inbox notice, and TTL bounded
by the original APNs expiration and one hour. There is no invented shared collapse
key for distinct alerts. The silent badge hint uses normal priority, zero TTL, and
`uac-inbox-sync` collapse. Native notification permission and channel/user settings
remain authoritative.

FCM notification messages are inherently collapsible and do not promise ordered
or complete offline presentation. Six preserved server inbox records and retry
receipts are tested here, but full Android inbox recovery and actual foreground,
background, cold-start, Doze, logout/rotation and device display remain separate
release gates. No deployment is performed by this harness.

Official contracts: [AndroidConfig](https://firebase.google.com/docs/reference/admin/node/firebase-admin.messaging.androidconfig),
[AndroidNotification](https://firebase.google.com/docs/reference/admin/node/firebase-admin.messaging.androidnotification),
[FCM collapse behavior](https://firebase.google.com/docs/cloud-messaging/customize-messages/collapsible-message-types),
[Functions emulator credentials](https://firebase.google.com/docs/emulator-suite/connect_functions).
