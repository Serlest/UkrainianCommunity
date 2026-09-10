# Android 86 — content management visual audit

Scope: featuredmanagement, contentplanning, and the authoring / cover / gallery / lifecycle UI reached through content work. Read the six complete UI files (4,524 lines before edits), their state models and existing UI fixtures. Android UI only; no backend, iOS, security rules or service-contract changes. Runtime status for every row below: **NOT VERIFIED** until the coordinator builds, runs and inspects PNGs.

## Exact UI tree and states

### Recommended banners / FeaturedManagementScreen

- List: explanation, create, refresh, loading, empty, populated image cards, repair-required warning, priority/section metadata.
- Card: edit; active/inactive (mutation semantics unchanged); delete -> inline confirm/cancel.
- Create/edit: internal name; Ukrainian title/subtitle; German title/subtitle; translation action (shared translation UI); image URL and 16:9 preview; system photo picker / uploading; action selector.
  - No action.
  - News, event, organization: target identifier field.
  - External link: URL field.
- Placement: home/events/organizations multi-select; Austria/federal-state scope; federal-state dropdown.
- Priority; duration; activate-after-save checkbox; save validity/disabled/saving; cancel.
- Back while editing -> protected discard dialog, close/continue.
- Failure card: access/invalid/image/missing/conflict/offline/unconfirmed/busy; unconfirmed offers status refresh, no implicit retry.
- The existing start/end scheduling fields in the model are not edited by this UI. This audit does not introduce a scheduling feature.

### Content planning / ContentPlanningContent

- Four list sections: drafts, scheduled, attention, history; loading, loaded-empty, populated, pagination/loading-more, denied, error/retry, recovery.
- Seven item states: READY, ATTENTION, SCHEDULED, PUBLISHING (including expired lease), FAILED, COMPLETED, ARCHIVED.
- Detail: title/kind/state; scheduled time when present; missing fields; verification notes; source links; failure message; recovery/error.
- Publishable detail: organization loading / none available / named choices -> explicit selection -> review and publish opens authoring via existing callback.
- Archive -> confirmation/cancel. Delete -> confirmation/cancel. Completed -> open published content callback.
- Recovery phases: BEGIN_UNCONFIRMED, LEASED, FINALIZE_UNCONFIRMED, FAIL_UNCONFIRMED, ARCHIVE_UNCONFIRMED, DELETE_UNCONFIRMED. Read-only reconciliation always; same-operation retry only in existing allowed phases.
- Source links open the OS handler. External browser styling is outside app layout ownership.

### Authoring / AuthoringContent

- Hub: organization identity, refresh, kinds news/events, status dropdown (published/review/rejected/archived/scheduled), create, empty/page-more, populated card.
- Item actions: view, edit, cover, lifecycle; read-only label when editing unavailable.
- Recovered local draft: continue, delete -> confirm. Storage failure and unsaved-exit recovery actions.
- New/edit/imported planning draft:
  - Text: Ukrainian title/summary/body; translation; optional German title/summary/body.
  - Details: category dropdown; up to two additional checkbox categories; tags; news-only regional scope and source; link title/URL.
  - Event dates: city/venue/address/location note; timezone; occurrence cards; all-day; start date/time; known-end toggle and end date/time; add/remove occurrence.
  - Event participation: registration mode (none/in-app/external registration/tickets), conditional capacity; price mode (unspecified/free/exact/from/range) and conditional amounts; price note; audience; min/max age; organizer and contact fields.
  - New-only publication settings: now/scheduled; scheduled date/time, timezone, validation.
- Date picker and time picker protected dialogs; invalid DST local time state.
- Preview dialog; publish/save/review confirmation dialog; leave form dialog; discard local text dialog; delete recovered draft dialog.
- Read-only/stale form, busy, confirmed, uncertain, recovery checked/conflict/absent, expired pending schedule and errors preserve their existing behavior.

### Cover / ContentCoverContent

- Account-required; loading/picker-open/preparing/busy; selected content; error/read-only.
- Prepared image preview and dimensions; current image; existing image unavailable; stale selection warning.
- Choose system photo; prepared -> save/discard; existing news cover -> remove linkage. Event cover removal is not offered.
- Upload/remove confirmation dialogs; pending leave dialog; confirmed; unconfirmed/reconcile/unresolved.

### Gallery / GalleryContent

- Account-required; refresh/loading/locked; denied/stale organization; confirmed; empty/overflow/populated.
- Selection editor: decoded preview, caption/count/error, choose, publish or replace, discard.
- Photo card: public image only for approved organization; caption; authorized file preview; replace when allowed; delete.
- Protected dialogs: upload, replace, remove, orphan-file cleanup, decoded file viewer, leave.
- Pending operation entries -> reconcile; unresolved; cleanup-available -> explicit cleanup confirmation.
- Gallery access is an organization route, not a direct planning action; retained in this audit because it is part of nested organization/content editing. No new navigation was added.

### Lifecycle / ContentLifecycleContent

- News deletion and event cancellation variants.
- Account-required; selected organization/content; error/loading/busy/stale/read-only/missing.
- Consequence explanation and destructive request action -> protected confirm/cancel.
- Uncertain result -> reconcile, observed unchanged/unavailable/cancelled/different; leave warning.
- Confirmed deleted/cancelled result.

## Defects and implemented presentation changes

1. Banner controls exposed raw wire values (`externalURL`, section identifiers, region scope). Replaced with localized labels while retaining wire values/callbacks.
2. Banner language fields lacked clear group boundaries. Added common section cards; retained both languages and translation flow.
3. Banner selectors formed long unstructured stacks. Added wrapping groups with consistent spacing. Federal state now selects a named state instead of requiring memorized backend codes.
4. Banner footer split two long actions into narrow equal columns. Stacked full-width save/cancel controls.
5. Planning long source titles used compact chips with little reading room. Replaced with multiline navigation rows and explicit primary/additional-source captions.
6. Scheduled planning detail omitted its scheduled time although the list showed it. Added a dedicated schedule card.
7. Organization choices in planning had inconsistent narrow widths. Full-width chips retain explicit single selection.
8. Authoring dropdowns sized to arbitrary selected text and presented label/value as one long line. Full-width two-line field-like buttons now separate field name from selection.
9. Event participation was a flat form. Added registration, cost, audience and organizer/contact headings; age fields stack to preserve usable width with larger fonts.
10. Authoring heading now distinguishes create/edit from the hub. All route guards and validation remain unchanged.
11. Cover actions had competing wrapping widths. Stacked full-width choose/save/remove actions, destructive remove tint.
12. Gallery remove and planning delete now have destructive tint. Lifecycle target identity is in a separate selection card rather than mixed into consequence text.

## New visual tests and evidence status

`Build86ContentVisualUiTest` contains paired Ukrainian/dark and German/light tests:

- Planning: every list state and detail state, organization selection, archive/delete dialogs, every recovery phase.
- Authoring: news/event hub, each editor section, preview, submission confirmation, recovery and leave; separate date/time dialog tests.
- Cover/lifecycle: news/event preview/actions, upload confirmation, news-only removal confirmation, reconciliation; deletion/cancellation target/actions/confirmation/recovery/leave/confirmed.
- Gallery: populated private gallery, prepared JPEG, caption/actions, upload/replace/delete/cleanup dialogs, decoded viewer, leave.
- Featured: populated list, inline delete confirmation, both language sections, media selector, each action branch, each placement option, region, priority, duration, footer and editor-leave dialog.

The host reproduces shared compact header, root 16dp inset, safe drawing insets and light/dark system bar icon appearance. Captures use the last Compose root (including protected dialog roots), with an explicit displayed assertion before `captureToImage`; filenames start `build86-content-` in app cache. No live service mutations. Prepared media uses actual generated JPEG bytes; separate Build85 image-pipeline tests remain responsible for HTTP media proof.

Validation performed here: pinned ktfmt and `git diff --check`. **No Gradle, emulator, screenshot capture or test execution by this worker.** Every runtime outcome remains NOT VERIFIED. A PNG file produced by a future test run still requires human/model visual inspection before visual PASS.

Remaining coverage caveats: system photo picker and shared translation dialogs are external/shared UI; recovery error variants with the same layout are inventoried but not every enum receives a separate screenshot. Runtime screens may reveal further density problems; coordinator should inspect all generated pages before release, including 2x font follow-up where relevant. No claim of release readiness is made by this source audit.

## Attempt 2 runtime review (font 100)

### Attempt 3 follow-up

### Font 200 attempt 1 review

### Font 200 attempt 2: corrected dialog capture

### Final font 100 review

Coordinator reports all 34 final matrix tests PASS. Final dialog/preview/viewer screenshots reviewed in `screenshots-font100-final-content-review`, labelled sheets 01, 03, 04, 05, 07, 10, 12, 13, 14, 16, 18. All reviewed dialogs now faithfully show their content and controls; no blocking clipping or overlaps found. The shorter Ukrainian edit action is fully visible, standard-size time dial remains legible, and planning missing-field labels are localized. This closes the prior font100 dialog-capture evidence gap. The latest font200 changes are verified in the final review below. No production/device or remote-function readiness claim follows from these offline UI fixtures.

### Final font 200 review

Coordinator reports **165/165 PASS** (34 visual tests and 131 regression tests) on the final APK. Individually inspected these final images in `/Users/serlest/Documents/Codex/2026-09-09/82-82/artifacts/android-build86/screenshots-font200-final/`:

- `build86-content-authoring-time-picker-de-light.png`
- `build86-content-authoring-time-picker-uk-dark.png`
- `build86-content-authoring-leave-EVENTS-de-light.png`
- `build86-content-authoring-leave-EVENTS-uk-dark.png`
- `build86-content-authoring-leave-NEWS-de-light.png`
- `build86-content-authoring-leave-NEWS-uk-dark.png`

**Visual PASS for all six final captures:** hour/minute inputs and labels are readable, time-dialog actions remain fully visible, and numerals no longer overlap. Both locales' event/news leave dialogs show complete text and fully visible actions with bottom padding. The shortened Ukrainian edit action does not clip. These are faithful dialog captures, not cropped Activity backgrounds. This closes the two presentation defects identified in font200 attempt 2; earlier pending rerun statements below are historical. No sources changed during this final review. Emulator fixture evidence does not establish physical-device, production-backend, or release readiness.

Coordinator reports 34 matrix tests PASS. Reviewed all regenerated dialog/preview/viewer captures in labelled sheets 01, 03, 04, 05, 07, 10, 12, 13, 14, 16, 18 of `screenshots-font200-attempt2-content-review`. Capture now faithfully contains each dialog rather than Activity background. Archive/delete, cover, gallery cleanup/upload/replace/delete/leave/viewer, featured leave and lifecycle dialogs have readable controls at 200%; authoring preview is explicitly scrollable. Localized planning missing fields verified on ATTENTION detail. Two real presentation defects became visible: 24h TimePicker numerals overlap at 200%, and Ukrainian authoring leave action wraps against the bottom edge. Switched to Material TimeInput at fontScale >=1.5 using the same state and shortened that action to “Редагувати далі”. Both latest changes require rerun, not yet visual PASS. Updated legacy planning assertion to localized label, preserving exact count; added unknown server-message preservation assertion.

Coordinator reports all 12 content tests PASS. All 188 content PNGs were reviewed using every filename-labelled contact sheet 01–24 in `screenshots-font200-attempt1-content-review`. All dialog/picker/viewer/preview captures affected by the old root selection are excluded from visual acceptance. Non-dialog pages retain readable wrapping and scroll access: banner selection chips wrap, footer actions remain full-width; authoring participation/age controls stack; media and gallery actions wrap; planning organization/action controls remain legible; lifecycle consequences and confirmation-result text wrap. No additional blocking non-dialog overlap was found. Long content legitimately extends beyond the scroll viewport, not beneath a fixed bottom bar. Horizontal planning tabs remain horizontally scrollable, as before.

Known missing-field identifiers in planning list/detail are now localized at presentation only (including German text, venue, address, dates, contact fields); unrecognized fields or server prose remain unchanged. This latest label patch still requires rebuilt runtime verification. Font 200 dialog visual acceptance remains NOT VERIFIED pending corrected capture rerun.

Coordinator reports all 34 matrix tests PASS. Targeted fresh review covered contact sheets 01, 02, 04, 11, 15, 16, and 19–24 under `screenshots-font100-attempt3-content-review` (each sheet names its source PNGs). Event editor and lifecycle-complete contamination is gone; featured state now shows the named Tirol selector. Planning scheduled/completed/failed/publishing/ready/attention lists, details, organization selection and recovery pages are populated and readable at font 100. ATTENTION missing-field descriptions still expose raw `germanBody` / `venue` identifiers (presentation follow-up identified).

**Screenshot evidence defect found despite test PASS:** dialog captures show cropped Activity background rather than the dialog (authoring confirm/preview, date picker, lifecycle confirm/leave). `onAllNodes(isRoot()).onLast()` is not window z-order. Helper now selects `isDialog()` explicitly, rejects stacked dialogs, otherwise selects the single root, and asserts visibility before capture. FLAG_SECURE unchanged. These dialog images remain NOT VERIFIED until rerun. Attempt 3 is therefore not a blanket visual PASS. No further runtime was run by this worker.

Coordinator ran the tests; this worker reviewed all 142 generated content PNGs via 18 filename-labelled contact sheets, with an individual enlargement of `build86-content-authoring-editor-EVENTS-3-uk-dark.png`. Reviewed files are listed below. This is contact-sheet visual review, not a claim of full-resolution inspection of every file.

Four tests failed: both planning and both picker locales. Cause: directly invoking Activity back dispatcher bypassed the dialog window, closing planning detail or finishing picker host Activity. Test now clicks the actual localized Cancel action and asserts dialog disappearance plus retained detail/host. No assertion was weakened.

Visual inspection also detected false-positive capture contamination: authoring EVENT pages retained the prior leave dialog, and lifecycle-complete retained its leave dialog. Both now dismiss through Continue editing / Stay here and assert dialog absence before continuing. These images are NOT visual PASS; they must be regenerated. Planning states beyond READY and time picker images were not generated and remain NOT VERIFIED.

The remaining generated cover/gallery, featured, planning READY and uncontaminated authoring/lifecycle layouts showed no blocking content overlap at font 100. Long forms remain scrollable; selected JPEG previews render. Featured unavailable-image fixture is not HTTP image proof. Some dialog/recovery screenshots show system icon contrast inconsistent with theme: fixture window restoration needs coordinator verification. Runtime featured state still shows raw `tirol`; the source dropdown change needs a rebuilt APK and fresh capture. No blanket visual or release PASS.

### Reviewed filenames

```text
build86-content-authoring-confirm-EVENTS-de-light.png
build86-content-authoring-confirm-EVENTS-uk-dark.png
build86-content-authoring-confirm-NEWS-de-light.png
build86-content-authoring-confirm-NEWS-uk-dark.png
build86-content-authoring-date-picker-de-light.png
build86-content-authoring-date-picker-uk-dark.png
build86-content-authoring-editor-EVENTS-0-de-light.png
build86-content-authoring-editor-EVENTS-0-uk-dark.png
build86-content-authoring-editor-EVENTS-1-de-light.png
build86-content-authoring-editor-EVENTS-1-uk-dark.png
build86-content-authoring-editor-EVENTS-2-de-light.png
build86-content-authoring-editor-EVENTS-2-uk-dark.png
build86-content-authoring-editor-EVENTS-3-de-light.png
build86-content-authoring-editor-EVENTS-3-uk-dark.png
build86-content-authoring-editor-NEWS-0-de-light.png
build86-content-authoring-editor-NEWS-0-uk-dark.png
build86-content-authoring-editor-NEWS-1-de-light.png
build86-content-authoring-editor-NEWS-1-uk-dark.png
build86-content-authoring-leave-EVENTS-de-light.png
build86-content-authoring-leave-EVENTS-uk-dark.png
build86-content-authoring-leave-NEWS-de-light.png
build86-content-authoring-leave-NEWS-uk-dark.png
build86-content-authoring-list-EVENTS-de-light.png
build86-content-authoring-list-EVENTS-uk-dark.png
build86-content-authoring-list-NEWS-de-light.png
build86-content-authoring-list-NEWS-uk-dark.png
build86-content-authoring-preview-EVENTS-de-light.png
build86-content-authoring-preview-EVENTS-uk-dark.png
build86-content-authoring-preview-NEWS-de-light.png
build86-content-authoring-preview-NEWS-uk-dark.png
build86-content-authoring-recovery-EVENTS-de-light.png
build86-content-authoring-recovery-EVENTS-uk-dark.png
build86-content-authoring-recovery-NEWS-de-light.png
build86-content-authoring-recovery-NEWS-uk-dark.png
build86-content-cover-actions-EVENTS-de-light.png
build86-content-cover-actions-EVENTS-uk-dark.png
build86-content-cover-actions-NEWS-de-light.png
build86-content-cover-actions-NEWS-uk-dark.png
build86-content-cover-preview-EVENTS-de-light.png
build86-content-cover-preview-EVENTS-uk-dark.png
build86-content-cover-preview-NEWS-de-light.png
build86-content-cover-preview-NEWS-uk-dark.png
build86-content-cover-recovery-EVENTS-de-light.png
build86-content-cover-recovery-EVENTS-uk-dark.png
build86-content-cover-recovery-NEWS-de-light.png
build86-content-cover-recovery-NEWS-uk-dark.png
build86-content-cover-remove-dialog-NEWS-de-light.png
build86-content-cover-remove-dialog-NEWS-uk-dark.png
build86-content-cover-upload-dialog-EVENTS-de-light.png
build86-content-cover-upload-dialog-EVENTS-uk-dark.png
build86-content-cover-upload-dialog-NEWS-de-light.png
build86-content-cover-upload-dialog-NEWS-uk-dark.png
build86-content-featured-action-event-de-light.png
build86-content-featured-action-event-uk-dark.png
build86-content-featured-action-externalURL-de-light.png
build86-content-featured-action-externalURL-uk-dark.png
build86-content-featured-action-news-de-light.png
build86-content-featured-action-news-uk-dark.png
build86-content-featured-action-none-de-light.png
build86-content-featured-action-none-uk-dark.png
build86-content-featured-action-organization-de-light.png
build86-content-featured-action-organization-uk-dark.png
build86-content-featured-delete-confirm-de-light.png
build86-content-featured-delete-confirm-uk-dark.png
build86-content-featured-duration-de-light.png
build86-content-featured-duration-uk-dark.png
build86-content-featured-image-pick-de-light.png
build86-content-featured-image-pick-uk-dark.png
build86-content-featured-internal-name-de-light.png
build86-content-featured-internal-name-uk-dark.png
build86-content-featured-leave-editor-dialog-de-light.png
build86-content-featured-leave-editor-dialog-uk-dark.png
build86-content-featured-list-de-light.png
build86-content-featured-list-uk-dark.png
build86-content-featured-priority-de-light.png
build86-content-featured-priority-uk-dark.png
build86-content-featured-save-de-light.png
build86-content-featured-save-uk-dark.png
build86-content-featured-section-events-de-light.png
build86-content-featured-section-events-uk-dark.png
build86-content-featured-section-home-de-light.png
build86-content-featured-section-home-uk-dark.png
build86-content-featured-section-organizations-de-light.png
build86-content-featured-section-organizations-uk-dark.png
build86-content-featured-state-de-light.png
build86-content-featured-state-uk-dark.png
build86-content-featured-title-de-de-light.png
build86-content-featured-title-de-uk-dark.png
build86-content-featured-title-uk-de-light.png
build86-content-featured-title-uk-uk-dark.png
build86-content-gallery-caption-actions-de-light.png
build86-content-gallery-caption-actions-uk-dark.png
build86-content-gallery-cleanup-de-light.png
build86-content-gallery-cleanup-dialog-de-light.png
build86-content-gallery-cleanup-dialog-uk-dark.png
build86-content-gallery-cleanup-uk-dark.png
build86-content-gallery-delete-dialog-de-light.png
build86-content-gallery-delete-dialog-uk-dark.png
build86-content-gallery-leave-dialog-de-light.png
build86-content-gallery-leave-dialog-uk-dark.png
build86-content-gallery-list-de-light.png
build86-content-gallery-list-uk-dark.png
build86-content-gallery-replace-dialog-de-light.png
build86-content-gallery-replace-dialog-uk-dark.png
build86-content-gallery-selected-de-light.png
build86-content-gallery-selected-uk-dark.png
build86-content-gallery-upload-dialog-de-light.png
build86-content-gallery-upload-dialog-uk-dark.png
build86-content-gallery-viewer-de-light.png
build86-content-gallery-viewer-uk-dark.png
build86-content-lifecycle-action-EVENTS-de-light.png
build86-content-lifecycle-action-EVENTS-uk-dark.png
build86-content-lifecycle-action-NEWS-de-light.png
build86-content-lifecycle-action-NEWS-uk-dark.png
build86-content-lifecycle-complete-EVENTS-de-light.png
build86-content-lifecycle-complete-EVENTS-uk-dark.png
build86-content-lifecycle-complete-NEWS-de-light.png
build86-content-lifecycle-complete-NEWS-uk-dark.png
build86-content-lifecycle-confirm-EVENTS-de-light.png
build86-content-lifecycle-confirm-EVENTS-uk-dark.png
build86-content-lifecycle-confirm-NEWS-de-light.png
build86-content-lifecycle-confirm-NEWS-uk-dark.png
build86-content-lifecycle-leave-EVENTS-de-light.png
build86-content-lifecycle-leave-EVENTS-uk-dark.png
build86-content-lifecycle-leave-NEWS-de-light.png
build86-content-lifecycle-leave-NEWS-uk-dark.png
build86-content-lifecycle-recovery-EVENTS-de-light.png
build86-content-lifecycle-recovery-EVENTS-uk-dark.png
build86-content-lifecycle-recovery-NEWS-de-light.png
build86-content-lifecycle-recovery-NEWS-uk-dark.png
build86-content-lifecycle-target-EVENTS-de-light.png
build86-content-lifecycle-target-EVENTS-uk-dark.png
build86-content-lifecycle-target-NEWS-de-light.png
build86-content-lifecycle-target-NEWS-uk-dark.png
build86-content-planning-archive-dialog-de-light.png
build86-content-planning-archive-dialog-uk-dark.png
build86-content-planning-detail-READY-de-light.png
build86-content-planning-detail-READY-uk-dark.png
build86-content-planning-list-READY-de-light.png
build86-content-planning-list-READY-uk-dark.png
build86-content-planning-organization-READY-de-light.png
build86-content-planning-organization-READY-uk-dark.png
```
