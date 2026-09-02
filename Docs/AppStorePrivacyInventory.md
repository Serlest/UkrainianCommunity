# App Store privacy inventory

Last archive and authenticated App Privacy UI verification: 2026-09-02, version 1.0.1 (65). The 30 archive privacy manifests are unchanged from build 64. See `Docs/PrivacyPublication-2026-09-02.md`, `Docs/Build65ReleaseReadiness-2026-09-02.md` and the ignored release evidence `build65-privacy-readback.md`.

This inventory is a release aid, not a substitute for the answers entered in App Store Connect. Recheck it whenever data flows or third-party SDKs change. Apple requires the App Store privacy answers to include the practices of third-party partners.

## Tracking

- The app does not use AppTrackingTransparency, IDFA, advertising attribution, or tracking domains.
- `PrivacyInfo.xcprivacy` declares `NSPrivacyTracking` as `false`.
- Do not answer that the app tracks users unless a future integration links app data with third-party data for advertising, advertising measurement, or data-broker purposes.

## Data collected by the app and backend

| App Store category | Concrete data | Linked to identity | Main purpose | Evidence / notes |
| --- | --- | --- | --- | --- |
| Contact Info — Name | Full name and display name | Yes | App Functionality | Account profile, authorship and community participation |
| Contact Info — Email Address | Authentication and profile email | Yes | App Functionality | Firebase Authentication and user profile |
| Contact Info — Phone Number | Optional published organization/specialist telephone number | Yes | App Functionality | `ContentModels.Organization.phone`; may be a sole trader's personal contact; not phone authentication |
| Contact Info — Physical Address | Publisher-supplied organization/specialist or event address | Yes | App Functionality | `ContentModels.address`; may be a home business; do not hide it under Other Contact Info |
| Contact Info — Other User Contact Info | Optional Telegram username and contact links | Yes | App Functionality | User-supplied profile or published content |
| Location — Coarse Location | Account's manually selected Austrian federal state | Yes | App Functionality, Analytics | Registration/profile regional selection and aggregate account-region reporting; not GPS or background location |
| User Content — Photos or Videos | Avatar, news/event/organization images and gallery media | Yes | App Functionality | Uploaded to Firebase Storage; current client selects images |
| User Content — Customer Support | Support requests, replies, feedback and content reports | Yes | App Functionality | Account-linked conversations and moderation/support handling; no assumption of Apple's optional-disclosure exemption |
| User Content — Other User Content | Bios, posts, events, organizations, comments, feedback and reports | Yes | App Functionality | Firestore content and moderation flows |
| Identifiers — User ID | Firebase UID and internal document IDs | Yes | App Functionality, Analytics | Authentication, ownership, consent authorization and account-linked analytics deduplication |
| Identifiers — Device ID | Firebase Installation ID for new builds, legacy FCM registration tokens during migration, and hashed document identifiers | Yes | App Functionality | Push notifications; not used for tracking. The dual-schema migration is documented in `Docs/PushRegistrationMigration.md` |
| Usage Data — Product Interaction | Operational account-feature records: per-account news/event view deduplication, public view counters, news likes, bookmarks, organization follows, event registrations and personal user/organization block preferences | Yes for per-account records; public counters are aggregate | App Functionality | Created when a signed-in user uses the relevant feature, independently of optional analytics consent; preserves requested state, prevents duplicate lifetime view counts and maintains feature/public counters |
| Usage Data — Product Interaction | Optional daily first-party signals for views, likes, bookmarks, follows and registrations | Yes while deduplicating; owner reports are aggregate | Analytics | Sent to the first-party aggregation callable only after explicit opt-in; owner reports do not expose participant lists |
| Diagnostics — Other Diagnostic Data | App diagnostic logs; Firebase SDK user-agent and transport diagnostics | Yes for app logs; SDK manifests also contain unlinked records | App Functionality, Analytics | Build 36 archive: Auth, Firestore, Installations and GoogleDataTransport declare diagnostic Analytics; do not confuse this with Firebase Analytics SDK or optional owner analytics |
| Other Data Types | Versioned legal/age confirmations; SDK messaging metadata | Yes for legal evidence; SDK metadata also declared unlinked | App Functionality, Analytics | Immutable legal evidence and 30-day organization proof; FirebaseMessaging's embedded manifest also declares OtherDataTypes/Analytics |

## Location distinction

The client does not request Core Location permission or read the device's location. The manually selected profile federal state is still account-linked regional information and is conservatively disclosed as Coarse Location. Public event/organization coordinates describe a venue, not the user's live device position. A publisher may nevertheless supply a personal business address, disclosed separately as Physical Address. Do not claim that absence of a location permission means no regional/contact data is collected.

## Data not observed in the audited client

- Contacts, health, fitness, financial, payment, browsing history, search history, sensitive information, advertising data, microphone, or device location.
- A user phone number is not part of the account profile. Phone numbers may appear as publisher-provided event or organization contact information.
- Optional first-party owner aggregate analytics is opt-in: the absence of a saved choice resolves to disabled. Operational records required for account features are separate and are not controlled by this consent.

## Operational feature records, analytics consent and retention

- Google/Firebase Analytics is not linked in the iOS target. The app does not send automatic SDK events, app-instance analytics identifiers, advertising signals or analytics-derived location.
- Consent is stored per local principal and journaled server-side with versioned disclosure evidence. A choice made by account A is not inherited by account B, and the legacy installation-wide opt-in is not migrated as consent. Guests cannot enable server aggregation because it requires a verified, non-anonymous account.
- The callable requires the exact current server-recorded consent generation. Production enablement still requires an approved lawful-basis/controller decision and matching published policy text.
- Signed-in use of account features creates operational account-linked records independently of optional analytics consent. Persistent per-content markers deduplicate news and event views across the content lifetime and drive public view counters. Like, bookmark, organization-follow and event-registration records preserve the feature state requested by the user and may also drive public counters or notifications. This is App Functionality processing, not optional analytics processing.
- Turning off optional analytics does not delete or prevent those operational records, reverse a requested action, or disable the corresponding public counters. It stops only future optional daily owner-analytics signals and invalidates incompatible queued signals.
- The client sends an optional analytics signal only for a verified, non-anonymous account after server-confirmed opt-in. Its payload contains the event name, canonical content identifier, consent generation, optional one-time action-proof binding and bounded occurrence time; display metadata is resolved again on the server.
- Optional interaction signals are account-linked while being deduplicated. The analytics backend accepts delayed signals for up to 48 hours, keeps signal-deduplication receipts for 72 hours, and keeps analytics account-activity/deletion markers for 60 days; owner-facing aggregate documents contain counts and public content metadata, not participant lists. Operational feature records follow their own feature/account/content lifecycle and are not governed by this analytics receipt period.
- Owner reporting keeps the sources distinct: daily views, actions and tracked-active windows use only opted-in signals, while public feature counters and total-account, status, account-registration, deletion and profile-region statistics are operational data calculated independently of optional analytics consent.
- The durable local outbox stores an opaque hash of the principal, the minimal event payload, and retry state. Opt-out, logout, or account replacement invalidates delivery and removes incompatible queued data.
- Neither operational feature records nor optional analytics signals are used for advertising or cross-app tracking. The public privacy policy and App Store Connect answers must preserve this App Functionality-versus-Analytics distinction and the same account-linked wording; do not describe either processing path as anonymous. Region reports use the region assigned to published content and never device location.

## Administrator-only presence (build 32)

- `updateUserPresence` records app foreground activity independently of optional aggregate analytics. This is account-linked activity: it is not anonymous, not public, and not a Firebase Auth sign-in timestamp.
- Only active, email-verified platform `owner` and `admin` accounts can obtain the sanitized online/last-seen result through `getManagedUserPresence`. Organization ownership, administration and moderation do not grant access. All direct client reads and writes are denied, including self reads.
- Storage is `users/{uid}/privatePresence/current`: one last-confirmed server timestamp and at most 32 random per-process/account session markers (sequence, active flag, server timestamp). No device identifiers, visited screens, content, location or historical activity timeline are recorded. Old session markers are pruned on subsequent updates after ten minutes; the last-seen timestamp persists until account deletion. Recursive account deletion removes the document; inactive/deleting/missing profiles cannot write new markers.
- The client sends only while authenticated and foreground-active, approximately twice per minute, plus transitions. It does not persist an offline queue. A missing disconnect signal expires after 90 seconds; an ordinary sign-out may also rely on expiry because the original credential is no longer available. The detail screen polls every 30 seconds while active. This is approximate presence, not proof of attendance or an exact disconnect timestamp.
- Privacy policy 2026.11, section 18, describes this separate administrative purpose and its legitimate-interest basis, restricted recipients, approximation, retention and right to object. Existing analytics opt-in is not consent for presence; analytics disclosure and its historical privacy version 2026.10 remain unchanged. Terms and organization rules also remain 2026.10.
- App Store category remains account-linked Product Interaction, App Functionality, no tracking, already present in the app privacy manifest. Verify the live App Store Connect answers before release; the manifest does not publish those answers. TestFlight notes must call out the new presence processing and link the updated privacy policy.

## Personal organization hiding (build 65)

The new private collection `users/{uid}/blockedOrganizations/{organizationId}` stores the requested organization ID, public organization name and block timestamp for the authenticated caller. A local per-account cache retains the last verified preference. This is an explicit personal safety control, independent of owner/user blocking, organization roles and optional analytics; no advertising or cross-app tracking is added. These operational preferences map to the existing account-linked Product Interaction/User ID disclosures for App Functionality. The authenticated App Privacy page was reread for build 65 and already declares these types/purposes; no questionnaire changes were made. This technical mapping is not an independent legal conclusion.

## Local Face ID / Touch ID protection

`AppLockService` uses Apple's `LocalAuthentication` and permits device-passcode fallback. It protects access to an existing password-authenticated session; it is not Sign in with Apple and does not replace Firebase Authentication. The app receives an authentication result, never a face template, fingerprint or device passcode. Only a per-account local preference under a hashed UID is stored. No biometric data is uploaded, so Face ID alone does not add Sensitive Info to the App Store label. Registration choice is optional/off by default and Profile retains enable/disable controls.

## SDK diagnostics and optional analytics are different

The optional switch controls the first-party daily content analytics, not every SDK diagnostic. The signed build 64 archive contains 30 privacy manifests, including the app's, with 14 distinct collected-data categories and no tracking declaration. The app does not override Firebase's default diagnostic collection setting. SDK declarations are included in the combined App Store answers; disabling the first-party switch is not a promise to disable all provider telemetry. Policy 2026.12 was operator-approved and published on 2026-09-02; website, Firestore and the build 64 offline bundle were compared by locale content hashes. This does not replace independent legal review.

## TOTP account protection

Privileged platform accounts use Firebase Authentication's TOTP factor. Setup material is passed to the user's chosen authenticator; factor membership and verification codes are processed for account security. Setup secrets and one-time codes are not stored in public profiles, Firestore content or application logs. Security/recovery audit events follow the existing protected-log retention rules. This is distinct from local biometrics and optional content analytics. Policy 2026.12 section 21 explains the flow. The release-64 change updates only policy text/version, not MFA behavior.

References checked on 2026-08-26: [Apple data definitions](https://developer.apple.com/app-store/app-privacy-details/) and [Firebase SDK disclosures](https://firebase.google.com/docs/ios/app-store-data-collection). The category mapping above is the technical audit's interpretation of those definitions, not a legal opinion.

## Required-reason API declaration

The first-party code uses `UserDefaults` and SwiftUI `@AppStorage` for user preferences and analytics consent. The privacy manifest declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, limited to data accessible only by this app. No first-party uses of file timestamp, system boot time, disk-space, or active-keyboard required-reason API categories were found.

## Submission verification

The local Xcode 26.6 Release-product audit on 2026-08-24 found the app manifest plus 29 embedded SDK manifests. This confirms packaging for the pinned dependencies, but the signed archive privacy report remains the submission source of truth.

1. Archive the exact release commit in Xcode.
2. Generate and inspect the archive's privacy report.
3. Compare the report, Firebase's current SDK disclosures, this inventory, the public privacy policy and App Store Connect answers.
4. Resolve every mismatch before upload; do not copy this table blindly into App Store Connect.
5. Verify the production App Check parameter is enabled only after App Attest registration and enforcement metrics have been confirmed.
