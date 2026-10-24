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

# Application audit acceptance

Follow [the audit method](Docs/AppAuditMethod.md) for the 19-block UAC review. Inventory nested routes, presentations and role-dependent variants before declaring a block covered. Verify transitions and intermediate loading frames, input/keyboard behavior, persistence after return, and actual visuals; test counts and opening a destination alone do not prove completeness. Separate simulator fixtures, production readback, device verification and TestFlight delivery in reports.

The user explicitly authorized block 7 on 2026-10-24. Preserve the distinction between this authorization and physical-device acceptance of individual fixes. Continue one audit block at a time.

Before a TestFlight delivery, inspect the required GitHub run for the source revision as well as local results. Investigate known failures; report a running hosted validation as pending, never as passed. Preserve assertions and production security/read deadlines when fixing CI scheduling.
