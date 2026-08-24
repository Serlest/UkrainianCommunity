import Foundation

enum OwnerAnalyticsFormatting {
    static func integer(
        _ value: Int,
        locale: Locale = LocalizationStore.locale
    ) -> String {
        value.formatted(.number.locale(locale))
    }

    static func percent(
        _ value: Double,
        locale: Locale = LocalizationStore.locale
    ) -> String {
        value.formatted(
            .percent
                .precision(.significantDigits(1...3))
                .locale(locale)
        )
    }

    static func list(
        _ values: [String],
        locale: Locale = LocalizationStore.locale
    ) -> String {
        let formatter = ListFormatter()
        formatter.locale = locale
        return formatter.string(from: values) ?? values.joined(separator: ", ")
    }

    static func date(
        _ value: Date,
        locale: Locale = LocalizationStore.locale
    ) -> String {
        value.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .omitted,
                locale: locale,
                calendar: AnalyticsFirestoreSchema.analyticsCalendar,
                timeZone: AnalyticsFirestoreSchema.analyticsTimeZone
            )
        )
    }

    static func categoryTitle(
        rawValue: String,
        contentType: AnalyticsContentType
    ) -> String {
        switch contentType {
        case .news:
            return NewsCategory(rawValue: rawValue)?.title ?? rawValue
        case .event:
            return EventCategory(rawValue: rawValue)?.title ?? rawValue
        case .organization:
            return rawValue
        }
    }
}
