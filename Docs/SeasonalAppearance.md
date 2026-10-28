# Seasonal appearance

Current source: 2026-10-28 complete reusable six-zone scenes. Delivery for this revision is a signed local iPhone installation, at the user's request. No TestFlight upload or global publication is implied. Historical receipts below describe their named earlier renderers.

## Complete scenes and editing

The owner adds a disabled draft: Halloween, GTA VI · Vice Nights, Christmas · Warm Evergreen, or New Year · Golden Midnight. Each contains six independent stable zones: brand ornament, upper corner, hanging objects, side edges, atmosphere and navigation cap. Each zone can be hidden, resized, assigned compatible native artwork or a custom transparent PNG, and configured with the supported animation, strength and applicable light color. Unsupported combinations cannot be saved.

- Halloween: static cached upper-left silk web, two native hanging spiders (web and visually beneath the cutout), yellow/orange botanical side leaves, native dimensional candle-lit pumpkin beside the scrolling logo, four rare staggered bats, and small bottom corner leaves.
- GTA VI · Vice Nights: original dimensional neon palm header, palm corner/side fragments, hanging chrome key and turquoise charm, rare warm glints, and restrained palm navigation corners. No game logo, asserted official release date or copied game image. Its disabled two-week draft is an editable starting window.
- Christmas · Warm Evergreen: original glass snow globe header, fir corner/edges and warm lights, two hanging clear glass baubles, distributed snow and a static realistic snow cap above the tab bar. Annual Vienna window December 15–28 by default.
- New Year · Golden Midnight: original champagne-flute header, gold star corner/edges and warm lights, two hanging clear glass baubles, distributed snow and the same tab-bar snow cap. Annual Vienna window December 28–January 8. No baked-in year digits.

The library retains scenes for next year. Annual repetition, start/end, timezone, sections and overlap priority remain editable. Applying an editor draft, saving the private library, and publishing enabled saved themes are separate operations. Nothing new is automatically enabled or published. Existing legacy scenes can explicitly be supplemented into six zones, retaining existing image frames and schedule.

A full-screen read-only preview uses the production header, backdrop, native tabs and scene renderer with sample scrollable cards and details. It does not fetch live content or publish. Switch tabs, scroll, open a sample detail and close back to the unchanged editor. Thumbnail previews are graphical samples, not complete live screens.

No decoration adds safe-area space, moves content down or intercepts gestures. The existing compact brand dock hosts the header ornament. Corner/hanging/edge decorations appear on eligible tab roots; snow and the navigation cap also continue through eligible details. Hidden tab bars suppress the cap. Authentication, modal presentations, keyboard, compact-height landscape and accessibility text sizes suppress decorations as appropriate. This is visual placement near the physical cutout using public safe areas, not ActivityKit or access to Dynamic Island contents.

## Rendering and performance boundaries

The static web is a cached 180-point UIKit bitmap per appearance, with baked strand shadow and a fade around the clock. No animated web mesh, morpher or full-screen blur. Raster ornaments are decoded/cropped once: header and hanging assets at most 384 pixels, other native ornaments at most 512, the static wide snow strip at most 768. Original generation prompts and paths: [complete scene asset catalog](SeasonalCompleteSceneAssets.json), [initial scene assets](SeasonalSceneAssets.json), [autumn artwork](SeasonalAutumnArtwork.md).

The native pumpkin renders only in the small scrolling header viewport and skips offscreen drawing. Other header ornaments use cached UIImageViews and bounded Core Animation glints. The full-window SceneKit layer contains only hanging objects and rare native bats: 10 Hz calm gravity polling, up to 30 fps during movement, no scene submissions at rest. Two spiders descend once and stay; scene pause preserves pose. One Core Motion source drives bounded pendula, including photographic keys/baubles. Sensor samples stay in memory, never stored or transmitted.

Legacy web `sway` does not animate the static web. Optional `spiderMotion` controls spiders independently; missing values use max(0.25, legacy sway). Explicit zero freezes them. Composed scenes separate web and spider elements. The web and first thread use shared screen-space geometry so their attachment stays aligned at every allowed size.

Atmosphere uses at most 20 tiny precreated snow CALayers in three depth sizes, analytically seeded across the screen immediately and animated by Core Animation. There is no per-flake display link, CPU update loop or full-screen image. Up to six small light layers and capped rare glints are separate. The snow cap is static. Reduced Motion, Low Power Mode, inactive/offscreen previews and explicit still styles stop animation and sensors. Static artwork remains where appropriate. Automated simulator checks do not prove physical iPhone frame pacing or tilt acceptance.

Four bats retain the lower-left entry, central loop and upper-right exit, staggered by 0.72 seconds, with eight-second flights in a 68-second cycle (shorter preview). There is no continuous full-screen flock.

## Persistence, compatibility and reuse without a build

`seasonalLibraries/current` is owner-only; `seasonalPresentations/current` permits public single-document get. Firestore envelopes stay schemaVersion 1 with JSON payload, UUID revision, updating UID and server timestamp. The JSON package is format 1 for legacy scenes and format 2 for composed zones. Old binaries reject unknown format 2 and show their normal interface; the new editor explains the app-update requirement. No database rules change is required. Both envelope and package are validated independently.

Only verified active owners satisfying legal acknowledgements may write. List/delete are denied. Optimistic transactions reject stale overwrite and server readback verifies canonical payload/revision. Published packages contain only enabled saved scenes. Disabling publication keeps the private library. Unknown schema/effects or malformed data fail closed.

Limits: 12 themes, six elements per theme, unique composed zones, three per legacy edge, 240000 UTF-8 bytes per package. Dates are start-inclusive/end-exclusive; annual recurrence uses the configured local calendar, including December–January and DST. Priority descending then stable ID resolves overlaps. JSON import assigns fresh IDs and keeps scenes disabled.

Custom PNG images and JSON backups allow new scenes using the installed capabilities without a new binary. Import downsamples locally to at most 256×256 and 48000 bytes, preserves transparency and rejects oversized/invalid input. JSON supports 1–8 PNG frames, playback 0.1–2 seconds per frame; compatible frame/flight/glow/float/swing styles reuse the same native renderer. New rendering capabilities still need an app update. No executable content is downloaded. Public packages are atomically cached for offline reuse; schedules expire locally, while early remote disable needs reconnection. No database query occurs per animation frame.

## Verification

Current candidate evidence: [complete scene receipt](Verification/SeasonalCompleteScenes20261028.json). Earlier source evidence: [initial four-scene receipt](Verification/SeasonalScenes20261028.json). Model, real rendering, UI screenshots, isolated Firebase SDK, local device installation, hosted CI and the user's physical acceptance remain separate gates. No TestFlight upload or production scene publication is part of this delivery.

## Historical renderer receipts

The following sections record already-delivered older builds and do not describe the current static web.

## Asymmetric web and bat group (build 134)

The native web is now an off-centre orb with unequal radial lengths, curved connecting strands, occasional incomplete cells and loose edge threads. The upper part continues beyond the window edge. A joined lower attachment carries the spider silk and follows the existing bounded web sway. Four bats enter with 0.72-second spacing, separate loop centres/radii, size variation and independent wing phases. The lead bat preserves build 133’s approved route. All four finish before the next spider window, including in editor preview. This is a native artwork update; saved seasonal schedules remain compatible.

Evidence: [flock verification](Verification/SeasonalFlock20261028.json). Simulator proof and TestFlight delivery do not substitute for the user’s aesthetic acceptance on iPhone.

## Persistent pair and pinned web (build 135)

Two spiders of different sizes descend with staggered starts, settle at different depths, and remain hanging across bat cycles. Static/reduced-motion presentation keeps both visible without animation. The web is 22% larger at the default size, capped relative to the viewport; its upper corridor remains narrow around the system cutout. Upper points are pinned. Two prebuilt GPU morph targets bend the lower lattice instead of rotating the whole web. Both silk attachment points use the same displacement function as those targets, so the threads follow the lattice. No mesh rebuilding is performed per frame. This remains decorative artwork behind the system cutout, without ActivityKit or access to Dynamic Island contents.

See [pair verification](Verification/SeasonalPair20261028.json). Real sensor response and aesthetic acceptance on iPhone remain separate from simulator verification.

## Scroll and web rendering follow-up (build 136)

The pumpkin now renders inside the actual scrolling brand header, in a small local SceneKit viewport. It no longer follows a screen-space anchor at the animation frame rate. Native headers do not publish moving anchors; legacy imported PNG ornaments keep their existing anchor path. The overlay keeps the web, two persistent spiders and four bats. Spider resting depth no longer depends on the header’s scrolling position.

The web returns to the pre-135 scale. A cached 3x antialiased silk texture on an 81-vertex, 128-triangle deformable sheet replaces 6,720 lit thread vertices/triangles and 13,440 target vertices. Two light morph targets retain pinned upper points and lower sway. HDR/bloom stay in the small pumpkin viewport; the full-window overlay uses unlit silk and 2x MSAA. Materials change only when the theme/appearance changes. Duplicate configuration/layout draws are coalesced into the active display tick, targeting 60 fps during movement/flight/descent and 15 fps for slow ambient idle motion, with renderer and display clocks matched. Static/low-power/reduced-motion behavior is retained.

Evidence: [performance follow-up](Verification/SeasonalPerformance20261028.json). The isolated simulator web benchmark is not an iPhone FPS measurement and does not prove GPU saturation in build 135. Frame pacing and the screen-space scroll attachment were addressed as distinct issues.
