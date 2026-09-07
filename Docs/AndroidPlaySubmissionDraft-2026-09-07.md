# Google Play submission draft — Android 1.0.2

Status: **draft only, not approved for submission**. This file prepares Play Console
copy and declarations from the repository state on 2026-09-07. It does not prove a
fresh signed AAB, Play Console configuration, production cloud behavior, legal
approval, or publication.

Application ID: `at.serlest.ukrainiancommunity`

Planned first Play version: `versionCode 1`, `versionName 1.0.2`

Default listing language: German (`de-DE`)

Additional listing language: Ukrainian (`uk`)

## Store listing copy

### German

**App name**

`UkrainianCommunity`

**Short description**

`News, Events und Organisationen für die ukrainische Community in Österreich.`

**Full description**

> UkrainianCommunity bringt Informationen und die ukrainische Community in
> Österreich an einem Ort zusammen.
>
> Entdecke aktuelle Beiträge, Veranstaltungen und Organisationen. Wähle dein
> Bundesland, suche nach passenden Inhalten und speichere interessante Einträge.
> Viele öffentliche Inhalte kannst du ohne Konto ansehen.
>
> Mit einem verifizierten Konto kannst du – abhängig von Inhalt und Berechtigung –
> Beiträge speichern, Organisationen folgen, dich für Veranstaltungen anmelden,
> Kommentare und Feedback senden sowie eigene Profil- und Organisationsfunktionen
> nutzen. Benachrichtigungen sind freiwillig und können in der App und im
> Betriebssystem verwaltet werden.
>
> Community-Sicherheit gehört dazu: Inhalte und Konten können gemeldet oder
> blockiert werden. Veröffentlichungen und Verwaltungsfunktionen sind
> rollenabhängig und können moderiert werden.
>
> Die App ist auf Deutsch und Ukrainisch verfügbar. Sie verwendet keine Werbung
> und kein appübergreifendes Werbetracking.
>
> Support: ukrainian.community@outlook.com

### Ukrainian

**Назва застосунку**

`UkrainianCommunity`

**Короткий опис**

`Новини, події та організації для української спільноти в Австрії.`

**Повний опис**

> UkrainianCommunity об’єднує корисну інформацію та українську спільноту в
> Австрії в одному застосунку.
>
> Переглядайте актуальні матеріали, події та організації. Обирайте федеральну
> землю, шукайте потрібний вміст і зберігайте цікаві записи. Багато публічних
> матеріалів доступні без облікового запису.
>
> З підтвердженим обліковим записом ви можете — залежно від матеріалу та прав
> доступу — зберігати записи, підписуватися на організації, реєструватися на
> події, залишати коментарі й звернення, а також користуватися функціями профілю
> та керування організаціями. Сповіщення добровільні; їх можна вимкнути в
> застосунку й налаштуваннях системи.
>
> Безпека спільноти є частиною сервісу: на матеріали та облікові записи можна
> поскаржитися або заблокувати їх. Публікація та керування залежать від ролі й
> можуть проходити модерацію.
>
> Застосунок доступний німецькою та українською мовами. Ми не показуємо рекламу
> й не використовуємо міжзастосункове рекламне відстеження.
>
> Підтримка: ukrainian.community@outlook.com

Before submission, compare every statement with the exact release build. In
particular, do not keep account actions, push, comments, registrations, blocking,
or organization management in the listing if their production routes are removed
from the release scope.

## URLs for Play Console

| Field | Proposed URL | Status before submission |
| --- | --- | --- |
| Privacy policy | `https://ukrainiancommunity-dbd5f.web.app/privacy` | **BLOCKED:** current published wording is iOS-specific and presence timing does not match the Android/shared implementation. Publish and read back an approved bilingual revision first. |
| Account deletion | `https://ukrainiancommunity-dbd5f.web.app/delete-account` | Repository page exists; **not yet deployment/read-back proof**. Verify public HTTP 200, mobile layout, both languages, links and mail action after an authorized Hosting deployment. |
| Support | `https://ukrainiancommunity-dbd5f.web.app/support` | Existing page; verify the deployed page contains the Android wording and deletion-page link. |
| Website | `https://ukrainiancommunity-dbd5f.web.app/` | Existing site; verify availability immediately before submission. |
| Illegal-content reporting | `https://ukrainiancommunity-dbd5f.web.app/report-illegal-content` | Relevant to UGC/DSA review; verify availability and submission behavior separately. |

### Account-deletion page audit

`website/delete-account/index.html` satisfies the main structural requirements in
source: it names UkrainianCommunity and Timofeev Philipp, covers iOS and Android,
gives an in-app path, provides an outside-the-app email request path, explains
identity verification, and distinguishes deletion/anonymization from limited
retention with a privacy-policy link.

Remaining issues before entering the URL in Play Console:

1. The page has no current public deployment/read-back evidence.
2. “Linked personal data” and “limited evidence” are broad. For stronger review
   clarity, the final approved page should list concrete examples of data normally
   deleted (account, profile, private lists, push registration) and data that may
   remain (legal, moderation, security and backups), plus the applicable retention
   periods or an immediately visible summary of them. This is a legal/content
   decision, not an authorized change in this draft.
3. Verify that an email request can be completed without reinstalling or signing
   into the app, that replies are monitored, and that ownership-transfer
   prerequisites do not become an unnecessary obstacle to deletion.
4. Add a visible `/delete-account` link to the deployed support/footer navigation
   if the final site review finds it insufficiently discoverable.
5. The external page cannot compensate for a broken in-app deletion route. Test
   both routes with disposable production-like accounts and verify backend cleanup.

Official requirement: [User Data policy and account deletion](https://support.google.com/googleplay/android-developer/answer/10144311?hl=en) and
[account-deletion implementation guidance](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en).

## Data Safety draft

This is a conservative technical mapping, **not a final legal determination**.
Play requires one package-level declaration covering the app and every bundled SDK.
Recheck it against the final AAB, Firebase SDK disclosures, production behavior,
privacy policy and any data received by organizations. Save uncertain answers as a
draft in Play Console until the controller/legal owner confirms them.

### Data collection and security overview

| Play question | Draft answer | Confidence / action |
| --- | --- | --- |
| Does the app collect or share required user-data types? | **Collects: Yes.** | Confirm final AAB SDK inventory. |
| Is all collected user data encrypted in transit? | **Yes**, provided the final production network-security manifest denies cleartext and all production endpoints remain HTTPS/Firebase TLS. | Verify the merged manifest and release runtime. |
| Can users request deletion? | **Yes**, only after both the in-app flow and deployed external page are proven. | Currently pending cloud/deployment proof. |
| Does the app share user data? | **UNCERTAIN.** Firebase acting only as a service provider can qualify for an exception. User-directed disclosure to an event organizer/organization may also qualify, but actual controller relationships and every flow must be reviewed before choosing Yes or No. | Do not copy the iOS “no tracking” answer into this field; tracking and sharing are different questions. |
| Tracking, sale, or advertising use | **No** based on current source and policy inventory. | Recheck dependencies; no Google/Firebase Analytics or advertising SDK is intended. |
| Independent security review | **No / not claimed.** | No qualifying review evidence is stored in the repository. |

### Data types

All “linked” answers below are conservative. “Optional” means the user can use the
basic public app without supplying that type; it does not mean the data is optional
after the user requests a feature that needs it.

| Play category / type | Collected | Linked | Required or optional | Purposes to select | Repository interpretation / uncertainty |
| --- | --- | --- | --- | --- | --- |
| Location — Approximate location | Yes | Yes | Required for registered profile; public browsing does not need it | App functionality; Analytics | Manually selected Austrian federal state and regional aggregates, not device GPS. Confirm Play’s interpretation of user-entered region. |
| Location — Precise location | No | — | — | — | No location permission or device-location acquisition. Publisher-entered venue coordinates describe content, not the user’s current device location. |
| Personal info — Name | Yes | Yes | Required for account/profile | App functionality; Account management | Display/profile name and authorship. |
| Personal info — Email address | Yes | Yes | Required for account | App functionality; Account management | Firebase email/password authentication, verification, reset and support identity. |
| Personal info — User IDs | Yes | Yes | Required for account | App functionality; Account management; Fraud prevention, security and compliance; Analytics | Firebase UID, ownership and consent/deduplication bindings. |
| Personal info — Address | Yes | Yes | Optional | App functionality | Publisher-entered organization, specialist or event contact address can be personal. |
| Personal info — Phone number | Yes | Yes | Optional | App functionality | Publisher contact number; not phone authentication. |
| Personal info — Other info | Yes | Yes | Mixed | App functionality; Account management; Fraud prevention, security and compliance; Analytics | Profile biography/Telegram/contact links, role/status, age/legal confirmations and region. Confirm whether some fields belong only under other categories. |
| Messages — Other in-app messages | Yes | Yes | Optional | App functionality; Developer communications; Fraud prevention, security and compliance | Support/feedback conversations and replies. Confirm whether content reports should also be mapped here or only as other UGC. |
| Photos and videos — Photos | Yes | Yes | Optional | App functionality | Avatar and user/publisher-uploaded content images. Current Android selection is images, not user video upload. |
| App activity — App interactions | Yes | Yes | Mixed | App functionality; Analytics | Likes, saves, follows, registrations, views/deduplication, blocking and optional consented analytics signals. |
| App activity — Other user-generated content | Yes | Yes | Optional | App functionality; Fraud prevention, security and compliance | Bios, posts, events, organizations, comments, feedback and content reports. |
| App activity — In-app search history | No, based on current implementation | — | — | — | Search/filter input is not intended to be stored as history. Recheck server logging and final client queries. |
| App info and performance — Diagnostics | Yes | Mixed / conservatively Yes | Automatic for necessary SDK transport; optional first-party analytics is separate | App functionality; Analytics; Fraud prevention, security and compliance | Firebase SDK transport/device/app-version diagnostics and protected system/audit diagnostics. Do not label Firebase diagnostics as Firebase Analytics. |
| Device or other IDs | Yes | Yes after account registration | Optional push; necessary App Check/service identifiers may be automatic | App functionality; Developer communications; Fraud prevention, security and compliance | Firebase Installation ID, FCM registration identifiers and App Check/Play Integrity technical identifiers. |

No current repository evidence supports declaring collection of contacts, financial
or payment information, health/fitness, calendar, audio files, browser history,
installed apps, advertising data, precise device location, or advertising ID.
Passwords and TOTP codes are processed by Firebase Authentication but are not
stored as Firestore profile fields; confirm with Google/Firebase’s current SDK Data
Safety guidance how the final form should represent authentication credential
processing.

For every collected type, confirm in Play Console:

- whether collection is required or optional;
- every applicable purpose;
- whether it is processed ephemerally;
- whether it is linked to identity;
- whether any transfer falls outside a “service provider,” “user initiated,” or
  legal-purpose sharing exception.

Official taxonomy and form guidance: [Provide information for Google Play’s Data safety section](https://support.google.com/googleplay/android-developer/answer/10787469?hl=en).

## Reviewer access instructions

Do not place real credentials in this repository. Replace bracketed placeholders
only inside Play Console. The review account must remain active, email-verified and
usable throughout review.

**Draft text for App access**

> The main News, Events and Organizations tabs can be browsed without an account.
> To review authenticated features, select Profile, choose Sign in, and use:
> email `[PLAY_REVIEW_EMAIL]`; password `[PLAY_REVIEW_PASSWORD]`.
>
> The account is already email-verified and active. It does not own an organization
> and can demonstrate profile settings, saved content, follows, event registrations,
> notification preferences, support/feedback, blocking/reporting and account
> deletion prerequisites without privileged administration.
>
> If a privileged workflow is included in the submitted release, use the separate
> account `[PLAY_REVIEW_PRIVILEGED_EMAIL]` with password
> `[PLAY_REVIEW_PRIVILEGED_PASSWORD]`. TOTP instructions/code delivery:
> `[PLAY_REVIEW_TOTP_INSTRUCTIONS]`. Do not require a reviewer to contact support,
> create a new account, wait for manual role approval, or use an expiring credential.
>
> Account deletion: Profile → Konto löschen / Видалити обліковий запис. The
> external deletion instructions are at
> https://ukrainiancommunity-dbd5f.web.app/delete-account.

Reviewer checklist:

- Test credentials contain no personal data and cannot access production owner
  secrets or unrelated private user data.
- Disable destructive owner/admin controls if they are not essential to review;
  otherwise provide a disposable, bounded privileged account and exact TOTP path.
- Verify sign-in, email-verification state, notification prompts, locale switching,
  account deletion and logout immediately before submission.
- Explain that notification permission is optional and public content remains
  available when it is denied.
- Provide any non-obvious navigation, test content ID or regional availability in
  the “Any other instructions” field.
- Keep backend data and the accounts available until review is complete.

Official review guidance: [Prepare your app for review](https://support.google.com/googleplay/android-developer/answer/9859455?hl=en) and
[publishing tips, including login credentials](https://support.google.com/googleplay/android-developer/answer/15191715?hl=en).

## App content declarations

- **Ads:** No, if the final AAB remains free of ad SDKs and advertising placements.
- **Content rating:** complete the IARC questionnaire against actual UGC,
  communication, moderation and external-link behavior. Do not infer a rating from
  the minimum account age.
- **Target audience:** policy says the service is not directed to children under 14.
  The exact Play age groups remain an operator/legal choice. Selecting `13–15`
  must be reviewed against Play’s children/families consequences; selecting only
  older groups must still be consistent with registration wording and real users.
- **UGC:** declare user-generated content. Verify readily discoverable in-app report
  and block controls for users and content, terms acceptance, moderation and timely
  response operations.
- **News and Magazine:** **UNCERTAIN.** The app contains a separately labelled news
  section and the proposed short description says “Nachrichten/Новини.” Determine
  the primary category and complete the News and Magazine declaration if Play treats
  the app as in scope. If declared as an aggregator, source attribution must be
  accurate for third-party material.
- **Permissions declaration:** the audited manifest has no SMS, Call Log, broad
  storage, location, camera, microphone, exact-alarm, `QUERY_ALL_PACKAGES`, ad-ID or
  other currently observed high-risk Play permission. Recheck the final merged AAB;
  Play decides which forms are required after upload.

Official sources:

- [Content rating requirements](https://support.google.com/googleplay/android-developer/answer/9859655?hl=en)
- [UGC moderation, reporting and blocking](https://support.google.com/googleplay/android-developer/answer/12923286?hl=en)
- [News and Magazine declaration](https://support.google.com/googleplay/android-developer/answer/16189314?hl=en)
- [Permissions declarations](https://support.google.com/googleplay/android-developer/answer/9214102?hl=en)

## Graphics and screenshots

Required/prepared state:

| Asset | Play requirement | Current evidence | Action |
| --- | --- | --- | --- |
| Store icon | 512 × 512 PNG, Play asset separate from the launcher resource | Android source has a 1024 × 1024 app image, but no reviewed 512 × 512 Play export | Export and visually verify a dedicated store icon. |
| Feature graphic | 1024 × 500, JPEG or 24-bit PNG without alpha | Missing | Create DE-neutral or separately localized approved artwork. |
| Phone screenshots | At least two are needed for a publishable store listing; use current Play constraints and accurate in-app imagery | Four audit captures exist at 1080 × 2424, but they show development/audit state and are not a signed-release store set | Capture clean final-AAB guest and signed-in screens; provide separate DE/UK images wherever text is visible. |
| Tablet/other form factors | Required only when distributing/optimizing for the applicable form factor, subject to the current Console prompts | No release tablet screenshot proof | Decide supported devices after Play device-catalog review; do not imply optimized tablet UX without testing. |
| Promo video | Optional | Missing | Omit for first release unless a final localized video is prepared. |

Suggested screenshot story for each language:

1. Home with current featured banner and regional quick filters.
2. News list and readable detail.
3. Events list/detail with registration capability shown accurately.
4. Organizations discovery and detail.
5. Saved/registrations/subscriptions for an authenticated test account.
6. Profile privacy, notification and safety controls.

Do not use staging/local labels, synthetic `.invalid` accounts, debug banners,
private IDs, unapproved user content, copyrighted source imagery without rights,
ranking claims, prices, “best” claims, or features not present in the exact release.

Official asset rules and guidance:

- [Add preview assets to showcase your app](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en-GB)
- [Store listing best practices](https://support.google.com/googleplay/android-developer/answer/13393723?hl=en)

## Release and Play checks

- Freeze source, build a fresh signed `productionRelease` AAB, and verify package,
  `versionCode`, `versionName`, certificate and SHA-256. The older build artifact is
  not evidence for the final source snapshot.
- Enrol in Play App Signing and distinguish the locally retained upload key from
  Google Play’s app-signing key. Back up the upload keystore and recovery material.
- Register relevant Play app-signing certificate fingerprints with services that
  bind app identity, then test the Play-delivered build rather than a local debug APK.
- `targetSdk 36` matches the mobile-app target requirement effective 2026-08-31;
  recheck immediately before submission.
- Validate the two bundled native-library families on a 16 KB page-size device and
  inspect Play’s bundle/pre-launch reports.
- Upload first to Internal testing. If the developer account is a personal account
  created after 2023-11-13, verify whether the current requirement for 12 testers
  continuously opted into Closed testing for 14 days applies before production
  access.
- Run physical-device Play Integrity/App Check, Auth/email links/TOTP, FCM
  foreground/background/cold start, Storage upload, callable/read-back, deletion,
  notification permission and release-minified runtime tests.
- Complete Store settings, countries, category, contact email, privacy URL, Data
  Safety, App access, target audience, content rating, ads, UGC/news declarations,
  pricing and review release notes. Upload/review/rollout remain separate actions.

Official release sources:

- [Create and set up an app](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en)
- [Use Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756?hl=en)
- [Set up an internal, closed or open test](https://support.google.com/googleplay/android-developer/answer/9845334?hl=en)
- [Testing requirements for new personal accounts](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en-GB)
- [Target API level requirements](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en-GB_ALL)
- [Support 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes)

## Submission stop conditions

Do not submit while any of these remains true:

- the AAB predates source freeze or fails release/R8/runtime verification;
- privacy, presence timing, Data Safety, app behavior and deletion wording disagree;
- `/privacy`, `/delete-account` or `/support` is unavailable or stale;
- reviewer credentials or required TOTP access do not work;
- Play Integrity/App Check rejects a legitimate Play-installed build;
- the final screenshots/listing promise a feature that the exact release does not
  provide;
- required Console declarations or applicable closed-testing access are incomplete.
