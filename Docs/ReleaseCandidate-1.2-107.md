# UAC 1.2 (107) — release preparation

This is a TestFlight candidate. The public App Store version remains 1.1 (82). Public submission and publication require a separate decision after the open gates in `Docs/ReleaseGates-1.2.json` are closed.

## TestFlight: What to Test

**Українська**

Перевірте вхід через email, Apple, Google та ключ доступу; повторне прийняття оновлених умов; навігацію Довідника; перемикання мови й регіону. Окремо перевірте добровільне вимірювання банерів: згоду, показ після секунди видимості, натискання, відкликання згоди та звіт власника за різні періоди. Повідомляйте про екрани, де дані не оновлюються або виглядають неправильно.

**Deutsch**

Bitte prüfen Sie die Anmeldung per E-Mail, Apple, Google und Passkey, die erneute Zustimmung zu aktualisierten Rechtstexten, die Navigation im Ratgeber sowie Sprach- und Regionswechsel. Prüfen Sie die gesondert freiwillige Banner-Messung: Einwilligung, Einblendung nach einer Sekunde Sichtbarkeit, Klick, Widerruf und den Bericht des App-Inhabers für verschiedene Zeiträume. Melden Sie Ansichten mit fehlenden oder unplausiblen Daten.

## App Store: What's New (draft)

**Українська**

У версії 1.2 з’явилися вхід через Apple і Google та ключі доступу. Довідник став повнішим і зручнішим для пошуку потрібної інформації. Ми покращили роботу правових повідомлень за слабкого зв’язку, налаштування безпеки та стабільність застосунку. Власник платформи може переглядати зведені покази й натискання банерів лише за окремою добровільною згодою користувача.

**Deutsch**

Version 1.2 ergänzt die Anmeldung mit Apple und Google sowie Passkeys. Der Ratgeber bietet mehr Inhalte und eine klarere Navigation. Hinweise bei schwacher Verbindung, Kontosicherheit und Stabilität wurden verbessert. Der App-Inhaber kann zusammengefasste Banner-Einblendungen und Klicks nur nach gesonderter freiwilliger Einwilligung der Nutzer sehen.

## App Review notes to replace the 1.1 text

UAC now requires an account. Reviewers can use the ordinary, email-verified review account supplied in App Store Connect; its credentials must stay in the dedicated sign-in fields. Email/password, Sign in with Apple, Google sign-in and passkeys are available. A newly signed-in account must review and accept the current Terms and Privacy Policy before accessing the app. Updated mandatory legal documents require fresh acceptance; declining leads to sign-out.

First-party content analytics and banner measurement are separate optional choices. Both require an affirmative action before collection, can be withdrawn in Settings, and do not block the basic account. The owner-only analytics screen shows aggregate reports, not user lists. Banner measurement counts eligible impressions and clicks after separate consent. No IDFA, advertising network, or cross-app tracking is used.

Use the ordinary review account for account-deletion or comment-moderation tests. Owner and administrator access has additional authentication. Account deletion is available in Profile > Settings. Support and privacy pages are linked in the app and on the product page.

## Current release limits

- External TestFlight availability depends on Apple's Beta App Review. Assignment or submission is not approval.
- Banner counts are consent-based action counts, not unique visitors or billing-grade reach. Events waiting offline may be discarded if the banner becomes ineligible before delivery.
- Physical-device sign-in, passkey, push, App Attest, content rights, final comment flows, final App Privacy/archive comparison and current screenshots need evidence before public App Review.
