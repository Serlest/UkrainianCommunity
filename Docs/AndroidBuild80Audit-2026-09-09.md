# Android 1.1 (80): audit and implementation checkpoint

Reference iOS: aa448a9 (1.1 / 80). Android baseline: 2b001a4 (1.0.3 / 79).
Changes are Android-only. No distribution or backend deployment performed.

## Verification boundary

This is an IN PROGRESS checkpoint, not full parity or release approval. Only Android source and this audit document changed. iOS, backend, Rules, production data and store tracks were not changed.

- Final local compile/assemble and lint: PASS (0 lint errors, 77 warnings, 1 hint).
- Local JVM: 1919 tests, 0 failures/errors/skips.
- Broad component UI on API37 at OS font 200%: first run 272/276 passed; four scenarios failed while awaiting docked IME.
- Enabling hardware-keyboard IME alone did not resolve the four failures: 17/21 passed on that recheck.
- Screenshot and input-method state showed a floating handwriting panel. Switching the AVD to ordinary English keyboard and disabling stylus handwriting resolved all four: affected full classes 21/21 PASS. No assertions weakened.
- Latest visual source, main screens + banner + browse + personal UI: 18/18 PASS at 200% and 18/18 PASS at 100%.
- Main captures cover DE/UK, light/dark home, news/events/organizations and details, guest profile, login, and bundled legal readers. These use synthetic fixtures.
- Actual new callable SDK transport, authenticated cloud journeys, API26 final binary, physical device, TalkBack and Play-installed candidate: NOT VERIFIED.

## Implemented Android changes

- Identity: versionName 1.1, versionCode 80.
- Details: grouped headline, metadata, image and article body; complete body typography; separate source/link card and wrapping tag chips. No source/legal content rewritten.
- Banners: full artwork with adaptive backdrop, no empty text panel, semitransparent text surface, current-index drag handler, and local starts/ends scheduling from fetched candidates. Font scaling remains unconstrained and actions retain 48dp targets.
- Shared section surfaces use UacSectionCard. Saved/subscriptions reuse feed cards with images and metadata.
- Public image errors no longer incorrectly identify production as a local test build.
- Legal reader: valid equal-width Markdown tables render as header/value rows with emphasis; malformed tables stay literal. Unit tests cover complete cells and malformed input.
- Organization review sends stable operationId and exact seconds:nanoseconds expectedRevision from the same validated preview. Existing non-resend reconciliation policy is retained.
- News/event moderation uses the build80 reviewContentModeration callable with exact loaded revision, operation ID and validated response. Acknowledged operations use durable local acknowledgement plus server read-back. Legacy/lost-response journals retain read-only reconciliation; automatic resubmission is not added.
- Account deletion transport deadline is 330s, allowing the deployed 300s operation to settle. Retry-window tests follow that deadline.

## Remaining work before full parity / release

1. Complete the per-package source/scenario comparison below, especially feedback/inbox, legal receipt integrity, block lists, settings recovery, and owner management.
2. Verify new callable contracts through Android Firebase SDK against isolated build80 backend fixtures. The old Android local callable harness does not establish support for the new moderation endpoint. No production destructive tests.
3. Resolve explicit recovery of new moderation operations after a lost response; do not claim same-operation replay is exposed by the current Android UI.
4. Complete authenticated owner/admin visual captures, real loaded artwork comparisons with iOS80, API26 and physical-device/TalkBack checks.
5. Build signed production candidate and proceed to store distribution only within the separately authorized scope. Local version metadata is not release proof.

## iOS build 80 package coverage

Each row must receive Android source evidence and scenario evidence before full parity can be claimed.

- NOT VERIFIED: Fix80-1 — Profile root reconciliation — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-1-handoff.md
- NOT VERIFIED: Build 80 package 2 — shared shell/layout handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-2-handoff.md
- NOT VERIFIED: Fix80-3 handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-3-handoff.md
- NOT VERIFIED: Build 80 — пакет 4 «Мои мероприятия» — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-4-handoff.md
- NOT VERIFIED: Fix80-05 — Saved content handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-5-handoff.md
- NOT VERIFIED: Fix80-6 — Followed organizations handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-6-handoff.md
- NOT VERIFIED: Fix80-7 — Recent views handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-7-handoff.md
- NOT VERIFIED: Fix80-8 handoff — Activity History — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-8-handoff.md
- NOT VERIFIED: Fix80-10 handoff — Feedback — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-10-handoff.md
- NOT VERIFIED: Fix80 package 12 — Уведомления — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-12-handoff.md
- NOT VERIFIED: Fix 80 — Package 13 handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-13-handoff.md
- NOT VERIFIED: Fix80-14 handoff — App Lock availability — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-14-handoff.md
- NOT VERIFIED: Fix80-15 — notification settings reliability — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-15-handoff.md
- NOT VERIFIED: Fix80-16 handoff — Security settings — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-16-handoff.md
- NOT VERIFIED: Fix80-17 — Заблокированные организации — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-17-handoff.md
- NOT VERIFIED: Fix80 package 18 — Blocked users — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-18-handoff.md
- NOT VERIFIED: Fix80-19 handoff — Legal reader and acceptance (sections 19 + 20) — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-19-handoff.md
- NOT VERIFIED: Fix80-20 handoff — Privacy reader cross-check — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-20-handoff.md
- NOT VERIFIED: Fix80 package 21 — Account deletion and DSA backend — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-21-handoff.md
- NOT VERIFIED: Fix80-22 organization request review handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-22-handoff.md
- NOT VERIFIED: Fix80-23 — Moderation handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-23-handoff.md
- NOT VERIFIED: Fix80-24 handoff — Feedback operation reconciliation — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-24-handoff.md
- NOT VERIFIED: Fix80-25 — Управління користувачами — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-25-handoff.md
- NOT VERIFIED: Fix80-26 — Баннеры — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-26-handoff.md
- NOT VERIFIED: Fix80-27 — Планування контенту — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-27-handoff.md
- NOT VERIFIED: Fix 80 — Package 28 handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-28-handoff.md
- NOT VERIFIED: Fix 80 — Package 29 handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-29-handoff.md
- NOT VERIFIED: Fix80-30 — Legal document management handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-30-handoff.md
- NOT VERIFIED: Fix80-31 — Legal evidence handoff — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-31-handoff.md
- NOT VERIFIED: Fix80-32 — System Logs — reference /Users/serlest/Developer/UAC-1.1-Build80/Docs/Fix80-32-handoff.md

## Android screen inventory

- accountdeletion: AccountDeletionUi.kt — full visual coverage NOT VERIFIED
- accountstatus: AccountStatusUi.kt — full visual coverage NOT VERIFIED
- announcements: AnnouncementUi.kt — full visual coverage NOT VERIFIED
- applock: AppLockUi.kt — full visual coverage NOT VERIFIED
- attendees: AttendeesUi.kt, AttendeesAccessUi.kt — full visual coverage NOT VERIFIED
- auth: AccountScreen.kt, AuthMfaScreen.kt — full visual coverage NOT VERIFIED
- authoring: AuthoringUi.kt — full visual coverage NOT VERIFIED
- browse: BrowseScreen.kt — full visual coverage NOT VERIFIED
- community: CommunityUi.kt — full visual coverage NOT VERIFIED
- contentlifecycle: ContentLifecycleUi.kt — full visual coverage NOT VERIFIED
- contentmedia: ContentCoverUi.kt — full visual coverage NOT VERIFIED
- contentplanning: ContentPlanningUi.kt — full visual coverage NOT VERIFIED
- dsaappeal: DsaAppealReviewUi.kt — full visual coverage NOT VERIFIED
- dsastatement: DsaStatementUi.kt — full visual coverage NOT VERIFIED
- featuredmanagement: FeaturedManagementUi.kt — full visual coverage NOT VERIFIED
- feedback: FeedbackCaseContextUi.kt, FeedbackUi.kt, FeedbackInboxUi.kt — full visual coverage NOT VERIFIED
- foundation: FoundationScreen.kt — full visual coverage NOT VERIFIED
- gallery: GalleryUi.kt — full visual coverage NOT VERIFIED
- history: HistoryUi.kt — full visual coverage NOT VERIFIED
- inbox: InboxPopupUi.kt, InboxUi.kt — full visual coverage NOT VERIFIED
- legalevidence: LegalEvidenceUi.kt — full visual coverage NOT VERIFIED
- moderation: ModerationDecisionUi.kt, ModerationScreen.kt — full visual coverage NOT VERIFIED
- organization: OrganizationUi.kt, OrganizationManagementUi.kt — full visual coverage NOT VERIFIED
- organizationreview: OrganizationReviewUi.kt — full visual coverage NOT VERIFIED
- owneranalytics: OwnerAnalyticsUi.kt — full visual coverage NOT VERIFIED
- personal: PersonalUi.kt — full visual coverage NOT VERIFIED
- platformrolemanagement: PlatformRoleUi.kt — full visual coverage NOT VERIFIED
- profilemedia: ProfileMediaUi.kt — full visual coverage NOT VERIFIED
- publicgallery: PublicGalleryUi.kt — full visual coverage NOT VERIFIED
- registrations: RegistrationsUi.kt — full visual coverage NOT VERIFIED
- reminders: ReminderUi.kt — full visual coverage NOT VERIFIED
- safety: SafetyUi.kt — full visual coverage NOT VERIFIED
- startup: StartupScreen.kt — full visual coverage NOT VERIFIED
- subscribers: SubscribersUi.kt — full visual coverage NOT VERIFIED
- systemlogs: SystemLogsUi.kt — full visual coverage NOT VERIFIED
- usermanagement: ManagedUsersUi.kt — full visual coverage NOT VERIFIED
- userstatusmanagement: UserStatusUi.kt — full visual coverage NOT VERIFIED

## Next work

Final 100%/200% verification and exact source/APK receipts saved under /Users/serlest/Documents/Codex/2026-09-09/80-80. Continue the outstanding functional comparison above. Full task is not yet complete.
