# Publication Control

Owner-only replacement for the old planning queue. The profile route keeps its stable `contentPlanning(nil)` identity; old draft notification IDs still open the legacy receipt screen. Existing iOS binaries and legacy server callables remain compatible.

## Data and counting

- `publicationControlItems/{kind}_{id}` records the first public appearance of news or an event. Idempotent Firestore handlers re-read canonical content in a transaction; counter updates are ignored. Removal/archival changes availability without rewriting first-publication history.
- New records use creation time only when content is initially public, otherwise the approval event time. Legacy backfill uses creation time and explicitly labels this limitation in the UI. Source article dates are not app publication times.
- Vienna calendar days. Austria-wide material counts once in its own row, not once for every federal state.
- Overview uses compact day-specific metadata, items use 30-row pages, run history uses bounded 80-row pages. Source text and image data are never downloaded for the dashboard.
- Runs and publication index records expire after 45 days. The UI allows the last 30 days. Latest per-source summaries remain available and become visibly stale rather than disappearing.

## Local reports

`functions/scripts/publicationControlSync.mjs --watch` observes the existing Events v4 report files and News v3 reports. It never searches, publishes, generates images, changes schedules, or changes original reports.

The bridge stores only compact counts, statuses and bounded explanations. Unknown counts remain null; incomplete coverage is not a successful complete result. Malformed completion timestamps fall back to the file modification time with an explicit warning. Publication-only continuations have distinct identities. The original evidence remains local.

The writer uses existing Firebase CLI credentials. Commits compare the current source revision; replay is idempotent, old reports cannot replace a newer source summary, and an immutable report changed after import requires investigation. A local cache records only successful imports. Network failures retry with bounded backoff. Failed imports appear in the overview.

Install/update the event-driven macOS observer:

```
python3 scripts/install_publication_control_observer.py --install
```

Agent: `com.serlest.uac.publication-control`. Logs: `build/publication-control-observer/`. It runs independently of the Codex turn after user login. Report synchronization requires this Mac to be awake and connected; the UI shows last synchronization and stale results. Publication indexing itself runs on the server. No new model calls or paid external subscription is required.

## Migration

`functions/scripts/publicationControlBackfill.mjs` previews the migration. `--apply` creates missing recent metadata records with source-version preconditions, archives unsupported legacy queue states and fills missing receipt retention dates. The original 97 planning documents are backed up locally before migration; existing linked publications and media are preserved. Completed legacy receipts retain the existing six-month retention policy. No automatic publication or bulk media deletion is part of migration.

## Verification

- `node --test functions/scripts/publicationControlSync.test.mjs`
- `npm --prefix functions run test:publication-control:integration`
- iOS: `PublicationControlTests`, `PublicationControlUITests`
- Verify deployed source and compiled helpers, read back index totals and source summaries, verify the local observer using an ignored filesystem probe, and check TTL state. Never insert fake production reports or publications for testing.
