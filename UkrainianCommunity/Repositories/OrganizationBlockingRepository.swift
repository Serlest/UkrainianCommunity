import Foundation

protocol OrganizationBlockingRepository {
    func fetchBlockedOrganizations() async throws -> [BlockedOrganization]
    func setBlocked(organizationID: String, isBlocked: Bool) async throws -> BlockedOrganization?
}

@MainActor
final class MockOrganizationBlockingRepository: OrganizationBlockingRepository {
    private var blocks: [String: BlockedOrganization] = [:]
    init() {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestHiddenOrganizations"] == "1" {
            blocks = ["hidden-graz": .init(organizationID: "hidden-graz", name: "Українська спільнота Graz", blockedAt: .now),
                      "hidden-wien": .init(organizationID: "hidden-wien", name: "Українська спільнота Wien", blockedAt: .now)]
        }
#endif
    }
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
