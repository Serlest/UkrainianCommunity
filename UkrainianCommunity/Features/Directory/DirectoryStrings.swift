import Foundation

enum DirectoryStrings {
    private static func value(_ uk: String, _ de: String) -> String {
        DirectoryText(ukrainian: uk, german: de).value(for: LocalizationStore.language)
    }

    static var introduction: String { value("Важливі теми для життя в Австрії — від перших кроків до щоденних питань.", "Wichtige Themen für das Leben in Österreich – vom Ankommen bis zum Alltag.") }
    static var browseSections: String { value("Переглянути розділи", "Bereiche entdecken") }
    static var searchPlaceholder: String { value("Пошук у довіднику", "Im Wegweiser suchen") }
    static var categoriesHeading: String { value("Розділи довідника", "Bereiche im Wegweiser") }
    static var startHeading: String { value("Початок в Австрії", "Ankommen in Österreich") }
    static var lifeHeading: String { value("Повсякденне життя", "Alltag") }
    static var supportHeading: String { value("Підтримка та участь", "Unterstützung und Teilhabe") }
    static var preparing: String { value("Матеріали додаємо після перевірки офіційних джерел.", "Inhalte werden nach Prüfung offizieller Quellen ergänzt.") }
    static var noResults: String { value("Нічого не знайдено", "Keine Treffer") }
    static var tryAnotherQuery: String { value("Спробуйте інше слово або перегляньте всі теми.", "Versuchen Sie ein anderes Wort oder sehen Sie alle Themen an.") }
    static var topicPending: String { value("Інформація готується", "Informationen in Vorbereitung") }
    static var topicPendingDetail: String { value("Ми додамо цю тему після перевірки актуальних офіційних джерел і посилань.", "Dieses Thema folgt nach Prüfung aktueller offizieller Quellen und Links.") }
    static var inCategory: String { value("У цьому розділі", "In diesem Bereich") }
}
