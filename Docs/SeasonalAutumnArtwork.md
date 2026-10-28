# Static autumn artwork

- Runtime asset: `UkrainianCommunity/Assets.xcassets/SeasonalAutumnLeaves.imageset/leaves.png` (341×512 RGBA, one shared texture).
- Generation: built-in `image_gen.imagegen`, `transparent_background=true`; no CLI/API fallback.
- Original: `/Users/serlest/.codex/generated_images/01a11559-70e2-7563-bf0b-6b743c40d10a/exec-e182c72e-efa4-4782-820c-13729f600c28.png` (1024×1536 RGBA). Preserved non-destructively; runtime copy downsampled with `sips -Z 512`.
- Web: original cached UIKit line artwork in `SeasonalStaticDecorations.swift`, two appearance-specific bitmaps, no animation or morph mesh.
- Leaves are part of the native `.web` composition, so existing saved annual themes remain compatible and do not require a production library/schedule write. Removing the web ornament also removes its leaves and two spiders. Existing compatible imported PNG artwork remains separate.

## Final generation prompt

Use case: photorealistic-natural. Asset type: transparent PNG decorative edge cluster for a premium iPhone autumn UI, not a mockup. Primary request: three exceptionally realistic autumn maple leaves, one golden yellow, one burnt orange, one amber with subtle red edges, slender natural stems, softly curled tips, fine raised veins, minute organic imperfections and realistic subsurface color. Composition: a narrow vertical cascading cluster, leaves overlap lightly, stems near the left side, leaf lobes pointing right into transparent empty space. Fit the entire cluster with generous transparent padding, no cropping. Soft diffuse neutral daylight, extremely subtle self-shadow only, convincing dimensionality, sharp botanical macro texture. Entire background truly transparent, no ground plane or rectangular shadow, no text, no icons, no frame, no glow, no autumn scenery. Original artwork. Intended to be displayed as a quiet static ornament along the left screen margin, about 30 pixels wide at final UI size; recognizable clear leaf silhouettes.
