import Foundation

enum AnalyticsPeriod: String, CaseIterable, Codable, Identifiable {
    case today
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

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
