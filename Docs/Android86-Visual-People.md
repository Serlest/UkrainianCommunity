# Build 86 — People, content moderation and organization review

Scope: Android UI only. Firebase/iOS/rules/repositories unchanged. Final synthetic visual matrix: **PASS at font 100 and 200**, Ukrainian/dark and German/light, all 10 people scenarios. Real-account/backend and physical-device verification remain **NOT VERIFIED** by this worker. Detailed evidence and exclusions follow below.

## Complete route and presentation tree

| Root | Branch | Static review / change | Screenshot fixture |
| --- | --- | --- | --- |
| `profile/users` | Search, loaded-result filters, count/cap/pagination | Clear search guidance; profile-shaped cards replace rounded multiline buttons | populated list, row; filters/pagination retain existing tests |
| users | Empty / loading / offline / denied | Existing gated states retained; no private rows on access denial | empty/offline/denied; loading remains existing test coverage |
| users → person | Identity, contact, region, role/status, warnings, dates | Identity appears before controls; long machine ID moved after readable profile facts | detail |
| person → authentication | Verified email, disabled auth, created/last login, providers, unavailable auth | Existing clear label/value layout retained | security |
| person → presence | Online/offline, last seen, loading/error/refresh | Separate card retained | presence fixture; refresh/error behavior existing suite |
| person → legal evidence | Terms/privacy/minimum-age/organization/analytics-granted/analytics-withdrawn records, source/date, version/locale/platform/checksum, search | Record title and timestamp emphasized; label/value lines instead of dense strings | all six recognized populated record variants |
| legal evidence | Owner denial / loading / failure + retry / empty / no search matches | Read and preserved existing guards and states | existing checks; runtime NOT VERIFIED |
| person → status | Current state, unavailable actions, stale/reload | Grouped management after profile/security/presence, readable card | actions/stale |
| status → WARN | Identity, effect, required reason, confirmation/cancel | Identity grouped in card; effect prominent | top and confirm, both languages |
| status → SUSPEND | Identity, effect, duration choices, calendar zone, reason, confirmation/cancel | Same composition; complete scrolling preserved | top and confirm, both languages |
| status → BAN | Identity, permanent restriction effect, reason, confirmation/cancel | Same composition | top and confirm, both languages |
| status → DEACTIVATE | Identity, effect, reason, confirmation/cancel | Same composition | top and confirm, both languages |
| status → RESTORE | Restricted target, restored access effect, reason, confirmation/cancel | Same composition | top and confirm, both languages |
| status outcomes | Journal unavailable; unresolved record/reconcile; success/failed attempt; busy; rejected/empty reason | Existing no-retry and busy guards retained | recovery, busy, rejected reason; existing outcome tests |
| person → platform role | Current role, restricted target, unverified/disabled auth eligibility | Grouped management; eligibility explanatory text retained | actions/ineligible |
| role → ASSIGN | Identity, user → administrator, effect, reason, confirmation/cancel | Identity/role transition card; prominent effect | top and confirm, both languages |
| role → REMOVE | Identity, administrator → user, effect, reason, confirmation/cancel | Same composition | top and confirm, both languages |
| role outcomes | Journal/reconciliation; attempt outcome; busy; rejected/empty reason | Existing guards retained | recovery/busy/validation; existing outcome suite |
| `profile/moderation` | Queue search, NEWS/EVENT kinds, sort choices, per-kind loading/retry/cap/empty | Type and sort separated into wrapping chip groups; consistent selected All chip | populated queue/errors/empty |
| moderation → news | Title, summary, media, body, creator/organization/publication/source/category/region/contact fields | Locale-formatted date; quieter list title hierarchy | populated detail/fields |
| moderation → event | Same plus venue/time/registration/age/price/cancellation facts | Same renderer retained for every optional field | populated detail/fields |
| news/event → APPROVE | Read-version confirmation and cancellation | Existing version guard, primary approval retained | each content kind, both languages |
| news/event → REJECT | Read-version confirmation and cancellation | Error-color rejection confirmation distinguishes its effect | each content kind, both languages |
| moderation outcomes | Pending recovery, journal error, busy, stale/access/conflict/unconfirmed/current/changed/unavailable observations | Existing atomic receipt contract unchanged | recovery; other behavior existing tests |
| `profile/organization-review` | Queue, sort, search, count/cap/loading/error/empty | Same compact queue layout | populated/errors/empty |
| organization → preview | Name, description, images, applicant, review notes, organization type, address, contact, mission, founding, social/donation fields | Existing gated private field cards retained; localized date | detail/address/contact |
| organization → APPROVE | Organization/applicant/status identity, ownership effect, confirm/cancel | Identity card and icon header | top and confirm, both languages |
| organization → REQUEST_REVISION | Identity, required message, confirm/cancel | Same hierarchy | top and confirm, both languages |
| organization → REJECT | Identity, required reason, confirm/cancel | Error-color confirm | top and confirm, both languages |
| organization outcomes | Read-only fingerprint; journal/error/reconciliation; pending; busy; invalid message | Existing callable preflight and cancellation rules retained | recovery; existing suite for busy/IME/validation |

## Evidence to run

`Build86PeopleVisualUiTest` has 10 scenarios (uk/dark and de/light for users+legal, all five status dialogs, both role dialogs, both moderation content kinds and their decisions, all three organization decisions). Every fixture is synthetic and uses no backend. Shared header, plain background, safe insets and actual status/navigation icon appearance match the app host. Files are saved to app cache as `build86-people-*.png`.

Protected dialog captures use Compose's image capture on the dialog scroll node; production secure-window behavior is not disabled. PNG creation and visual readability must be verified by the coordinator; test source is not runtime evidence.

Existing functional suites remain necessary: ManagedUsersUiTest, UserStatusUiTest, PlatformRoleUiTest, PlatformRoleHostUiTest, ModerationUiTest, ModerationDecisionUiTest, OrganizationReviewUiTest. Their privileged/backend proofs must not be inferred from the new synthetic screenshots.

Local completion: formatter parses edited Kotlin, `git diff --check` clean. No Gradle, emulator, cloud mutation, commit or release executed by this worker.

## First runtime review (font 100)

Reviewed all 88 available `build86-people-*` PNGs from `screenshots-font100`, grouped in 11 contact sheets. These are partial scenario evidence, not full-tree PASS: status and role scenarios completed; users/legal, moderation and organization each failed in both languages before their remaining screenshots. Missing branches remain NOT VERIFIED pending the next coordinator run.

The six failures were traced to: synthetic users/moderation hosts omitting the persistent screen-level BackHandler; legal evidence actually registering back only inside a disposable lazy header; and an organization APPROVE fixture carrying text although its contract requires an empty message. Persistent handlers and the fixture were corrected without weakening navigation/confirmation assertions. Legal evidence now preserves embedded toolbar back even after the header scrolls out of composition.

Visible follow-ups: optional event start/end timestamps were raw ISO and now use the existing localized formatter with raw fallback; long role/status effect explanations now use body typography rather than heading weight. No horizontal text clipping was observed in the available font-100 captures. Stale legal event/source fixture identifiers were replaced with supported values. These source follow-ups and the branches previously interrupted still require a fresh build/runtime and screenshot review. Larger-font runtime is NOT VERIFIED here.

## Attempt 3 follow-up (font 100)

Coordinator runtime `matrix-font100-attempt3.log`: all 10 people scenarios PASS (34 overall). Reviewed all 17 contact sheets from `screenshots-font100-attempt3`, including previously interrupted legal/back, both moderation decision kinds, all three organization decisions and error/empty/recovery branches. Localized event start/end dates and lighter status/role explanations are present and readable; legal record titles and sources are localized. Navigation assertions now complete. No additional material visual defect or horizontal clipping found in these captures.

The extracted directory contains four obsolete legal PNGs named `privacyAccepted` / `organizationTermsAccepted` (both locales), left from the earlier fixture; these are explicitly excluded from fresh proof. Current six supported legal-event variants are present separately. This is synthetic Compose/emulator evidence only, not real-account/backend or physical-device proof. Font 200 remains pending the coordinator's separate run and review.

## Font 200 attempt 1

Users/legal, all status actions and both platform-role actions completed (six scenarios). Moderation and organization scenarios (four) reached decisions, then failed the post-back `assertExists(moderation-search)`: at 200% the queue's lazy search is outside composition. The test now scrolls to that node and asserts displayed, preserving a stronger actual reachability check. Production code was not changed for this test issue; corrected runtime is pending.

Reviewed all 17 extracted contact sheets, counting only the visibly fresh font-200 captures. The six legal records, identity/security/presence, role/status forms and recovery/validation states, NEWS approve/reject, organization approve/reject/revision forms are readable with wrapping and scrolling. No additional material clipping defect found. EVENT and moderation/organization error/empty/recovery captures left after the failed post-back step are stale font-100 and are NOT VERIFIED at font 200 until rerun. Old unsupported legal fixture images also remain excluded.

## Final font 200 attempt 2

`matrix-font200-attempt2.log` ends `OK (34 tests)`; all 10 people scenarios complete. Reviewed fresh previously missing EVENT queue/detail/fields/approve/reject, moderation empty/error/recovery and organization empty/error/recovery captures in `screenshots-font200-attempt2` (contact sheets 01, 04–06, 08–09). Text wraps within cards; actions, dates and explanations remain readable. No new material visual defect found; no additional source change required.

Together with the reviewed font-100 attempt 3 and completed font-200 users/legal/status/role/organization-decision captures, the requested synthetic people screenshot matrix is complete at both scales and both locale/theme combinations. This does not promote legacy tests or unpictured state variants to screenshot proof, nor assert live moderation/status/role writes, production permissions, network media, TalkBack or physical-device correctness. Historical attempt limitations above are retained as provenance, superseded only for branches actually rerun and reviewed.
