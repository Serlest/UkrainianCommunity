import Foundation

enum LegalEditorText {
    static var active: String { LocalizationStore.localizedString("legal_editor.active", defaultValue: "Aktuelles Dokument", table: "LegalEditor") }
    static var history: String { LocalizationStore.localizedString("legal_editor.history", defaultValue: "Versionsverlauf", table: "LegalEditor") }
    static var read: String { LocalizationStore.localizedString("legal_editor.read", defaultValue: "Ansehen", table: "LegalEditor") }
    static var compare: String { LocalizationStore.localizedString("legal_editor.compare", defaultValue: "Mit aktueller Version vergleichen", table: "LegalEditor") }
    static var added: String { LocalizationStore.localizedString("legal_editor.added", defaultValue: "Hinzugefügt", table: "LegalEditor") }
    static var removed: String { LocalizationStore.localizedString("legal_editor.removed", defaultValue: "Entfernt", table: "LegalEditor") }
    static var noChanges: String { LocalizationStore.localizedString("legal_editor.noChanges", defaultValue: "Der Text ist unverändert.", table: "LegalEditor") }
    static var privateDraft: String { LocalizationStore.localizedString("legal_editor.privateDraft", defaultValue: "Der Entwurf bleibt bis zur Veröffentlichung privat.", table: "LegalEditor") }
    static var closeTitle: String { LocalizationStore.localizedString("legal_editor.closeTitle", defaultValue: "Änderungen vor dem Verlassen speichern?", table: "LegalEditor") }
    static var leaveUnsaved: String { LocalizationStore.localizedString("legal_editor.leaveUnsaved", defaultValue: "Ohne Speichern verlassen", table: "LegalEditor") }
    static var discardTitle: String { LocalizationStore.localizedString("legal_editor.discardTitle", defaultValue: "Gespeicherten Entwurf verwerfen?", table: "LegalEditor") }
    static var discard: String { LocalizationStore.localizedString("legal_editor.discard", defaultValue: "Entwurf verwerfen", table: "LegalEditor") }
    static var discardMessage: String { LocalizationStore.localizedString("legal_editor.discardMessage", defaultValue: "Der gespeicherte Entwurf wird gelöscht. Das aktuelle Dokument bleibt unverändert.", table: "LegalEditor") }
    static var tooLong: String { LocalizationStore.localizedString("legal_editor.tooLong", defaultValue: "Titel: maximal 500 Zeichen. Text pro Sprache: maximal 100.000 Zeichen.", table: "LegalEditor") }
    static var more: String { LocalizationStore.localizedString("legal_editor.more", defaultValue: "Mehr laden", table: "LegalEditor") }
    static var actions: String { LocalizationStore.localizedString("legal_editor.actions", defaultValue: "Weitere Aktionen", table: "LegalEditor") }
    static var privacyVersionTitle: String { LocalizationStore.localizedString("legal_editor.privacyVersionTitle", defaultValue: "Version und Kenntnisnahme", table: "LegalEditor") }
    static var privacyPublishMessage: String { LocalizationStore.localizedString("legal_editor.privacyPublishMessage", defaultValue: "Diese Version ersetzt die aktuelle Datenschutzerklärung. Nutzer bestätigen die Kenntnisnahme; ihre Entscheidung zur optionalen Analyse bleibt unverändert.", table: "LegalEditor") }
}
