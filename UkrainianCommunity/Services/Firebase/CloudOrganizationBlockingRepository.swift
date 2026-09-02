import Foundation

nonisolated struct OrganizationBlockFunctionRequest: Encodable {
    let organizationId: String
    let isBlocked: Bool
}

nonisolated struct OrganizationBlockFunctionRecord: Decodable {
    let organizationId: String
    let name: String
    let blockedAt: String

    func model() throws -> BlockedOrganization {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard !organizationId.isEmpty, !organizationId.contains("/"),
              let date = formatter.date(from: blockedAt) else { throw AppError.validationFailed }
        return BlockedOrganization(organizationID: organizationId, name: name, blockedAt: date)
    }
}

nonisolated struct OrganizationBlockFunctionResponse: Decodable {
    let organizationId: String
    let isBlocked: Bool
    let block: OrganizationBlockFunctionRecord?

    func validated(for organizationID: String, isBlocked expectedState: Bool) throws -> BlockedOrganization? {
        guard organizationId == organizationID, isBlocked == expectedState,
              isBlocked == (block != nil), block == nil || block?.organizationId == organizationID else {
            throw AppError.validationFailed
        }
        return try block?.model()
    }
}

struct CloudOrganizationBlockingRepository: OrganizationBlockingRepository {
    private let client = CloudFunctionsClient.shared

    func fetchBlockedOrganizations() async throws -> [BlockedOrganization] {
        struct Request: Encodable {}
        struct Response: Decodable { let blocks: [OrganizationBlockFunctionRecord] }
        let response: Response = try await client.call(.getBlockedOrganizations, request: Request())
        return try response.blocks.map { try $0.model() }
    }

    func setBlocked(organizationID: String, isBlocked: Bool) async throws -> BlockedOrganization? {
        let response: OrganizationBlockFunctionResponse = try await client.call(
            .setOrganizationBlocked,
            request: OrganizationBlockFunctionRequest(organizationId: organizationID, isBlocked: isBlocked)
        )
        return try response.validated(for: organizationID, isBlocked: isBlocked)
    }
}
