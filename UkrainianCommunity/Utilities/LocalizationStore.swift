import Foundation

enum LocalizationStore {
    nonisolated static var language: AppLanguage {
        get { AppLanguage.stored }
        set { AppLanguage.stored = newValue }
    }

    nonisolated static var locale: Locale {
        Locale(identifier: language.localeIdentifier)
    }

    nonisolated static func localizedString(_ key: String, defaultValue: String) -> String {
        let bundle = bundle(for: language.rawValue) ?? .main
        return bundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }

    nonisolated static func localizedFormat(_ key: String, defaultValue: String, arguments: [CVarArg]) -> String {
        let format = localizedString(key, defaultValue: defaultValue)
        return String(format: format, locale: locale, arguments: arguments)
    }

    nonisolated static func dateString(from date: Date, dateStyle: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .none) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    nonisolated private static func bundle(for languageCode: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
