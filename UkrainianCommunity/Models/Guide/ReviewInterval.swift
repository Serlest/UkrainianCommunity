import Foundation

enum ReviewInterval: String, Codable, CaseIterable, Identifiable {
    case critical
    case normal
    case stable

    var id: String { rawValue }

    var months: Int {
        switch self {
        case .critical:
            3
        case .normal:
            6
        case .stable:
            12
        }
    }
}
