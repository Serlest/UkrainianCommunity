import Foundation

enum AnalyticsPeriod: String, CaseIterable, Codable, Identifiable {
    case today
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    var analyticsTitle: String {
        switch self {
        case .today: AppStrings.OwnerAnalytics.periodToday
        case .sevenDays: AppStrings.OwnerAnalytics.periodSevenDays
        case .thirtyDays: AppStrings.OwnerAnalytics.periodThirtyDays
        }
    }

    var dayCount: Int {
        switch self {
        case .today:
            1
        case .sevenDays:
            7
        case .thirtyDays:
            30
        }
    }
}
