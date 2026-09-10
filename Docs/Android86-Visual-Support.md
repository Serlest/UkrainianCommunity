# Android 86 visual registry: announcements and support

Scope: Android UI only. No backend, authorization, iOS, role, schema, publishing, or support mutation changes. Source inspection covers the complete four UI files named below. This registry is not runtime proof.

## Verification status

| Evidence | Status |
|---|---|
| Full source inspection of AnnouncementUi.kt, FeedbackUi.kt, FeedbackInboxUi.kt, FeedbackCaseContextUi.kt | PASS |
| Pinned ktfmt 0.64 parsing/formatting of edited Kotlin | PASS |
| git diff --check | PASS |
| Compilation, component tests, screenshot execution | NOT VERIFIED — coordinator owns Gradle/AVD |
| Pixel review on real devices / large font / production data | NOT VERIFIED |

## Implemented design changes

Announcement editor now has six separate cards: Ukrainian text, German text, recipients, regions, delivery, review/publication. Each card has a semantic icon heading. Recipient group identifiers are translated; region names use existing region labels. History items are cards with title, localized lifecycle status, actions, and statistics. Empty history and empty person-search results have explicit explanations. Preview titles use title typography. Existing review, publication confirmation, and callbacks are preserved.

Support filters/search form one card; search has a leading icon. Status is a compact badge on list items and details. Replies are grouped in a dedicated card with heading, full-width submit/close controls, and existing pending/retry protection. Empty results have a card. Case fields remain selectable plain text and retain their existing access checks and screenshot protection.

## Complete branch inventory

All runtime rows below remain **NOT VERIFIED** until coordinator execution and image review. “Added” means a populated synthetic screenshot scenario exists in `Build86SupportVisualUiTest`; it does not mean it passed.

### Announcements: owner management

| Branch | Source/changes | Added visual scenario |
|---|---|---|
| Initial list, new action, populated history | Heading, cards, translated status | de/light + uk/dark |
| Empty list, failure, saved notice, loading, pagination | Existing state semantics preserved; empty explanation/error color | Empty/offline + populated pagination; loading/notice source-inspected |
| Ukrainian title/body and translation action | Card, heading, existing fields unchanged | Populated first screen |
| German title/body and reverse translation action | Card, heading | Populated language card |
| Translation confirmation/editor | Shared ContentTranslationButton unchanged | Existing AnnouncementUiTest covers apply flow; runtime NOT VERIFIED |
| Recipient groups | Localized labels, same wire values | Populated recipient card |
| Specific users: open, search, selected states, no matches, next page, close | Dialog spacing, empty state, stable tags | Picker populated and no matches |
| Region selection, empty means all Austria | Region display labels, same keys | Populated region card |
| Start date/time and end date/time | Existing native pickers, stable button tags | Both date/time dialogs opened; time cancel avoids mutations |
| iOS/Android targets | Existing controls inside delivery card | Populated delivery card |
| Acknowledgement, feedback, push options | Existing callbacks/conditions preserved | Populated delivery card |
| Review checkbox and draft save/test/preview/publish | Release card, explicit save label | Release card and enabled publish after review |
| Preview dialog: both languages and audience summary | Title hierarchy | Protected-dialog Compose capture |
| Publish confirmation and cancel | Existing confirmation preserved | Open + cancel; asserts publish callback count zero |
| Audience counters | Existing values, same source | Populated release card |
| Draft item edit; published stats/stop; expired/cancelled labels | Per-item cards, translated states | Draft/published populated + stats; other states source-inspected |
| Public history: signed in/guest push, loading/error/empty/open | Existing body retained | Existing component tests; source-inspected, runtime NOT VERIFIED |
| Popup acknowledgement/once/feedback/actions disabled | Existing protected dialog and dismiss semantics | Three popup variants in both locales |

### Support: own requests and management inbox

| Branch | Source/changes | Added visual scenario |
|---|---|---|
| Destination account/access gate | Existing authority checks unchanged | Manager denied fixture |
| Manager populated list | Status cards, unread emphasis | Populated list + rows |
| Loaded count/scope, OPEN/ANSWERED/CLOSED/UNKNOWN/ALL filters | Controls card, preserved counts/filter callbacks | Populated controls; remaining filters existing FeedbackInboxUiTest |
| Newest/oldest and query/search clear/rejected input/partial page | Search icon, preserved query handling | Populated controls/partial; rejected input existing tests |
| Empty, loading, read failure, stale retained data, invalid count, more | Existing semantics; empty card | Empty + offline with retained rows |
| Own composer: types, draft, send, pending, retry, confirmed link, not ready | Existing conditions, full-width button | Populated own composer; pending/confirmed existing FeedbackUiTest |
| Detail header: subject, status, case number, refresh/limited history | Status badge | Populated detail |
| User/support/system/legacy messages | Existing source, selectable text | Populated user + support messages |
| Older messages button | Existing limit/pagination | Populated limited conversation |
| Reply: normal / pending / unconfirmed retry / account not ready | Reply card, full-width controls | Normal/retry/account gate |
| Closed / archived / unknown read-only | Existing conditions | Closed/unknown; archived shares closed branch |
| Management ordinary close confirmation/dismiss | Existing protection, full-width entry | Open + cancel; asserts close callback count zero |
| DSA case forbids ordinary close, own decision-review link | Existing gating unchanged | Existing FeedbackCaseContextUiTest; source-inspected |
| Case details: location/explanation/basis/evidence/appeal | Existing icon heading and selectable content | All six populated fields captured |
| Case good-faith true/false; optional fields absent | Existing accurate copy retained | True and false/absent appeal |
| Case missing/malformed data | Existing warning retained | Invalid case warning |
| Case loading/error/stale session/wrong selected ID | Existing fail-closed checks retained | Existing FeedbackCaseContextUiTest; runtime NOT VERIFIED |
| FLAG_SECURE lease acquire/release | Unchanged | Existing security tests; not bypassed for screenshots |

## New screenshot harness

`Android/app/src/androidTest/java/at/uac/android/Build86SupportVisualUiTest.kt`

Six tests: supportGermanLight, supportUkrainianDark, announcementsGermanLight, announcementsUkrainianDark, popupsGermanLight, popupsUkrainianDark. Host uses real shared UacHeader, theme/background, one owner of safe insets and 16dp horizontal content padding. Light status icons are explicitly configured. Fixtures contain synthetic long bilingual copy; callbacks perform no remote operations. Screenshots go to target app cache as `build86-support-*.png`.

Protected dialogs and synthetic case-content nodes use Compose `captureToImage`; OS screenshots are never used to bypass FLAG_SECURE. Native date/time screenshots are normal platform dialogs. No test has been executed by this worker. A coordinator must inspect resulting images and record failures before treating any visual branch as accepted.

## Font100 runtime and image review checkpoint

Coordinator reported all six support tests PASS. This worker visually opened all 82 PNGs from `artifacts/android-build86/screenshots-font100/build86-support-*.png` in the Codex task directory. This does not validate production data or physical devices. The earlier NOT VERIFIED table entries remain accurate for branches not included in these six scenarios.

Reviewed in both German/light and Ukrainian/dark (41 captures per configuration):

- Announcement top, German content, audience, regions, delivery, release, draft item, published item/statistics, offline empty, preview, publish confirmation, recipient picker and no-results picker.
- Announcement start date/time, end date/time native dialogs; acknowledge, once and disabled protected popups.
- Inbox top, populated item, empty, offline retained data, denied; own populated composer.
- Conversation top, reply, retry, account gate, CLOSED, UNKNOWN and protected close confirmation.
- Case location, explanation, basis, evidence, appeal, good-faith, unconfirmed good-faith and invalid case.

Findings and follow-up edits:

- No horizontal clipping found in the captured Compose forms, buttons or protected dialogs. Scroll-boundary cuts at the fixed header and bottom are viewport boundaries, not lost content; per-section captures demonstrate access.
- Native pickers used system English and light colors in Ukrainian/dark. Fixed with explicitly localized configuration context and light/dark native dialog theme. Date button labels now use app locale, medium date and short time, without seconds/English AM.
- Audience preview exposed `registered`; changed to existing localized group labels. Checkbox rows now have an 8dp text gap.
- Native start-date-uk contained an incomplete draw; end-time-uk captured the previous calendar. Added native accessibility-idle synchronization before screenshots. These two artifacts are reviewed but NOT acceptable visual evidence; require recapture.
- Case field crops verify wrapping only, not whole-card composition. Added full-root companion screenshots at each scrolled field for next runtime.

Not covered/accepted yet: font200; post-fix native locale/theme and draw capture; whole case-card composition; keyboard-visible forms; loading/pending actions; real role/session transitions; actual publish/stop/send/close effects; physical-device/TalkBack. No mutation callbacks were exercised by visual fixtures. Follow-up source parsed/formatted with pinned ktfmt; Gradle/AVD were not run by this worker.

## Font100 attempt3 follow-up

Coordinator reports 34/34 matrix PASS, including support 6/6, lint PASS and 1950 unit tests PASS. Reviewed all 30 changed/new screenshots in `screenshots-font100-attempt3`: audience, delivery, regions, release, preview; start/end native date/time; case-layout location/explanation/basis/evidence/appeal/good-faith, each in DE/light and UK/dark.

Accepted at font100: checkbox spacing, localized date-button format, localized preview groups, full case-card hierarchy and wrapping, native dark/light theme, calendar month/day grid/button localization, complete native window drawing. All 12 full case-layout captures show readable complete cards without clipping. Earlier incomplete native drawing artifacts are superseded by attempt3.

Residual minor localization issue: the native DatePicker selected-date header still displays the process-language abbreviated weekday/month (`Thu, Sep`) while its calendar and buttons correctly use DE/UK. This platform-owned header has no public locale setter; no process-global locale mutation or private view-ID/reflection workaround was introduced. Date selection remains readable in the localized grid and date-button label. Font200, keyboards, physical-device and remote-action gates remain unverified here.

## Font200 attempt1 visual review

Coordinator reports support 6/6 PASS. This worker opened and visually reviewed **all 94** `build86-support-*.png` in `artifacts/android-build86/screenshots-font200-attempt1`: all 41 paired captures listed above plus six paired full-root case-layout captures (location, explanation, basis, evidence, appeal, good-faith).

Compose review PASS for captured content: announcement form sections and action rows, history items, recipient search/results, protected preview/publish/popups, support filters/results/empty/offline/denied, own composer, conversation/reply/retry/read-only/account-gate/close dialog, all case text and card composition. Text wraps; buttons remain reachable through scrolling; long bilingual text does not overflow horizontally. A clipped adjacent item at a scroll viewport edge is not content loss. Preview has a scrollable body with a persistent close button. Keyboard-open states remain NOT VERIFIED.

Native calendar grid and action buttons fit at 200%; the previously noted selected-header locale limitation remains. **Native clock dial visual FAIL:** inner 24-hour numerals crowd/overlap at 200%. Implemented a scoped platform spinner theme only for announcement time dialogs at fontScale >= 1.5 (`announcement_picker_styles.xml`, `AnnouncementDateTimeButton`). Light/dark styling, localized context, 24-hour selection and callbacks are preserved; smaller font sizes retain the original clock. No global font/locale override or private API. This final fallback requires coordinator compilation/runtime/recapture before acceptance; pre-fix time screenshots are not accepted evidence.

Still not covered: keyboard-visible editing, loading/pending action states, physical-device/TalkBack, real role/session changes and remote publish/stop/send/close outcomes. Visual fixtures have no remote mutation callbacks. Worker did not run Gradle or AVD.

## Font200 attempt2 picker acceptance

Coordinator reports the latest matrix **34/34 PASS**. Visually reviewed all eight native picker captures in `screenshots-font200-attempt2`: announcement start-date, end-date, start-time and end-time, each DE/light and UK/dark. All four time windows now show correctly separated hour/minute spinner columns, complete selected/adjacent values and unobstructed localized Cancel/OK buttons. No overlap or clipping remains. Both light and dark themes are correct. All four calendar windows and visible date-button labels remain readable without layout regression; the documented platform selected-header language limitation is unchanged.

The large-font time-picker visual defect is **PASS / resolved** on this emulator configuration. Attempt1 clock screenshots are superseded by attempt2. Normal-font native controls were previously accepted in font100 attempt3; the spinner branch activates only at >=150%. Physical-device, keyboard editing, TalkBack and remote-action gates remain separate and unverified by this visual review.
