# Android cross-platform legal wording — approval draft

Status: **draft only**. This does not change, publish, activate or supersede the
current iOS legal documents. It records the smallest bilingual wording changes
needed before the Android build can use the same legal family.

## Verified public/source mismatch on 2026-09-07

| Page | Public read-back | Repository source | Required action |
| --- | --- | --- | --- |
| `/privacy` | HTTP 200; version 2026.13; scope says iOS only | Same iOS-only scope and Apple-only local-lock wording | Approve a new immutable bilingual version before publication. |
| `/terms` | Not changed by this draft | Version 2026.10 says iOS only; Ukrainian notification settings name iOS | Approve a new immutable bilingual version before publication. |
| `/support` | HTTP 200; live wording says iOS only | Source already says iOS or Android | Deploy/read back together with the approved cross-platform release. |
| `/delete-account` | HTTP 404 | Source covers iOS and Android | Deploy and verify mobile layout, both languages and mail flow. |
| `/report-illegal-content` | HTTP 200 | Existing shared page | No Android-specific text change identified in this pass. |

## Proposed privacy replacements

Candidate version identifier: `2026.14` **only after owner/legal approval**.

### Scope — German

> Diese Erklärung gilt für die iOS- und Android-App UkrainianCommunity sowie die
> öffentlichen Support- und Rechtsseiten. UkrainianCommunity ist Verantwortlicher
> für Konten, Plattformbetrieb, Zugriffskontrolle, Moderation, Sicherheit,
> Benachrichtigungen und die hier beschriebene Erstanbieter-Analyse.

### Scope — Ukrainian

> Ця політика поширюється на застосунок UkrainianCommunity для iOS та Android, а
> також на публічні сторінки підтримки й правових документів. UkrainianCommunity є
> відповідальною особою щодо облікових записів, роботи платформи, контролю доступу,
> модерації, безпеки, сповіщень і описаної тут аналітики першої сторони.

### Security attestation — German

Replace `App Check/App Attest` with:

> App Check mit Apple App Attest beziehungsweise Google Play Integrity hilft zu
> prüfen, ob Anfragen von einer echten App-Instanz stammen.

### Security attestation — Ukrainian

Replace `App Check/App Attest` with:

> App Check разом з Apple App Attest або Google Play Integrity допомагає
> підтвердити, що запит надходить від справжнього екземпляра застосунку.

### Local app lock — German

> Die Prüfung erfolgt durch die lokale Systemauthentifizierung des Geräts — auf
> iOS über Apple LocalAuthentication, auf Android über die geschützte
> Biometrie-/Gerätecode-Schnittstelle. Je nach Gerätekonfiguration kann der
> Gerätecode als Alternative angeboten werden. Wir erhalten ausschließlich das
> Ergebnis der Prüfung, keine Gesichtsvorlage, Fingerabdrücke oder den Gerätecode.

### Local app lock — Ukrainian

> Перевірку виконує локальна системна автентифікація пристрою — Apple
> LocalAuthentication в iOS або захищений системний інтерфейс біометрії чи коду
> пристрою в Android. Залежно від налаштувань альтернативою може бути код пристрою.
> Ми отримуємо лише результат перевірки, а не шаблон обличчя, відбитки пальців чи
> код пристрою.

The remainder of the existing paragraph about local-only hashed account settings,
no cross-device synchronization and no biometric transfer can remain unchanged.

## Proposed terms replacements

### Scope — German

Replace `Diese Bedingungen gelten für die iOS-App` with:

> Diese Bedingungen gelten für die iOS- und Android-App, die zugehörigen
> Webseiten und alle darin angebotenen Funktionen.

### Scope — Ukrainian

Replace `Ці умови поширюються на iOS-застосунок` with:

> Ці умови поширюються на застосунок для iOS та Android, пов’язані вебсторінки та
> всі доступні в них функції.

### Notification settings — Ukrainian

Replace the final sentence of the notification section with:

> Налаштування керуються в застосунку й системних параметрах iOS або Android.

The German notification paragraph is already platform-neutral.

## Build 72 additions to review before approval

The privacy inventory must explicitly account for the new announcement flow:

- Firebase Installation ID and FCM token used for optional delivery;
- a secret-derived installation document identifier and short-lived challenge;
- platform, language, account binding, verification and delivery timestamps;
- presentation, acknowledgement and action receipts;
- anonymous guest metrics derived from the installation secret;
- delivery outcome and bounded retry state;
- translation rate-limit records and text sent to the existing translation service.

The current code avoids personal announcement content in lock-screen text and push
data. The legal owner should still confirm purposes, legal bases, recipients,
retention and whether guest metrics need a separate description before approving
the candidate version.

## Approval and publication gate

Before any source replacement or Hosting deployment:

1. approve both language texts and the new immutable version identifier;
2. update Firestore legal documents and active pointers without rewriting old versions;
3. update Hosting privacy/terms/support/deletion pages in one scoped release;
4. verify HTTP 200, locale switching, hashes and preservation of unrelated Hosting files;
5. update the Android bundled legal snapshot and acceptance contract to the same version;
6. retest iOS legal history/acceptance so Android enablement cannot regress iOS.
