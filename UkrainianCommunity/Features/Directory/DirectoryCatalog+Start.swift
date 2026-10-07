import Foundation

extension DirectoryCatalog {
    static let startCategories: [DirectoryCategory] = [
        category("safety", "Безпека та захист", "Sicherheit & Schutz",
                 summaryUK: "Важливі теми про захист і підтримку", summaryDE: "Wichtige Themen zu Schutz und Unterstützung",
                 symbol: "shield.lefthalf.filled", topics: [
            topic("emergency", "Невідкладна допомога", "Notfallhilfe"),
            topic("domestic-violence", "Домашнє насильство", "Häusliche Gewalt"),
            topic("women", "Допомога жінкам", "Hilfe für Frauen"),
            topic("children", "Захист дітей", "Kinderschutz"),
            topic("discrimination", "Дискримінація та переслідування", "Diskriminierung & Belästigung")
        ]),
        category("first-steps", "Перші кроки", "Erste Schritte",
                 summaryUK: "Орієнтація після прибуття", summaryDE: "Orientierung nach der Ankunft",
                 symbol: "figure.walk.arrival", topics: [
            topic("arrival", "Прибуття та перші дії", "Ankunft & erste Schritte"),
            topic("checklist", "Покроковий список", "Schritt-für-Schritt-Liste"),
            topic("initial-support", "Початкова підтримка", "Erste Unterstützung")
        ]),
        category("registration", "Реєстрація", "Anmeldung",
                 summaryUK: "Адреса й офіційні записи", summaryDE: "Wohnsitz und Behördentermine",
                 symbol: "checklist", topics: [
            topic("residence-registration", "Реєстрація адреси", "Wohnsitz anmelden"),
            topic("address-change", "Зміна адреси", "Adressänderung"),
            topic("appointments", "Запис до установ", "Behördentermine")
        ]),
        category("residence", "Статус перебування", "Aufenthalt",
                 summaryUK: "Підстави й дозволи на проживання", summaryDE: "Status und Aufenthaltstitel",
                 symbol: "person.crop.rectangle", topics: [
            topic("temporary-protection", "Тимчасовий захист", "Vorübergehender Schutz"),
            topic("residence-permits", "Дозволи на проживання", "Aufenthaltstitel"),
            topic("rwr-plus", "Червона-біло-червона картка плюс", "Rot-Weiß-Rot-Karte plus"),
            topic("status-change", "Зміна статусу", "Statuswechsel")
        ]),
        category("documents", "Документи", "Dokumente",
                 summaryUK: "Посвідчення, переклади й копії", summaryDE: "Ausweise, Übersetzungen und Kopien",
                 symbol: "doc.text.fill", topics: [
            topic("identity", "Посвідчення особи", "Identitätsnachweise"),
            topic("passport", "Паспорт", "Reisepass"),
            topic("translations", "Переклад документів", "Dokumentenübersetzung"),
            topic("lost-documents", "Втрачені документи", "Verlorene Dokumente")
        ]),
        category("citizenship", "Громадянство", "Staatsbürgerschaft",
                 summaryUK: "Шлях до громадянства", summaryDE: "Weg zur Staatsbürgerschaft",
                 symbol: "globe.europe.africa.fill", topics: [
            topic("requirements", "Умови", "Voraussetzungen"),
            topic("application", "Заява та процедура", "Antrag & Verfahren"),
            topic("documents", "Потрібні документи", "Benötigte Unterlagen")
        ]),
        category("housing", "Житло", "Wohnen",
                 summaryUK: "Прийом, тимчасове житло й оренда", summaryDE: "Aufnahme, Unterkunft und Miete",
                 symbol: "house.lodge.fill", topics: [
            topic("reception", "Де приймають людей", "Aufnahmestellen"),
            topic("temporary-housing", "Тимчасове житло", "Vorübergehende Unterkunft"),
            topic("rent", "Оренда та права мешканців", "Miete & Wohnrechte"),
            topic("housing-support", "Допомога з житлом", "Wohnunterstützung")
        ])
    ]
}
