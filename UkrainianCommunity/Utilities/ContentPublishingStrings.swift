import Foundation

enum ContentPublishingStrings {
    private static var isUkrainian: Bool { LocalizationStore.language == .ukrainian }

    static var ukrainianRequired: String { isUkrainian ? "Українська версія" : "Ukrainische Version" }
    static var germanOptional: String { isUkrainian ? "Німецька версія (необов’язково)" : "Deutsche Version (optional)" }
    static var germanFallbackHint: String { isUkrainian ? "Порожні поля автоматично покажуть український текст." : "Leere Felder zeigen automatisch den ukrainischen Text." }
    static var serviceSuggestions: String { isUkrainian ? "Популярні варіанти" : "Beliebte Vorschläge" }
    static var addGermanVersion: String { isUkrainian ? "Додати німецьку версію" : "Deutsche Version hinzufügen" }
    static var hideGermanVersion: String { isUkrainian ? "Сховати німецьку версію" : "Deutsche Version ausblenden" }
    static var multipleDates: String { isUkrainian ? "Дати та сеанси" : "Termine und Zeiten" }
    static var addOccurrence: String { isUkrainian ? "Додати ще дату" : "Weiteren Termin hinzufügen" }
    static var removeOccurrence: String { isUkrainian ? "Видалити дату" : "Termin entfernen" }
    static var participation: String { isUkrainian ? "Участь" : "Teilnahme" }
    static var noRegistration: String { isUkrainian ? "Без реєстрації" : "Ohne Anmeldung" }
    static var inAppRegistration: String { isUkrainian ? "Реєстрація в застосунку" : "Anmeldung in der App" }
    static var externalRegistration: String { isUkrainian ? "Реєстрація на сайті організатора" : "Anmeldung beim Veranstalter" }
    static var externalTickets: String { isUkrainian ? "Квитки на зовнішньому сайті" : "Tickets auf externer Website" }
    static var externalLink: String { isUkrainian ? "Зовнішнє посилання" : "Externer Link" }
    static var linkButtonTitle: String { isUkrainian ? "Текст кнопки" : "Text der Schaltfläche" }
    static var secureWebLinkRequired: String { isUkrainian ? "Вкажіть повне безпечне посилання, що починається з https://" : "Gib einen vollständigen sicheren Link ein, der mit https:// beginnt." }
    static var priceType: String { isUkrainian ? "Відображення ціни" : "Preisanzeige" }
    static var priceUnspecified: String { isUkrainian ? "Не вказано" : "Nicht angegeben" }
    static var priceFree: String { isUkrainian ? "Безкоштовно" : "Kostenlos" }
    static var priceExact: String { isUkrainian ? "Точна ціна" : "Fester Preis" }
    static var priceFrom: String { isUkrainian ? "Ціна від" : "Preis ab" }
    static var priceRange: String { isUkrainian ? "Діапазон цін" : "Preisspanne" }
    static var maximumPrice: String { isUkrainian ? "Максимальна ціна" : "Höchstpreis" }
    static var priceNote: String { isUkrainian ? "Примітка до ціни" : "Preishinweis" }
    static var informationOnly: String { isUkrainian ? "Ціна має інформаційний характер. Застосунок не продає квитки." : "Der Preis dient nur zur Information. Die App verkauft keine Tickets." }
    static var imageDetails: String { isUkrainian ? "Опис зображення" : "Bildinformationen" }
    static var imageCaption: String { isUkrainian ? "Підпис" : "Bildunterschrift" }
    static var imageAltText: String { isUkrainian ? "Опис для VoiceOver" : "Beschreibung für VoiceOver" }
    static var imageCredit: String { isUkrainian ? "Автор або джерело фото" : "Bildnachweis" }
    static var callToAction: String { isUkrainian ? "Додаткова дія" : "Zusätzliche Aktion" }
    static var optional: String { isUkrainian ? "Необов’язково" : "Optional" }
    static var publishingFieldsTooLong: String { isUkrainian ? "Скоротіть текст у додаткових полях до дозволеної довжини." : "Kürze den Text in den zusätzlichen Feldern auf die zulässige Länge." }
}

extension EventParticipationMode {
    var localizedTitle: String {
        switch self {
        case .none: ContentPublishingStrings.noRegistration
        case .inAppRegistration: ContentPublishingStrings.inAppRegistration
        case .externalRegistration: ContentPublishingStrings.externalRegistration
        case .externalTickets: ContentPublishingStrings.externalTickets
        }
    }
}

extension EventPriceKind {
    var localizedTitle: String {
        switch self {
        case .unspecified: ContentPublishingStrings.priceUnspecified
        case .free: ContentPublishingStrings.priceFree
        case .exact: ContentPublishingStrings.priceExact
        case .startingFrom: ContentPublishingStrings.priceFrom
        case .range: ContentPublishingStrings.priceRange
        }
    }
}

extension String {
    nonisolated func trimmedOrFallback(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
