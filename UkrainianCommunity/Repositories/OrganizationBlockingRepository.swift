import Foundation

protocol OrganizationBlockingRepository {
    func fetchBlockedOrganizations() async throws -> [BlockedOrganization]
    func setBlocked(organizationID: String, isBlocked: Bool) async throws -> BlockedOrganization?
}

@MainActor
final class MockOrganizationBlockingRepository: OrganizationBlockingRepository {
    private var blocks: [String: BlockedOrganization] = [:]
    func fetchBlockedOrganizations() async throws -> [BlockedOrganization] { Array(blocks.values) }
    func setBlocked(organizationID: String, isBlocked: Bool) async throws -> BlockedOrganization? {
        if isBlocked {
            blocks[organizationID] = BlockedOrganization(organizationID: organizationID, name: "Organization", blockedAt: .now)
        } else {
            blocks[organizationID] = nil
        }
        return blocks[organizationID]
    }
}
