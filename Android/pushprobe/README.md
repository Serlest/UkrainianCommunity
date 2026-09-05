# UAC synthetic push transport probe

This separate **debug-only** Android application is not the UAC app or a release
flavor. It has no dependency on `:app` and no Auth, Firestore, Functions, Analytics,
Crashlytics, private inbox, external route, topic subscription, or production
configuration. Root owns module inclusion, builds, the exact AVD and all sends.

## Fixed identity and build gate

- Project: `uac-android-test-20260903` / `966536981122`.
- Firebase Android app: `1:966536981122:android:2b617eb5d71f37b8dbe29b`.
- Android package: `at.serlest.ukrainiancommunity.staging`.
- Allowed runtime: debug API37 SDK-phone AVD with ranchu/goldfish hardware.
- Firebase BoM34.18.0 / Messaging25.1.2, new FID `register` / `unregister` APIs.

Root adds `include(":pushprobe")` in settings when ready. An optional build
property `-PuacPushProbeSdkConfig=/absolute/path/to/test-google-services.json`
reads the authorized test SDK config without copying it into source. The project,
number, app ID and package must all match exactly. With no config, build and unit
tests remain possible, but registration is disabled. There is no release variant,
google-services plugin, default FirebaseInitProvider, emulator/cloud fallback or
runtime environment selector. The main local APK is unchanged.

## Consent and proof boundaries

First launch, missing config and permission denial do not initialize a default
Firebase app or ask for an FID. A user explicitly enables the test, grants the OS
permission and gets a one-hour run. Only then does the fixed default test app
initialize. Auto-init, analytics/default collection, delivery export and
notification delegation are disabled in manifest/runtime; there is no Analytics
SDK. Registration is not automatic on subsequent Activity resumes.

Opt-out immediately masks delivery, clears the private target descriptor and
cancels only this package's own notifications. A serial worker then waits for any
actual registration operation before unregistering. It does not detach an SDK
Task when the Activity goes away. Registration failure is treated as uncertain
and requires explicit cleanup before another opt-in. Process death during an
unconfirmed registration changes to opt-out/cleanup, never a fabricated target.
Receipt-storage corruption fails closed and is visible; it cannot be claimed as
successful registration cleanup.

## Single-installation target, not logs

After actual registration acknowledgement, the SDK's current FID is written only
to `no_backup/push-probe/target.json` in this package's Android sandbox. It includes
the fixed project/app/package, installation hash, run ID, generation, registration
time and expiry. Root may transfer that **one exact** AVD's descriptor to a private
task `work/` file for a trusted send. Do not print it, put it in test output,
screenshots, clipboard, reports, git, or logs. UI shows only a hash prefix. No
legacy token API is used. `no_backup/push-probe/state.json` contains only bounded
safe event enums/timestamps, hashes and synthetic UUIDs, never FID/token/body.

Before sending, verify the package/AVD, all descriptor identity fields, current
registered UI and matching fingerprint, unexpired run, and a single installation
target. Send from trusted tooling, never from an APK/service-account credential.
Do not call owner-only application test endpoints as a guest.

## Exact synthetic data-only payload

The data map has exactly these fields (all strings):

```json
{
  "kind": "uac-synthetic-push-v1",
  "runId": "<UUID from private target>",
  "targetHash": "<SHA256 installation hash from private target>",
  "probeId": "<new canonical UUID for this one test message>",
  "sentAtEpochMs": "<current milliseconds>",
  "expiresAtEpochMs": "<later, at most 5 minutes after sentAt>"
}
```

Send **data-only**, no `notification`, title/body/localization/image/link/route,
topic or multicast. Expected `from` is the exact test project number. Unknown
fields, another run/installation, excessive TTL, expiry, denied permission/channel
or a repeated probe ID do not post. The local channel is `uac_push_probe`; it never
recreates a user-disabled channel under a different name. Notification text is
always the hardcoded generic `UAC Test / Synthetic notification delivery test.`
Tap opens only this same diagnostic Activity, through explicit immutable unique
PendingIntent; it records an event only for the current valid run/seen probe ID.

For current HTTP v1 use the single `message.fid` target field (not a multicast
array), `android.restricted_package_name` equal to the fixed staging package,
and an explicit short `android.ttl`, such as `"120s"`. No analytics label or
notification block. See the [official FCM REST message contract](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages).
The probe retains all seen IDs within a run, up to 64; at capacity it rejects new
messages rather than evict an ID and permit an old payload to replay.

Important SDK boundary: the standard Firebase service can auto-display a
notification-envelope message in background before `onMessageReceived`. This
probe's controlled sender must therefore always use data-only. The handler also
rejects notification envelopes when delivered to it in foreground; that check is
not claimed as a background server-envelope firewall. No hidden SDK override is
used. Main-app private push needs the separate fresh-ownership/inbox design.

## Evidence to collect

1. No config / no consent / permission denial: no target file or initialization.
2. Explicit allow/register: `REGISTER_ACK`; service callback is a separate event.
3. One provider-accepted send, separately actual device `RECEIVED`, `NOTIFY_POSTED`
   and a real visible notification/tap. A notify call alone is not visible proof.
4. Foreground, ordinary background, cold-process delivery and expired/duplicate
   payload decisions. Do not force-stop and call that a normal cold start.
5. Opt-out: immediate no-display, actual `UNREGISTER_ACK`; callback is separate.
   Check the old FID using one explicit trusted test send, not a broadcast.
6. Channel/permission denied or unregister failure remains visible, with no
   automatic re-register or duplicate write. System permission/Doze manipulation
   only on the exact approved AVD under root's runtime lock.

This proves only synthetic native FCM transport. It does not prove main-app
registration Rules, account ownership/logout race safety, private inbox routing,
delivery guarantees, App Check, real biometric authentication, Android release
legal/Data Safety, or release readiness.

Official contracts used: [Messaging API](https://firebase.google.com/docs/reference/android/com/google/firebase/messaging/FirebaseMessaging),
[service API](https://firebase.google.com/docs/reference/android/com/google/firebase/messaging/FirebaseMessagingService),
[Android client setup](https://firebase.google.com/docs/cloud-messaging/android/client),
[receive behavior](https://firebase.google.com/docs/cloud-messaging/android/receive-messages).

## Explicit instrumented phases

`at.uac.pushprobe.ProbeSafetyDeviceTest` uses only this module and actual
UiAutomation controls. API37/qemu guards run before any permission interaction.
No shell grant, app-data reset, send, or fake Firebase result is used.

- `a_noConsentAndActualPermissionDenialNeverInitializeFirebase`:
  `expectFreshPushProbe=true`, genuinely fresh never-opted-in/OS-denied install.
- `b_actualRegisterUiAndOptOutWaitForRealUnregister`: `expectPushProbeCloud=true`,
  initially inactive registration. It never takes over root's active target.
- `c_prepareSingleSend`: `expectPushProbePrepare=true`, initially inactive. On
  successful UI registration it deliberately keeps the single target for root's
  later send; failure attempts cleanup. It does not print the descriptor.
- `d_cleanupSingleSend`: `expectPushProbeCleanup=true` plus exact
  `expectedPushProbeRun` and `expectedPushProbeGeneration` from that descriptor.
  Actual UI opt-out/SDK acknowledgement; pending-cleanup retry is allowed only for
  that same generation. A different or newer run is never stopped by late cleanup.

Use class/method selection for each phase. Missing flags mean skipped, not passed
native proof. Root must finish with confirmed cleanup and descriptor removal.
