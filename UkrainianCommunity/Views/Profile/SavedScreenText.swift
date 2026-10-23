import Foundation

enum SavedScreenText {
    static var search: String { LocalizationStore.localizedString("saved.search", defaultValue: "Gespeicherte Inhalte durchsuchen", table: "SavedScreen") }
    static var partial: String { LocalizationStore.localizedString("saved.partial", defaultValue: "Ein Teil der gespeicherten Inhalte ist geladen. Suche, Sortierung und Zähler gelten für geladene Einträge.", table: "SavedScreen") }
    static var more: String { LocalizationStore.localizedString("saved.more", defaultValue: "Weitere laden", table: "SavedScreen") }
    static var saved: String { LocalizationStore.localizedString("saved.saved", defaultValue: "Gespeichert am", table: "SavedScreen") }
    static var network: String { LocalizationStore.localizedString("saved.network", defaultValue: "Gespeicherte Inhalte konnten nicht geladen werden. Prüfen Sie Ihre Verbindung und versuchen Sie es erneut.", table: "SavedScreen") }
    static var failed: String { LocalizationStore.localizedString("saved.failed", defaultValue: "Gespeicherte Inhalte konnten nicht geladen werden. Versuchen Sie es erneut.", table: "SavedScreen") }
}
