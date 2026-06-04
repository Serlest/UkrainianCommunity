import Foundation

enum GuideMaterialKind: String, Codable, CaseIterable, Identifiable {
    case page

    var id: String { rawValue }
}
