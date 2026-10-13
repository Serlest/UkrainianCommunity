# Google Play graphics — build 79 candidate

These files are prepared assets, not proof of Play Console upload or brand-owner
approval.

Capture source: final signed production APK SHA-256
`99b7da9de8702e0e3df9872ebce1f136e84131c2c1ffcd6a6dfdd436c128176b`,
package `at.serlest.ukrainiancommunity`, version `1.0.3 (79)`.

| File | Required size | Verified | SHA-256 |
| --- | --- | --- | --- |
| `store-icon-512.png` | 512 × 512 | PNG, no alpha, visually inspected | `c8faca0cfc977c2b00df54a80f019e7591a60b4bf1bef2889ee3f3165c4ce6af` |
| `feature-graphic-build79.png` | 1024 × 500 | PNG, no alpha, text-free, visually inspected | `11604396e34dcf6e4b77903a0e89074b58a37bebeb8be9abf3f80dae56f0fa73` |

The store icon is a deterministic downscale of the current 1024 × 1024 Android
app image. The feature graphic was produced with the built-in image generator and
then resized to the exact Play canvas. It contains no generated text or modified
logo.

Final generation prompt:

> Premium, calm and welcoming abstract Google Play feature-graphic background for
> UkrainianCommunity: airy geometric landscape suggesting Austrian Alps and an
> inclusive city community; polished restrained mobile-app illustration; soft
> white and sky blue, navy, Ukrainian blue/yellow and tiny red ribbon accents;
> generous negative space; no words, letters, logos, flags, people, device mockups,
> borders or watermarks.

Before upload, the owner must approve the feature graphic and reconfirm both files
against the exact signed release candidate.

## Phone screenshot candidates

The localized candidates under `screenshots/de-DE/` and `screenshots/uk/` were
refreshed on 2026-09-08 from the exact upload-key-signed, R8-minified build-79
production APK on the API 37 Play AVD at 1080 x 1920. They are RGB JPEG files
without test labels, synthetic accounts, private identifiers or debug overlays.

Each locale contains the same four-screen story:

1. `01-home.jpg` — current public news and event discovery.
2. `02-events.jpg` — event filters and upcoming event cards.
3. `03-organizations.jpg` — organization discovery and category filters.
4. `04-profile.jpg` — guest sign-in boundary and features available without an account.

Suggested German alt text:

- `01-home.jpg`: `Startseite mit regionalen Nachrichten und Veranstaltungen.`
- `02-events.jpg`: `Kommende Veranstaltungen mit Suche und Kategorien.`
- `03-organizations.jpg`: `Organisationen in Österreich mit Kategorieauswahl.`
- `04-profile.jpg`: `Profilbereich mit Anmeldung und Gastzugang.`

Suggested Ukrainian alt text:

- `01-home.jpg`: `Головна сторінка з регіональними новинами та подіями.`
- `02-events.jpg`: `Майбутні події з пошуком і категоріями.`
- `03-organizations.jpg`: `Організації в Австрії з вибором категорії.`
- `04-profile.jpg`: `Розділ профілю з входом і гостьовим доступом.`

The captures contain current public production content. Before uploading them,
reconfirm that every visible third-party photo may be reused in store marketing;
replace any uncertain capture with owner-controlled content rather than cropping
out attribution or assuming publication rights cover promotional use.
