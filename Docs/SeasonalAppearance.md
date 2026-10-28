# Seasonal appearance

Current source: 2026-10-28 static autumn artwork and four reusable scene templates. This source update has not been delivered to TestFlight. Historical build-specific receipts below describe earlier renderers, not the current web implementation.

## Scenes and editing

The owner creates a disabled draft from the Add scene menu: Halloween, GTA VI · Vice Nights, Christmas · Warm Evergreen, or New Year · Golden Midnight. The library keeps saved themes after their season ends. Dates, timezone, sections, priority, size, optional illumination and applicable motion remain editable. A preview ignores the current schedule. Applying an editor change, saving the owner library, and publishing enabled saved themes are separate operations. Disabling publication keeps the library. No new theme is automatically enabled or published.

- Halloween: a cached transparent quarter-corner silk web at the upper left; two hanging native spiders, one attached to the web and one visually under the system cutout; cached yellow/orange botanical leaves at the edges; a carved 3D pumpkin beside the scrolling logo, with a candle fading almost out; four rare staggered articulated bats.
- GTA VI · Vice Nights: original photographic palm fragments with restrained cyan/pink point lights at the edges. No game logo, asserted release date or game image. A two-week disabled draft is merely an editable starting window.
- Christmas · Warm Evergreen: photographic fir, berries, brass bell and warm ornament fragments, tiny soft lights and at most six slow snow particles. Annual Vienna window December 15–28 by default.
- New Year · Golden Midnight: photographic gold stars and champagne ornaments with tiny warm lights. Annual Vienna window December 28–January 8. No baked-in year digits.

No decoration adds safe-area space, moves the content down or intercepts gestures. Only pumpkin/custom-image themes reserve the existing compact brand dock; other scenes keep the full logo. Overlays appear on eligible tab roots, hide on nested routes/authentication/full-screen presentations/keyboard use and compact-height landscape, and respect the local seasonal-effects preference. This is visual placement around the physical cutout, not ActivityKit or access to Dynamic Island contents.

## Rendering and performance boundaries

The web is two cached 180-point UIKit bitmaps (light/dark), with baked strand shadow and a subtle fade around the status region. There is no animated web mesh, morpher or full-screen blur. Leaves and new scene ornaments are transparent bundled bitmaps, decoded/cropped once and capped at 512 pixels. Original generation prompts and asset paths: [asset catalog](SeasonalSceneAssets.json), [autumn artwork](SeasonalAutumnArtwork.md).

A small header SceneKit viewport scrolls with the actual logo; the pumpkin does not bob or poll motion sensors. Candle intensity affects the light and carved eye/mouth materials. The full-window SceneKit view contains only spiders and rare bats: 10 Hz calm gravity polling, up to 30 fps during descent, swing or flight, and no scene submissions at rest. Offscreen header rendering is skipped. Two spiders descend once, remain visible, and preserve their pose while animation pauses. One bounded Core Motion source drives the spider pendula; samples stay in memory and are neither stored nor transmitted.

Legacy web `sway` no longer controls the static web. Optional web-only `spiderMotion` (0…1) controls spiders independently; missing values use max(0.25, legacy sway), preserving the requested moving spiders when an older saved package disabled web sway. Explicit zero freezes them. Other artwork rejects this field. Old readers ignore the optional field. Native palm artwork is a new enum capability and requires this app update; unsupported packages fail closed on older binaries.

The other three scenes have no display link, Core Motion source or 3D renderer: static UIImageViews, up to six tiny Core Animation opacity lights, and optional capped Christmas CAEmitterLayer snow. Reduced Motion, accessibility text sizes, Low Power Mode and inactive scenes stop animated effects; leaving the view removes animations/emitter and stops sensors. Static artwork stays visible where appropriate. These budgets and simulator CPU measurements are not a guarantee of physical iPhone FPS.

Bat paths retain the approved lower-left entry, central circular loop and upper-right exit. Four staggered eight-second flights begin 0.72 seconds apart in a 68-second cycle (shorter preview cycle). No continuous flock covers the interface.

## Persistence, safety and reuse

`seasonalLibraries/current` is owner-only. `seasonalPresentations/current` allows public single-document get. Both contain schemaVersion (1), JSON payload, UUID revision, updating user and server timestamp. List/delete are denied. Verified active owners satisfying legal acknowledgements may write. Optimistic transactions prevent stale overwrite; server readback verifies exact canonical payload/revision. Published packages include only enabled saved themes. Unknown schema/effects or malformed data fail closed.

Up to 12 themes, six elements per theme, three per legacy edge and 240000 UTF-8 bytes per library are validated. Dates are start-inclusive/end-exclusive; annual recurrence follows the selected timezone and local calendar, including December–January and DST boundaries. Priority descending then stable ID resolves overlaps. The owner may reuse a built-in theme, duplicate a saved theme or import/export a JSON backup. Imports get fresh IDs and remain disabled.

Custom `image` artwork accepts 1–8 embedded transparent PNG frames, each <=48000 bytes and <=256×256, playback 0.1–2 seconds per frame. This enables new decorative images without another binary. New native effect capabilities require an app update. No executable content is downloaded. Public decorative data is cached atomically for offline reuse; cached schedules expire locally. An offline device sees a remote early-disable only after reconnecting. No database query occurs per animation frame.

## Verification

Current evidence and exact limits: [four-scene receipt](Verification/SeasonalScenes20261028.json). Automated model, real view rendering, UI screenshots and isolated Firebase SDK checks are distinct from device acceptance and TestFlight delivery. The physical phone was paired and the local Release installed, but launch was blocked by its lock state; new physical tilt/scroll acceptance remains pending. Earlier paused audit results are recorded separately in PhysicalAcceptance11to19Progress20261027.json.

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
