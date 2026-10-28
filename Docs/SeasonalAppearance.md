# Seasonal appearance

Current source: post-review scene redesign, 2026-10-28/29, local candidate 1.2.1 (138). The user rejected the prior composition as incomplete. This revision is for local iPhone testing; there is no TestFlight upload or production scene publication in this work. Physical visual acceptance must be recorded separately from source, simulator and SDK results.

## Everyday owner workflow

The first card offers the four prepared scenes and any saved custom scenes. Preview applies a scene only to the owner's current app window, over the actual news/events/organizations/directory/profile screens. A visible End preview button clears this override. The preview bypasses the local effects preference but does not change it, write the cache or contact the publication API. It is cleared when owner access is lost. Bundled previews are available while server configuration is loading; community activation stays disabled until the owner's server state is confirmed.

Enable saves a new preset if necessary and publishes exactly one manual scene. It replaces the previous live scene, irrespective of calendar dates, until the owner disables it or resumes the schedule. This does not disable or erase future calendar plans in the private library. Disable is available in the same card and above the list. Saved edits to an active scene expose Update, applying them without an intermediate off state. Unsaved drafts must be saved or discarded before a different scene can be activated or the management screen can be dismissed into local preview; disabling the current publication remains possible. Reopening quick settings uses the current private draft rather than overwriting it with the saved version.

Private and public writes are revision-checked separately. The UI reports activation only after the public write and exact server readback succeed. If the second write fails, the previous public scene remains displayed and the saved private draft is retained for retry. There is no invented atomicity across these two documents.

Detailed artwork, sections, dates, yearly repetition, priority and schedule publishing remain below the quick controls. A full-screen sample preview is also available inside the editor; it is distinct from the local preview over actual content. Both local previews keep the display awake only while open. Shared wake leases restore the original idle-timer value after the last preview closes; no iOS lock setting is changed.

## Four complete six-zone scenes

Each scene has independent brand, corner, hanging, edges, atmosphere and navigation zones. Zones support visibility, compatible artwork or custom PNG, size, supported animation and applicable light color. Invalid combinations cannot be saved. Existing legacy scenes can explicitly be supplemented into zones without losing images or dates.

- Halloween: static cached upper-left silk web; two persistent native spiders, attached to the web and visually beneath the cutout; botanical yellow/orange side leaves; candle-lit dimensional pumpkin beside the scrolling logo; four rare staggered bats; small bottom-corner leaves.
- GTA VI · Vice Nights: original neon palm header, palm corner/edges, hanging chrome key and turquoise charm, restrained warm glints and palm navigation corners. No copied game image, official logo or asserted release date. The disabled two-week starting window is editable.
- Christmas: original realistic fir tree beside the logo, nine native garland lights with steady/glow/twinkle choices, fir fragments, two hanging glass baubles, full-screen snow and a thin snow rim above navigation. The snow globe remains an optional replacement. Default annual Vienna window December 15–28.
- New Year: crystal champagne-flute header, gold stars and warm lights, two hanging glass baubles, snow and navigation snow rim. No baked-in year digits. Default annual Vienna window December 28–January 8.

Nothing new is automatically enabled or published. Saved scenes and dates remain available next year. One global schedule winner is chosen before checking its section list, so another theme cannot appear on a different tab merely because its priority competitor excludes that tab.

## One shared renderer and readable placement

The main TabView owns one decoration layer, rather than creating one per section. Header ornaments remain inside their actual scrolling headers. Switching ordinary tabs preserves the shared particles, hanging objects and animation clock. Snow and the navigation rim continue through eligible details; large decorations hide there. Keyboard, authentication, modal gates, compact landscape and accessibility text sizes suppress effects as appropriate. The global layer is suspended while the seasonal editor is open, avoiding duplicate hidden effects behind its previews.

Header visibility is published as a Boolean only; moving CGRect anchors are not broadcast for native decorations. Hanging objects hide when the header scrolls out or moves offscreen, preserving their nodes and clock. Returning does not restart their entrance. Bats and snow can continue separately. Winter hanging lengths stay in the header band to protect section headings. The top cutout placement uses public safe areas, not ActivityKit or access to Dynamic Island contents.

## Budgets and power behavior

The web is static cached light/dark artwork with clock-area fade: no animated mesh, morpher or full-screen blur. Bundled photographic assets are decoded/cropped once; header/hanging assets are at most 384 pixels, other source ornaments at most 512, the legacy snow-strip source at most 768. The current snow rim is a small view-sized 2x raster, regenerated only when its size/style changes. Original prompts and paths are in [the complete asset catalog](SeasonalCompleteSceneAssets.json).

Snow uses at most 48 small precreated CALayers in three depth/size groups, seeded across the viewport immediately. Light mode uses filled blue-gray flakes with a soft highlight; dark mode uses a white core. Changing the system/app appearance recolors existing snow layers in place without restarting their fall or allocating a second snow field. Position and drift are Core Animation animations, without per-flake SwiftUI updates, display links or database writes. At most six small edge lights and capped rare glints are separate. The tree uses nine tiny light layers; the tree itself does not fade in and out.

The snow rim occupies only the upper lip of the actual native tab bar. Optional accumulation reveals a bounded additional layer over 90 seconds, protecting icons and labels. This is a decorative effect, not physical snow simulation or stored weather data. The thumbnail has a fixed-size navigation strip and matching placement rather than drawing snow through its icons.

A small SceneKit viewport owns the pumpkin. One full-window SceneKit view owns hanging objects and bats, with HDR/bloom disabled there. Calm gravity polling is 10 Hz and active movement at most 30 fps; no scene submissions occur at rest. Hidden hanging objects stop their sensor work; bat timing can continue. One motion source drives bounded pendula. Samples stay in memory and are not transmitted. Four bats retain their lower-left entry, central loop and upper-right exit, staggered by 0.72 seconds in a 68-second cycle.

Reduced Motion, Low Power Mode, inactive scenes and explicit still modes stop animation. Editor previews pause during image import, date/help presentations and name input. Leaving a view removes animations and stops sensors. Simulator CPU/memory measurements are not physical iPhone FPS evidence.

## Data, compatibility and reuse

The public presentation has one listener at the app root, independent of login. It loads its atomic cache immediately, never blocks startup, and skips repeated JSON decoding/disk writes for identical revision/payload metadata events. It does not query on tab switches or animation frames. Owner configuration reads run concurrently with a bounded read deadline, with retry after failure; writes retain their readback/revision checks and are not treated as failed solely from an arbitrary client timeout.

`seasonalLibraries/current` is owner-only; `seasonalPresentations/current` allows public single-document get. Firestore envelopes remain schemaVersion 1, with JSON payload, revision, updating UID and server timestamp. JSON format 1 is legacy, format 2 adds composed zones, and format 3 adds manualThemeID. A manual package must contain exactly one enabled selected scene. Older clients reject unknown formats/effects and retain ordinary UI. Production rules are unchanged.

Only verified active owners satisfying legal acknowledgements may write; list/delete are denied. Packages allow up to 12 themes, six elements, unique composed zones and 240000 UTF-8 bytes. Dates are start-inclusive/end-exclusive; annual recurrence respects timezone, DST and December–January. Priority then stable ID resolves schedule overlaps. Import creates disabled copies with fresh IDs; export preserves saved library data.

New images and combinations within installed capabilities can be distributed without a new binary. PNG import preserves transparency and locally downsamples to at most 256×256 and 48000 bytes; JSON supports 1–8 small frames at 0.1–2 seconds per frame. New renderer capabilities still need an app update. No remote executable code is accepted. Offline cached schedules expire locally; an early remote disable requires reconnection.

## Verification and delivery

Current evidence: [post-review verification](Verification/SeasonalExperiencePolish20261029.json). Earlier [complete-scene evidence](Verification/SeasonalCompleteScenes20261028.json) describes the user-rejected preceding iteration, not acceptance of this redesign. Physical tests are opt-in and only read actual feeds/use local previews; they never save a library, publish a scene or change credentials. Physical access was blocked by iOS device lock during the night, and must not be described as a passed visual check.

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
