import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct SystemLogActorIdentityResolverTests {
    @Test func missingProfileReturnsNil() async throws {
        let resolver = LiveSystemLogActorIdentityResolver(
            reads: readsReturning(nil)
        )

        let identity = try await resolver.resolve(userID: "deleted-user")

        #expect(identity == nil)
    }

    @Test func currentProfileIdentityIsTrimmedAndPrefersDisplayName() async throws {
        let user = AppUser(
            id: "actor-1",
            fullName: " Full Name ",
            displayName: " Current Name ",
            city: "",
            email: " actor@example.com ",
            bio: "",
            role: .user,
            blockState: .active,
            createdAt: .now,
            updatedAt: .now
        )
        let resolver = LiveSystemLogActorIdentityResolver(
            reads: readsReturning(user)
        )

        let identity = try await resolver.resolve(userID: user.id)

        #expect(identity == SystemLogActorIdentity(
            displayName: "Current Name",
            email: "actor@example.com"
        ))
    }

    @Test func fullNameIsUsedWhenDisplayNameIsBlank() async throws {
        let user = AppUser(
            id: "actor-2",
            fullName: " Full Name ",
            displayName: "  ",
            city: "",
            email: "",
            bio: "",
            role: .user,
            blockState: .active,
            createdAt: .now,
            updatedAt: .now
        )
        let resolver = LiveSystemLogActorIdentityResolver(
            reads: readsReturning(user)
        )

        let identity = try await resolver.resolve(userID: user.id)

        #expect(identity == SystemLogActorIdentity(displayName: "Full Name", email: nil))
    }

    private func readsReturning(_ user: AppUser?) -> UserManagementReads {
        UserManagementReads(
            users: { _ in fatalError("Unexpected users page read") },
            user: { _ in user },
            organizations: { fatalError("Unexpected organizations read") },
            securityMetadata: { _ in fatalError("Unexpected security metadata read") }
        )
    }
}
