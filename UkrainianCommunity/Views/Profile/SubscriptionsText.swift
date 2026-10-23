import Foundation

enum SubscriptionsText {
    static var search: String { LocalizationStore.localizedString("subscriptions.search", defaultValue: "Abonnements durchsuchen", table: "Subscriptions") }
    static var partial: String { LocalizationStore.localizedString("subscriptions.partial", defaultValue: "Ein Teil der Abonnements ist geladen. Suche und Sortierung gelten für geladene Einträge.", table: "Subscriptions") }
    static var more: String { LocalizationStore.localizedString("subscriptions.more", defaultValue: "Weitere laden", table: "Subscriptions") }
    static var since: String { LocalizationStore.localizedString("subscriptions.since", defaultValue: "Abonniert seit", table: "Subscriptions") }
}
