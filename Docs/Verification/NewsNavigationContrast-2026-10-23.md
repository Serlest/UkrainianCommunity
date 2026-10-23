# News and navigation contrast — 2026-10-23

## Cause and changes

- The selected tab inherited a fixed dark-blue fill token as its foreground, including in dark appearance. Inactive tab foregrounds depended on system translucency/vibrancy. Configure opaque dynamic foregrounds for all native tab layouts and both standard/scroll-edge appearances; give the selected indicator a contrasting blue surface.
- Keep the native system glass/blur background and accessibility behavior. Keep the bar background visible at the scroll edge; do not add a second custom blur. Scope tab appearance to the actual controller rather than a global appearance proxy or global control tint.
- SwiftUI reapplies its own selected-tab tint on navigation. Set the TabView tint explicitly, retain the original tint inside each root screen, and use ice-blue dark-mode selection text to cover the system's lighter selected-glass pill (including a 45% gray material in the contrast test).
- Compact news metadata used translucent secondary text at caption2 size. Use opaque adaptive metadata colors, caption size, and an opaque news-card surface in the existing palette.
- Unselected filter chips applied additional opacity to already-translucent secondary labels. Use primary text for unselected chips while retaining selected white-on-blue styling.
- Use primary text for the news filter summary displayed directly on the grouped background.

## Verification

Local evidence: `build/news-contrast-20261023/` (ignored).

- Contrast tests cover metadata/card opacity, selected/unselected navigation colors against material extremes, selected indicator, light/dark appearances, and existing accent safeguards. Minimum asserted text contrast: 4.5:1. Native material rendering is also reviewed visually; token ratios alone do not prove all possible compositor backgrounds.
- Two UI journeys select each of the five tabs and capture the news feed before/after scrolling, in Ukrainian light appearance and German dark appearance.
- Final source: `Delivery.xcresult`, 7 passed, 0 failed, 0 skipped; device build `device-delivery-build.log` succeeded. Reviewed final selected organization tab and light news screenshots. The mock regional feed is short, so scrolling this fixture does not prove a long live feed or every possible photo behind the bar.
- Physical iPhone 16 Pro Max, iOS 27.0.1: installed a separately signed `at.serlest.UkrainianCommunity.ContrastAudit` build with mock repositories. Captured/read back light and dark news/navigation, then both appearances with system Reduce Transparency + Increase Contrast enabled. These are actual device screenshots, not previews. Image placeholders reflect mock content, not a production image-loading diagnosis.
- `device-appearance-before.json` and `device-appearance-after.json` results match exactly. System appearance/accessibility settings were restored.
- Initial contrast check rejected the original dark-blue navigation token at 4.17:1 on a light dark-mode material; the dedicated navigation blue was adjusted before successful reruns.
- Localization validation (3268 entries) and repository structure passed; whitespace checks passed.

No backend/schema changes, TestFlight upload or public release. Main UAC installation/data were not replaced by the device audit copy. Live news retrieval is outside this visual change; testing uses existing mock repositories.
