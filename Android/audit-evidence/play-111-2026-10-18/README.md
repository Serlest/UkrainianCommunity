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
