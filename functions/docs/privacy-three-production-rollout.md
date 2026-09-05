# Three-function privacy rollout — read-only preparation, 2026-09-05

## Fixed scope and evidence

Only these existing GEN_2 HTTP functions in `ukrainiancommunity-dbd5f`,
`europe-west3`, in this order:

1. `trackAnalyticsEvent` — deploy the reader that accepts .12/.13 receipts FIRST.
2. `updateAnalyticsConsent`.
3. `updateAnalyticsConsentV2`.

No deploy was executed. Coordinator reports shared QA PASS on
`0681aa0540a8557a57f8c49f9f295bc5266784f2`: build/lint, unit 392,
integration 74, Rules 172, npm audit 0. This task did not rerun those checks.

Fresh GET-only snapshot at `2026-09-05T16:21:47.404589+00:00`: 121 functions;
all three targets ACTIVE. Each uses nodejs22, 256Mi, 1 CPU, 60 seconds,
concurrency 80, ALLOW_ALL ingress, allTrafficOnLatestRevision true. Max instances:
track 10, consent 20 each. minInstanceCount is absent (do not replace absence with
a guessed setting). All have ENFORCE_ANALYTICS_APP_CHECK=false, no secret env/volume
bindings, no VPC connector or Cloud Run template VPC access. Automatic runtime
update policy is present. Actual build/service account identities, complete env
maps, config, Cloud Run service and IAM are preserved privately, not copied into
public reports. IAM can contain personal identities.

Existing deployed source archives for all three have the SAME SHA256:
`bf156ec82ab4390b67c74f0602fc743ab31be97f79f4f95ddfe66318e90282c3`.
Their source lock contains uuid 9.0.1. This is a source-lock finding; the installed
image dependency tree was not inspected.

## Concrete candidate, stored privately

Private directory in the server worktree:
`Secrets/privacy-rollout-20260905/` (git-ignored; directory 0700, files 0600).

- `privacy-three-candidate.zip`: SHA256
  `cfe04dc3e3de9b6f7fe4cb0fc420219e059cd85032868745cc503639549d5038`.
- `candidate-manifest.json`: fixed allowlist, order, file hashes, base SHA.
- `*-function.json`, `*-run.json`, `*-function-iam.json`, `*-run-iam.json`:
  full original settings/identities. `all-functions-before.json` includes all 121
  updateTime values; `appcheck-before.json` preserves global App Check settings.
- `*-source-before.zip`: rollback source bytes; these contain historical source
  config and must stay private. Do not move archives or raw metadata to outputs/git.

The ZIP is the current production archive with EXACTLY FIVE entries replaced:
`package.json`, `package-lock.json`, `src/analytics/analyticsConsent.ts`,
`lib/analytics/analyticsConsent.js`, `lib/analytics/analyticsConsent.js.map`.
The first three match Git 0681aa0; compiled files were read from the coordinator's
verified worktree without compilation. Other 104 archive entries are byte-identical.
No added entries. Both existing source and compiled index are preserved. The old
`lib/analytics/trackAnalyticsEvent.js` is byte-identical to verified code: it imports
the changed consent compatibility helper, so its FUNCTION still needs redeploy.

This avoids uploading the full current index and added runtime modules (including
Android) into the privacy package. Package diffs are ONLY the scoped uuid override
and lock node. Firebase versions remain unchanged. This assembled narrow ZIP has
NOT itself been built/tested; shared QA validates its changed source/dependency
inputs, not a new complete artifact build. Coordinator must explicitly resolve
this artifact-composition gate before execution. No additional testing is performed
or implicitly authorized by this document.

## Preservation strategy for the coordinator's later execution

Use the Cloud Functions v2 **source-only PATCH** with exact update mask
`buildConfig.source`. Never omit updateMask, never pass `serviceConfig`, runtime,
entryPoint, env maps, secrets, VPC, labels, build account, IAM or eventTrigger in
the patch. Do not synthesize defaults from source callable options. This leaves
existing resource configuration outside the write scope. The provider still
creates build/revision IDs and may refresh the base runtime under its already
configured automatic update policy; read-back remains mandatory.

Request shape (review template, not an executed request):

```json
{
  "name": "projects/ukrainiancommunity-dbd5f/locations/europe-west3/functions/ALLOWLIST_NAME",
  "buildConfig": {
    "source": {
      "storageSource": {
        "bucket": "GENERATED_UPLOAD_BUCKET",
        "object": "GENERATED_UPLOAD_OBJECT",
        "generation": "GENERATED_UPLOAD_GENERATION"
      }
    }
  }
}
```

Endpoint: `PATCH https://cloudfunctions.googleapis.com/v2/{name}?updateMask=buildConfig.source`.
These placeholders must come from the future upload response, never guessed.

Execution checklist for a separately authorized coordinator:

1. Freeze other deploys; rerun the GET-only snapshot helper into a NEW private
   directory. Require target updateTime/settings/source identity equal to this
   baseline, fixed allowlist present, current state ACTIVE. Abort on drift rather
   than overwrite another deployment. v2 Function exposes no documented conditional
   updateTime precondition for this PATCH; the pre-read is not an atomic lock.
2. Confirm the candidate SHA and five-entry diff, source/App Check settings and
   closure above; resolve the narrow artifact QA gate. Preserve a recoverable copy
   of all before sources/configuration. Do not run old deploy/verify scripts.
3. Only then generate an upload URL, upload the exact private ZIP (do not log the
   signed URL), and obtain the storageSource identity per the official API.
   Upload/build/PATCH are future external mutations, absent from this preparation.
4. PATCH one function at a time in the fixed order above, only source. Wait for
   its operation completion; a timeout means uncertain status, not permission to
   retry blindly. Read the operation/function until reconciled before proceeding.
5. Read back each ACTIVE function and resolved source archive. Verify candidate
   entry checksums and source identity (provider archive wrapping may differ).
   Verify nodejs22/entrypoint unchanged, all non-source BUILD settings equal,
   build/service accounts equal, env maps equal, secret bindings equal, VPC equal,
   resources/scaling/concurrency/ingress/traffic policy unchanged. Only provider
   output build/sourceProvenance/revision IDs and times are expected to change.
6. Compare Cloud Run effective template settings, IAM bindings/conditions, App
   Check service modes and code option semantics. Treat unexpected provider-managed
   annotation changes as reviewable diffs, not a blanket ignore. No IAM rewriting,
   scheduler pause, Rules deploy, global App Check or MFA change is part of this.
7. Require the other 118 functions' updateTime/source identities unchanged. No
   new functions or schedulers. Record exact source proof separately from future
   callable/runtime canary proof. Publish/activate .13 notice or client only after
   all three are confirmed. Privacy document/site publication is a separate plan.

## Failure / rollback boundary

If the consumer fails to deploy, stop before either producer. If a producer fails,
keep the upgraded compatible consumer and stop publication; .12 remains supported.
Do not blindly roll `trackAnalyticsEvent` back to the old .12-only helper once ANY
.13 receipts may have been written: new producers can default to .13 even before
notice publication. Keep the compatible consumer or make a forward repair. Reverting
producer source can also reject explicit .13 requests; assess issued clients first.
Do not delete/alter historical receipts to make rollback convenient. The archived
old source is an available artifact, not an automatically safe data rollback.

## Search/dependency scope — deliberately NOT added to this allowlist

The memory repair needs a separate rollout of `searchManagedUsers` AND
`listLegalEvidenceAccounts`. Redeploying the three privacy functions does not
change those endpoint revisions, even if a package contains their code. Their
bounded-memory fallback must remain `incomplete`; no migration/ready flag/Rules
change is required or authorized. Reads stay O(N). Neither presence endpoint is
needed. Search needs its own current-source/settings closure review and package;
this privacy ZIP intentionally does not contain its new helper.

The uuid patch reaches ONLY rebuilt revisions. The three-function rollout patches
those three source locks; it cannot establish a fleet-wide zero-warning result.
A later search rollout can patch those two as well. To claim all production uuid
warnings removed, inventory each remaining revision's lock/image dependencies and
redeploy each affected existing function separately under approved allowlists.
There are 118 other function resources after this scope, not 118 proven vulnerable
call paths; their source archives were not downloaded by this task. Do NOT expand
to `--only functions`, all exports, Android push functions, Rules or scheduler jobs.
Shared local npm audit 0 is not a deployed-fleet audit.

## Read-only helper and official API references

`functions/scripts/preparePrivacyProductionRollout.py` has a fixed three-function
allowlist, accepts only account/private output location, requests cloud resources
with GET only and has no apply mode. It reads source ZIPs without extracting or
executing their contents. Tokens remain in memory; raw records stay under Secrets.
It was executed once for the snapshot above, not as a runtime test.

The old `production-release/deploy-functions.py` targets 23 exports with Firebase
CLI and cannot be reused here. The old `verify-deployment.py` contains a scheduler
`:pause` POST; despite its name it is not read-only. `control.py` was inspected but
not imported/executed or copied with its hardcoded personal account.

- [v2 PATCH and updateMask](https://docs.cloud.google.com/functions/docs/reference/rest/v2/projects.locations.functions/patch)
- [Function build/service configuration](https://docs.cloud.google.com/functions/docs/reference/rest/v2/projects.locations.functions)
- [Future source upload API](https://docs.cloud.google.com/functions/docs/reference/rest/v2/projects.locations.functions/generateUploadUrl)
