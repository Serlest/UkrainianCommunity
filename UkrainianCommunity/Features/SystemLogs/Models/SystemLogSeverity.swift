import Foundation

enum SystemLogSeverity: String, Codable, CaseIterable, Hashable, Comparable {
    case debug
    case info
    case notice
    case warning
    case error
    case critical

    private var rank: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .notice: 2
        case .warning: 3
        case .error: 4
        case .critical: 5
        }
    }

    static func < (lhs: SystemLogSeverity, rhs: SystemLogSeverity) -> Bool {
        lhs.rank < rhs.rank
    }
}
