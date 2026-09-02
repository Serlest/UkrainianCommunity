# Firebase App Check rollout

App Check must be introduced in phases. Enabling enforcement before the updated app is in use can reject legitimate Firestore, Storage, Authentication, and callable Function requests.

## Production snapshot — 2026-09-02

- The iOS app `at.serlest.UkrainianCommunity` is registered with both App Attest and DeviceCheck.
- Storage enforcement is active.
- Cloud Firestore and Authentication remain in monitoring mode.
- The controlled physical-device run of build 63 was included in a clean one-hour window:
  - Firestore: 842 of 842 requests verified; no invalid, outdated, or unknown requests.
  - Authentication: 31 of 31 requests verified; no invalid, outdated, or unknown requests.
- The preceding 24-hour and seven-day windows still contained older unverified traffic. A clean one-hour window proves the current test device is configured correctly, but it is not enough evidence to block all other clients.
- Three development debug-token installations are registered. Token values remain outside the repository.
- Callable source currently has 53 `onCall` construction sites: 2 enforced, 50 explicitly monitoring, and 1 controlled by a deployment parameter.

## Implemented in the repository

- Release builds prefer Apple App Attest and fall back to DeviceCheck on devices that do not support App Attest.
- Debug builds and simulators use the Firebase App Check debug provider.
- The App Attest production entitlement is present.
- App Check is configured before `FirebaseApp.configure()`.
- No debug token is stored in source control.
- The analytics callable reads the `ENFORCE_ANALYTICS_APP_CHECK` deployment parameter; its safe default is `false` until this rollout gate is complete.
- Every callable must declare `enforceAppCheck` explicitly. `npm run validate:app-check-policy` and CI reject new implicit defaults.

## Required console setup before deployment

1. In Firebase Console, open **App Check → Apps**.
2. Register the iOS app `at.serlest.UkrainianCommunity` with the App Attest provider.
3. Keep the default one-hour token TTL unless production metrics justify another value.
4. For every developer simulator, copy the token printed by Firebase App Check in the Xcode console and register it under **Manage debug tokens**.
5. If CI later accesses enforced Firebase services, create a dedicated debug token, store it only as an encrypted GitHub Actions secret, and pass it as `AppCheckDebugToken`. Never commit it.

## Safe enforcement sequence

1. Keep Storage enforced and use `writeClientDiagnostic` and `deleteNotificationPushRegistration` as callable canaries.
2. Confirm a release-signed physical-device build can sign in, read and write Firestore, upload media, and call both canaries.
3. Observe at least one complete 24-hour period with no unexplained invalid traffic from supported clients. The project release gate is at least 99.5% verified requests, with every remaining unverified request classified before enforcement.
4. Set `ENFORCE_ANALYTICS_APP_CHECK=true` for a reviewed analytics-only deployment. Verify valid analytics writes and the absence of App Check rejections before expanding callable coverage.
5. Move privileged/owner callables from explicit monitoring to enforcement in one reviewed deployment group at a time. Do not include automation or bridge clients until their App Check path is proven.
6. Enable Firestore enforcement only after the current public/TestFlight client population satisfies the 24-hour gate and rollback access has been verified.
7. Enable Authentication enforcement last because a mistake there can block sign-in and account recovery rather than a single feature.
8. Observe errors and metrics after every stage for at least one normal usage cycle. Do not combine a new enforcement stage with an unrelated Functions, Rules, or release deployment.
9. Do not enable replay protection by default; assess its added latency separately for sensitive endpoints.

## Current hold

Do not enable Firestore or Authentication enforcement from the 2026-09-02 snapshot alone. The current build is valid, but the broader 24-hour client population has not yet passed the gate. This hold is a release-safety decision, not an App Check configuration failure.

## Rollback

If legitimate requests are rejected, disable enforcement for the affected product in Firebase Console. Disabling enforcement does not require an app release. Revoke any exposed debug token immediately.
