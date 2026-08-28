# UAC App Store screenshot set

Release-preparation assets captured from the current iPhone and iPad simulator builds.

- Localizations: German (`de`) and Ukrainian (`uk`)
- iPhone target canvas: 1320 × 2868 pixels
- iPad target canvas: 2064 × 2752 pixels
- Content: real UAC application UI and current public guest content
- Status bar: deterministic 09:41, full Wi-Fi and battery

Generated image directories are intentionally ignored by Git to avoid adding
large release binaries to the source repository. Locally, `raw/` and
`raw-ipad/` contain the unmodified XCTest captures; `final/` and `final-ipad/`
contain the App Store-ready branded compositions. Run `compose.py` with Pillow
available to reproduce both final sets.

The final images are intended for App Store Connect version 1.0. They must be visually reviewed before upload and must continue to match the submitted build.
