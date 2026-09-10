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

Final validation is still in progress. Intermediate evidence is not the release gate:

- 1,950 JVM tests passed with zero failure/error/skip; local build and lint passed before final
  small visual corrections. Final build/test repetition follows.
- All 34 populated synthetic visual traversal scenarios passed at font100 and font200 before
  final owner/time-input corrections; corrected branches must be recaptured.
- Management regression at native font200 with docked keyboard: 129/130 passed. The remaining
  test expected the old technical field label; updated to the exact localized label, with a new
  test preserving unknown server prose. Final repetition pending.
- Every generated branch group was visually inspected. Invalid early captures (wrong dialog root,
  stale files, open leave dialogs) were explicitly excluded and regenerated, not counted as PASS.

Synthetic component tests do not prove all live-cloud operations. No production deletion, user
restriction, role change, broadcast, moderation decision or support closure was performed.
Physical-device, TalkBack, OEM differences and complete live functional parity remain distinct.
Native calendar header may follow system language; calendar body/buttons follow app language.

## Release

Not published yet. Only Google Play Internal testing is authorized. Record the exact signed
artifact, SHA-256 and Play availability read-back here after final acceptance; no public rollout.
