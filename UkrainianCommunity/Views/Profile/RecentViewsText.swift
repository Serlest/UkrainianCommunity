import Foundation

enum RecentViewsText {
    static var contentType: String { LocalizationStore.localizedString("recentViews.contentType", defaultValue: "Inhaltstyp", table: "RecentViews") }
    static var search: String { LocalizationStore.localizedString("recentViews.search", defaultValue: "Verlauf durchsuchen", table: "RecentViews") }
    static var limit: String { LocalizationStore.localizedString("recentViews.limit", defaultValue: "Die letzten 30 Einträge. Erneutes Öffnen verschiebt einen Eintrag nach oben.", table: "RecentViews") }
    static var filteredEmpty: String { LocalizationStore.localizedString("recentViews.filteredEmpty", defaultValue: "Keine Einträge für diese Auswahl. Ändern Sie den Filter oder die Suche.", table: "RecentViews") }
    static var networkError: String { LocalizationStore.localizedString("recentViews.networkError", defaultValue: "Der Verlauf konnte nicht geladen werden. Prüfen Sie die Internetverbindung und versuchen Sie es erneut.", table: "RecentViews") }
    static var loadError: String { LocalizationStore.localizedString("recentViews.loadError", defaultValue: "Der Verlauf konnte nicht aktualisiert werden. Bitte versuchen Sie es erneut.", table: "RecentViews") }
}
