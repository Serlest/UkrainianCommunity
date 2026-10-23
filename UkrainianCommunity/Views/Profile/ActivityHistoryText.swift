import Foundation

enum ActivityHistoryText {
    static var title: String { LocalizationStore.localizedString("activityHistory.title", defaultValue: "Verlauf meiner Aktionen", table: "ActivityHistory") }
    static var search: String { LocalizationStore.localizedString("activityHistory.search", defaultValue: "Aktionen durchsuchen", table: "ActivityHistory") }
    static var contentType: String { LocalizationStore.localizedString("activityHistory.contentType", defaultValue: "Inhaltstyp", table: "ActivityHistory") }
    static var savedFilter: String { LocalizationStore.localizedString("activityHistory.savedFilter", defaultValue: "Speicheraktionen", table: "ActivityHistory") }
    static var limit: String { LocalizationStore.localizedString("activityHistory.limit", defaultValue: "Die letzten 100 Aktionen: Speichern, Folgen und Anmeldungen. Angesehene Inhalte stehen unter „Kürzlich angesehen“.", table: "ActivityHistory") }
    static var filteredEmpty: String { LocalizationStore.localizedString("activityHistory.filteredEmpty", defaultValue: "Keine Aktionen für diese Auswahl. Ändern Sie den Filter oder die Suche.", table: "ActivityHistory") }
    static var networkError: String { LocalizationStore.localizedString("activityHistory.networkError", defaultValue: "Die Aktionen konnten nicht geladen werden. Prüfen Sie die Internetverbindung und versuchen Sie es erneut.", table: "ActivityHistory") }
    static var loadError: String { LocalizationStore.localizedString("activityHistory.loadError", defaultValue: "Die Aktionen konnten nicht vollständig geladen oder gespeichert werden. Bitte versuchen Sie es erneut.", table: "ActivityHistory") }
    static var clearTitle: String { LocalizationStore.localizedString("activityHistory.clearTitle", defaultValue: "Aktionsverlauf löschen?", table: "ActivityHistory") }
    static var emptyTitle: String { LocalizationStore.localizedString("activityHistory.emptyTitle", defaultValue: "Hier gibt es noch keine Aktionen.", table: "ActivityHistory") }
    static var clearMessage: String { LocalizationStore.localizedString("activityHistory.clearMessage", defaultValue: "Nur die Einträge werden gelöscht. Gespeicherte Inhalte, Abonnements und Anmeldungen bleiben bestehen.", table: "ActivityHistory") }
    static var deleteMessage: String { LocalizationStore.localizedString("activityHistory.deleteMessage", defaultValue: "Nur dieser Eintrag wird gelöscht. Die ausgeführte Aktion wird dadurch nicht rückgängig gemacht.", table: "ActivityHistory") }
}
