# Scoped Hosting plan — privacy 2026.13

Prepared for the coordinator. No Hosting version, upload or release was created
in this task. Production access was GET-only. Ten offline fake-transport tests
passed; the default live dry-run passed. These results do not prove write
permission, successful upload, finalization or publication.

## Exact scope and live baseline

- Fixed site: `ukrainiancommunity-dbd5f`, live channel.
- Source release: `1788368004857000`, released 2026-09-02T16:53:24.857Z.
- Source version: `sites/ukrainiancommunity-dbd5f/versions/6b5136dd545373fa`.
- Complete source inventory: 15 ACTIVE files, including `/__/firebase/init.js`
  and `/__/firebase/init.json`. All 14 files other than `/privacy/index.html`
  retain their exact Hosting hashes. The script never reads local substitutes
  for those files and never performs a whole-site Firebase CLI deployment.
- Copy the entire current version `config` exactly: security/cache headers, DSA
  Cloud Run rewrite, cleanUrls and trailing slash behavior remain unchanged.
- Only changed file: `/privacy/index.html`. Its old Hosting hash is
  `4dce3552dcfeb6967fe87e9c4bcdd99a6237a205949e3d2134cc71e79e5d69ea`.
- New raw HTML SHA-256:
  `014f47ba8e18df18135fffeb27c27df93553fcb84785ce7719dc908b178e803d`.
- New Hosting gzip SHA-256 from the dry-run runtime:
  `b7f1d251b2a9199c329ad24447b4b8c9a9f5bb47d497d209aca963726bcad42e`.
  The exact deterministic gzip bytes are hashed and then uploaded. If a different
  Python/zlib runtime produces different compression, create/review a fresh plan.

The saved plan contains complete `beforeFiles`, `afterFiles`, live `config`,
release identity, old public HTML hash and local input fingerprints. No access
tokens, account identities or API user objects are stored or printed. A read-only
snapshot from this task is in the coordinator's
`status/privacy-hosting-dry-run.json`; generate a fresh plan from the integrated
checkout before applying.

## Commands and guards

Run these commands from the integrated checkout. The sibling Firestore publisher
module is required for the canonical source/bundle/website checks. No packages
need installing. The same external `control.py` authentication helper is used;
`--control PATH` can relocate it, but its project must match the fixed site.

Default command performs GET requests only and saves a new plan:

```sh
python3 scripts/publish_privacy_hosting_2026_13.py --plan work/privacy-hosting-plan.json
```

Review the one-path delta, the source content and the full unchanged config/map.
Before any writes, the coordinator must finish common verification, coordinate
Firestore policy/consent compatibility, and reserve a window with **no other
Hosting deployer** (including CI). No deployment lock is acquired by the script.

Only the coordinator should run this explicit write command:

```sh
python3 scripts/publish_privacy_hosting_2026_13.py --apply --plan work/privacy-hosting-plan.json --state work/privacy-hosting-state.json
```

`--apply` recomputes the whole dry-run plan and requires equality before creating
anything. It also checks today's Vienna effective date. Existing state files are
never reused: the journal is reserved before the first write and records intent
before each API mutation, so an interrupted attempt cannot silently restart.

The future apply path is:

1. Recheck release ID/version/time, every baseline file hash, public 2026.12 HTML,
   and local canonical sources/bundle/generated HTML/date against the plan.
2. Create one new Hosting version using the exact live config. The new version's
   tool label identifies this publisher, without rewriting the old version.
3. Populate the **complete** existing filemap with one hash replacement, in
   batches of at most 1,000 paths. If Hosting requests an upload for any hash other
   than the selected gzip payload, stop; never upload unrelated local assets.
4. Upload only those selected gzip bytes if the API requests them. Validate the
   returned upload target against the fixed site and newly created version.
5. Finalize the candidate, then read back its entire config and ACTIVE filemap.
   They must exactly match the plan before a release is attempted.
6. Read the current release again, compare with the original, then release the
   new version once. There are no automatic retries of writes.
7. Read back the active version/config/full filemap and fetch public `/privacy`
   with a cache-busting query. Require the raw HTML hash and both DE/UK 2026.13
   markers. Exact HTML equality to the source-generated page covers both locale
   bodies. Read the release once more to detect changes during verification.

**Concurrency limitation:** Hosting `releases.create` exposes no ETag or expected
current-release parameter. The before-release check is not atomic CAS. A deploy
between the final GET and POST remains possible; an exclusive deploy window is
therefore required. If another deployment is observed, stop. The script will not
roll back someone else's subsequent release automatically.

## Uncertain response and rollback

Keep plan and state files together. If creation/population/upload/finalization is
unconfirmed, inspect the saved phase and any candidateVersion. A candidate version
may exist without being live. Do not repeat `--apply` with a fresh state to hide
an uncertain attempt. This script intentionally has no automatic resume/cleanup.

After a release attempt, use read-only verification with the same files:

```sh
python3 scripts/publish_privacy_hosting_2026_13.py --verify --plan work/privacy-hosting-plan.json --state work/privacy-hosting-state.json
```

It creates no remote objects. It may update the local journal with a verified
release identity. A cache mismatch leaves publication unconfirmed; a later
read-only verification can resolve propagation, without repeating a release.

Rollback is a separate explicit coordinator action. It requires this exact
verified new release to remain live and checks that the original version still
has the original config/filemap. It creates a new release referencing the old
version: it does not rebuild, delete or modify either version and uploads nothing.

```sh
python3 scripts/publish_privacy_hosting_2026_13.py --rollback --plan work/privacy-hosting-plan.json --state work/privacy-hosting-state.json
```

After an uncertain rollback response, do not issue another rollback; read back:

```sh
python3 scripts/publish_privacy_hosting_2026_13.py --verify-rollback --plan work/privacy-hosting-plan.json --state work/privacy-hosting-state.json
```

The same non-atomic release API limitation applies to rollback. Read-back checks
original config/filemap, old public HTML hash and bilingual 2026.12 markers. This
rolls back Hosting only: Firestore active privacy and deployed consent Functions
are not reverted. A mixed policy state must keep release gates closed until the
coordinator reconciles it. Prior immutable Firestore versions must never be edited.

## Offline validation and API references

```sh
python3 -m unittest discover -s scripts -p test_publish_privacy_hosting_2026_13.py -v
```

10/10 passed: default CLI sends no mutations, only one file is uploaded, full map
and config retained, guard before creation and before release, unrelated requested
upload rejected, repeated state refused, lost release response recovered read-only,
wrong HTML rejected, original-version rollback, and refusal to override a later
release. All write paths were tested only against an in-memory fake, without
ports, credentials or production operations.

Primary references used to prepare the request shapes:
- [Hosting REST deployment workflow](https://firebase.google.com/docs/hosting/api-deploy):
  full filemap, hash of gzip bytes, raw compressed upload, finalize then release.
- [Version files inventory](https://firebase.google.com/docs/reference/hosting/rest/v1beta1/sites.versions.files/list):
  ACTIVE status and pagination.
- [populateFiles](https://firebase.google.com/docs/reference/hosting/rest/v1beta1/sites.versions/populateFiles):
  required upload hashes and version-scoped upload URL.
- [Create a release](https://firebase.google.com/docs/reference/hosting/rest/v1beta1/sites.releases/create):
  versionName query parameter, channel parent and absence of a CAS parameter.

## GET-only diagnostic helper after finalize-intent interruption

The coordinator's attempt for candidate
`sites/ukrainiancommunity-dbd5f/versions/289d3fbeb1ea99d4` stopped with a generic
exception while its journal still said `finalize-intent`. That phase covers the
PATCH response and subsequent inventory/baseline reads until release-intent; it
alone does not identify the failing operation or prove finalize failed.

On subsequent GET-only inspection, candidate status was FINALIZED, fileCount 15,
all ACTIVE file hashes and config matched the reviewed plan, and the original
version inventory was unchanged. At the helper's live-release read, the baseline
was still live. This is a point-in-time diagnosis, not the coordinator's later
release result. No original traceback was saved, so the original cause remains
unconfirmed (a transport/JSON/schema error cannot be distinguished retrospectively).
Do not attribute it to any one of those possibilities without evidence.

Use the new helper on any existing state, without repeating apply or finalize:

```sh
python3 scripts/diagnose_privacy_hosting_2026_13.py --plan PATH_TO_ORIGINAL_PLAN --state PATH_TO_ORIGINAL_STATE
```

It issues only GET requests. Its transport rejects every other method and any
upload before reaching the network. It does not update the local journal. It
reports candidate metadata, exact candidate-map comparison, baseline preservation,
current release identity and public HTML hash. Independent reads continue when
one stage fails, with a separate error entry per stage.

Error output contains exception class, allowlisted missing schema key, HTTP
status, JSON line/column or OS errno where applicable, plus file/line/function
locations. Raw exception messages, response text, account objects, credentials
and local variables are never printed. Four offline safety tests passed. This
improves future diagnosis; it does not recover the suppressed original exception.
Only the coordinator may decide how to release the already finalized candidate.
