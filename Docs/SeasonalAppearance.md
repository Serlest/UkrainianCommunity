# Seasonal appearance

Status: the original renderer was delivered in TestFlight 130. The revised native 3D scene and its delivery are documented in SeasonalDepth20261028 and TestFlight131 verification reports. Physical iPhone acceptance is separate.
The previously paused physical acceptance backlog remains in PhysicalAcceptance11to19Progress20261027.json; this feature does not close any of those cases.

## Product boundaries

- An owner maintains a reusable library separately from the public presentation. Saving/editing/importing a theme never changes the published presentation. Publishing uses only saved enabled themes. Disabling the presentation keeps the library.
- Halloween is the first built-in editable template: original native 3D pumpkin with carved eye/mouth openings and a pulsing interior, a darker web from the top of the window, a descending pendulum spider and an occasional articulated bat. Other built-in primitives are snowflake, star and pine. Custom small transparent PNG frames allow future artwork without a new binary.
- Decorations overlay the five main tab roots without a safe-area inset. An anchored compact brand cluster places the pumpkin beside the logo while keeping header height and controls accessible. The web starts at the window top, visually behind the physical system cutout; no ActivityKit or custom Dynamic Island is used. Nested routes, authentication, full-screen presentations, keyboard use and compact-height landscape hide the scene.
- Local user preference `seasonalEffectsEnabled` defaults to true. Reduced Motion, accessibility text sizes and Low Power Mode stop animation and tilt; background/invisible scenes stop Core Motion. Motion samples exist only in memory; no collection, storage or transmission.
- The data format still supports at most six elements, three per legacy edge. Built-in pumpkin/web/bat use scene-specific placement; the editor explains this instead of offering an ineffective left/right picker. Other artwork retains embedded PNG playback. The native Metal-backed SceneKit scene uses original procedural meshes/PBR materials; geometry is built when element data changes, not each frame. It targets 30 fps while eligible. Core Motion supplies relative gravity for pumpkin parallax, absolute gravity for hanging direction and user acceleration for opposite inertial impulse. Bounded damped dynamics avoid jumps after pauses. Spider and bat have disjoint time windows (14-second descent/hold/return, 4.5-second flight in a 68-second cycle); preview cycles are shorter. Static artwork does not continuously run a blank 3D renderer. New effects outside these capabilities require an application update. No executable content or third-party animation runtime is downloaded.

## Persistence and schedule

`seasonalLibraries/current` is owner-only. `seasonalPresentations/current` permits a public single-document get. Both have exactly schemaVersion (1), payload (JSON string), revision (UUID), updatedBy (current owner), updatedAt (server timestamp). List/delete are denied. Only verified, active owners satisfying current legal acknowledgements may write. Optimistic transactions prevent stale overwrites; a server readback verifies the exact canonical payload/revision. Unknown schemas or malformed packages fail closed.

Each payload is a SeasonalLibrary with up to 12 uniquely identified themes and <=240000 UTF-8 bytes. Theme fields are defined in SeasonalTheme.swift. ISO8601 UTC dates in exported JSON use second precision. UI dates use the explicitly selected IANA timezone. Windows are start-inclusive/end-exclusive. Annual recurrence preserves local calendar times and includes the previous-year start to support Christmas → January. It never applies before the original start year. Priority descending, then stable theme ID ascending determines the single winner for an overlapping section.

The public document is observed independently of the startup gate and only while the scene is active. A complete valid package is cached atomically; embedded artwork requires no later downloads. An offline missing snapshot does not remove the cache; confirmed missing or malformed server data clears it. Cached schedules are evaluated locally every second while eligible, including start and end boundaries. A remote early-disable cannot reach an offline device until it reconnects. Cache is public decorative data and may safely survive account changes. No fixed polling query per animation frame.

## Future packages without another build

1. Create an original theme or copy a saved theme in the owner library. Templates remain available after the season ends.
2. For new artwork, create a JSON package using the exported format and import it through Files. Imports always receive new theme IDs and are disabled until explicitly scheduled.
3. Custom image elements use artwork `image`, 1–8 base64 PNG frames, frameDuration 0.1–2 seconds, each PNG <=48000 bytes, one image, width/height <=256. The whole package still fits 240000 bytes. All IDs, numeric ranges, schedule/sections and edge capacity are validated before rendering or saving.
4. Owner previews light/dark immediately regardless of schedule, adjusts dates/sections/priority/motion, then applies changes locally. Saving the library and publishing the schedule are separate explicit steps.
5. Export a backup through Files. Removing a theme from the library does not silently remove its already published snapshot; publish the new schedule to apply removals. Context menu supports creating a disabled copy.

## Acceptance ledger

Required scenarios: library load/missing/error/retry; owner/nonowner/blocked role; save/conflict/readback; import size/schema/PNG/unknown enum rejection; export/import disabled copy; preview/local editing/cancel/discard; save versus publish isolation; schedule and annual/DST/New Year boundaries; overlap priority; local cache/offline end; live disable/reconnect; reduced motion/low power/background sensor stop; five roots versus nested/editor/auth/keyboard; light/dark/UK/DE/maximum text/portrait/landscape; real-device tilt/performance. Evidence and remaining physical gates belong in Docs/Verification/SeasonalAppearance20261028.json.

Apple references: [Core Motion lifecycle](https://developer.apple.com/documentation/coremotion/cmmotionmanager/startdevicemotionupdates(using:)), [motion purpose string](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmotionusagedescription), [downloaded code restriction, 2.5.2](https://developer.apple.com/app-store/review/guidelines/#software-requirements). The downloadable format is decorative data interpreted by the bundled renderer, not code.
