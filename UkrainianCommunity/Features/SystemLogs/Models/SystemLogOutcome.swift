import Foundation

enum SystemLogOutcome: String, Codable, CaseIterable, Hashable {
    case success
    case failed
    case blocked
    case pending
    case approved
    case rejected
    case skipped
    case unknown
}
