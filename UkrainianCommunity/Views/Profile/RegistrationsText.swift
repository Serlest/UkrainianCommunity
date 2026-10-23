import Foundation

enum RegistrationsText {
    static var ongoing: String { LocalizationStore.localizedString("registrations.ongoing", defaultValue: "Laufend", table: "Registrations") }
    static var cancelled: String { LocalizationStore.localizedString("registrations.cancelled", defaultValue: "Abgesagt", table: "Registrations") }
    static var ongoingBadge: String { LocalizationStore.localizedString("registrations.ongoingBadge", defaultValue: "Findet gerade statt", table: "Registrations") }
    static var pastBadge: String { LocalizationStore.localizedString("registrations.pastBadge", defaultValue: "Beendet", table: "Registrations") }
    static var upcomingBadge: String { LocalizationStore.localizedString("registrations.upcomingBadge", defaultValue: "Bevorstehend", table: "Registrations") }
    static var cancelledBadge: String { LocalizationStore.localizedString("registrations.cancelledBadge", defaultValue: "Abgesagt", table: "Registrations") }
    static var ongoingEmpty: String { LocalizationStore.localizedString("registrations.ongoingEmpty", defaultValue: "Aktuell finden keine angemeldeten Veranstaltungen statt", table: "Registrations") }
    static var cancelledEmpty: String { LocalizationStore.localizedString("registrations.cancelledEmpty", defaultValue: "Keine abgesagten Veranstaltungen", table: "Registrations") }
    static var emptyFilter: String { LocalizationStore.localizedString("registrations.emptyFilter", defaultValue: "In dieser Gruppe gibt es keine geladenen Anmeldungen.", table: "Registrations") }
    static var scope: String { LocalizationStore.localizedString("registrations.scope", defaultValue: "Hier stehen nur Anmeldungen in UAC. Anmeldungen auf externen Websites werden nicht automatisch übernommen.", table: "Registrations") }
    static var partial: String { LocalizationStore.localizedString("registrations.partial", defaultValue: "Ein Teil der Anmeldungen ist geladen. Filter und Zähler beziehen sich auf geladene Veranstaltungen.", table: "Registrations") }
    static var loadMore: String { LocalizationStore.localizedString("registrations.loadMore", defaultValue: "Weitere laden", table: "Registrations") }
    static var retry: String { LocalizationStore.localizedString("registrations.retry", defaultValue: "Liste aktualisieren", table: "Registrations") }
}
