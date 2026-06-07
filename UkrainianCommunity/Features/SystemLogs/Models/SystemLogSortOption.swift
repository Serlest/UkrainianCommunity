import Foundation

enum SystemLogSortOption: String, Codable, CaseIterable, Identifiable {
    case newestFirst
    case oldestFirst
    case severityHighToLow
    case severityLowToHigh
    case category

    var id: String { rawValue }
}
