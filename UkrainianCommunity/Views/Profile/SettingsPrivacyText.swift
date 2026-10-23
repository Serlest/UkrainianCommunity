import Foundation

enum SettingsPrivacyText {
    static var privacyTitle: String { LocalizationStore.localizedString("settingsPrivacy.privacy", defaultValue: "Datenschutz und Einwilligungen", table: "SettingsPrivacy") }
    static var hiddenContentTitle: String { LocalizationStore.localizedString("settingsPrivacy.hiddenContent", defaultValue: "Ausgeblendete Inhalte", table: "SettingsPrivacy") }
    static var bannerUnavailable: String { LocalizationStore.localizedString("settingsPrivacy.bannerUnavailable", defaultValue: "Die Bannermessung ist für dieses Konto derzeit nicht verfügbar.", table: "SettingsPrivacy") }
}
