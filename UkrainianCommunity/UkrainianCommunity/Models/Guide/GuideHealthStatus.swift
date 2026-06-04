import Foundation

enum GuideHealthStatus: String, Codable, CaseIterable, Identifiable {
    case current
    case dueSoon
    case overdue
    case archived

    var id: String { rawValue }
}
