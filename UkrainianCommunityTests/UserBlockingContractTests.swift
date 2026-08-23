import Foundation
import Testing
@testable import UkrainianCommunity

@Suite("User blocking contract")
struct UserBlockingContractTests {
    @Test func cloudFunctionNameMatchesBackendContract() {
        #expect(CloudFunctionName.setUserBlocked.rawValue == "setUserBlocked")
        #expect(CloudFunctionName.allCases.contains(.setUserBlocked))
    }

    @Test func requestContainsOnlyTrustedMutationFields() throws {
        let request = UserBlockFunctionRequest(targetUserId: "user-2", isBlocked: true)
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )

        #expect(object["targetUserId"] as? String == "user-2")
        #expect(object["isBlocked"] as? Bool == true)
        #expect(object.count == 2)
    }

    @Test func mockRepositoryReturnsExistingDisplayDataWhenUnblocking() async throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let repository = MockUserBlockingRepository(blockedUsers: [
            BlockedUser(
                targetUserId: "user-2",
                displayName: "Olena",
                avatarURL: URL(string: "https://example.com/avatar.jpg"),
                blockedAt: date,
                updatedAt: date
            )
        ])

        let receipt = try await repository.setBlocked(targetUserID: "user-2", isBlocked: false)
        #expect(receipt.targetUserId == "user-2")
        #expect(receipt.displayName == "Olena")
        #expect(receipt.isBlocked == false)
    }
}
