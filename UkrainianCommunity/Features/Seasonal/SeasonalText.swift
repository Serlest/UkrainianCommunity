import Foundation

enum SeasonalText {
    static func value(_ key: String, _ fallback: String) -> String {
        LocalizationStore.localizedString("seasonal." + key, defaultValue: fallback, table: "Seasonal")
    }
    static var title: String { value("title", "Saisonale Gestaltung") }
    static var subtitle: String { value("subtitle", "Gespeicherte Themen, Vorschau und Zeitplan") }
    static var invalid: String { value("invalid", "Das Themenpaket ist ungültig oder zu groß. Unterstützt wird Format 1 bis 240 KB mit kleinen PNG-Grafiken.") }
    static var conflict: String { value("conflict", "Die Daten wurden auf einem anderen Gerät geändert. Laden Sie sie erneut; Ihre Änderungen sind noch geöffnet.") }
    static var ownerOnly: String { value("ownerOnly", "Nur der App-Inhaber kann Themen verwalten.") }
    static var unavailable: String { value("unavailable", "Die Verbindung konnte nicht bestätigt werden. Prüfen Sie das Internet und versuchen Sie es erneut.") }
    static var preference: String { value("preference", "Saisonale Effekte") }
    static var preferenceHint: String { value("preferenceHint", "Dekorationen auf den Hauptseiten. Reduzierte Bewegung und Energiesparen werden berücksichtigt.") }
    static func section(_ section: SeasonalSection) -> String {
        switch section {
        case .news: AppStrings.Tabs.home
        case .events: AppStrings.Tabs.eventsCompact
        case .organizations: AppStrings.Tabs.organizationsCompact
        case .directory: AppStrings.Tabs.directory
        case .profile: AppStrings.Tabs.profile
        }
    }
    static func artwork(_ artwork: SeasonalArtwork) -> String { value(artwork.rawValue, artwork.rawValue.capitalized) }
}
