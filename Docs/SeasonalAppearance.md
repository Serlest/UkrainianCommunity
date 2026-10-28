# Seasonal appearance

Status: iOS implementation and local automated verification complete; physical-device acceptance and TestFlight delivery pending. See [verification evidence](Verification/SeasonalAppearance20261028.json).
The previously paused physical acceptance backlog remains in PhysicalAcceptance11to19Progress20261027.json; this feature does not close any of those cases.

## Product boundaries

- An owner maintains a reusable library separately from the public presentation. Saving/editing/importing a theme never changes the published presentation. Publishing uses only saved enabled themes. Disabling the presentation keeps the library.
- Halloween is the first built-in editable template: vector pumpkin with warm pulsing eyes/mouth, fine web and a small bat. Other built-in primitives are snowflake, star and pine. Custom small transparent PNG frames allow future artwork without a new binary.
- Decorations use a protected top strip on the five main tab roots. Nested routes, authentication, full-screen presentations, keyboard use and compact-height landscape have no live decoration strip. This deliberately reserves layout space instead of putting artwork over text, search or notification controls.
- Local user preference `seasonalEffectsEnabled` defaults to true. Reduced Motion, accessibility text sizes and Low Power Mode stop animation and tilt; background/invisible strips stop Core Motion. Motion samples exist only in memory; no collection, storage or transmission.
- Initial renderer supports a maximum of six elements, three per edge, gentle sway/tilt, candle glow and bounded PNG frame playback. New effects outside these capabilities require an application update. No executable content or third-party animation runtime is downloaded.

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
