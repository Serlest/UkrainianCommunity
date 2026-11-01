# Vice City banner-towing flights

Two photorealistic aircraft cutouts share one texture. The first tows a blue
“WELCOME TO / Vice City” banner; the second a purple “WHY SIXTY-NINE WHEN YOU CAN /
NINE1NINE / VICE CITY’S SEXIEST NIGHTCLUB” banner. Typography is recreated for the
app, not an extracted original game texture. These are layered 2D sprites, not
live 3D aircraft models.

The pair departs at 5 and 17 seconds in a 76-second cycle; each crossing takes
18 seconds. Both fly right to left, with separate heights, a small climb and
subtle banking. The towline includes a Y bridle. Sixteen shared-texture strips
per banner provide a small travelling cloth wave; the leading edge stays fixed.
A small compositor propeller supplement adds movement to the aircraft image.

The overlay does not participate in layout or hit testing. It uses Core Animation
without new timers, display links, motion sensors or SwiftUI frame updates. Flight
layers are reused for identical configuration, recreated on size changes and
removed when animation is disabled. Existing Reduce Motion, accessibility text,
low-power and background handling apply. Explicit Santa/fireworks override the
Vice flights, so effects do not mix. Physical frame-rate/battery behavior still
requires device profiling; simulator metrics are not a 120 Hz guarantee.

## Compatibility and delivery

A new client build is required for these larger, staggered, waving banners. The
existing downloadable-image flight is limited to small square ornaments with
synchronized movement. No schema version, Firestore field or enum value is added:
new clients derive the pair from the scene's visible viceHeader artwork when no
explicit celebration is selected. Released clients continue to decode exactly
the same schedule and render their existing scene. Server libraries, presentations,
calendar dates and user preferences are unchanged by this implementation.

Scene enablement, scheduling and selection continue to use the existing server
configuration. New flight models/motion capabilities still require client code.

## Artwork provenance

Plane asset: `UkrainianCommunity/Assets.xcassets/SeasonalVicePlane.imageset/plane.png`.
Generated with the built-in image_gen tool, transparent background, 2026-11-02.
Native banner textures are rendered once by SeasonalViceFlights.banner.

Generation prompt:

> Use case: product-mockup. Asset: one transparent PNG cutout for a premium iPhone game-themed decoration animation. Render ONE photorealistic small white and cream high-wing single-engine piston banner-towing airplane, Cessna 172-like silhouette: accurate strut-braced main wing, realistic cabin glazing, correct nose spinner/propeller, fixed tricycle landing gear, horizontal and vertical tail, subtle red accent stripe, rivets and convincing painted metal. Flight direction LEFT: nose on LEFT, tail on RIGHT. Strict broadside three-quarter view, see port side and a little underside, wings foreshortened realistically, level cruising flight. Neutral daylight, restrained reflections, physically coherent miniature aircraft, no cartoon. Whole plane fits with margin, centered, fills width. NO banner, NO tow rope, NO background, NO ground, NO sky, NO text, NO drop shadow rectangle. Propeller depicted subtly motion-blurred but aircraft sharp. Actual transparent alpha background. Deliver highly detailed cutout useful at small screen size.

Reference reporting and imagery (not bundled as app artwork):
- https://www.gta6.fr/actualites/47052-gta-vi-la-campagne-marketing-du-jeu-dans-les-villes.html
- https://i.imgur.com/9DnqsEU.jpeg
- https://gtavicentre.com/assets/marketing/planes.webp (labelled real-life/game comparison)
