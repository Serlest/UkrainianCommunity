# Analytics App Check release gate

`trackAnalyticsEvent` declares the boolean Firebase parameter
`ENFORCE_ANALYTICS_APP_CHECK`. Its default is intentionally `false`, so this
change cannot lock existing production clients out during deployment.

Set the parameter to `true` only after all of the following are verified:

1. The production iOS bundle is registered for App Check and the App Attest
   provider is enabled in the Firebase console.
2. DeviceCheck fallback works on devices where App Attest is unavailable.
3. Debug tokens are registered for local development and CI; no debug provider
   is compiled into Release builds.
4. App Check request metrics show that the currently supported production app
   versions send valid tokens to `trackAnalyticsEvent`.
5. A staged/TestFlight deployment succeeds with enforcement enabled before the
   production parameter is changed.

After the gate passes, deploy with `ENFORCE_ANALYTICS_APP_CHECK=true`, verify the
callable error rate, and record the console/configuration evidence in the release
checklist. Roll back the parameter—not the analytics data schema—if older supported
clients are unexpectedly rejected.
