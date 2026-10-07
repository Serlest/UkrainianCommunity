import Foundation

extension DocumentGuides {
    static let translations = DirectoryGuide(
        cardSummary: .init(ukrainian: "Коли потрібен присяжний перекладач і що перекладати", german: "Wann ein gerichtlich beeideter Übersetzer nötig ist"),
        introduction: .init(ukrainian: "Апостиль підтверджує справжність підпису й печатки, а переклад передає зміст. Це дві різні дії; вимоги задає установа, якій ви подаєте документ.", german: "Die Apostille bestätigt Unterschrift und Siegel; die Übersetzung überträgt den Inhalt. Das sind verschiedene Schritte; die empfangende Behörde bestimmt die Anforderungen."),
        sections: [
            .init("ask", "questionmark.circle", "Спитайте перед замовленням", "Vorher bei der Behörde fragen",
                  "Уточніть: потрібен оригінал чи копія; приймають українську / англійську чи потрібна німецька; чи має переклад бути засвідченим у Австрії; чи потрібен апостиль. Вимоги для MA 35, Standesamt, школи, університету чи роботодавця можуть відрізнятися.",
                  "Fragen Sie: Original oder Kopie; wird Ukrainisch/Englisch akzeptiert oder ist Deutsch nötig; muss die Übersetzung in Österreich beglaubigt sein; ist eine Apostille erforderlich? Anforderungen von MA 35, Standesamt, Schule, Hochschule oder Arbeitgeber können unterschiedlich sein."),
            .init("sworn", "person.text.rectangle", "Завірений переклад для Австрії", "Beglaubigte Übersetzung für Österreich",
                  "Якщо орган вимагає beglaubigte Übersetzung, шукайте загальноприсяжного й судово сертифікованого перекладача у державному реєстрі Justiz за мовою «Ukrainisch» та федеральною землею. Уточніть, чи перекладати апостиль, усі сторінки, печатки та зворот документа.",
                  "Verlangt die Behörde eine beglaubigte Übersetzung, suchen Sie in der amtlichen Justiz-Liste nach allgemein beeideten und gerichtlich zertifizierten Übersetzern für „Ukrainisch“ und Ihren Gerichtssprengel. Fragen Sie, ob Apostille, alle Seiten, Stempel und Rückseite mitzuübersetzen sind."),
            .init("ukraine", "arrow.left.arrow.right", "Переклад для України", "Übersetzung für die Ukraine",
                  "Іноземні документи для українського консульства часто подають з перекладом українською, засвідченим у порядку, який воно вказує. Австрійський переклад німецькою не замінює український. Перед оплатою апостиля й перекладу перевірте інструкцію конкретної консульської послуги.",
                  "Ausländische Urkunden für ein ukrainisches Konsulat werden oft mit einer nach dessen Regeln beglaubigten ukrainischen Übersetzung verlangt. Eine deutsche Übersetzung ersetzt diese nicht. Prüfen Sie die Anleitung der konkreten Konsularleistung vor Bezahlung von Apostille und Übersetzung."),
            .init("copies", "doc.on.doc", "Копія, скан і оригінал", "Kopie, Scan und Original",
                  "Завірена копія підтверджує відповідність копії оригіналу, але не замінює апостиль на документі й не доводить правильність змісту. Нотаріус або суд може засвідчити копію чи підпис за своєю компетенцією. Скан із телефону зазвичай достатній лише для попередньої перевірки, якщо орган так дозволяє.",
                  "Eine beglaubigte Kopie bestätigt die Übereinstimmung mit dem Original, ersetzt aber keine Apostille und bescheinigt nicht den Inhalt. Notar oder Gericht können Kopien oder Unterschriften im Rahmen ihrer Zuständigkeit beglaubigen. Ein Handy-Scan reicht meist nur für Vorprüfung, wenn die Behörde dies zulässt.")
        ], sources: [translators, austrianApostille, ukrainianApostille, birthAT]
    )

    static let apostille = DirectoryGuide(
        cardSummary: .init(ukrainian: "Яка держава ставить апостиль і який орган обрати", german: "Welcher Staat und welche Behörde apostilliert"),
        introduction: .init(ukrainian: "Апостиль оформлює держава, яка видала офіційний документ. Спочатку дізнайтеся в приймаючого органу, чи потрібен він саме для цієї мети й цього виду документа.", german: "Die Apostille stellt der Staat aus, der die öffentliche Urkunde ausgestellt hat. Fragen Sie zuerst die empfangende Stelle, ob sie für diesen Zweck und diese Urkunde nötig ist."),
        sections: [
            .init("ukraine", "building.2", "Українське свідоцтво в Австрії", "Ukrainische Urkunde in Österreich",
                  "Для свідоцтв ДРАЦС, витягів, нотаріальних та судових документів МЗС України вказує Мін’юст України; для дипломів — МОН; для довідок про несудимість — МВС; для окремих міграційних і податкових документів — відповідно ДМС чи ДПС. МЗС України відповідає за інші визначені категорії. Тип документа важливіший за те, у якому місті ви живете.",
                  "Für ukrainische Standesamtsurkunden, Auszüge, notarielle und gerichtliche Urkunden nennt das Außenministerium das Justizministerium; für Bildungsnachweise das Bildungsministerium; für Strafregisterauszüge das Innenministerium; für bestimmte Migrations- oder Steuerdokumente DMS bzw. Steuerbehörde. Andere Kategorien fallen dem Außenministerium zu. Entscheidend ist die Dokumentart, nicht Ihr Wohnort."),
            .init("austria", "building.columns", "Австрійський документ в Україні", "Österreichische Urkunde in der Ukraine",
                  "Австрійський документ апостилює компетентний австрійський орган: залежно від видавця це BMEIA, уряд землі або суд. Австрійське BMEIA у Відні не апостилює українські документи. Для окремих електронних австрійських документів існує е-апостиль; перевірте вимоги й збережіть оригінальний електронний файл.",
                  "Eine österreichische Urkunde apostilliert die zuständige österreichische Stelle: je nach Aussteller BMEIA, Landesregierung oder Gericht. Das BMEIA in Wien apostilliert keine ukrainischen Urkunden. Für bestimmte elektronische österreichische Dokumente gibt es e-Apostillen; prüfen Sie die Voraussetzungen und bewahren Sie die originale elektronische Datei auf."),
            .init("bmeia", "mappin.and.ellipse", "Якщо компетентне BMEIA", "Wenn das BMEIA zuständig ist",
                  "Бюро консульських засвідчень приймає без запису за адресою Leopold-Figl-Gasse 5, 1010 Wien, у будні 09:00–12:30. За даними BMEIA, збір — 24,20 € за документ; при поданні поштою додається разовий збір 21 €. Перед поїздкою перевірте, чи потрібне попереднє засвідчення саме вашого австрійського документа і чи не змінилися години та збори.",
                  "Das Büro für Konsularbeglaubigungen nimmt ohne Termin in der Leopold-Figl-Gasse 5, 1010 Wien, werktags 09:00–12:30 Uhr an. Laut BMEIA beträgt die Gebühr 24,20 € je Urkunde; bei postalischer Einreichung kommt eine einmalige Eingabegebühr von 21 € hinzu. Prüfen Sie vor Anreise, ob Ihre österreichische Urkunde vorbeglaubigt werden muss und ob Öffnungszeiten und Gebühren noch gelten.", source: apostilleOffices),
            .init("order", "list.number", "Порядок дій", "Reihenfolge",
                  "1. Отримайте оригінал або повторне свідоцтво.\n2. Спитайте приймаючий орган про апостиль і мову.\n3. Зверніться до компетентного органу держави видачі.\n4. Замовте переклад у формі, яку прийме адресат; уточніть, чи перекладати сам апостиль.\nАпостиль не виправляє помилки у ПІБ або датах — їх виправляє орган видачі.",
                  "1. Besorgen Sie Original oder neue Urkunde.\n2. Fragen Sie die empfangende Stelle nach Apostille und Sprache.\n3. Wenden Sie sich an die zuständige Stelle des Ausstellerstaats.\n4. Lassen Sie in der geforderten Form übersetzen und klären Sie die Übersetzung der Apostille.\nEine Apostille berichtigt keine Fehler in Namen oder Daten; das kann nur die ausstellende Stelle."),
            .init("exceptions", "exclamationmark.circle", "Винятки й консульські документи", "Ausnahmen und Konsularurkunden",
                  "Міжнародні угоди можуть звільняти окремі документи від апостиля. На документи, видані дипломатичними або консульськими установами, Гаазький апостиль за загальним правилом не ставиться. Якщо документ видано консульством, уточніть у приймаючого органу інший спосіб підтвердження або потрібний первинний документ.",
                  "Internationale Abkommen können einzelne Urkunden von der Apostille befreien. Dokumente diplomatischer oder konsularischer Vertretungen fallen grundsätzlich nicht unter die Haager Apostille. Bei Konsularurkunden klären Sie mit der empfangenden Stelle einen anderen Nachweis oder die nötige ursprüngliche Urkunde.")
        ], sources: [ukrainianApostille, austrianApostille, apostilleOffices]
    )

    static let austrianDocuments = DirectoryGuide(
        cardSummary: .init(ukrainian: "Австрійські свідоцтва, Meldebestätigung та довідка про несудимість", german: "Österreichische Urkunden, Meldebestätigung und Strafregister"),
        introduction: .init(ukrainian: "За австрійським документом звертайтеся до австрійського органу, який веде відповідний реєстр. Українське посольство не видає австрійських свідоцтв.", german: "Für österreichische Dokumente ist die österreichische Registerbehörde zuständig. Die ukrainische Botschaft stellt keine österreichischen Urkunden aus."),
        sections: [
            .init("civil", "person.2", "Народження, шлюб, смерть", "Geburt, Ehe, Tod",
                  "Свідоцтва про події, зареєстровані в Австрії, отримують через Standesamt; повторні австрійські витяги можуть бути доступні також через Urkundenservice з ID Austria або EU Login, якщо дані внесено до центрального реєстру. Для подання в Україні перевірте потребу в апостилі та перекладі.",
                  "Urkunden über in Österreich beurkundete Ereignisse erhalten Sie beim Standesamt; neue Auszüge können bei vorhandenen Registerdaten auch über den Urkundenservice mit ID Austria oder EU Login verfügbar sein. Für die Verwendung in der Ukraine klären Sie Apostille und Übersetzung."),
            .init("address", "house", "Підтвердження адреси", "Meldebestätigung",
                  "Meldebestätigung підтверджує адресу в Австрії, а не громадянство чи право перебування. Якщо старе підтвердження загублено або установі потрібне нове, замовте його в Meldebehörde або через офіційний онлайн-сервіс за наявності потрібної електронної ідентифікації.",
                  "Die Meldebestätigung belegt die Adresse in Österreich, nicht Staatsangehörigkeit oder Aufenthaltsrecht. Ist die alte Bestätigung verloren oder wird eine aktuelle verlangt, beantragen Sie sie bei der Meldebehörde oder mit geeigneter elektronischer Identifikation online."),
            .init("criminal", "doc.text.magnifyingglass", "Австрійська довідка про несудимість", "Österreichische Strafregisterbescheinigung",
                  "Strafregisterbescheinigung Австрії запитують у компетентному поліційному органі або громаді, у Відні — у Polizeikommissariat; є й онлайн-сервіс. Це не українська довідка про несудимість. Якщо роботодавець просить спеціальну довідку для догляду або роботи з дітьми, звичайна довідка може не підійти.",
                  "Eine österreichische Strafregisterbescheinigung beantragen Sie bei zuständiger Polizeibehörde oder Gemeinde, in Wien beim Polizeikommissariat; auch ein Onlinedienst existiert. Sie ist keine ukrainische Strafregisterbescheinigung. Für Pflege oder Kinderarbeit kann eine besondere Bescheinigung statt der allgemeinen nötig sein."),
            .init("apostille", "seal", "Для використання за кордоном", "Für die Verwendung im Ausland",
                  "Австрійський документ, призначений для України чи іншої держави, може потребувати апостиля австрійського компетентного органу. У Відні BMEIA приймає лише визначені категорії австрійських документів; для інших зверніться до земельного органу чи суду. Не надсилайте український оригінал до BMEIA як австрійський.",
                  "Eine österreichische Urkunde für die Ukraine oder einen anderen Staat kann eine Apostille der zuständigen österreichischen Stelle brauchen. Das BMEIA in Wien bearbeitet nur bestimmte österreichische Dokumente; sonst sind Landesbehörde oder Gericht zuständig. Senden Sie keine ukrainische Urkunde als österreichisches Dokument an das BMEIA.")
        ], sources: [birthAT, recordsAT, criminalAT, apostilleOffices]
    )
}
