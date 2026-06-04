import Foundation

enum GuideNodeKind: String, Codable, CaseIterable, Identifiable {
    case section
    case folder

    var id: String { rawValue }
}
