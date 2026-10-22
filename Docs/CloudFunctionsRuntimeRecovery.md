# Cloud Functions runtime recovery — 2026-10-23

## Isolated failure

The production incident began on October 22 around 21:18 UTC, before the journal deployment. Existing Node.js 22 functions returned platform HTML 500 because instances could not start. Rebuilding the application with automatic runtime updates did not recover it.

Controlled, private probes in `europe-west3` used a temporary service account with no application data roles:

- Google's ordinary hello container started.
- The application image combined through automatic base-image updates reproduced the internal health-check failure.
- The same function source built with `--runtime-update-policy on-deploy` started in 5.61 seconds and returned the expected application JSON 401 for an unauthenticated request.
- Production banner measurement also returned its normal JSON 401 after routing traffic to the verified replacement revision. Real news/event counter deliveries subsequently returned 204.

This isolates the failing runtime assembly path; it does not identify Google's internal implementation defect. The missing `heapsize.sh` error from running a scratch application image *without* its required runtime is a separate, invalid configuration, not the production root-cause evidence.

## Recovery method

`on-deploy` packages the runtime into the deployment rather than composing it automatically at instance startup. Existing service accounts, environment variables, memory/concurrency limits, Eventarc filters/retry settings and scheduler targets must be preserved. Route all traffic to the verified revision; a previous explicit traffic pin otherwise continues serving the old image even when deployment reports success.

The Cloud Functions API's operation `metadata.sourceToken` allows sibling functions using identical source and runtime policy to reuse the successfully built image. It is not necessary to rebuild the same application separately for every export. Keep opaque tokens and deployment operation responses out of committed documentation.

Existing Firebase CLI updates preserve `onDeployUpdatePolicy` when it is omitted from their field mask. A subsequent Firebase deployment of the final journal source was used to verify that behavior. New functions default to automatic updates, so create them with an explicit `on-deploy` policy. A function whose first deployment failed may have neither service configuration nor Eventarc trigger; reconstruct both from its declared source options and verify invocation IAM.

## Required read-back

1. Cloud Functions state ACTIVE and `buildConfig.onDeployUpdatePolicy` present.
2. Cloud Run Ready=True; intended replacement revision receives 100% traffic and its container health check succeeds.
3. A protected callable returns application JSON 401 on a request without credentials, rather than platform HTML 500/403. This proves startup and routing, not authenticated business behavior.
4. Eventarc destination/filter/retry and invoker identity match the intended handler. Confirm genuine delivery success where available.
5. Compare the deployed source archive with local compiled handlers, then verify any derived-index migration.
6. Inspect new failures after the last recovery operation, rather than accepting alert auto-resolution as proof.

Security/runtime patches are now applied during deployments. Do not leave the deployment process idle indefinitely. Re-enable automatic updates only after an isolated canary using the real application source passes cold-start and application-response checks. Do not add paid minimum instances to mask this failure.

Private probe services, function and service account were removed after diagnosis. No Google support request was sent. Evidence is retained locally in `build/cloud-startup-investigation-20261022/`.

Official references: [runtime update policy API](https://docs.cloud.google.com/functions/docs/reference/rest/v2/projects.locations.functions#BuildConfig), [gcloud function deployment](https://docs.cloud.google.com/sdk/gcloud/reference/functions/deploy).
