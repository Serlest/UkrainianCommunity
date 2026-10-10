import Foundation

extension DirectoryCatalog {
    static let lifeCategories: [DirectoryCategory] = [
        category("health", "Здоров’я", "Gesundheit",
                 summaryUK: "Лікарі, лікарні, ліки, діти та профілактика", summaryDE: "Ärzte, Krankenhäuser, Medikamente, Kinder und Vorsorge",
                 symbol: "cross.case.fill", topics: [
            topic("where-to-go", "Куди звернутися спочатку", "Wohin zuerst?"),
            topic("doctors", "Лікарі та прийом", "Ärzte & Termine"),
            topic("specialists", "Спеціалісти та направлення", "Fachärzte & Überweisungen"),
            topic("clinics", "Клініки та лікарні", "Kliniken & Krankenhäuser"),
            topic("dental", "Стоматологія", "Zahnbehandlung"),
            topic("medication", "Аптеки та ліки", "Apotheken & Medikamente"),
            topic("ongoing-care", "Хронічні хвороби й терапія", "Chronische Erkrankungen & Therapie"),
            topic("pregnancy", "Вагітність і пологи", "Schwangerschaft & Geburt"),
            topic("child-health", "Здоров’я дітей", "Kindergesundheit"),
            topic("prevention", "Щеплення та профілактика", "Impfungen & Vorsorge"),
            topic("patient-rights", "Права пацієнта й скарги", "Patientenrechte & Beschwerden")
        ]),
        category("mental-health", "Психічне здоров’я", "Psychische Gesundheit",
                 summaryUK: "Підтримка й консультації", summaryDE: "Unterstützung und Beratung",
                 symbol: "brain.head.profile", topics: [
            topic("counseling", "Психологічні консультації", "Psychologische Beratung"),
            topic("crisis", "Допомога під час кризи", "Hilfe in Krisen"),
            topic("children", "Підтримка дітей", "Unterstützung für Kinder")
        ]),
        category("insurance", "Страхування", "Versicherung",
                 summaryUK: "Медичне та інше страхування", summaryDE: "Kranken- und weitere Versicherungen",
                 symbol: "checkmark.shield.fill", topics: [
            topic("ukrainian-cover", "Страхування для українців", "Versicherung für Ukrainer"),
            topic("health-cover", "Медичне страхування жителів", "Krankenversicherung für Einwohner"),
            topic("family-cover", "Страхування сім’ї", "Familienversicherung"),
            topic("other-cover", "Інші види страхування", "Weitere Versicherungen")
        ]),
        category("work", "Робота", "Arbeit",
                 summaryUK: "Працевлаштування й трудові права", summaryDE: "Jobs und Arbeitnehmerrechte",
                 symbol: "briefcase.fill", topics: [
            topic("work-rights", "Право на роботу", "Arbeitsberechtigung"),
            topic("job-search", "Пошук роботи", "Arbeitssuche"),
            topic("employee-rights", "Трудові права", "Arbeitnehmerrechte"),
            topic("self-employment", "Самозайнятість", "Selbstständigkeit")
        ]),
        category("qualifications", "Кваліфікації", "Qualifikationen",
                 summaryUK: "Дипломи й професійне навчання", summaryDE: "Abschlüsse und Berufsbildung",
                 symbol: "graduationcap.fill", topics: [
            topic("recognition", "Визнання дипломів", "Anerkennung von Abschlüssen"),
            topic("regulated-professions", "Регульовані професії", "Reglementierte Berufe"),
            topic("training", "Професійні курси", "Berufliche Weiterbildung")
        ]),
        category("education", "Освіта", "Bildung",
                 summaryUK: "Садок, школа й навчання", summaryDE: "Kindergarten, Schule und Studium",
                 symbol: "books.vertical.fill", topics: [
            topic("kindergarten", "Дитячий садок", "Kindergarten"),
            topic("school", "Школа", "Schule"),
            topic("higher-education", "Вища освіта", "Hochschule"),
            topic("language", "Мовні курси", "Sprachkurse")
        ]),
        category("family", "Сім’я та діти", "Familie & Kinder",
                 summaryUK: "Догляд за дітьми й підтримка сім’ї", summaryDE: "Kinderbetreuung und Familienhilfe",
                 symbol: "person.2.fill", topics: [
            topic("childcare", "Догляд за дітьми", "Kinderbetreuung"),
            topic("parenting", "Підтримка батьків", "Elternberatung"),
            topic("family-services", "Сімейні служби", "Familienangebote")
        ]),
        category("transport", "Транспорт", "Mobilität",
                 summaryUK: "Міський транспорт, поїзди й таксі", summaryDE: "Nahverkehr, Bahn und Taxi",
                 symbol: "tram.fill", topics: [
            topic("local-transport", "Міський транспорт", "Öffentlicher Nahverkehr"),
            topic("rail", "Поїзди", "Bahn"),
            topic("bus", "Міжміські автобуси", "Fernbusse"),
            topic("taxi", "Таксі", "Taxi"),
            topic("accessible-travel", "Безбар’єрні поїздки", "Barrierefrei unterwegs")
        ])
    ]
}
