# Privacy revision 2026.21 — banner measurement draft

This is a proposed amendment to `privacy.de.md` and `privacy.uk.md`. It is not
published or active. The current consent for content analytics remains separate.

## Deutsch — in die Datenschutzerklärung übernehmen

**Abschnitt 3, zusätzliche Datenkategorie:** Freiwillige Banner-Messung:
Banner-ID, App-Bereich, sichtbare Einblendung oder Tippen sowie Zeitpunkt.
Für die Übermittlung werden Konto-ID, Zustimmungs-ID und Ereignis-ID zur
Autorisierung und Vermeidung doppelter Zählungen verarbeitet. Ereignisbelege
werden nach 72 Stunden zur Löschung fällig. Die Berichte enthalten tägliche, zusammengefasste
Werte je Banner und App-Bereich; keine Teilnehmerlisten.

**Abschnitt 4, zusätzliche Rechtsgrundlage:** Freiwillige Messung sichtbarer
Banner-Einblendungen und Aufrufe für Reichweitenberichte an den
Plattforminhaber: Art. 6 Abs. 1 lit. a DSGVO (gesonderte Einwilligung).

**Abschnitt 5:** Die Banner-Messung ist freiwillig. Ablehnung oder Widerruf
beeinträchtigen die Nutzung des Basiskontos und die Anzeige der Banner nicht.

**Neuer Abschnitt nach Abschnitt 10:** Die Banner-Messung ist standardmäßig
ausgeschaltet und unabhängig von der Einwilligung in die Analyse von
Nachrichten, Veranstaltungen und Organisationen. Eine Einblendung zählt,
wenn ein Banner mindestens eine Sekunde lang zu mindestens 50 % sichtbar ist;
ein bewusstes Tippen zählt als Aufruf. Die Messung erfolgt nur mit einer
gesonderten, versionierten, serverseitig bestätigten Einwilligung eines
angemeldeten Kontos. Die Wahl gilt für dieses Konto auf allen angemeldeten
Geräten. Sie lässt sich jederzeit in den Einstellungen für die
Zukunft widerrufen. Nach einem Widerruf werden lokal wartende Banner-Ereignisse
verworfen; eine noch nicht bestätigte Widerrufsanfrage wird erneut gesendet.
Es werden keine Werbe-ID, keine Drittanbieter-Werbenetzwerke und kein
appübergreifendes Tracking verwendet. Der Plattforminhaber sieht nur
zusammengefasste Zahlen, keine Besucherlisten für Werbepartner.

**Abschnitt 12, Aufbewahrung:** Ereignisbelege zur Deduplizierung höchstens
72 Stunden (planmäßige Löschung kann sich verzögern); technische Anfragelimits
nach zwei Stunden zur Löschung fällig; tägliche
Banner-Zusammenfassungen 395 Tage. Lokal wartende Ereignisse werden nach
48 Stunden nicht mehr gesendet und beim nächsten Verarbeitungslauf entfernt.
Zustimmungsnachweise bleiben während der Kontobeziehung und
danach nur soweit für gesetzliche Pflichten oder Rechtsansprüche erforderlich;
bei Kontolöschung wird die Konto-ID darin anonymisiert.

## Українською — внести до політики приватності

**Розділ 3, додаткова категорія даних:** Добровільне вимірювання банерів:
ID банера, розділ застосунку, видимий показ або натискання та час. Для
авторизації передачі й захисту від повторного підрахунку ID акаунта, згоди
та події обробляються для перевірки прав і усунення дублів. Квитанції подій
підлягають видаленню через 72 години. Звіти містять зведені денні
показники за банером і розділом, без списків користувачів.

**Розділ 4, додаткова правова підстава:** Добровільне вимірювання видимих
показів і натискань банерів для звітів власнику платформи: ст. 6(1)(a) GDPR
(окрема згода).

**Розділ 5:** Вимірювання банерів добровільне. Відмова або відкликання згоди
не обмежують базовий акаунт і показ самих банерів.

**Новий розділ після розділу 10:** Вимірювання банерів початково вимкнене
й не залежить від згоди на аналітику новин, подій та організацій. Показ
зараховується, коли банер видно щонайменше на 50 % протягом однієї секунди;
свідоме натискання зараховується окремо. Для вимірювання потрібна окрема,
версійна та підтверджена сервером згода користувача, який увійшов до
акаунта. Вибір діє для цього акаунта на всіх пристроях, де виконано вхід.
Її можна відкликати в налаштуваннях у будь-який час із дією на
майбутнє. Після відкликання локальні події в черзі видаляються, а
непідтверджений запит на відкликання надсилається повторно. Рекламний ID,
сторонні рекламні мережі й відстеження між застосунками не використовуються.
Власник платформи бачить лише зведені числа, без списків відвідувачів для
рекламодавців.

**Розділ 12, зберігання:** Квитанції для усунення дублювання підлягають
видаленню через 72 години (планове видалення може затримуватися),
технічні ліміти запитів — через дві години, денні зведення — 395 днів. Локальні
події не передаються після 48 годин і видаляються під час наступної обробки.
Докази згоди зберігаються протягом
існування акаунта, а після цього лише наскільки потрібно для законних
обов’язків або правових вимог; під час видалення акаунта його ID у них
знеособлюється.

Before activation, update both complete policy files and their legal manifest,
publish the privacy revision, update iOS and Android privacy declarations for
the actual data flow, then set the matching app privacy version. Do not infer
banner consent from the existing content-analytics choice.
