# App Store privacy inventory

Last code audit: 2026-08-22

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
| Contact Info — Other User Contact Info | Optional Telegram username; organization/event contact email, phone and links | Usually | App Functionality | User-supplied profile or published content |
| User Content — Photos or Videos | Avatar, news/event/organization images and gallery media | Yes | App Functionality | Uploaded to Firebase Storage; current client selects images |
| User Content — Other User Content | Bios, posts, events, organizations, comments, feedback and reports | Yes | App Functionality | Firestore content and moderation flows |
| Identifiers — User ID | Firebase UID and internal document IDs | Yes | App Functionality | Authentication, authorization and ownership |
| Identifiers — Device ID | FCM registration token and its hashed document identifier | Yes | App Functionality | Push notifications; not used for tracking |
| Usage Data — Product Interaction | Views, likes, bookmarks, follows, registrations and comparable actions | Yes for server aggregates; Firebase Analytics depends on consent | App Functionality; Analytics | Analytics must remain disabled until explicit opt-in |
| Diagnostics — Other Diagnostic Data | Security, moderation, audit and operational logs | Yes when an actor is known | App Functionality | Restricted system logs used for safety and support |

## Location distinction

The client does not request Core Location permission or read the device's location. Event and organization editors can supply a place or coordinates for public content. Before submission, verify App Store Connect wording against the shipped build; do not label this as device precise-location collection unless the app begins reading a user's device location.

## Data not observed in the audited client

- Contacts, health, fitness, financial, payment, browsing history, search history, sensitive information, advertising data, microphone, or device location.
- A user phone number is not part of the account profile. Phone numbers may appear as publisher-provided event or organization contact information.
- Analytics is opt-in: the absence of a saved choice now resolves to disabled.

## Required-reason APIs

The first-party code uses `UserDefaults` and SwiftUI `@AppStorage` for user preferences and analytics consent. The privacy manifest declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, limited to data accessible only by this app. No first-party uses of file timestamp, system boot time, disk-space, or active-keyboard required-reason API categories were found.

## Submission verification

1. Archive the exact release commit in Xcode.
2. Generate and inspect the archive's privacy report.
3. Compare the report, Firebase's current SDK disclosures, this inventory, the public privacy policy and App Store Connect answers.
4. Resolve every mismatch before upload; do not copy this table blindly into App Store Connect.
