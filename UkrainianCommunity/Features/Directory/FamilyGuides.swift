import Foundation

enum FamilyGuides {
    private static let childcare = DirectorySource(name: "oesterreich.gv.at · Kinderbetreuung", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/familie-und-kinderfuersorge/kinderbetreuung/2/Seite.370110")
    private static let childcareFunding = DirectorySource(name: "oesterreich.gv.at · Kinderbetreuungsbeihilfe", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/familie-und-kinderfuersorge/kinderbetreuung/Seite.370300")
    private static let familyAdvice = DirectorySource(name: "oesterreich.gv.at · Familienberatungsstellen", url: "https://www.oesterreich.gv.at/de/themen/familie_und_partnerschaft/online_services_zu_familie_und_partnerschaft/Aktuelle-Apps")
    private static let familySearch = DirectorySource(name: "Bundeskanzleramt · Familienberatung", url: "https://www.familienberatung.gv.at/beratungsstellen/")
    private static let childHelp = DirectorySource(name: "Gesundheitsportal · Hilfe für Kinder und Jugendliche", url: "https://www.gesundheit.gv.at/service/beratungsstellen/gesund-leben/gesunde-lebenswelten/schulberatung.html")

    static func guide(for topicID: String) -> DirectoryGuide? {
        switch topicID {
        case "childcare": childcareGuide
        case "parenting": parenting
        case "family-services": familyServices
        default: nil
        }
    }

    private static let childcareGuide = DirectoryGuide(
        cardSummary: .init(ukrainian: "Ясла, садок, Hort, Tageseltern і допомога з оплатою", german: "Krippe, Kindergarten, Hort, Tageseltern und Kostenhilfe"),
        introduction: .init(ukrainian: "Оберіть догляд за віком дитини, робочим графіком і потребами сім’ї. Про запис і обов’язковий рік садка детально написано в категорії «Освіта».", german: "Wählen Sie Betreuung nach Alter, Arbeitszeiten und Familienbedarf. Anmeldung und Pflichtjahr stehen ausführlich unter „Bildung“."),
        sections: [
            .init("options", "figure.child", "Порівняйте варіанти", "Angebote vergleichen", "До трьох років зазвичай доступні Kinderkrippe або Tageseltern; старшим — Kindergarten, школярам — Hort чи цілоденна школа. Запитайте про реальний час відкриття, закриття на канікули, харчування, доступність для дитини з інвалідністю й правила відсутності через хворобу.", "Für Kinder unter drei kommen Krippe oder Tageseltern infrage, später Kindergarten, für Schulkinder Hort oder Ganztagsschule. Tatsächliche Öffnungszeiten, Ferien, Essen, Inklusion und Regeln bei Krankheit erfragen.", source: childcare),
            .init("search", "magnifyingglass", "Шукайте через громаду", "Über die Gemeinde suchen", "Попросіть Gemeinde/Magistrat перелік місць і строки заяв, паралельно спитайте приватні заклади. Не вважайте внесення до списку очікування гарантією місця. Якщо працюєте позмінно, попросіть одразу пояснити ранні, вечірні або канікулярні варіанти.", "Gemeinde/Magistrat nach Plätzen und Fristen fragen und private Einrichtungen parallel kontaktieren. Warteliste ist keine Platzzusage. Bei Schichtarbeit früh nach Randzeiten und Ferienbetreuung fragen.", source: childcare),
            .init("cost", "eurosign.circle", "Вартість та AMS-допомога", "Kosten und AMS-Beihilfe", "Порівняйте внесок, харчування й додаткові години; суми залежать від землі та установи. Якщо догляд потрібен для роботи чи курсу, запитайте AMS про Kinderbetreuungsbeihilfe ще до початку роботи, заходу й догляду: пізня заява може не покрити витрати. Земля може мати власні пільги.", "Beitrag, Essen und Zusatzstunden vergleichen; Kosten hängen von Land und Einrichtung ab. Für Arbeit oder Kurs AMS vor Arbeits-, Maßnahmen- und Betreuungsbeginn nach Kinderbetreuungsbeihilfe fragen: spätere Anträge können zu spät sein. Landeseigene Förderung prüfen.", source: childcareFunding)
        ], sources: [childcare, childcareFunding]
    )

    private static let parenting = DirectoryGuide(
        cardSummary: .init(ukrainian: "Безкоштовна розмова про виховання, стосунки та кризу в родині", german: "Kostenlose Beratung zu Erziehung, Beziehung und Familienkrisen"),
        introduction: .init(ukrainian: "По допомогу можна звернутися до того, як ситуація стане кризою. Державою підтримувані сімейні консультації безкоштовні й конфіденційні.", german: "Hilfe ist schon vor einer Krise möglich. Staatlich geförderte Familienberatung ist kostenlos und vertraulich."),
        sections: [
            .init("find", "person.2", "Знайдіть консультацію", "Beratung finden", "На державному порталі оберіть землю, тему й спосіб консультації. Запитайте про мову, участь другого з батьків, конфіденційність і можливість онлайн-розмови. На першу зустріч підготуйте короткий опис проблеми й питання, яких хочете торкнутися.", "Auf dem staatlichen Portal Bundesland, Thema und Beratungsform auswählen. Nach Sprache, Einbeziehung des anderen Elternteils, Vertraulichkeit und Online-Termin fragen. Für das Erstgespräch Anliegen und Fragen kurz notieren.", source: familySearch),
            .init("child", "figure.child", "Якщо складно дитині", "Wenn das Kind belastet ist", "Запитайте дитину, з ким вона хоче говорити, та зверніться до педіатра, шкільної психології або відповідної консультації. Для дитини й підлітка доступна анонімна безкоштовна лінія 147. При безпосередній загрозі життю чи насильстві телефонуйте 144 або 133.", "Fragen Sie das Kind nach einer vertrauten Person und kontaktieren Sie Kinderarzt, Schulpsychologie oder Beratung. Kinder und Jugendliche erreichen anonym und kostenlos 147. Bei unmittelbarer Lebens- oder Gewaltgefahr 144 oder 133 wählen.", phoneNumber: "147", source: childHelp),
            .init("plan", "checklist", "Домовтеся про наступний крок", "Nächsten Schritt vereinbaren", "Попросіть консультанта сформулювати, яку допомогу можна отримати далі: батьківські зустрічі, психолог, медіація або соціальна служба. Якщо проблема пов’язана з насильством, не погоджуйтеся на спільну розмову без оцінки безпеки; зверніться до центру захисту в категорії «Безпека».", "Mit der Beratung nächste Schritte festlegen: Elternberatung, Psychologie, Mediation oder Sozialdienst. Bei Gewalt keine gemeinsame Aussprache ohne Sicherheitsklärung vereinbaren; nutzen Sie die Gewaltschutzhilfe unter „Sicherheit“.", source: familyAdvice)
        ], sources: [familySearch, familyAdvice, childHelp]
    )

    private static let familyServices = DirectoryGuide(
        cardSummary: .init(ukrainian: "Сімейні консультації, Kinder- und Jugendhilfe й захист дитини", german: "Familienberatung, Kinder- und Jugendhilfe und Kinderschutz"),
        introduction: .init(ukrainian: "Різні установи вирішують різні питання: консультації підтримують добровільно, Kinder- und Jugendhilfe організовує допомогу та захист, суд розглядає спори про опіку.", german: "Stellen haben unterschiedliche Aufgaben: Beratung unterstützt freiwillig, Kinder- und Jugendhilfe organisiert Hilfe und Schutz, Gerichte entscheiden Obsorgekonflikte."),
        sections: [
            .init("advice", "bubble.left.and.bubble.right", "Добровільна сімейна консультація", "Freiwillige Familienberatung", "Шукайте державою підтримувану Familienberatungsstelle за місцем проживання. Вона може допомогти із вихованням, розлукою, вагітністю, конфліктами й побутовими питаннями. Уточніть мову, конфіденційність та чи потрібен запис; сама консультація безкоштовна.", "Suchen Sie eine öffentlich geförderte Familienberatungsstelle am Wohnort. Sie hilft bei Erziehung, Trennung, Schwangerschaft, Konflikten und Alltag. Sprache, Vertraulichkeit und Termin klären; Beratung ist kostenlos.", source: familyAdvice),
            .init("welfare", "hand.raised", "Якщо дитині потрібен захист", "Wenn ein Kind Schutz braucht", "Зверніться до Kinder- und Jugendhilfe місцевої Bezirksverwaltungsbehörde або Magistrat. Опишіть конкретні факти, безпечний спосіб зв’язку і терміновість. При безпосередній небезпеці — поліція 133; дитина може також самостійно зателефонувати 147. Місцева служба визначить форму підтримки з урахуванням інтересів дитини.", "Kontaktieren Sie Kinder- und Jugendhilfe bei Bezirksverwaltungsbehörde oder Magistrat. Konkrete Beobachtungen, sicheren Rückruf und Dringlichkeit nennen. Bei akuter Gefahr Polizei 133; das Kind kann selbst 147 anrufen. Die lokale Stelle prüft passende Hilfe im Kindeswohlinteresse.", source: childHelp),
            .init("custody", "doc.text", "Опіка та контакт після розлуки", "Obsorge und Kontakt nach Trennung", "Запишіть існуючі судові рішення й домовленості, не змінюйте їх односторонньо. Для спору про опіку або контакт зверніться за юридичною консультацією; Familiengerichtshilfe працює лише за дорученням суду й не є звичайною консультацією. При ризику насильства спочатку складіть план безпеки.", "Bestehende Gerichtsbeschlüsse und Absprachen festhalten, nicht einseitig ändern. Für Obsorge- oder Kontaktstreit Rechtsberatung suchen; Familiengerichtshilfe handelt im Gerichtsauftrag und ist keine allgemeine Beratungsstelle. Bei Gewalt zuerst Sicherheit klären.", source: familyAdvice)
        ], sources: [familyAdvice, familySearch, childHelp]
    )
}
