import Foundation

nonisolated struct BlockedOrganization: Codable, Identifiable, Equatable, Sendable {
    let organizationID: String
    let name: String
    let blockedAt: Date
    var id: String { organizationID }
}

struct OrganizationBlockTarget: Identifiable {
    let organizationID: String
    let name: String
    var id: String { organizationID }

    init(_ organization: Organization) {
        organizationID = organization.id
        name = organization.localizedName
    }
}
