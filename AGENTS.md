# TestFlight release verification

Before creating or uploading an iOS TestFlight build, run:

```sh
python3 scripts/validate_release_configuration.py --verify-deployed-analytics
```

This read-only check requires the existing gcloud session. It compares consent contracts in the actual deployed analytics handlers with this checkout. A local unit-test pass does not prove that the deployed server accepts the current consent version. Resolve any missing contract and verify the deployed source before uploading. Do not replace this check with an HTTP health check or a source-only comparison.

Keep ordinary CI configuration validation offline; use the explicit flag for release preparation.

# Cloud Functions runtime verification

The 2026-10-23 runtime incident was isolated to automatic base-image composition. Production functions use `buildConfig.onDeployUpdatePolicy`; patches are received on deployment. Preserve that policy until an isolated automatic-update canary has passed an actual cold start. New functions must explicitly use the same policy. See [runtime recovery](Docs/CloudFunctionsRuntimeRecovery.md).

After server deployment, verify Cloud Run readiness and 100% traffic on the intended revision, actual callable responses, and Eventarc triggers. Cloud Functions `ACTIVE` alone is insufficient. Do not replace a source verification with an unauthenticated health probe.
