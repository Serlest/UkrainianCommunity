# Performance Baseline

## Stage 15: launch profile

- Date: 2026-08-24
- App commit before optimization: `edde27a1c48bb366906e2057d8c2028d41702657`
- Build: Release, iOS Simulator, dSYM enabled
- Device: iPhone 17 Pro simulator
- Runtime: iOS 26.4 (`25G83`)
- Profiler: ETTrace `v1.1.0`, main thread, launch capture
- Flow: relaunch the installed app and wait until the Home feed is visibly stable
- Runs: one baseline and one after capture

The app executable and the temporary ETTrace framework were UUID-matched to their dSYMs before each capture. ETTrace reported `0.0%` samples without a library. The temporary profiler dependency was removed after profiling.

## Trace-backed finding

`LocalizationStore.localizedString(_:defaultValue:)` repeatedly resolved the language `.lproj` path and created a `Bundle` for every localized string. The baseline attributed `15.373 ms` inclusive main-thread work to this method during launch.

The fix keeps one thread-safe `Bundle` per language. The after trace attributed `5.145 ms` inclusive work to the same method, a reduction of `10.228 ms` (`66.5%`). The remaining sample represents the first bundle creation and localized lookup.

| Metric | Baseline | After | Delta |
| --- | ---: | ---: | ---: |
| `LocalizationStore.localizedString` inclusive | 15.373 ms | 5.145 ms | -66.5% |
| Share of active main-thread samples | 1.01% | 0.29% | -0.72 pp |
| Unattributed samples | 0% | 0% | unchanged |

## Findings not changed

The largest stacks were Swift runtime conformance lookup, SwiftUI/AttributeGraph layout, and UIKit/Core Animation work. The captures did not expose a sufficiently specific, repeatable application-code root cause in those stacks, so stage 15 does not apply speculative view restructuring or blanket `Equatable` changes.

## Caveats

- Simulator profiling is useful for attribution but is not a substitute for final on-device Instruments measurements.
- The captures contain different idle durations because recording was stopped manually. Compare the focused stack above, not total wall-clock duration.
- Network and Firebase state can vary between launches.
- One before/after pair is enough to verify removal of repeated bundle creation, but broader launch metrics require multiple on-device runs before release.

Apple recommends measuring a focused flow, changing one confirmed cause, and re-recording the same flow. See [Improving your app's performance](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance/), [Improving your app's rendering efficiency](https://developer.apple.com/documentation/xcode/improving-your-app-s-rendering-efficiency), and [Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/).

## Stage 16: feed scrolling audit

- Date: 2026-09-02
- App build: 62
- Flow: repeated vertical scrolling on Home, Events, and Organizations after content and images were loaded
- Validation device available during the audit: iPhone 17 Pro simulator, iOS 26.4

The current tree already included adaptive image downsampling, cached relative-date formatting, lazy grids, solid grouped feed surfaces, and full ProMotion frame-rate access. The follow-up code review found two remaining sources of repeated rendering work:

- every event row observed the complete `EventsViewModel` even though the row rendered only its immutable `Event` value;
- Events and Organizations still applied material and shadow effects to every repeated card and metadata chip, while the Home feed had already removed those effects.

The follow-up removes the redundant row observation and uses the same lightweight repeated-card treatment across all three public feeds. The simulator Debug build succeeded and the three `ScrollPerformancePolicyTests` passed.

### Measurement limitation

The iPhone was offline during this audit. Xcode reported that both the Animation Hitches and SwiftUI instruments are unsupported on the selected simulator runtime. Therefore this stage does not claim a measured device hitch rate or frame rate. The release gate still requires one focused Animation Hitches capture on a connected iPhone using the Release build and the same scrolling flow.
