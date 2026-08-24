# Firebase App Check rollout

App Check must be introduced in phases. Enabling enforcement before the updated app is in use can reject legitimate Firestore, Storage, Authentication, and callable Function requests.

## Implemented in the repository

- Release builds prefer Apple App Attest and fall back to DeviceCheck on devices that do not support App Attest.
- Debug builds and simulators use the Firebase App Check debug provider.
- The App Attest production entitlement is present.
- App Check is configured before `FirebaseApp.configure()`.
- No debug token is stored in source control.
- The analytics callable reads the `ENFORCE_ANALYTICS_APP_CHECK` deployment parameter; its safe default is `false` until this rollout gate is complete.

## Required console setup before deployment

1. In Firebase Console, open **App Check → Apps**.
2. Register the iOS app `at.serlest.UkrainianCommunity` with the App Attest provider.
3. Keep the default one-hour token TTL unless production metrics justify another value.
4. For every developer simulator, copy the token printed by Firebase App Check in the Xcode console and register it under **Manage debug tokens**.
5. If CI later accesses enforced Firebase services, create a dedicated debug token, store it only as an encrypted GitHub Actions secret, and pass it as `AppCheckDebugToken`. Never commit it.

## Safe enforcement sequence

1. Deploy the updated app without enforcement.
2. Confirm App Check metrics show valid requests from production users for Firestore, Storage, Authentication, and Cloud Functions.
3. Investigate unexpected unverified traffic before blocking it.
4. Enable enforcement one service at a time, beginning with a low-risk service.
5. Observe errors and metrics after each service for at least one normal usage cycle.
6. Set `ENFORCE_ANALYTICS_APP_CHECK=true` for the reviewed deployment and verify the analytics callable after active clients send valid tokens.
7. Do not enable replay protection by default; assess its added latency separately for sensitive endpoints.

## Rollback

If legitimate requests are rejected, disable enforcement for the affected product in Firebase Console. Disabling enforcement does not require an app release. Revoke any exposed debug token immediately.
