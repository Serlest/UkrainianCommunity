import Foundation

enum LocalizationStore {
    private nonisolated static let localizedBundleCache = LocalizedBundleCache()
    private nonisolated static let dateFormatterCache = LocalizedDateFormatterCache()

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

    nonisolated static func compareForSorting(_ lhs: String, _ rhs: String) -> ComparisonResult {
        lhs.compare(
            rhs,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: nil,
            locale: locale
        )
    }

    nonisolated static func dateString(from date: Date, dateStyle: DateFormatter.Style = .medium, timeStyle: DateFormatter.Style = .none) -> String {
        dateFormatterCache.string(
            from: date,
            locale: locale,
            dateStyle: dateStyle,
            timeStyle: timeStyle
        )
    }

    nonisolated static func dateString(from date: Date, localizedTemplate template: String) -> String {
        dateFormatterCache.string(from: date, locale: locale, localizedTemplate: template)
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
        localizedBundleCache.bundle(for: languageCode)
    }
}

private nonisolated final class LocalizedBundleCache: @unchecked Sendable {
    private let lock = NSLock()
    private var bundles: [String: Bundle] = [:]

    func bundle(for languageCode: String) -> Bundle? {
        lock.lock()
        defer { lock.unlock() }

        if let cachedBundle = bundles[languageCode] {
            return cachedBundle
        }

        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return nil
        }
        bundles[languageCode] = bundle
        return bundle
    }
}

private nonisolated final class LocalizedDateFormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    func string(
        from date: Date,
        locale: Locale,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> String {
        withFormatter(
            key: cacheKey(
                locale: locale,
                format: "styles:\(dateStyle.rawValue):\(timeStyle.rawValue)"
            )
        ) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateStyle = dateStyle
            formatter.timeStyle = timeStyle
            return formatter
        } format: {
            $0.string(from: date)
        }
    }

    func string(from date: Date, locale: Locale, localizedTemplate template: String) -> String {
        withFormatter(key: cacheKey(locale: locale, format: "template:\(template)")) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter
        } format: {
            $0.string(from: date)
        }
    }

    private func cacheKey(locale: Locale, format: String) -> String {
        [
            locale.identifier,
            TimeZone.current.identifier,
            String(describing: Calendar.current.identifier),
            format
        ].joined(separator: "|")
    }

    private func withFormatter(
        key: String,
        create: () -> DateFormatter,
        format: (DateFormatter) -> String
    ) -> String {
        lock.lock()
        defer { lock.unlock() }

        let formatter: DateFormatter
        if let cachedFormatter = formatters[key] {
            formatter = cachedFormatter
        } else {
            let newFormatter = create()
            formatters[key] = newFormatter
            formatter = newFormatter
        }
        return format(formatter)
    }
}
