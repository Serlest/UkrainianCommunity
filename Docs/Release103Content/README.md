# UAC 1.0.3 / F02 — German event repair

Prepared 5 September 2026 against checkpoint `120a60212c12a3451332c18fdfdcbe3a0b6f8df9`. **Implementation only. No publication, tests, builds, app launches, or runtime validation have been performed by this task.** Live reads and editorial source checks were performed.

## Deliverables and scope

- `translations.json`: complete German title/summary/details for all four records; three source-verified candidates and one explicitly held translation of the existing announcement.
- `eligible.patch.json`: three Firestore writes, one per verified event. Each changes exactly `localizations.de.title`, `localizations.de.details`, `localizations.de.summary`. No entire locale-map replacement; no changes to UK, top-level fallbacks, times, organization, source URL, media, moderation or metadata.
- `held.patch.json`: the fourth candidate, **not eligible for publication**. Do not send this file to Firestore. The supplied publisher rejects its ID with no bypass switch.
- `*.baseline.json`: freshly read exact Firestore document name/updateTime and selected public source fields; these are projected baselines, not full backups. Media access tokens, credentials and user metadata are excluded.
- `publish_de.py`: default offline inspection, explicit read-only preflight, one atomic commit for explicitly selected eligible IDs, and read-back. Uses the existing local `control.py` authorization; does not alter that helper or a shared publisher.
- `test_publish_de.py`: offline safety tests written for the coordinator's common verification phase; not run during implementation.
- `SOURCES.md`: fact/source map, uncertain items and editorial decisions.

The original assignment requested only title/details. Static code review found that `UkrainianCommunity/Repositories/Firebase/FirestoreContentPublishingCoding.swift:62–71` requires `summary` too and otherwise discards the entire locale. All four live documents have no German map. The coordinator explicitly approved adding **only `localizations.de.summary`** on 5 September. No app contract was changed.

## Original preconditions

| ID | Exact live updateTime | Candidate |
| --- | --- | --- |
| 09CBA4CE-6066-4DA1-822A-F50A02E25A44 | 2026-08-30T09:34:06.417167Z | eligible |
| 4CCF2D2C-204B-403C-AD3C-162767C7BB65 | 2026-08-27T21:47:37.434991Z | eligible |
| 97E3A6BD-49AF-4EEB-A32C-6A61DCE857E2 | 2026-08-29T14:06:08.703039Z | eligible |
| FE5637D0-6B8D-483B-869C-C628E3941D92 | 2026-09-04T12:41:00.332095Z | held: parish confirmation needed |

Any changed updateTime stops publication. Do not refresh a timestamp without re-reading the current text and repeating the editorial review. The patch intentionally has no timestamp transform; Firestore supplies its own new document updateTime.

## Coordinator verification phase — future commands

Run from the integrated checkout only after the common verification phase begins. The following examples were **not executed** by this task. Set `PACKAGE` to that checkout's absolute `Docs/Release103Content` path and `EVIDENCE_ROOT` to a fresh private evidence parent outside git.

```sh
python3 -m unittest discover -s "$PACKAGE" -p 'test_publish_de.py'
python3 "$PACKAGE/publish_de.py" inspect
python3 "$PACKAGE/publish_de.py" preflight --evidence-dir "$EVIDENCE_ROOT/preflight"
```

Review full German prose against sources, the three-field masks and baseline times; check that the iOS DTO accepts each locale including summary. Inspect card/detail rendering in German, then Ukrainian; assert all UK fields, fallback strings, identity, dates and images are preserved. Check paragraph wrapping and non-empty content. These iOS/UI checks remain for the coordinator. The offline unit file exercises masks/preconditions, held rejection, stale data, one atomic commit, no-write preflight, server conflict, uncertain transport result without resend, and non-target-field preservation.

After common checks pass and the coordinator chooses to publish, provide a real nonempty verification record. The script records its path and hash; existence does **not** independently prove the tests passed. The project-confirmation flag is a deliberate invocation guard, not a request for additional user permission.

```sh
python3 "$PACKAGE/publish_de.py" publish \
  --event 09CBA4CE-6066-4DA1-822A-F50A02E25A44 \
  --event 4CCF2D2C-204B-403C-AD3C-162767C7BB65 \
  --event 97E3A6BD-49AF-4EEB-A32C-6A61DCE857E2 \
  --confirm-project ukrainiancommunity-dbd5f \
  --verification-record "$VERIFICATION_RECORD" \
  --evidence-dir "$EVIDENCE_ROOT/publication"
```

The parish hold does not block these three. The script validates the exact patch shape and translation match, checks each live baseline, records hashes of all non-target Firestore fields, and sends a **single atomic commit** with the original updateTime preconditions. It then reads each selected document and compares target strings and non-target-field hashes. Evidence files are exclusive-create, mode 0600; full document contents and auth headers are never saved. Every invocation must use a new evidence directory, except read-back, which uses the original publication directory.

If the response is uncertain or non-200, the tool performs one read-back and exits for coordinator review; **no mutation retry**. If even that GET fails, use the read-back mode once network/auth is restored. Preserve the same selected IDs and order as the publication invocation:

```sh
python3 "$PACKAGE/publish_de.py" read-back \
  --event 09CBA4CE-6066-4DA1-822A-F50A02E25A44 \
  --event 4CCF2D2C-204B-403C-AD3C-162767C7BB65 \
  --event 97E3A6BD-49AF-4EEB-A32C-6A61DCE857E2 \
  --evidence-dir "$EVIDENCE_ROOT/publication"
```

A concurrent/trigger change to any non-target field makes read-back fail conservatively; investigate rather than overwriting it. A successful read-back after a timeout establishes observed target state, but the script deliberately leaves the uncertain transport outcome for review. No automatic rollback is provided. All target fields were absent in the baseline: a reviewed rollback would delete only these three leaves under a **fresh post-publication precondition**, after checking for subsequent author edits. Never restore an entire document from these projected baselines.

## Remaining limitations

- F02 can be reduced from four to one after successful publication/read-back/UI review of the eligible set; it cannot yet be declared fully closed.
- Parish-specific confirmation for 20 September 2026 at 10:30, confession and mothers' prayer remains missing. The generic diocesan 15:00 timetable is conflicting evidence, not proof the date-specific UAC entry is wrong.
- Hall's existing structured end time is 17:00 local; no end time was confirmed in the read pages. This patch neither asserts that end time in German nor changes the structured field.
- Existing hackathon timestamps contain `:04` seconds; the script preserves them and distinguishes 09:00 admission from 09:30 program start in the text.
- UK descriptions remain shorter and retain old editorial timing notes in Hall/Marktplatz; revising them is outside this approved German-only mask.
- Images, their rights, external website availability on publication day and on-device rendering have not been verified here. Publication may invoke existing Firestore triggers; no trigger/runtime checks were run.

REST design references: [atomic commit](https://docs.cloud.google.com/firestore/docs/reference/rest/v1/projects.databases.documents/commit), [field-mask writes](https://docs.cloud.google.com/firestore/docs/reference/rest/v1/Write), [updateTime precondition](https://docs.cloud.google.com/firestore/docs/reference/rest/v1/Precondition).
