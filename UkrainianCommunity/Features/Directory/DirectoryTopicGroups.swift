import Foundation

struct DirectoryTopicGroup: Identifiable {
    let id: String
    let title: DirectoryText
    let topicIDs: [String]

    init(_ id: String, _ uk: String, _ de: String, _ topicIDs: [String]) {
        self.id = id
        title = DirectoryText(ukrainian: uk, german: de)
        self.topicIDs = topicIDs
    }
}

enum DirectoryTopicGroups {
    static func isComplete(categoryID: String) -> Bool { groups[categoryID] != nil }

    static func forCategory(_ category: DirectoryCategory) -> [DirectoryTopicGroup] {
        groups[category.id] ?? []
    }

    private static let groups: [String: [DirectoryTopicGroup]] = [
        "safety": [
            .init("immediate", "Небезпека зараз", "Akute Gefahr", ["emergency", "fire-gas", "poisoning", "road-accident", "mountains-water", "disasters"]),
            .init("people", "Насильство і захист людей", "Gewalt und Schutz von Menschen", ["domestic-violence", "women", "children", "assault", "discrimination"]),
            .init("mental", "Психологічна криза", "Psychische Krise", ["mental-crisis"])
        ],
        "first-steps": [
            .init("arrival", "Прибуття і перші дні", "Ankunft und erste Tage", ["arrival", "checklist", "initial-support"]),
            .init("daily", "Здоров’я, діти, робота", "Gesundheit, Kinder und Arbeit", ["health-insurance", "children", "work-language"])
        ],
        "registration": [
            .init("address", "Адреса проживання", "Wohnsitz", ["residence-registration", "housing-types", "address-change", "leaving-austria"]),
            .init("protection", "Тимчасовий захист", "Vorübergehender Schutz", ["protection-registration", "after-registration"]),
            .init("appointments", "Звернення до установ", "Behördentermine", ["appointments"])
        ],
        "residence": [
            .init("choose", "Визначити підставу", "Aufenthaltsgrund klären", ["residence-permits", "temporary-protection", "international-protection"]),
            .init("study-family", "Навчання і родина", "Studium und Familie", ["student-residence", "austrian-family", "eu-family", "third-country-family"]),
            .init("work", "Робота", "Arbeit", ["work-residence", "rwr-plus"]),
            .init("continuity", "Зміна і продовження", "Wechsel und Verlängerung", ["status-change", "residence-renewal", "permanent-residence"])
        ],
        "documents": [
            .init("identity", "Особисті документи", "Ausweise und persönliche Dokumente", ["identity", "passport", "ukrainian-id", "child-documents", "lost-documents"]),
            .init("records", "Свідоцтва і довідки", "Urkunden und Nachweise", ["civil-records", "name-change", "tax-number", "police-certificate", "power-of-attorney"]),
            .init("use", "Використання документів в Австрії", "Dokumente in Österreich verwenden", ["translations", "apostille", "driving-licence", "austrian-documents"]),
            .init("consulates", "Консульська допомога", "Konsularische Hilfe", ["consulate-austria", "consulates-nearby"])
        ],
        "citizenship": [
            .init("paths", "Визначити шлях", "Einbürgerungsweg finden", ["overview", "six-years", "ten-years"]),
            .init("status", "Ваш статус і родина", "Aufenthalt und Familie", ["protection", "student", "austrian-spouse", "other-statuses", "children"]),
            .init("requirements", "Перевірити умови", "Voraussetzungen prüfen", ["language", "livelihood", "absences", "dual-citizenship"]),
            .init("apply", "Підготувати заяву", "Antrag vorbereiten", ["documents", "application"])
        ],
        "housing": [
            .init("immediate", "Перший прихисток", "Erste Unterkunft", ["arrival-housing", "temporary-housing"]),
            .init("find", "Пошук житла", "Wohnung finden", ["find-rental", "viewing", "shared-flat", "student-housing", "social-housing"]),
            .init("rent", "Оренда і витрати", "Miete und Kosten", ["rental-contract", "rent-costs", "deposit", "rental-agents", "housing-support"]),
            .init("living", "Права і переїзд", "Wohnen und Umzug", ["tenant-rights", "ending-lease", "moving"]),
            .init("buy", "Купівля", "Kauf", ["buying", "buying-costs", "foreign-buyers"])
        ]
    ]
}
