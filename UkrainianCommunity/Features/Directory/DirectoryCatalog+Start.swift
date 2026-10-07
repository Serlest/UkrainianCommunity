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
            topic("assault", "Напад і злочин", "Angriff und Straftat"),
            topic("discrimination", "Дискримінація та переслідування", "Diskriminierung & Belästigung"),
            topic("fire-gas", "Пожежа та запах газу", "Brand und Gasgeruch"),
            topic("mountains-water", "Гори та водойми", "Berge und Gewässer"),
            topic("poisoning", "Отруєння", "Vergiftung"),
            topic("disasters", "Негода та катастрофи", "Unwetter und Katastrophen"),
            topic("road-accident", "Дорожня пригода", "Verkehrsunfall"),
            topic("mental-crisis", "Психологічна криза", "Psychische Krise")
        ]),
        category("first-steps", "Перші кроки", "Erste Schritte",
                 summaryUK: "Житло, перші дні, допомога, здоров’я, діти й робота",
                 summaryDE: "Unterkunft, erste Tage, Hilfe, Gesundheit, Kinder und Arbeit",
                 symbol: "figure.walk.arrival", topics: [
            topic("arrival", "Де зупинитися після прибуття?", "Wo kann ich nach der Ankunft bleiben?"),
            topic("checklist", "Що зробити в перші дні?", "Was ist in den ersten Tagen zu tun?"),
            topic("initial-support", "Де отримати базову допомогу?", "Wo bekomme ich Grundversorgung?"),
            topic("health-insurance", "Як отримати медичну допомогу?", "Wie bekomme ich medizinische Hilfe?"),
            topic("children", "Що зробити для дитини?", "Was braucht mein Kind?"),
            topic("work-language", "З чого почати роботу й мову?", "Wie beginne ich mit Arbeit und Deutsch?")
        ]),
        category("registration", "Реєстрація", "Anmeldung",
                 summaryUK: "Адреса, тимчасовий захист, посвідчення й переїзд",
                 summaryDE: "Wohnsitz, Schutz, Ausweis und Umzug",
                 symbol: "checklist", topics: [
            topic("residence-registration", "Реєстрація адреси", "Wohnsitz anmelden"),
            topic("housing-types", "Якщо немає власного житла", "Wenn Sie keine eigene Wohnung haben"),
            topic("protection-registration", "Реєстрація для тимчасового захисту", "Erfassung für vorübergehenden Schutz"),
            topic("after-registration", "Посвідчення після реєстрації", "Ausweis nach der Erfassung"),
            topic("address-change", "Зміна адреси", "Adressänderung"),
            topic("leaving-austria", "Виїзд і зняття з обліку", "Wegzug und Abmeldung"),
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
