# Registration wording for the next legal-document versions

This is a review draft, not an active legal document. The bundled fallback currently
identifies Terms `2026.10` and Privacy `2026.13`; the active Firebase versions must be
read back before creating successor drafts. Published versions and their content hashes
must remain immutable.

## Terms, section 3

Replace the first sentence of the registration paragraph.

- DE: „Die Nutzung der App setzt ein persönliches Konto voraus. Für die Registrierung
  sind richtige und aktuelle Angaben erforderlich.“
- UK: „Для користування застосунком потрібен особистий обліковий запис. Під час
  реєстрації слід указувати правдиві й актуальні дані.“

Keep the rest of the paragraph on personal accounts, credential sharing, and incident
reporting, subject to the owner's legal review.

## Privacy, section 5

The current paragraph says a password is required for every account. Replace its first
two sentences with wording that distinguishes email/password from Apple and Google.

- DE: „Für ein Konto benötigen wir eine E-Mail-Adresse, einen Anzeigenamen, das
  ausdrücklich ausgewählte österreichische Bundesland, die Bestätigung des Mindestalters
  und eine technische Konto-ID. Ein Passwort ist nur bei Registrierung mit E-Mail und
  Passwort erforderlich; es wird von Firebase Authentication verarbeitet und nicht als
  Profilfeld oder im Administrationsbereich gespeichert. Bei Anmeldung mit Apple oder
  Google erhalten wir die für die Anmeldung und Kontoverknüpfung erforderlichen
  Anbieterangaben über Firebase Authentication.“
- UK: „Для облікового запису потрібні електронна адреса, ім’я для показу, явно вибрана
  федеральна земля Австрії, підтвердження мінімального віку й технічний ID. Пароль
  потрібен лише для реєстрації за електронною адресою і паролем; його обробляє Firebase
  Authentication, а не поле профілю чи адміністративний розділ. Під час входу через
  Apple або Google ми отримуємо через Firebase Authentication дані постачальника,
  потрібні для входу та прив’язки облікового запису.“

Review the remaining paragraph and section 8 for an accurate description of the exact
Apple/Google data received and each provider's role before publication.

## Privacy, section 19

Replace the opening paragraph about the optional local app lock.

- DE: „Bei der Registrierung oder später im Profil kann freiwillig eine lokale
  App-Sperre aktiviert werden; die Auswahl ist zunächst ausgeschaltet. Sie schützt
  eine bereits bei Firebase angemeldete Sitzung unabhängig davon, ob die Anmeldung
  mit E-Mail und Passwort, Apple oder Google erfolgte. Die lokale Sperre ist von
  diesen Anmeldemethoden getrennt und ersetzt sie nicht. Ein- und Ausschalten
  bleiben im Profil möglich.“
- UK: „Під час реєстрації або пізніше в профілі можна добровільно ввімкнути локальне
  блокування застосунку; спочатку цей перемикач вимкнений. Воно захищає сесію,
  у яку вже виконано вхід через Firebase, незалежно від способу входу: електронна
  адреса й пароль, Apple або Google. Локальне блокування є окремим від цих способів
  входу й не замінює їх. У профілі його можна вмикати та вимикати.“

## Publication checks

1. Review both languages and the full provider data flow; update App Store privacy
   answers if the real collection changes.
2. Create successor versions through the legal-document owner workflow, with new
   hashes and a change summary. Do not overwrite an accepted published version.
3. Read back the published Firebase pointer and document, then verify in-app
   acceptance and the public privacy page.

References: [GDPR Article 13](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32016R0679),
[Apple App Review Guidelines 5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage).
