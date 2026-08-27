# Content Editor V2 execution plan

## Scope boundary

Implement and release the public news and event editor expansion. Stop before the
owner-only semi-automatic `Чернетки / Майбутні / Потребують уваги` workflow.

Baseline rollback tag: `checkpoint/build-37-pre-content-editor-v2-20260826`

## Non-negotiable product rules

- Ukrainian content is required. German content is optional and falls back to Ukrainian.
- Ukrainian Community never sells tickets, processes payments, charges commission, or handles refunds.
- Paid events expose informational pricing and an HTTPS link to the organizer or ticket provider.
- Existing editors and published-content components are reused; preview must render the real components.
- Existing records and build 37 remain readable throughout rollout.
- Organization and application role boundaries must not expand.

## Delivery checklist

### 0. Baseline and audit

- [x] Tag and push the build 37 rollback point.
- [x] Capture local Rules/index hashes and production Function/Rules inventory.
- [x] Map model, DTO, repository, editor, detail/list, localization, Rules, Functions, indexes, and tests.
- [x] Record production compatibility constraints and preserve the legacy field contract.

### 1. Backward-compatible domain model

- [x] Add versioned Ukrainian/German localized text values with Ukrainian fallback.
- [x] Add concrete event occurrences for single and multi-date schedules with independent times.
- [x] Preserve legacy `startDate`/`endDate` and derive the overall boundary from occurrences for old clients.
- [x] Add participation mode: none, in-app registration, external registration, external tickets.
- [x] Add informational price kind: unspecified, free, exact, from, range.
- [x] Add bounded external HTTPS action metadata.
- [x] Add news source/action/media metadata without arbitrary HTML.
- [x] Add focused pure-model and decoding compatibility tests.

### 2. Event editor and presentation

- [x] Keep the existing editor shell and progressive steps.
- [x] Add optional German fields without losing unsaved values.
- [x] Add intuitive date/occurrence creation and removal with independent date, time, and all-day values.
- [x] Separate in-app registration from external registration/ticket links.
- [x] Add real list-card preview using the production component.
- [x] Display the next active occurrence and the complete schedule consistently.
- [x] Update filters, calendar export, editing/copying, reminders, cancellation, and notification semantics.

### 3. News editor and presentation

- [x] Keep the existing three-step editor and shared visual language.
- [x] Add optional German title/summary/body with Ukrainian fallback.
- [x] Add source attribution, image caption/alt/credit, and an optional external action without arbitrary HTML.
- [x] Add real list-card preview using the production component.
- [x] Preserve existing comments, likes, bookmarks, moderation, and analytics behavior.

### 4. Firebase contracts

- [x] Extend strict Firestore top-level schemas with optional v2 fields while staying below the Rules expression limit.
- [x] Preserve organization/author/moderation immutability and role separation.
- [x] Reuse the existing image path; no Storage expansion is needed.
- [x] Adjust Functions so nested schedule and publishing changes produce meaningful notifications.
- [x] Avoid new query shapes, so no new index is required.
- [x] Test old writes, new writes, forbidden extra fields, forged identity, and relevant roles.

### 5. Verification and rollout

- [x] Run focused model/editor and Firestore contract tests.
- [x] Run all Function unit tests and Firestore/Storage Rules tests.
- [x] Run isolated Debug and Release builds.
- [ ] Verify Simulator UI in Ukrainian/German, Dynamic Type, VoiceOver, portrait, and landscape.
- [ ] Verify a physical device separately.
- [x] Deploy backward-compatible Functions/Rules only after explicit preflight evidence; no index change was required.
- [ ] Verify build 37 against the updated backend before uploading the next TestFlight build.
- [x] Commit logical checkpoints; push them before any production deployment.

## Rollback rules

- Never remove legacy fields during this project.
- Do not mass-migrate production content.
- Roll back iOS from the baseline tag or a focused revert.
- Roll back Functions individually using the recorded baseline hashes/source commit.
- Roll back Rules to the recorded production ruleset; read back and verify after deployment.
- Extra indexes may remain because they do not mutate content.
- New documents always dual-write Ukrainian legacy fields so build 37 can render them.

## Production rollout evidence

- Firebase project: `ukrainiancommunity-dbd5f`.
- Functions deployed in `europe-west3`: `cancelEvent`, `notifyEventUpdatedOnUpdate`, and `notifyEventCancelledOnDelete`.
- Active Firestore ruleset: `5e0f7b6c-e530-4dd4-9fdb-2a5928c8e440`.
- Active/local Firestore Rules SHA-256: `ea74d25a1a433c4d271ae0878a187c7bf8d853e2a46d95c99d2564f09a7b4f4d`.
- No Storage Rules, indexes, hosting, production documents, or unrelated Functions were changed.
