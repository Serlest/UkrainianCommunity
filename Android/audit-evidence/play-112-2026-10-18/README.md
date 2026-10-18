# Android 1.2 (112) — compact Directory recent preview

## Scope
- Existing UacCard surface, colors and rounded corners; a single card containing three compact title-only rows, separators and chevrons.
- Titles use maxLines1 and ellipsis. Merged accessibility semantics retain the complete text (verified), without a duplicated content description.
- Minimum48dp row and Show More targets; minimum height only, no fixed maximum height. No metadata, description or refresh in the home preview. Full feed keeps existing metadata and pagination.
- Show More retains loaded-count/hasMore logic introduced111. No placeholder banner restored.

## Targeted verification
- Four targeted UI tests PASS,13.823seconds. Compact preview testedUK/DE xlight/dark, one-line actual text layout/ellipsis/full semantics,48dp targets, real bundled article reader/back, full feed fourth item/article/back, one source fetch across round trip, plus111 pagination/empty/banner-error regression.
- Screenshots compact112-{uk,de}-{light,dark}.png are isolated UI harness with fixture titles. Back button at top is test-only navigation; not a new product button.
- Real reader source remains bundled in this local test; no production database writes.
- No full audit rerun;111 banner regression remains applicable since banner code is unchanged.

Visual review is required before signed archive/upload; delivery receipts to follow.

## Final outcome
- Root reviewed and accepted all four screenshots before signing. No additional large-font/small-width run claimed.
- Signed112 source2f3a19dbaad44e39e944e9c706a14ee63ad84866 pushed. Release build SUCCESS2m; package/signature/version/production flags verified.
- Internal release13 AVAILABLE: “Für interne Tester verfügbar”,18Oct09:29 Europe/Vienna.
- Existing Closed Alpha release4 submitted, exact track status “Wird überprüft.”111 now “Durch einen anderen Release ersetzt”. Google confirmation required restarting111review to submit112; done as necessary for latest requested build.108 remains “Für ausgewählte Tester verfügbar”.112 not yet available to the common closed group.
- Managed publishing OFF;100% closed rollout after approval. No audience edits, public production changes or production database writes.
- Play0errors,1native-debug-symbols warning; ReTrace mapping attached, zero supported-device loss.
- Immutable AAB/APK hashes and build flags in build-receipt.json; exact status in delivery-receipt.json; Console screenshots attached.
- Owned emulator stopped with data preserved.
