# Android 1.1 (80): audit and implementation checkpoint

Reference iOS: aa448a9 (1.1 / 80). Android baseline: 2b001a4 (1.0.3 / 79).
Changes are Android-only. No distribution or backend deployment performed.

## Verification boundary

This is a source-wide audit with implemented fixes, not full parity or release approval. Only Android source and this audit document changed. iOS, backend, Rules, production data and store tracks were not changed.

- Local compile/assemble and lint: PASS (0 lint errors, 77 existing warnings, 1 hint).
- JVM: 1932 tests, 0 failures/errors/skips.
- API26: initial component 276/276 PASS; expanded UI suite 297/297 PASS at OS font 200%, including owner analytics/roles/announcements and unavailable markers. Expanded suite preceded the final read-only moderation marker change.
- API37: MainActivity + affected UI classes 28/28 PASS at each OS font 100% and 200%; synthetic light/dark, German/Ukrainian captures. Final exact-artifact rerun recorded separately below.
- Local Android Auth/Firestore SDK + demo-only Android callable gateway to actual iOS80 handlers: 6/6 PASS on API37; registration/verification/restore, feedback transaction/replay, exact read acknowledgement, legal integrity/tampering, moderation receipt/replay/payload conflict/stale revision/server marker.
- App TOTP protection remained active: no-TOTP privileged source authorization was rejected. The lower-level fixture transport test is not a positive owner/admin UI authorization test.
- On API26, Auth/Feedback 4/4 and earlier transport/legal 2/2 passed. Reinstall of the last candidate hung in the AVD package installer; no final API26 SDK result is claimed. Owned AVD was stopped and subsequent verification moved to API37.
- Final Android source / local APK: API37 font 200%, 307/307 PASS (299 component UI + 6 SDK/transport + 2 MainActivity journeys), build80-owner-final-api37.log. Earlier exact-artifact 34/34 receipt is retained for commit 50275b8.
- Owner workflow build/lint PASS, 1932 JVM tests with zero failures/errors/skips. Lint remains 0 errors, 77 existing warnings, 1 hint.
- Physical device, TalkBack, positive real TOTP, production Firebase Functions SDK, cloud journeys and Play-installed candidate: NOT VERIFIED.
- First-pass screenshots and 1919-test receipts are retained in the output directory as historical evidence; newer files use build80/full-audit names. Only screenshots actually refreshed by the new runner are counted.

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

1. Close the explicit workflow gaps below: activity-history uncertain-write recovery, DSA submission/review actions, legal document editor.
2. Extend positive authenticated journeys to TOTP owner/admin and production-configured Firebase Functions transport. Local Auth/Firestore SDK plus Android local callable gateway now have isolated build80 backend proof.
3. Lost responses with exact current server operation marker now reconcile read-only. Changed/deleted targets without durable acknowledgement still require stronger receipt recovery; UI does not expose same-operation resend.
4. Complete authenticated owner/admin visual captures, real loaded artwork comparisons with iOS80, API26 and physical-device/TalkBack checks.
5. Build signed production candidate and proceed to store distribution only within the separately authorized scope. Local version metadata is not release proof.

## iOS build 80 package coverage

Source comparison covers all supplied handoffs (9 and 11 have no separate handoff). “Reviewed” is source evidence, not a runtime PASS. Gaps are explicit functional differences.

| Package | Area | Result | Evidence / boundary |
|---|---|---|---|
| 1 | Profile root | Reviewed | PersonalIntegration/PersonalUi keep loading/error scoped to session. Badge freshness across every production route remains device verification. |
| 2 | Shared shell and layout | Fixed + component tests | UacSectionCard, grouped details and feed cards; 48dp actions; typography not clamped. API26/37 component checks are not complete screenshot parity. |
| 3 | Organization deletion | Reviewed | OrganizationManagement + ContentLifecycle confirmations/reconciliation exist; real cascade is shared backend and was not executed. |
| 4 | My events | Reviewed | RegistrationsRepository/FirestoreRegistrationsSource use server reads and guarded mutations. Cancellation after backend mode changes needs positive SDK journey. |
| 5 | Saved | Fixed + tests | Validated bookmark IDs now survive unavailable content as removable placeholders; no automatic marker deletion; server-confirmed explicit removal. |
| 6 | Subscriptions | Fixed + tests | Same explicit unavailable-marker removal for subscriptions; cursor and account scope retained. |
| 7 | Recent views | Reviewed | History source resolves targets individually and filters visibility; MainActivity safety applies to history. Live blocked-organization scenario remains unverified. |
| 8 | Activity history | Gap | Android reconciliation is read-only after uncertain writes. No equivalent complete iOS80 stable-operation resend workflow claimed. |
| 10 | Feedback | Fixed + SDK tests | Message cursor pagination past 100; equal-timestamp tie-break; loaded depth preserved on refresh; exact-snapshot user-read acknowledgement cannot consume a newer reply. |
| 12 | Notifications | Fixed + component tests | Inbox, feedback, popup listener transient errors reconnect with bounded backoff. Dismissal mutations are not replayed. Positive push delivery is not tested. |
| 13 | Analytics consent | Reviewed | Existing receipt-backed consent, fail-closed UI and identity guards; Build68PrivacyLegalUiTest. Production consent journey remains unverified. |
| 14 | App lock | Reviewed + component tests | SystemAppLockAuthenticator checks device credential independently of strong biometrics; Android native credential fallback retained. Physical biometric/credential test remains. |
| 15 | Notification settings | Reviewed | Inbox preferences and reminder state are separate; permission settings exposed. Real notification delivery/reboot coverage not established by this run. |
| 16 | Security settings | Reviewed + SDK tests | Auth session restore/verification local SDK checks passed. Existing TOTP validation and MFA UI tested with fixtures; positive real TOTP remains unverified. |
| 17 | Blocked organizations | Fixed + unit tests | Unknown block policy remains fail-closed. Uncertain mutation gets one immediate read-back without resending; explicit success only from confirmed list. |
| 18 | Blocked users | Fixed + unit tests | Same uncertain-write read-back; backend deleted-target unblock behavior is not changed by Android work. |
| 19/20 | Legal reader and acceptance | Fixed + SDK tests / dependency | SERVER pointer/version read, canonical/legacy hash and YYYY.minor/numeric-version consistency validation, validated Markdown display and table rendering. Tampering rejected. New iOS registration receipts are ios-only in reference Rules; Android initial-registration evidence parity needs shared Rules design. |
| 21 | Account deletion | Fixed + unit tests | 330s request reaches common protocol policy (previous 300s cap removed). No destructive cloud account test; backend DSA retention/resume remains shared implementation. |
| 22 | Organization review | Fixed + contract tests | Stable operationId and exact loaded expectedRevision sent; positive TOTP-authorized server journey still unverified. |
| 23 | Moderation / DSA | Fixed moderation + SDK tests; DSA gap | New endpoint allowlisted and non-idempotent; receipt/replay/conflict contract validated. Exact server operation marker reconciles lost response without resend. DSA appeals remain read-only preparation in Android. |
| 24 | Feedback reconciliation | Reviewed + SDK tests | Existing stable message ID transaction verified with repeat/read-back; no duplicate reply. Read acknowledgement now added separately. |
| 25 | User management | Reviewed + component tests | Existing auth metadata and truncation handling retained. Full privileged live user-management journey is not covered. |
| 26 | Banners | Fixed + component tests | Artwork FIT with adaptive background, optional scrim, current-index gesture key, local schedule boundary refresh. Authenticated banner editor uses existing validations. |
| 27 | Content planning | Reviewed + component tests | Existing draft/lease recovery and explicit retry; organization selection and draft editing retained. Every malformed backend draft combination remains unverified. |
| 28 | Owner analytics | Fixed + component test | Missing daily documents or update timestamps mark daily coverage unavailable and hide misleading daily totals/trend; other available sections remain. Source names localized. Cached owner data is now bound to the exact account/session revision and scrubbed on change. |
| 29 | Donation management | Implemented + unit/UI verification | Added owner-only native editor, DE/UK fields, HTTPS validation, exact baseline transaction, post-save SERVER read, retained draft after failed refresh, blocked resend until readback and dirty navigation confirmation. Positive real TOTP editor write remains unverified. |
| 30 | Legal document management | Gap | No Android draft/CAS/publish editor equivalent found. Reader/evidence fixes do not provide publication controls. |
| 31 | Legal evidence | Fixed + component tests | Existing paginated owner callable; added search and version/locale/app/platform/source-record/hash detail, localized provenance. Full evidence population relies on backend receipts. |
| 32 | System logs | Reviewed + component tests | Existing SERVER reads and refreshed detail; owner/admin visibility retained. No production log mutation performed. |

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

## Additional fixes in the full-audit pass

- Common transport allowlist/non-idempotent policy now includes reviewContentModeration, and deleteOwnAccount permits the requested 330 seconds.
- Legal content verifies canonical and legacy hashes before display; local synthetic fixtures now carry valid hashes.
- Feedback uses paged message reads, preserves loaded history depth, and acknowledges only the exact read snapshot using a transaction.
- Transient listener failures reconnect for feedback, inbox and popup heads without replaying writes.
- Block mutations reconcile uncertain outcomes with fresh lists.
- Unavailable saved/subscription markers have explicit remove controls with pending/error states.
- Incomplete daily analytics no longer appear as complete zero statistics.
- Legal evidence has search and detailed provenance.
- Moderation lost-response reconciliation accepts only matching server operation/actor/status/preserved content; status alone is insufficient.

## Owner-workflow follow-up

- Added `feature/donationsettings`: owner access is checked from the current profile/token; app requires TOTP. Settings are read from SERVER and saved with an exact baseline transaction to `appConfig/donation`.
- A confirmed write followed by failed refresh retains the just-saved draft and reports that distinction. An uncertain write blocks another save until explicit readback. No automatic mutation retry was introduced by the ViewModel.
- Dirty Back, tab changes and header Settings navigation ask before discarding; account changes clear the private draft. Both locales remain separate, with multiline fields and normal Android keyboard/insets.
- Empty public support labels use the existing iOS default wording; the owner-configured message still appears once.
- Fixed cached owner analytics surviving session changes. Tests cover account revision changes and clearing cached private data.
- No support configuration or legal document was written to production. No new public legal text was authored.

## Final artifacts

Output: `/Users/serlest/Documents/Codex/2026-09-09/80-80`.

- `artifacts/app-local-debug-build80-audit.apk`: latest local/demo APK, not a Play release.
- `full-audit-verification.json`: exact installed/application hashes, test counts and boundaries.
- `full-audit-source-manifest.json`: tracked Android source hashes and commit.
- `screenshots/build80-final-api37`: 22 refreshed synthetic screen captures. Donation images are component-host captures; system chrome is not production-window evidence for that editor.
- `build80-owner-final-api37.log`: 307/307 PASS. Screenshot-only fixture follow-up: `build80-donation-captures-api37.log`, 2/2 PASS.

## Next work

Verification logs and source/APK receipts saved under /Users/serlest/Documents/Codex/2026-09-09/80-80. Continue the outstanding functional comparison above. Full task is not yet complete.


## Google Play Internal testing — 2026-09-09

User explicitly requested upload for testing after receiving the audit limitations.

- Signed production build from `85ef15cf3d88aa72d74f06fff6706e81566578f5`: `assembleProductionRelease` + `bundleProductionRelease` PASS, including R8 and lintVital.
- Package `at.serlest.ukrainiancommunity`, version `1.1 (80)`, min/target SDK `26 / 36`; upload certificate matches build 79. APK signature and AAB JAR signature verified.
- AAB SHA-256: `00e6f73e950b90cde0c9e2e9337bfc924a9a31f549cc80f27f2733c606682a1c`.
- APK SHA-256: `ce85a228398565896c85e0f47a152238452e9e4fa3fae736becda2fc99a48039`.
- Google Play accepted version 80 and published release **1.1 (80) – Internal** on existing internal track `4701365572505552935`. Final Console read-back: **Aktiv**, **Für interne Tester verfügbar**, published 9 Sept. 14:53 (Console display).
- One nonblocking warning: native debug symbols absent; ReTrace mapping is attached. No supported devices lost compared with build 79.
- Tester link read back: https://play.google.com/apps/internaltest/4701365572505552935
- Existing tester access unchanged. No public, open or closed testing release, and no backend/iOS deployment.
- Physical Play installation, device runtime and previously listed parity limitations remain unverified/open.
- Receipt: output `build80-play-internal-receipt.json`; production artifacts under `artifacts/app-production-release-build80-UPLOAD-SIGNED.{aab,apk}`. Build log `build80-production-release.log`; AAB signature log `build80-aab-signature.log`.
