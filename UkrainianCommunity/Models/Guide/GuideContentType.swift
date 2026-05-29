import Foundation

enum GuideContentType: String, Codable, CaseIterable, Identifiable {
    case guide
    case quickInfo
    case checklist
    case contact
    case process

    var id: String { rawValue }
}
