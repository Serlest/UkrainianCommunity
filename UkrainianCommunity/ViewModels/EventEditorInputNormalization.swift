import Foundation

/// Pure input transformations shared by editor validation and publication.
/// Keep acceptance and fallback rules stable when changing presentation.
enum EventEditorInputNormalization {
    static func combinedDate(dateFrom dateValue: Date, timeFrom timeValue: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: dateValue)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: timeValue)

        var components = DateComponents()
        components.year = dateComponents.year
        components.month = dateComponents.month
        components.day = dateComponents.day
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second ?? 0

        return calendar.date(from: components) ?? dateValue
    }

    static func priceText(from price: Double) -> String {
        guard price > 0 else { return "" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_AT")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: price)) ?? "\(price)"
    }

    static func isValidPositiveIntegerOrBlank(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || Int(trimmed).map { $0 > 0 } == true
    }

    static func isValidNonNegativeDecimalOrBlank(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return Double(trimmed.replacingOccurrences(of: ",", with: ".")).map { $0 >= 0 } == true
    }

    static func isValidAgeOrBlank(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || Int(trimmed).map { (0...120).contains($0) } == true
    }

    static func normalizedURLString(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else {
            return nil
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           url.host?.isEmpty == false {
            return url.absoluteString
        }

        guard !trimmed.contains("://"), trimmed.contains("."),
              let url = URL(string: "https://\(trimmed)"),
              url.host?.isEmpty == false else {
            return trimmed
        }

        return url.absoluteString
    }

    static func additionalCategories(_ categories: [EventCategory], excluding selectedCategory: EventCategory) -> [EventCategory] {
        Array(categories.reduce(into: [EventCategory]()) { result, candidate in
            guard candidate != selectedCategory,
                  candidate != .unspecified,
                  !result.contains(candidate) else { return }
            result.append(candidate)
        }.prefix(EventCategory.maximumAdditionalCategoryCount))
    }
}
