import Foundation

enum DonationEditorText {
    static var visible: String { LocalizationStore.localizedString("donation_editor.visible", defaultValue: "Für Nutzer sichtbar", table: "DonationEditor") }
    static var hidden: String { LocalizationStore.localizedString("donation_editor.hidden", defaultValue: "Für Nutzer ausgeblendet", table: "DonationEditor") }
    static var previewLanguage: String { LocalizationStore.localizedString("donation_editor.previewLanguage", defaultValue: "Sprache der Vorschau", table: "DonationEditor") }
    static var editLanguage: String { LocalizationStore.localizedString("donation_editor.editLanguage", defaultValue: "Textsprache", table: "DonationEditor") }
    static var checkLink: String { LocalizationStore.localizedString("donation_editor.checkLink", defaultValue: "Link prüfen", table: "DonationEditor") }
    static var linkFailed: String { LocalizationStore.localizedString("donation_editor.linkFailed", defaultValue: "Der Link konnte nicht geöffnet werden.", table: "DonationEditor") }
    static var limits: String { LocalizationStore.localizedString("donation_editor.limits", defaultValue: "Titel: 120 Zeichen · Nachricht: 2.000 · Schaltfläche: 80.", table: "DonationEditor") }
    static var missingText: String { LocalizationStore.localizedString("donation_editor.missingText", defaultValue: "Füllen Sie vor dem Aktivieren alle Texte in beiden Sprachen aus.", table: "DonationEditor") }
    static var conflict: String { LocalizationStore.localizedString("donation_editor.conflict", defaultValue: "Die Einstellungen wurden inzwischen geändert. Ihre Eingaben bleiben erhalten. Laden Sie die aktuelle Fassung, bevor Sie weiter speichern.", table: "DonationEditor") }
    static var unconfirmed: String { LocalizationStore.localizedString("donation_editor.unconfirmed", defaultValue: "Die Speicherung konnte nicht bestätigt werden. Laden Sie die Einstellungen erneut, um den Serverstand zu prüfen.", table: "DonationEditor") }
    static var reload: String { LocalizationStore.localizedString("donation_editor.reload", defaultValue: "Aktuelle Einstellungen laden", table: "DonationEditor") }
    static var reloadTitle: String { LocalizationStore.localizedString("donation_editor.reloadTitle", defaultValue: "Aktuelle Einstellungen laden und lokale Änderungen verwerfen?", table: "DonationEditor") }
    static var saveAndClose: String { LocalizationStore.localizedString("donation_editor.saveAndClose", defaultValue: "Speichern und schließen", table: "DonationEditor") }
    static var fieldRequired: String { LocalizationStore.localizedString("donation_editor.fieldRequired", defaultValue: "Dieses Feld ist bei aktivierter Unterstützung erforderlich.", table: "DonationEditor") }
    static var fieldTooLong: String { LocalizationStore.localizedString("donation_editor.fieldTooLong", defaultValue: "Die zulässige Zeichenanzahl wurde überschritten.", table: "DonationEditor") }
}
