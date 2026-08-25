import Foundation

enum SystemLogSortOption: String, Codable, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst
    case severityHighToLow
    case severityLowToHigh
    case category

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestFirst: AppStrings.SystemLogs.sortNewest
        case .oldestFirst: AppStrings.SystemLogs.sortOldest
        case .severityHighToLow: AppStrings.SystemLogs.sortSeverityHigh
        case .severityLowToHigh: AppStrings.SystemLogs.sortSeverityLow
        case .category: AppStrings.SystemLogs.sortCategory
        }
    }

    var systemImage: String {
        switch self {
        case .newestFirst: "clock.arrow.circlepath"
        case .oldestFirst: "clock"
        case .severityHighToLow: "exclamationmark.triangle.fill"
        case .severityLowToHigh: "info.circle"
        case .category: "square.grid.2x2"
        }
    }
}
