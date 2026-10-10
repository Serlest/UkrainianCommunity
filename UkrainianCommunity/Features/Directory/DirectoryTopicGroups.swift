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
            .init("route", "Порядок дій", "Schritte nach der Ankunft", ["arrival", "checklist"])
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
        ],
        "health": [
            .init("start", "Знайти допомогу", "Hilfe finden", ["where-to-go", "doctors", "specialists", "clinics"]),
            .init("treatment", "Лікування", "Behandlung", ["dental", "medication", "ongoing-care"]),
            .init("family", "Родина і профілактика", "Familie und Vorsorge", ["pregnancy", "child-health", "prevention"]),
            .init("rights", "Права пацієнта", "Patientenrechte", ["patient-rights"])
        ],
        "mental-health": [
            .init("support", "Підтримка й лікування", "Beratung und Behandlung", ["counseling"]),
            .init("urgent", "Криза і захист", "Krise und Schutz", ["crisis", "children"])
        ],
        "insurance": [
            .init("public", "Медичне покриття", "Krankenversicherung", ["ukrainian-cover", "health-cover", "family-cover"]),
            .init("private", "Інші ризики", "Weitere Risiken", ["other-cover"])
        ],
        "work": [
            .init("find", "Почати роботу", "Arbeit aufnehmen", ["work-rights", "job-search"]),
            .init("conditions", "Умови й власна справа", "Arbeitsbedingungen und Selbständigkeit", ["employee-rights", "self-employment"])
        ],
        "qualifications": [
            .init("recognize", "Оцінити освіту", "Qualifikation prüfen", ["recognition", "regulated-professions"]),
            .init("develop", "Довчитися", "Weiterbildung", ["training"])
        ],
        "education": [
            .init("children", "Для дітей", "Für Kinder", ["kindergarten", "school"]),
            .init("adults", "Навчання дорослих", "Bildung für Erwachsene", ["higher-education", "language"])
        ],
        "family": [
            .init("daily", "Щоденна підтримка", "Unterstützung im Alltag", ["childcare", "parenting"]),
            .init("services", "Служби для сім’ї", "Dienste für Familien", ["family-services"])
        ],
        "finances": [
            .init("daily", "Банк і податки", "Bank und Steuern", ["banking", "taxes"]),
            .init("later", "Пенсія", "Pension", ["pension"])
        ],
        "social-support": [
            .init("claims", "Державні виплати", "Staatliche Leistungen", ["benefits", "family-benefits", "basic-support"]),
            .init("help", "Додаткова допомога", "Weitere Hilfe", ["aid-organizations"])
        ],
        "legal": [
            .init("rights", "Порада й захист прав", "Beratung und Rechtsschutz", ["legal-aid", "consumer-rights"]),
            .init("procedure", "Спілкування з установами", "Behördenkontakte", ["authorities", "interpreting"])
        ],
        "communication": [
            .init("connections", "Телефон та інтернет", "Telefon und Internet", ["phone", "internet"]),
            .init("letters", "Листи", "Post", ["postal"])
        ],
        "digital": [
            .init("services", "Онлайн-послуги", "Online-Dienste", ["online-services", "digital-identity"]),
            .init("security", "Захист", "Schutz", ["online-safety"])
        ],
        "community": [
            .init("orientation", "Місцева орієнтація", "Orientierung vor Ort", ["local-services", "community"]),
            .init("participation", "Долучитися", "Mitmachen", ["volunteering"])
        ],
        "leisure": [.init("ideas", "Ідеї для дозвілля", "Freizeitideen", ["leisure"])],
        "accessibility": [
            .init("rights", "Посвідчення й послуги", "Ausweis und Angebote", ["disability", "accessible-services"]),
            .init("support", "Засоби підтримки", "Hilfsmittel", ["assistive-devices"])
        ],
        "care": [.init("care", "Організувати догляд", "Pflege organisieren", ["home-care", "care-services"])],
        "seniors": [.init("seniors", "Підтримка у старшому віці", "Unterstützung im Alter", ["seniors"])],
        "transport": [
            .init("public", "Громадський транспорт", "Öffentlicher Verkehr", ["local-transport", "rail", "bus"]),
            .init("other", "Інші поїздки й доступність", "Weitere Wege und Barrierefreiheit", ["taxi", "accessible-travel"])
        ]
    ]
}
