# Android current working checkpoint

Updated: 2026-09-11, Europe/Vienna.

## Canonical Android baseline

- Product version: `1.1 (86)`.
- Package: `at.serlest.ukrainiancommunity`.
- Working tree: `/Users/serlest/Developer/UAC-Android-1.1-Build86`.
- Working branch: `codex/android-current-1.1-86`.
- Exact source commit used for the Google Play artifact: `cda63d6e03b95bacbff405c5539f7fd8acc75989`.
- Immutable local tag for that source: `android-1.1-build86-play-internal`.
- Signed AAB SHA-256: `61ef0c7b1428fca9210a91c96f9a6f2a04bd88a098042460af5b2e5ac110ca6a`.
- Release receipt: `/Users/serlest/Documents/Codex/2026-09-09/82-82/artifacts/android-build86/build86-play-internal-receipt.json`.
- AAB: `/Users/serlest/Documents/Codex/2026-09-09/82-82/artifacts/android-build86/release/UAC-1.1-86.aab`.

The AAB hash was recalculated on 2026-09-11 and matches the release receipt. Google Play read-back recorded this artifact as active in Internal testing. This is not a public-production release.

## Relationship to the current branch

The working branch contains the exact Build 86 Android source plus later release/legal documentation through commit `75558c1a7dc88c6b2739436a3c7fa2c96836cb69`. A path-scoped comparison from `cda63d6` through `75558c1` found no changes under `Android/`, so the Android product source still matches the uploaded Build 86 artifact.

All new Android UI or functional work must start in this working tree and branch unless a newer Google Play receipt explicitly supersedes this checkpoint. Do not use the legacy Build 80 working tree or `codex/android-build80-visual-20260909` as the current baseline.

## Evidence boundaries

- Confirmed: source commit, version metadata, locally retained AAB hash, and saved Google Play Internal read-back receipt.
- Not confirmed by this checkpoint: installation on the user's physical phone, live production-functional parity, or public rollout.
