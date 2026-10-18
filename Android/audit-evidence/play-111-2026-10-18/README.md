# Android 1.2 (111) — Directory follow-up

## Changes
- Removed DirectoryWelcomeHero from runtime UI, preserving bundled bootstrap/offline catalog and editor access.
- Successful empty banner response has no fallback hero or empty banner item. Published banner carousel remains unchanged. Banner read failure now has localized retry in Directory.
- Recent home preview renders at most three entries. DE “Mehr anzeigen” / UK “Показати більше” opens the existing full feed when loaded count >3 OR server hasMore, without fetching or resetting the feed. Full feed retains pagination.
- Removed empty catalog-status lazy item; deep-link anchor calculation now uses the same conditional status item.

## Verification
- Local APK/instrumentation compilation passed.
- Nine targeted instrumentation tests PASS (49.393 seconds): three new preview/empty/error tests, five recent/deep-link/region tests, one image/banner/profile regression across home/events/organizations/directory.
- Banner regression used a real JPEG in isolated Storage emulator demo-uac-android; fixture deleted in finally. Production-shaped banner placements include directory. Screenshot directory-real-banner.png inspected: image plus short overlay, category heading directly follows carousel, no welcome hero. Its recent-callable failure is expected in this isolated Storage-only test, not production evidence.
- Earlier placement decoder fix shipped in 109/110; hero removal and three-row preview are new in111, not in110.
- No production database writes or backend/rules changes. This is targeted regression, not a renewed claim of all private/provider/physical-device flows.

Delivery and immutable artifact hashes will be recorded after signed build and Play read-back.

## Final build and delivery
- Signed AAB/APK111 source b742a67c050e8cd1c7d76cea3f8b186255045c02, pushed. Signature/package/version checked; production backend, release App Check, Apple and passkeys flags verified.
- AAB SHA256 97d65aab22f5dfbd11091b2d3aa69d974d85f6c27857226c5f4876cc8ad12e79.
- APK SHA256 1f1af609122838248c7de71d4a1332f8a5ddb7f94e392ff9819e7b95bfe6a374.
- Lint0errors/100warnings/4hints. Signed release BUILD SUCCESSFUL2m11s.
- Play Internal release12 AVAILABLE, “Für interne Tester verfügbar”,18Oct09:10. Same selected internal list2, no audience edits.
- Same immutable111 bundle promoted to existing Closed Alpha release3 based on direct user request to deliver beta to common closed testers. One change submitted, Console confirms review workflow with prechecks.111 is NOT yet confirmed available to this group;108 remains available.100% rollout after approval, managed publishing off.
- Play0errors,1native-debug-symbols warning, ReTrace map attached; no supported-device loss.
- No public production release, backend writes, or tester audience changes. Physical device/provider end-to-end validation remains separate.
- Screenshots: play-internal.jpg (available111), play-alpha-review.jpg (submitted111).
- Owned Android emulator and Storage emulator stopped; data preserved.
