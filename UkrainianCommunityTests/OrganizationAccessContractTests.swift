import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct OrganizationAccessContractTests {
    @Test func clientCompatibilityMatchesAll1080ReleasedDecisions() throws {
        struct Fixture: Decodable {
            let actor: String
            let state: String
            let system: Bool
            let expected: [String: Bool]
        }
        struct Contract: Decodable { let fixtures: [Fixture] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let contract = try JSONDecoder().decode(Contract.self, from: Data(contentsOf: root.appendingPathComponent("Contracts/organization-access-v1.json")))
        for fixture in contract.fixtures {
            let uid = fixture.actor == "blocked-org-owner" || fixture.actor == "warned-org-owner" ? "org-owner" : fixture.actor
            let role: GlobalRole = fixture.actor == "owner" ? .owner : fixture.actor == "app-admin" ? .admin : fixture.actor == "legacy-top-admin" ? .topAdmin : .user
            let user: AppUser? = fixture.actor == "guest" ? nil : AppUser(id: uid, fullName: "Fixture", displayName: "Fixture", city: "Wien",
                email: "fixture@example.invalid", bio: "", role: .user, globalRole: role,
                blockState: fixture.actor == "blocked-org-owner" ? .bannedPermanent : .active,
                accountStatus: fixture.actor == "warned-org-owner" ? .warned : .active,
                createdAt: .now, updatedAt: .now)
            let organization = Organization(id: fixture.system ? Organization.systemOrganizationID : "fixture",
                name: "Fixture", description: "Fixture", city: "Wien", ownerId: "org-owner", adminIds: ["org-admin"],
                moderatorIds: ["org-moderator"], submittedByUserId: "outsider", createdAt: .now, updatedAt: .now,
                moderationStatus: try #require(ModerationStatus(rawValue: fixture.state)), likeCount: 0, likeState: .notLiked)
            let actual = [
                "editInfo": PermissionService.canEditOrganizationInfo(organization, user: user),
                "manageContent": PermissionService.canAccessManagedOrganization(organization, user: user),
                "manageTeam": PermissionService.canManageOrganizationRoles(organization, user: user),
                "viewSubscribers": PermissionService.canViewOrganizationSubscriberIdentities(organization, user: user),
                "createNews": PermissionService.canCreateOrganizationNews(organization, user: user),
                "editNews": PermissionService.canEditOrganizationNews(organization, user: user),
                "createEvent": PermissionService.canCreateOrganizationEvent(organization, user: user),
                "editEvent": PermissionService.canEditOrganizationEvent(organization, user: user),
                "deleteContent": PermissionService.canDeleteOrganizationContent(organization, user: user),
            ]
            #expect(actual == fixture.expected, "\(fixture.actor)/\(fixture.state)/system=\(fixture.system)")
        }
    }
}
