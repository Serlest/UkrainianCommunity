# Android 86 — management descendants

Baseline: Android Internal85, source `9584da6`, receipt `3092762`.
Scope: all ten management entries and their nested forms, details, pickers and confirmations.
Android UI only; no iOS, backend, Rules, account roles or production records changed.

## Coverage map

The full inventory is [Android86-Management-Visual-Matrix.md](Android86-Management-Visual-Matrix.md).
Detailed source/branch/visual evidence and explicit remaining limitations are recorded in:

- [Owner tools](Android86-Visual-Owner.md): project support, analytics and system logs.
- [People and review](Android86-Visual-People.md): users, status, roles, legal evidence,
  news/event moderation and organization applications.
- [Announcements and support](Android86-Visual-Support.md): recipients, regions,
  scheduling, previews, inbox, conversations and case metadata.
- [Content](Android86-Visual-Content.md): featured banners, planning, authoring,
  media, galleries, lifecycle/recovery and publication confirmations.

## Changes

- Grouped long forms into labelled sections with consistent action hierarchy, spacing and cards.
- Replaced technical audience/region/missing-field values with localized labels where known;
  preserved unknown server messages and diagnostic identifiers.
- Improved user identity, status/role effect descriptions, review decisions and legal metadata.
- Moved log maintenance below records; kept red destructive confirmations and cancellation.
- Improved analytics metric layout and trend readability; fixed duplicate lazy keys and stale
  detail scroll position when following a related material.
- Fixed persistent back handling in embedded legal evidence after its lazy header scrolled away.
- Localized and themed announcement date/time dialogs; large text uses spinner time input.
- Large-text authoring uses numeric time input; discard actions fit without cropped labels.

## Verification checkpoint

Final source: `cda63d6`. Evidence under `artifacts/android-build86` in the 82-82 task workspace:

- PASS: 1,950 JVM tests, zero failure/error/skip; final local builds and lint (`final-validation.log`).
- PASS: 34 populated visual traversal scenarios at font100 (`matrix-font100-final.log`).
- PASS: 165 tests at native font200 with docked keyboard: the same 34 visual scenarios plus
  131 component regressions (`final-font200-regression.log`, 293.224 seconds).
- Final captures are in `screenshots-font100-final` and `screenshots-font200-final`.
  Paired configurations are German/light and Ukrainian/dark, not every locale/theme permutation.
- The earlier 129/130 regression result is superseded: the obsolete technical-label expectation
  was localized and unknown server prose now has a separate passing preservation test.
- Every generated branch group was visually inspected. Invalid early captures (wrong dialog root,
  stale files, open leave dialogs) were explicitly excluded and regenerated, not counted as PASS.

Synthetic component tests do not prove all live-cloud operations. No production deletion, user
restriction, role change, broadcast, moderation decision or support closure was performed.
Physical-device, TalkBack, OEM differences and complete live functional parity remain distinct.
Native calendar header may follow system language; calendar body/buttons follow app language.

## Release

Published 2026-09-10 09:36 Vienna, Internal only. Play read-back: `Aktiv`,
`Neuester Release: 1.1 (86) – Internal`, `Für interne Tester verfügbar`, one version code.
Package `at.serlest.ukrainiancommunity`, versionCode86, versionName1.1, min26/target36.
Signed AAB SHA-256: `61ef0c7b1428fca9210a91c96f9a6f2a04bd88a098042460af5b2e5ac110ca6a`.
Signed APK SHA-256: `f1db7f50a50f7346821265fb6afd06aee8d72d95014b80015f78ab20fadbf93f`.
Production build PASS; APK signature verification PASS. No supported-device losses versus85.
One non-blocking Play warning: native debug symbols absent. ReTrace mapping present.
[Internal test installation](https://play.google.com/apps/internaltest/4701365572505552935).
Receipt: `artifacts/android-build86/build86-play-internal-receipt.json` in task workspace.
Play availability is not proof of installation or live functions on the user's phone. No public rollout.
AVD font and keyboard settings restored after testing; work phone untouched.
