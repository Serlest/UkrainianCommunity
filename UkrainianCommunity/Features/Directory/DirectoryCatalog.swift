import Foundation

enum DirectoryCatalog {
    private static func topic(_ id: String, _ uk: String, _ de: String) -> DirectoryTopic {
        DirectoryTopic(id: id, title: DirectoryText(ukrainian: uk, german: de))
    }

    private static func category(
        _ id: String, _ uk: String, _ de: String,
        summaryUK: String, summaryDE: String, symbol: String,
        topics: [DirectoryTopic]
    ) -> DirectoryCategory {
        DirectoryCategory(
            id: id, title: DirectoryText(ukrainian: uk, german: de),
            summary: DirectoryText(ukrainian: summaryUK, german: summaryDE),
            symbol: symbol, topics: topics
        )
    }

    static let categories: [DirectoryCategory] = [
        category("safety", "Безпека та захист", "Sicherheit & Schutz",
                 summaryUK: "Теми про безпеку та підтримку", summaryDE: "Themen zu Schutz und Unterstützung",
                 symbol: "shield.lefthalf.filled", topics: [
            topic("emergency", "Невідкладна допомога", "Notfallhilfe"),
            topic("domestic-violence", "Домашнє насильство", "Häusliche Gewalt"),
            topic("women", "Допомога жінкам", "Hilfe für Frauen"),
            topic("children", "Захист дітей", "Kinderschutz"),
            topic("discrimination", "Дискримінація та переслідування", "Diskriminierung & Belästigung")
        ]),
        category("first-steps", "Перші кроки", "Erste Schritte",
                 summaryUK: "Після прибуття та на початку життя", summaryDE: "Nach der Ankunft und beim Neubeginn",
                 symbol: "figure.walk.arrival", topics: [
            topic("arrival", "Прибуття та перші дії", "Ankunft & erste Schritte"),
            topic("registration", "Реєстрація місця проживання", "Wohnsitz anmelden"),
            topic("initial-support", "Початкова підтримка", "Erste Unterstützung"),
            topic("checklist", "Покроковий список", "Schritt-für-Schritt-Liste")
        ]),
        category("residence", "Статус і документи", "Aufenthalt & Dokumente",
                 summaryUK: "Право перебування та офіційні процедури", summaryDE: "Aufenthaltsrecht und Behördenwege",
                 symbol: "person.text.rectangle", topics: [
            topic("temporary-protection", "Тимчасовий захист", "Vorübergehender Schutz"),
            topic("residence-permits", "Дозволи на проживання та RWR+", "Aufenthaltstitel & RWR+"),
            topic("documents", "Особисті документи", "Persönliche Dokumente"),
            topic("citizenship", "Громадянство", "Staatsbürgerschaft")
        ]),
        category("housing", "Житло", "Wohnen",
                 summaryUK: "Прийом, оренда та житлова допомога", summaryDE: "Aufnahme, Miete und Wohnhilfe",
                 symbol: "house.lodge.fill", topics: [
            topic("reception", "Де приймають людей", "Aufnahmestellen"),
            topic("temporary-housing", "Тимчасове житло", "Vorübergehende Unterkunft"),
            topic("rent", "Оренда та права мешканців", "Miete & Wohnrechte"),
            topic("housing-support", "Допомога з житлом", "Wohnunterstützung")
        ]),
        category("health", "Здоров’я", "Gesundheit",
                 summaryUK: "Лікарі, клініки та психічне здоров’я", summaryDE: "Ärzte, Kliniken und psychische Gesundheit",
                 symbol: "cross.case.fill", topics: [
            topic("doctors", "Лікарі та прийом", "Ärzte & Termine"),
            topic("clinics", "Клініки та лікарні", "Kliniken & Krankenhäuser"),
            topic("medication", "Аптеки та ліки", "Apotheken & Medikamente"),
            topic("mental-health", "Психічне здоров’я", "Psychische Gesundheit"),
            topic("pregnancy", "Вагітність і пологи", "Schwangerschaft & Geburt")
        ]),
        category("insurance", "Страхування", "Versicherung",
                 summaryUK: "Медичне та інше страхування", summaryDE: "Kranken- und weitere Versicherungen",
                 symbol: "checkmark.shield.fill", topics: [
            topic("health-cover", "Медичне страхування", "Krankenversicherung"),
            topic("ukrainian-cover", "Страхування для українців", "Versicherung für Ukrainer"),
            topic("family-cover", "Страхування сім’ї", "Familienversicherung"),
            topic("other-cover", "Інші види страхування", "Weitere Versicherungen")
        ]),
        category("work", "Робота та професія", "Arbeit & Beruf",
                 summaryUK: "Працевлаштування та кваліфікація", summaryDE: "Jobs und Qualifikationen",
                 symbol: "briefcase.fill", topics: [
            topic("work-rights", "Право на роботу", "Arbeitsberechtigung"),
            topic("job-search", "Пошук роботи", "Arbeitssuche"),
            topic("recognition", "Визнання дипломів", "Anerkennung von Abschlüssen"),
            topic("employee-rights", "Трудові права", "Arbeitnehmerrechte"),
            topic("self-employment", "Самозайнятість", "Selbstständigkeit")
        ]),
        category("education", "Освіта та сім’я", "Bildung & Familie",
                 summaryUK: "Діти, навчання та підтримка сім’ї", summaryDE: "Kinder, Lernen und Familienhilfe",
                 symbol: "books.vertical.fill", topics: [
            topic("kindergarten", "Дитячий садок", "Kindergarten"),
            topic("school", "Школа", "Schule"),
            topic("higher-education", "Вища освіта", "Hochschule"),
            topic("language", "Мовні курси", "Sprachkurse"),
            topic("family", "Підтримка сім’ї", "Familienhilfe")
        ]),
        category("transport", "Транспорт", "Mobilität",
                 summaryUK: "Місто, поїзди, автобуси та таксі", summaryDE: "Nahverkehr, Bahn, Bus und Taxi",
                 symbol: "tram.fill", topics: [
            topic("local-transport", "Міський транспорт", "Öffentlicher Nahverkehr"),
            topic("rail", "Поїзди", "Bahn"),
            topic("bus", "Міжміські автобуси", "Fernbusse"),
            topic("taxi", "Таксі", "Taxi"),
            topic("accessible-travel", "Безбар’єрні поїздки", "Barrierefrei unterwegs")
        ]),
        category("finances", "Гроші та підтримка", "Geld & Unterstützung",
                 summaryUK: "Виплати, рахунки та податки", summaryDE: "Leistungen, Konten und Steuern",
                 symbol: "eurosign.circle.fill", topics: [
            topic("benefits", "Соціальні виплати", "Sozialleistungen"),
            topic("banking", "Банківський рахунок", "Bankkonto"),
            topic("taxes", "Податки", "Steuern"),
            topic("pension", "Пенсія", "Pension")
        ]),
        category("legal", "Право та консультації", "Recht & Beratung",
                 summaryUK: "Юридична допомога й права споживачів", summaryDE: "Rechtsberatung und Verbraucherrechte",
                 symbol: "building.columns.fill", topics: [
            topic("legal-aid", "Юридична допомога", "Rechtsberatung"),
            topic("authorities", "Державні установи", "Behörden"),
            topic("consumer-rights", "Права споживачів", "Verbraucherrechte"),
            topic("translation", "Переклад і супровід", "Dolmetschen & Begleitung")
        ]),
        category("daily-life", "Повсякденне життя", "Alltag",
                 summaryUK: "Зв’язок, послуги та громада", summaryDE: "Kommunikation, Dienste und Gemeinschaft",
                 symbol: "sun.max.fill", topics: [
            topic("phone", "Телефон та інтернет", "Telefon & Internet"),
            topic("digital-services", "Цифрові послуги", "Digitale Dienste"),
            topic("local-services", "Місцеві служби", "Lokale Angebote"),
            topic("community", "Спільнота та дозвілля", "Gemeinschaft & Freizeit")
        ]),
        category("accessibility", "Доступність і догляд", "Barrierefreiheit & Pflege",
                 summaryUK: "Підтримка людей з інвалідністю та літніх людей", summaryDE: "Hilfe für Menschen mit Behinderung und Ältere",
                 symbol: "figure.roll", topics: [
            topic("disability", "Підтримка людей з інвалідністю", "Unterstützung bei Behinderung"),
            topic("care", "Догляд", "Pflege"),
            topic("seniors", "Допомога літнім людям", "Hilfe für Ältere"),
            topic("accessibility-services", "Доступні послуги", "Barrierefreie Angebote")
        ])
    ]
}
