import FirebaseFirestore
import Foundation

protocol OrganizationRoleManagementService {
    func updateRole(
        role: CommunityRole,
        organization: Organization,
        targetUserID: String,
        actor: AppUser,
        isRemoval: Bool
    ) async throws

    func transferOwner(
        organization: Organization,
        newOwnerID: String,
        actor: AppUser
    ) async throws
}

final class FirestoreOrganizationRoleManagementService: OrganizationRoleManagementService {
    private let database: Firestore
    private var organizationsCollection: CollectionReference { database.collection("organizations") }
    private var auditCollection: CollectionReference { database.collection("auditLogs") }

    init(database: Firestore = Firestore.firestore()) {
        self.database = database
    }

    func updateRole(
        role: CommunityRole,
        organization: Organization,
        targetUserID: String,
        actor: AppUser,
        isRemoval: Bool
    ) async throws {
        let organizationReference = organizationsCollection.document(organization.id)
        let previousRole = Self.role(for: targetUserID, in: organization)
        let actorIsPlatformOwner = actor.globalRole.authorizationRole == .owner

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

                if isRemoval, currentOwnerId == targetUserID {
                    errorPointer?.pointee = AppError.permissionDenied.asNSError
                    return nil
                }

                if !isRemoval, currentOwnerId == targetUserID, role != .communityOwner {
                    errorPointer?.pointee = AppError.permissionDenied.asNSError
                    return nil
                }

                if !actorIsPlatformOwner, role == .communityOwner {
                    errorPointer?.pointee = AppError.permissionDenied.asNSError
                    return nil
                }

                let updatedAdminIds = currentAdminIds.filter { $0 != targetUserID }
                let updatedModeratorIds = currentModeratorIds.filter { $0 != targetUserID }
                var organizationUpdate: [String: Any] = [
                    "adminIds": updatedAdminIds,
                    "moderatorIds": updatedModeratorIds,
                    "updatedAt": FieldValue.serverTimestamp()
                ]

                if !isRemoval {
                    switch role {
                    case .communityOwner:
                        organizationUpdate["ownerId"] = targetUserID
                    case .communityAdmin:
                        organizationUpdate["adminIds"] = Array(Set(updatedAdminIds + [targetUserID])).sorted()
                    case .communityModerator:
                        organizationUpdate["moderatorIds"] = Array(Set(updatedModeratorIds + [targetUserID])).sorted()
                    case .member:
                        break
                    }
                }

                transaction.updateData(organizationUpdate, forDocument: organizationReference)

                transaction.setData([
                    "actionType": isRemoval ? "organizationRoleRemoved" : "organizationRoleAssigned",
                    "targetUserId": targetUserID,
                    "performedBy": actor.id,
                    "createdAt": FieldValue.serverTimestamp(),
                    "reason": "Organization management hub",
                    "note": NSNull(),
                    "previousValue": [
                        "organizationId": organization.id,
                        "role": previousRole?.rawValue ?? "none"
                    ],
                    "newValue": [
                        "organizationId": organization.id,
                        "role": isRemoval ? "none" : role.rawValue
                    ]
                ], forDocument: self.auditCollection.document())
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
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
