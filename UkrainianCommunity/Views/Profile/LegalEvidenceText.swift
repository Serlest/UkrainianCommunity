import Foundation

enum LegalEvidenceText {
    static var about: String { LocalizationStore.localizedString("legal_evidence_ui.about", defaultValue: "Über diese Nachweise", table: "LegalEvidenceUI") }
    static var details: String { LocalizationStore.localizedString("legal_evidence_ui.details", defaultValue: "Technische Details", table: "LegalEvidenceUI") }
    static var summary: String { LocalizationStore.localizedString("legal_evidence_ui.summary", defaultValue: "Erfasster Bestätigungsstand", table: "LegalEvidenceUI") }
    static var current: String { LocalizationStore.localizedString("legal_evidence_ui.current", defaultValue: "Aktuelle Version bestätigt", table: "LegalEvidenceUI") }
    static var outdated: String { LocalizationStore.localizedString("legal_evidence_ui.outdated", defaultValue: "Frühere Version bestätigt", table: "LegalEvidenceUI") }
    static var unknown: String { LocalizationStore.localizedString("legal_evidence_ui.unknown", defaultValue: "Kein Nachweis vorhanden", table: "LegalEvidenceUI") }
    static var confirmed: String { LocalizationStore.localizedString("legal_evidence_ui.confirmed", defaultValue: "Bestätigung erfasst", table: "LegalEvidenceUI") }
    static var granted: String { LocalizationStore.localizedString("legal_evidence_ui.granted", defaultValue: "Einwilligung erteilt", table: "LegalEvidenceUI") }
    static var withdrawn: String { LocalizationStore.localizedString("legal_evidence_ui.withdrawn", defaultValue: "Einwilligung zurückgezogen", table: "LegalEvidenceUI") }
    static var more: String { LocalizationStore.localizedString("legal_evidence_ui.more", defaultValue: "Weitere Einträge laden", table: "LegalEvidenceUI") }
    static var partial: String { LocalizationStore.localizedString("legal_evidence_ui.partial", defaultValue: "Die Historie wird seitenweise geladen. Suche und Filter gelten für die gesamte Historie.", table: "LegalEvidenceUI") }
    static var continueHistory: String { LocalizationStore.localizedString("legal_evidence_ui.continue", defaultValue: "Auf dieser Seite gibt es keine Treffer. Weitere Einträge durchsuchen.", table: "LegalEvidenceUI") }
    static var prepareExport: String { LocalizationStore.localizedString("legal_evidence_ui.prepareExport", defaultValue: "Vollständigen Export vorbereiten", table: "LegalEvidenceUI") }
    static var exporting: String { LocalizationStore.localizedString("legal_evidence_ui.exporting", defaultValue: "Vollständige Historie wird geladen…", table: "LegalEvidenceUI") }
    static var profileSnapshot: String { LocalizationStore.localizedString("legal_evidence_ui.profileSnapshot", defaultValue: "Bestätigungsstand im Profil", table: "LegalEvidenceUI") }
    static var profileNotice: String { LocalizationStore.localizedString("legal_evidence_ui.profileNotice", defaultValue: "Aus dem Profil übernommen. Ein eigenständiger Beleg zu dieser Bestätigung fehlt.", table: "LegalEvidenceUI") }
    static var readVersion: String { LocalizationStore.localizedString("legal_evidence_ui.readVersion", defaultValue: "Erfasste Dokumentversion ansehen", table: "LegalEvidenceUI") }
    static var versionUnavailable: String { LocalizationStore.localizedString("legal_evidence_ui.versionUnavailable", defaultValue: "Diese Dokumentversion konnte nicht verifiziert werden. Sie wurde nicht durch die aktuelle Version ersetzt.", table: "LegalEvidenceUI") }
    static var versionTitle: String { LocalizationStore.localizedString("legal_evidence_ui.versionTitle", defaultValue: "Bestätigte Dokumentversion", table: "LegalEvidenceUI") }
    static var verifiedHash: String { LocalizationStore.localizedString("legal_evidence_ui.verifiedHash", defaultValue: "Dokument stimmt mit dem gespeicherten Nachweis überein.", table: "LegalEvidenceUI") }
    static var missingHash: String { LocalizationStore.localizedString("legal_evidence_ui.missingHash", defaultValue: "Die Version ist gespeichert; der ursprüngliche Nachweis enthält keinen Text-Prüfwert.", table: "LegalEvidenceUI") }
    static var loaded: String { LocalizationStore.localizedString("legal_evidence_ui.loaded", defaultValue: "Geladene Einträge", table: "LegalEvidenceUI") }
}
