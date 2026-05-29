import Foundation

enum GuideStatus: String, Codable, CaseIterable, Identifiable {
    case draft
    case review
    case approved
    case published
    case needsReview
    case archived

    var id: String { rawValue }
}
