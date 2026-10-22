# TestFlight release verification

Before creating or uploading an iOS TestFlight build, run:

```sh
python3 scripts/validate_release_configuration.py --verify-deployed-analytics
```

This read-only check requires the existing gcloud session. It compares consent contracts in the actual deployed analytics handlers with this checkout. A local unit-test pass does not prove that the deployed server accepts the current consent version. Resolve any missing contract and verify the deployed source before uploading. Do not replace this check with an HTTP health check or a source-only comparison.

Keep ordinary CI configuration validation offline; use the explicit flag for release preparation.
