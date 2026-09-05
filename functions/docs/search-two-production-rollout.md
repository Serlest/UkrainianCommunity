# Two-function search rollout — read-only preparation, 2026-09-05

## Fixed scope

Only `searchManagedUsers` and `listLegalEvidenceAccounts`, existing GEN_2 HTTP
functions in `ukrainiancommunity-dbd5f` / `europe-west3`. No new exports/endpoints,
Android, presence, scheduler, Rules, migrations or index activation. Each function
has its OWN source ZIP; do not reuse one function's archive for the other.

Both candidates use the verified server inputs from
`0681aa0540a8557a57f8c49f9f295bc5266784f2`. QA results were provided by the
coordinator; this task did not run tests, builds, dependency installation or audit.
These assembled ZIPs still require the coordinator's scoped composition review
and any required validation. Do not deploy until the coordinator's UI/SDK gates
and artifact review are satisfied. This document does not perform deployment.

## Actual production snapshot

GET-only snapshot `2026-09-05T16:36:07.332343+00:00`, 121 functions. Both targets
ACTIVE, nodejs22, 256Mi, 1 CPU, 60 seconds, concurrency 80, maxInstances 10,
ALLOW_ALL ingress, latest revision traffic enabled. minInstanceCount absent.
Both have zero Secret Manager bindings/volumes, no VPC connector, and
ENFORCE_ANALYTICS_APP_CHECK=false. Full service/build accounts, env, IAM and Cloud
Run settings are private; public evidence contains hashes/counts only.

Private artifacts (0700 directory / 0600 files; git-ignored):
`Secrets/search-rollout-20260905/` in the server worktree.

| Target | Candidate ZIP SHA256 | Changes to its own production archive |
|---|---|---|
| searchManagedUsers | `99fa7355b9c55a65899387eec545d083619835e46fdc906a26da174de4153b5c` | 11 replaced entries, 3 added helper entries, 241 byte-identical entries |
| listLegalEvidenceAccounts | `47e8e5161b264c6001ac965e259ea8cd9e42e6152b4c0051a8b05c9aeb957452` | 5 replaced entries, 3 added helper entries, 104 byte-identical entries |

ZIP names: `<function>-candidate.zip`. Before sources/settings/IAM are named
`<function>-source-before.zip`, `*-function.json`, `*-run.json`, `*-function-iam.json`,
`*-run-iam.json`. `candidate-manifest.json` records all changed-file hashes and
per-function base ZIP hashes. `all-functions-before.json` and
`appcheck-before.json` capture unrelated resources and product App Check modes.
No raw metadata/archives may be copied into outputs/git; historical source archives
can contain dotenv configuration. Tokens are never written or printed.

## Important live-to-verified drift: review explicitly

`listLegalEvidenceAccounts` is already on the current legacy-owner security
contract. Its only runtime change is the complete streaming/top-K search and the
new helper. Browse/cursors and owner/verified/active checks are preserved. No new
MFA requirement is added to this legacy endpoint.

**searchManagedUsers is older in production than the tested checkpoint.** Its
live search uses NFKC and a single substring within any one field. The verified
candidate uses NFKD/diacritic removal/punctuation splitting and AND tokens across
the combined searchable fields. This is an existing tested checkpoint change in
addition to bounded memory; it is NOT identical to current production semantics.
For example `muller wien` can now match a display name Müller and city Wien across
fields. Punctuation/diacritic normalization can also change rejected queries.

Its deployed `auth/context` and `userPermissions` also predate conditional MFA.
The candidate includes BOTH verified modules (source/compiled/map) so the handler
actually honors `requiresMultiFactorAuth === true` for owner/admin and requires
a TOTP-authenticated token. Leaving the old helper in place would silently omit
the tested MFA gate. This strengthens the actual live search endpoint and may
reject an existing privileged session until its TOTP sign-in is complete. It does
not mutate account flags, MFA enrollment, session settings, or any other deployed
endpoint. No real-user/profile reads were used to infer which accounts are affected.

Coordinator must explicitly review this live-to-checkpoint behavior difference
and corresponding auth/composition evidence before deploying management search.
Do not describe it as an auth-neutral memory-only deployment. Source-only settings
preservation protects resource config, not application behavior. The candidate
keeps the approved code/security contract; no special bypass was invented.

## Exact source composition and dependency delta

For each module listed below, `.ts`, `.js` and `.js.map` come from the verified
worktree. Source bytes were compared with Git 0681aa0, compiled bytes were copied
without executing them. Existing source/compiled indexes are byte-identical to
each respective production archive. No Android module is added or changed.

- Management: replace `users/userManagementQueries`, `auth/context`,
  `permissions/userPermissions`; add `users/adminUserSearch`.
- Legal: replace `legal/legalEvidence`; add `users/adminUserSearch`.
- Both: package.json retains its respective production scripts, engines and
  dependency declarations; ONLY the tested scoped uuid overrides are added.
  package-lock.json is the full verified lock, with unchanged Firebase SDK versions.
- Legal lock differs only in uuid 9.0.1 → 11.1.1.
- Management's older lock additionally advances two nested gaxios entries
  7.1.5 → 7.3.1 and qs 6.15.3 → 6.16.0, besides uuid. These are already in the
  tested lock, not newly resolved versions. No added/removed dependency nodes.
  This older-source delta must be included in the scoped composition assessment.

Index readiness is always `incomplete` at both production call sites. No env or
request parameter can set it ready. Full counts and late matches are retained;
only response-sized results remain in memory. Reads stay **O(N)**. This package
contains no index migration and performs no index writes. The dormant ready path
must not be enabled by the rollout operator.

## Later source-only execution / preservation contract

Use a separate operation for each target, serially, after coordinator gates.
Recommended order: legal first (smaller live delta), then management after its
explicit security/normalization review. Neither depends on the other or changes
the separately planned privacy revisions.

1. Immediately before this scope, obtain a fresh GET-only snapshot into a NEW
   private directory using `prepareSearchProductionRollout.py`. Match target
   updateTime/source/settings to the packaged baseline; abort/review on drift.
   If privacy has deployed since the snapshot, refresh unrelated-function baseline
   rather than treating those expected prior changes as part of search rollout.
2. Freeze competing deployments. Check the correct per-target ZIP checksum and
   before-source identity, retain private rollback archives. The API has no
   documented atomic updateTime precondition for the following patch; a pre-read
   alone is not an atomic deployment lock.
3. For each target generate/upload its specific candidate ZIP only after external
   execution authorization. Never log signed URLs or tokens. Do not run generic
   Firebase `--only functions` or regenerate the index from all repository exports.
4. PATCH only `buildConfig.source` via Cloud Functions v2 with exact
   `updateMask=buildConfig.source`. Body contains only `name` and
   `buildConfig.source.storageSource` from that uploaded archive. Do NOT send
   serviceConfig, runtime, entryPoint, env, secrets, accounts, VPC, labels, IAM or
   eventTrigger. Never omit updateMask. See privacy-three-production-rollout.md
   for the same request template and official API references.
5. Wait for operation completion, then ACTIVE/read-back before next target.
   Reconcile an uncertain operation instead of blind retry. Compare downloaded
   resolved source entries with the candidate manifest (archive wrapper may vary).
6. Require runtime/entryPoint, non-source build settings/build account, complete
   environment maps, service account, secrets, VPC, resources, scaling, ingress,
   concurrency, traffic settings, IAM bindings/conditions and App Check unchanged.
   Provider sourceProvenance/build/revision identifiers/times naturally change;
   automatic runtime policy can refresh provider base patches, not the nodejs22
   major selection. Review other diffs explicitly, including Cloud Run settings.
7. Compare the other 119 function updateTime/source identities against the freshly
   captured immediate search baseline. No new endpoint, schedule, IAM/Rules/App
   Check mutation. Preserve raw evidence privately, publish only sanitized hashes.

Old production-release/deploy-functions.py is a 23-function CLI scope, and its
verify-deployment.py can POST scheduler pause; neither is suitable here.

## Rollback and result claims

No data/index writes occur in this package, so each old source archive is available
for a per-function source rollback. Reverting management also reverts its newer
normalization and conditional MFA check, and reverting either loses bounded memory
and its dependency updates. Do not silently weaken auth during incident handling;
review a forward repair or deliberate rollback with the coordinator.

After source/config read-back, claim only these two deployed revisions updated.
Functional production canary proof remains separate. Even if privacy's three have
also deployed, only five selected revisions received these locks; no fleet-wide
redeploy/audit claim. Worst-case read cost remains O(N).

`prepareSearchProductionRollout.py` is GET-only with an immutable-in-source pair
allowlist and no apply mode. It was executed once for metadata/source preparation.
No callable invocation, runtime test, build, deploy or migration occurred here.
