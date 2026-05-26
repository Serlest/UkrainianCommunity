import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

enum AccountDeletionStage: String, Equatable {
    case privateDataCleanup = "private_data_cleanup"
    case interactionCleanup = "interaction_cleanup"
    case registrationCleanup = "registration_cleanup"
    case avatarCleanup = "avatar_cleanup"
    case publicProfileDelete = "public_profile_delete"
    case userDocumentDelete = "user_document_delete"
    case authUserDelete = "auth_user_delete"
}

enum AccountDeletionError: Error, Equatable {
    case platformOwner
    case ownsOrganization
    case requiresRecentLogin
    case stageFailed(AccountDeletionStage, permissionDenied: Bool)
}

struct RegisteredUserDocumentData: Equatable {
    let id: String
    let fullName: String
    let displayName: String
    let city: String
    let email: String
    let bio: String
    let telegramUsername: String?
    let role: String? = nil
    let isBlocked: Bool
    let blockState: String
    let globalRole: String
    let canManageGuide: Bool
    let selectedFederalState: String
    let accountStatus: String
    let warningCount: Int
    let communityMemberships: [[String: String]]
    let acceptedTermsAt: Date
    let acceptedPrivacyAt: Date
    let termsVersion: String
    let privacyVersion: String

    var firestoreData: [String: Any] {
        [
            "id": id,
            "fullName": fullName,
            "displayName": displayName,
            "city": city,
            "email": email,
            "bio": bio,
            "telegramUsername": telegramUsername ?? NSNull(),
            "isBlocked": isBlocked,
            "blockState": blockState,
            "globalRole": globalRole,
            "canManageGuide": canManageGuide,
            "selectedFederalState": selectedFederalState,
            "accountStatus": accountStatus,
            "warningCount": warningCount,
            "communityMemberships": communityMemberships,
            "acceptedTermsAt": Timestamp(date: acceptedTermsAt),
            "acceptedPrivacyAt": Timestamp(date: acceptedPrivacyAt),
            "termsVersion": termsVersion,
            "privacyVersion": privacyVersion,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
    }
}

final class UserProfileService {
    static let shared = UserProfileService()

    private init() {}

    func ensureUserDocumentExists(for uid: String) async {
        let document = Firestore.firestore().collection("users").document(uid)

        do {
            let snapshot = try await document.getDocument()

            if snapshot.exists {
                return
            }

            try await document.setData([
                "id": uid,
                "isBlocked": false,
                "blockState": UserBlockState.active.rawValue,
                "globalRole": GlobalRole.user.rawValue,
                "canManageGuide": false,
                "selectedFederalState": AustrianFederalState.tirol.rawValue,
                "displayName": "",
                "telegramUsername": NSNull(),
                "accountStatus": AccountStatus.active.rawValue,
                "warningCount": 0,
                "communityMemberships": [],
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
        } catch {
        }
    }

    func createRegisteredUserDocument(for uid: String, draft: RegistrationProfileDraft) async throws {
        let document = Firestore.firestore().collection("users").document(uid)
        let payload = Self.makeRegisteredUserDocumentData(uid: uid, draft: draft)

        do {
            try await document.setData(payload.firestoreData)
            try? await upsertPublicProfile(
                uid: uid,
                displayName: draft.displayName,
                avatarURL: nil,
                city: "",
                federalState: draft.selectedFederalState
            )
        } catch {
            if let nsError = error as NSError?, nsError.domain == FirestoreErrorDomain {
                switch nsError.code {
                case FirestoreErrorCode.permissionDenied.rawValue:
                    throw AppError.permissionDenied
                case FirestoreErrorCode.unavailable.rawValue, FirestoreErrorCode.deadlineExceeded.rawValue:
                    throw AppError.network
                default:
                    throw AppError.unknown
                }
            }

            throw error
        }
    }

    func fetchUserProfile(uid: String) async -> AppUser? {
        let document = Firestore.firestore().collection("users").document(uid)

        do {
            let snapshot = try await document.getDocument()

            guard snapshot.exists, let data = snapshot.data() else {
                return nil
            }

            let isBlocked = data["isBlocked"] as? Bool ?? false
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? .now
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt
            let communityMemberships: [CommunityMembershipDTO]? = (data["communityMemberships"] as? [[String: Any]])?.compactMap { rawMembership in
                guard
                    let organizationId = rawMembership["organizationId"] as? String,
                    let role = rawMembership["role"] as? String
                else {
                    return nil
                }

                return CommunityMembershipDTO(organizationId: organizationId, role: role)
            }

            let user = AppUser(dto: UserDTO(
                id: data["id"] as? String ?? uid,
                fullName: data["fullName"] as? String ?? "",
                displayName: data["displayName"] as? String,
                city: data["city"] as? String ?? "",
                email: data["email"] as? String ?? "",
                avatarURL: data["avatarURL"] as? String,
                bio: data["bio"] as? String ?? "",
                telegramUsername: data["telegramUsername"] as? String,
                role: data["role"] as? String,
                blockState: data["blockState"] as? String ?? (isBlocked ? UserBlockState.suspendedUntil.rawValue : UserBlockState.active.rawValue),
                globalRole: data["globalRole"] as? String,
                moderatorSections: data["moderatorSections"] as? [String],
                canManageGuide: data["canManageGuide"] as? Bool,
                accountStatus: data["accountStatus"] as? String,
                banExpiresAt: (data["banExpiresAt"] as? Timestamp)?.dateValue(),
                warningCount: data["warningCount"] as? Int,
                communityMemberships: communityMemberships,
                selectedFederalState: data["selectedFederalState"] as? String,
                acceptedTermsAt: (data["acceptedTermsAt"] as? Timestamp)?.dateValue(),
                acceptedPrivacyAt: (data["acceptedPrivacyAt"] as? Timestamp)?.dateValue(),
                termsVersion: data["termsVersion"] as? String,
                privacyVersion: data["privacyVersion"] as? String,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))

            return user
        } catch {
            return nil
        }
    }

    func upsertPublicProfile(for user: AppUser) async throws {
        try await upsertPublicProfile(
            uid: user.id,
            displayName: user.preferredDisplayName,
            avatarURL: user.avatarURL,
            city: user.city,
            federalState: user.selectedFederalState
        )
    }

    private func upsertPublicProfile(
        uid: String,
        displayName: String,
        avatarURL: URL?,
        city: String,
        federalState: AustrianFederalState?
    ) async throws {
        var data: [String: Any] = [
            "id": uid,
            "displayName": displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let avatarURL {
            data["avatarURL"] = avatarURL.absoluteString
        } else {
            data["avatarURL"] = FieldValue.delete()
        }

        if let federalState {
            data["federalState"] = federalState.rawValue
        } else {
            data["federalState"] = FieldValue.delete()
        }

        try await Firestore.firestore()
            .collection("publicProfiles")
            .document(uid)
            .setData(data, merge: true)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UserProfileService {
    static func makeRegisteredUserDocumentData(uid: String, draft: RegistrationProfileDraft) -> RegisteredUserDocumentData {
        RegisteredUserDocumentData(
            id: uid,
            fullName: draft.displayName,
            displayName: draft.displayName,
            city: "",
            email: draft.email,
            bio: "",
            telegramUsername: draft.telegramUsername?.nilIfEmpty,
            isBlocked: false,
            blockState: UserBlockState.active.rawValue,
            globalRole: GlobalRole.user.rawValue,
            canManageGuide: false,
            selectedFederalState: draft.selectedFederalState.rawValue,
            accountStatus: AccountStatus.active.rawValue,
            warningCount: 0,
            communityMemberships: [],
            acceptedTermsAt: draft.acceptedTermsAt,
            acceptedPrivacyAt: draft.acceptedPrivacyAt,
            termsVersion: draft.termsVersion,
            privacyVersion: draft.privacyVersion
        )
    }
}

struct FirestoreUserRepository: UserRepository {
    func fetchCurrentUser() async throws -> AppUser {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        guard let user = await UserProfileService.shared.fetchUserProfile(uid: uid) else {
            throw AppError.notFound
        }

        try? await UserProfileService.shared.upsertPublicProfile(for: user)
        return user
    }

    func fetchSettings() async throws -> UserSettings {
        .stored
    }

    func updateProfile(_ profile: EditableUserProfileDraft) async throws -> AppUser {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let document = Firestore.firestore().collection("users").document(uid)
        let trimmedFullName = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCity = profile.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBio = profile.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTelegramUsername = profile.telegramUsername?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        try await document.updateData([
            "fullName": trimmedFullName,
            "displayName": trimmedDisplayName,
            "city": trimmedCity,
            "bio": trimmedBio,
            "telegramUsername": (trimmedTelegramUsername?.isEmpty == false) ? trimmedTelegramUsername! : NSNull(),
            "selectedFederalState": profile.selectedFederalState.rawValue,
            "avatarURL": profile.avatarURL?.absoluteString ?? FieldValue.delete(),
            "updatedAt": FieldValue.serverTimestamp()
        ])

        guard let updatedUser = await UserProfileService.shared.fetchUserProfile(uid: uid) else {
            throw AppError.notFound
        }

        try? await UserProfileService.shared.upsertPublicProfile(for: updatedUser)
        return updatedUser
    }

    func deleteAccount(currentUser: AppUser) async throws {
        guard let authUser = Auth.auth().currentUser, authUser.uid == currentUser.id else {
            throw AppError.permissionDenied
        }
        let uid = authUser.uid

        guard isRecentlyAuthenticated(authUser) else {
            throw AccountDeletionError.requiresRecentLogin
        }

        guard currentUser.globalRole.effectiveRole != .owner else {
            throw AccountDeletionError.platformOwner
        }

        guard !currentUser.communityMemberships.contains(where: { $0.role == .communityOwner }) else {
            throw AccountDeletionError.ownsOrganization
        }

        let database = Firestore.firestore()
        // TODO: Enforce organization-owner deletion blocking server-side via Cloud Function or
        // an ownedOrganizationIds/ownedOrganizationCount marker on users/{uid}.
        do {
            try await cleanupPrivateUserData(userID: uid, database: database)
        } catch {
            throw accountDeletionStageFailure(.privateDataCleanup, error: error)
        }

        do {
            try await cleanupInteractionDocuments(userID: uid, database: database)
        } catch {
            throw accountDeletionStageFailure(.interactionCleanup, error: error)
        }

        do {
            try await cleanupRegistrationDocuments(userID: uid, database: database)
        } catch {
            throw accountDeletionStageFailure(.registrationCleanup, error: error)
        }

        do {
            try await cleanupProfileAvatar(userID: uid)
        } catch {
            throw accountDeletionStageFailure(.avatarCleanup, error: error)
        }

        do {
            try await database.collection("publicProfiles").document(uid).delete()
        } catch {
            throw accountDeletionStageFailure(.publicProfileDelete, error: error)
        }

        do {
            try await database.collection("users").document(uid).delete()
        } catch {
            throw accountDeletionStageFailure(.userDocumentDelete, error: error)
        }

        do {
            try await authUser.delete()
        } catch {
            if isRequiresRecentLogin(error) {
                throw AccountDeletionError.requiresRecentLogin
            }
            throw accountDeletionStageFailure(.authUserDelete, error: error)
        }
    }

    private func isRecentlyAuthenticated(_ user: User) -> Bool {
        guard let lastSignInDate = user.metadata.lastSignInDate else {
            return false
        }

        return Date().timeIntervalSince(lastSignInDate) < 240
    }

    private func accountDeletionStageFailure(_ stage: AccountDeletionStage, error: Error) -> AccountDeletionError {
        let nsError = error as NSError
        let isPermissionDenied = nsError.domain == FirestoreErrorDomain
            && nsError.code == FirestoreErrorCode.permissionDenied.rawValue

        #if DEBUG
        print("Account deletion failed [\(stage.rawValue)] \(nsError.domain)(\(nsError.code)): \(nsError.localizedDescription)")
        #endif

        return .stageFailed(stage, permissionDenied: isPermissionDenied)
    }

    private func isRequiresRecentLogin(_ error: Error) -> Bool {
        let nsError = error as NSError
        return AuthErrorCode(rawValue: nsError.code) == .requiresRecentLogin
    }

    private func cleanupPrivateUserData(userID: String, database: Firestore) async throws {
        let privateSubcollections = [
            "recentViews",
            "activityLog",
            "newsBookmarks",
            "eventBookmarks",
            "organizationBookmarks",
            "eventViews",
            "newsViews"
        ]

        for subcollection in privateSubcollections {
            try await deleteDocuments(
                in: database.collection("users").document(userID).collection(subcollection),
                limit: 100
            )
        }
    }

    private func cleanupInteractionDocuments(userID: String, database: Firestore) async throws {
        // TODO: Reconcile aggregate counters server-side. Bulk client cleanup deletes the source docs
        // without trying to decrement mixed news/event/organization counters optimistically.
        while true {
            let snapshot = try await database.collection("likes")
                .whereField("userId", isEqualTo: userID)
                .limit(to: 500)
                .getDocuments()
            guard !snapshot.documents.isEmpty else { return }

            let batch = database.batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()

            if snapshot.documents.count < 500 {
                return
            }
        }
    }

    private func cleanupRegistrationDocuments(userID: String, database: Firestore) async throws {
        // TODO: Reconcile event registeredCount server-side. Client account deletion removes
        // registration source docs without direct aggregate counter writes.
        try await deleteDocuments(
            in: database.collection("registrations").whereField("userId", isEqualTo: userID),
            limit: 500
        )
    }

    private func cleanupProfileAvatar(userID: String) async throws {
        do {
            try await Storage.storage()
                .reference()
                .child("profileImages/\(userID)/avatar.jpg")
                .delete()
        } catch {
            let nsError = error as NSError
            if nsError.domain == StorageErrorDomain,
               StorageErrorCode(rawValue: nsError.code) == .objectNotFound {
                return
            }

            throw error
        }
    }

    private func deleteDocuments(in collection: CollectionReference, limit: Int) async throws {
        while true {
            let snapshot = try await collection.limit(to: limit).getDocuments()
            guard !snapshot.documents.isEmpty else { return }

            let batch = Firestore.firestore().batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()

            if snapshot.documents.count < limit {
                return
            }
        }
    }

    private func deleteDocuments(in query: Query, limit: Int) async throws {
        while true {
            let snapshot = try await query.limit(to: limit).getDocuments()
            guard !snapshot.documents.isEmpty else { return }

            let batch = Firestore.firestore().batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()

            if snapshot.documents.count < limit {
                return
            }
        }
    }
}

struct FirestoreFeedbackRepository: FeedbackRepository {
    private let collection = Firestore.firestore().collection("feedback")

    func submitFeedback(_ feedback: FeedbackItem) async throws {
        try await collection.document(feedback.id).setData([
            "id": feedback.id,
            "type": feedback.type.rawValue,
            "message": feedback.message,
            "status": feedback.status.rawValue,
            "createdAt": Timestamp(date: feedback.createdAt),
            "userId": feedback.userId,
            "userDisplayName": feedback.userDisplayName
        ])
    }

    func fetchFeedback() async throws -> [FeedbackItem] {
        let snapshot = try await collection
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return snapshot.documents.map { document in
            makeFeedbackItem(from: document)
        }
    }

    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws {
        try await collection.document(id).updateData([
            "status": status.rawValue
        ])
    }

    private func makeFeedbackItem(from document: QueryDocumentSnapshot) -> FeedbackItem {
        let data = document.data()
        let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()

        return FeedbackItem(
            id: data["id"] as? String ?? document.documentID,
            type: FeedbackType(rawValue: data["type"] as? String ?? "") ?? .question,
            message: data["message"] as? String ?? "",
            status: FeedbackStatus(rawValue: data["status"] as? String ?? "") ?? .open,
            createdAt: createdAt,
            userId: data["userId"] as? String ?? "",
            userDisplayName: data["userDisplayName"] as? String ?? ""
        )
    }
}
