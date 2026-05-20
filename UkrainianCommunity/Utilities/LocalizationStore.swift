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

    nonisolated static func timeRangeString(startDate: Date, endDate: Date?, isAllDay: Bool? = nil) -> String {
        if isAllDay ?? isAllDayInterval(startDate: startDate, endDate: endDate) {
            return localizedString("events.all_day", defaultValue: "All day")
        }

        let startTime = dateString(from: startDate, dateStyle: .none, timeStyle: .short)

        guard let endDate, endDate > startDate else {
            return startTime
        }

        let endTime = dateString(from: endDate, dateStyle: .none, timeStyle: .short)
        return "\(startTime)–\(endTime)"
    }

    nonisolated private static func isAllDayInterval(startDate: Date, endDate: Date?) -> Bool {
        guard let endDate, endDate > startDate else {
            return false
        }

        let calendar = Calendar.current
        let startOfStartDay = calendar.startOfDay(for: startDate)
        guard abs(startDate.timeIntervalSince(startOfStartDay)) < 60 else {
            return false
        }

        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfStartDay) ?? startOfStartDay
        let lastMinuteOfDay = calendar.date(byAdding: .minute, value: -1, to: nextDay) ?? nextDay
        return abs(endDate.timeIntervalSince(nextDay)) < 60 || abs(endDate.timeIntervalSince(lastMinuteOfDay)) < 60
    }

    nonisolated private static func bundle(for languageCode: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }
}
