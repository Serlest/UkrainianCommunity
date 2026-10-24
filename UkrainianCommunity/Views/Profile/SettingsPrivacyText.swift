import Foundation

enum SettingsPrivacyText {
    static var showOrganizationTitle: String { LocalizationStore.localizedString("settingsPrivacy.showOrganizationTitle", defaultValue: "Organisation wieder anzeigen?", table: "SettingsPrivacy") }
    static func showOrganizationMessage(_ name: String) -> String {
        String(format: LocalizationStore.localizedString("settingsPrivacy.showOrganizationMessage", defaultValue: "Inhalte von „%@“ werden wieder in Ihrem Feed angezeigt.", table: "SettingsPrivacy"), name)
    }
    static var hiddenOrganizationsIntro: String { LocalizationStore.localizedString("settingsPrivacy.hiddenOrganizationsIntro", defaultValue: "Organisationen, deren Inhalte Sie in Ihrem Feed ausgeblendet haben.", table: "SettingsPrivacy") }
    static var privacyTitle: String { LocalizationStore.localizedString("settingsPrivacy.privacy", defaultValue: "Datenschutz und Einwilligungen", table: "SettingsPrivacy") }
    static var hiddenContentTitle: String { LocalizationStore.localizedString("settingsPrivacy.hiddenContent", defaultValue: "Ausgeblendete Inhalte", table: "SettingsPrivacy") }
    static var bannerUnavailable: String { LocalizationStore.localizedString("settingsPrivacy.bannerUnavailable", defaultValue: "Die Bannermessung ist für dieses Konto derzeit nicht verfügbar.", table: "SettingsPrivacy") }
    static var profileSavedPending: String { LocalizationStore.localizedString("settingsPrivacy.profileSavedPending", defaultValue: "Änderungen sind gespeichert. Die Bestätigung konnte nicht geladen werden. Prüfen Sie die Verbindung und versuchen Sie die Bestätigung erneut.", table: "SettingsPrivacy") }
    static var verifySavedProfile: String { LocalizationStore.localizedString("settingsPrivacy.verifySavedProfile", defaultValue: "Speicherung prüfen", table: "SettingsPrivacy") }
    static var verifyingProfile: String { LocalizationStore.localizedString("settingsPrivacy.verifyingProfile", defaultValue: "Speicherung wird geprüft…", table: "SettingsPrivacy") }
    static var hiddenSearch: String { LocalizationStore.localizedString("settingsPrivacy.hiddenSearch", defaultValue: "Ausgeblendete Organisationen suchen", table: "SettingsPrivacy") }
}
