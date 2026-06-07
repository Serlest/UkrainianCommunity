import Foundation

enum SystemLogActorRole: String, Codable, CaseIterable, Hashable {
    case guest
    case user
    case organizationModerator
    case organizationAdmin
    case organizationOwner
    case guideEditor
    case moderator
    case admin
    case owner
    case system
    case unknown
}
