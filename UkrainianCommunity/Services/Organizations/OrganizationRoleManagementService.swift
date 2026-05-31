import FirebaseFirestore
import Foundation

protocol OrganizationRoleManagementService {
    func updateRole(
        role: CommunityRole,
        organization: Organization,
        targetUserID: String,
        actor: AppUser,
        isRemoval: Bool,
        reason: String?
    ) async throws

    func transferOwner(
        organization: Organization,
        newOwnerID: String,
        actor: AppUser
    ) async throws
}

final class FirestoreOrganizationRoleManagementService: OrganizationRoleManagementService {
    private let database: Firestore
    private let cloudFunctionsClient: CloudFunctionsClient
    private var organizationsCollection: CollectionReference { database.collection("organizations") }
    private var auditCollection: CollectionReference { database.collection("auditLogs") }

    init(
        database: Firestore = Firestore.firestore(),
        cloudFunctionsClient: CloudFunctionsClient = .shared
    ) {
        self.database = database
        self.cloudFunctionsClient = cloudFunctionsClient
    }

    func updateRole(
        role: CommunityRole,
        organization: Organization,
        targetUserID: String,
        actor: AppUser,
        isRemoval: Bool,
        reason: String?
    ) async throws {
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = OrganizationRoleChangeFunctionRequest(
            organizationId: organization.id,
            targetUserId: targetUserID,
            reason: trimmedReason?.isEmpty == false ? trimmedReason : nil
        )

        if isRemoval {
            switch Self.role(for: targetUserID, in: organization) {
            case .communityAdmin:
                _ = try await cloudFunctionsClient.removeOrganizationAdmin(request)
            case .communityModerator:
                _ = try await cloudFunctionsClient.removeOrganizationModerator(request)
            case .communityOwner:
                throw AppError.permissionDenied
            case .member, nil:
                return
            }
            return
        }

        switch role {
        case .communityAdmin:
            _ = try await cloudFunctionsClient.assignOrganizationAdmin(request)
        case .communityModerator:
            _ = try await cloudFunctionsClient.assignOrganizationModerator(request)
        case .communityOwner:
            try await transferOwner(organization: organization, newOwnerID: targetUserID, actor: actor)
        case .member:
            return
        }
    }

    func transferOwner(
        organization: Organization,
        newOwnerID: String,
        actor: AppUser
    ) async throws {
        let organizationReference = organizationsCollection.document(organization.id)

        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                let organizationSnapshot = try transaction.getDocument(organizationReference)
                guard let organizationData = organizationSnapshot.data() else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let currentOwnerId = organizationData["ownerId"] as? String
                let currentAdminIds = organizationData["adminIds"] as? [String] ?? []
                let currentModeratorIds = organizationData["moderatorIds"] as? [String] ?? []
                let oldOwnerId = currentOwnerId ?? ""

                guard actor.globalRole.authorizationRole == .owner, !newOwnerID.isEmpty else {
                    errorPointer?.pointee = AppError.permissionDenied.asNSError
                    return nil
                }

                transaction.updateData([
                    "ownerId": newOwnerID,
                    "adminIds": currentAdminIds.filter { $0 != newOwnerID && $0 != oldOwnerId },
                    "moderatorIds": currentModeratorIds.filter { $0 != newOwnerID && $0 != oldOwnerId },
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: organizationReference)

                transaction.setData([
                    "actionType": "organizationOwnerChanged",
                    "targetUserId": newOwnerID,
                    "performedBy": actor.id,
                    "createdAt": FieldValue.serverTimestamp(),
                    "reason": "Organization management hub",
                    "note": NSNull(),
                    "previousValue": [
                        "organizationId": organization.id,
                        "ownerId": currentOwnerId ?? "none"
                    ],
                    "newValue": [
                        "organizationId": organization.id,
                        "ownerId": newOwnerID
                    ]
                ], forDocument: self.auditCollection.document())
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    private static func role(for userID: String, in organization: Organization) -> CommunityRole? {
        if organization.ownerId == userID { return .communityOwner }
        if organization.adminIds.contains(userID) { return .communityAdmin }
        if organization.moderatorIds.contains(userID) { return .communityModerator }
        return nil
    }
}
