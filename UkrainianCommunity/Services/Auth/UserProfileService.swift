import Foundation
import FirebaseAuth
import FirebaseFirestore

struct RegisteredUserDocumentData: Equatable {
    let id: String
    let fullName: String
    let displayName: String
    let city: String
    let email: String
    let bio: String
    let telegramUsername: String?
    let role: String
    let isBlocked: Bool
    let blockState: String
    let globalRole: String
    let moderatorSections: [String]
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
            "role": role,
            "isBlocked": isBlocked,
            "blockState": blockState,
            "globalRole": globalRole,
            "moderatorSections": moderatorSections,
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
                "role": "user",
                "isBlocked": false,
                "globalRole": GlobalRole.user.rawValue,
                "moderatorSections": [],
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
            let moderatorSections = data["moderatorSections"] as? [String]
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
                role: data["role"] as? String ?? UserRole.user.rawValue,
                blockState: data["blockState"] as? String ?? (isBlocked ? UserBlockState.blocked.rawValue : UserBlockState.active.rawValue),
                globalRole: data["globalRole"] as? String,
                moderatorSections: moderatorSections,
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
            role: UserRole.user.rawValue,
            isBlocked: false,
            blockState: UserBlockState.active.rawValue,
            globalRole: GlobalRole.user.rawValue,
            moderatorSections: [],
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
            "updatedAt": FieldValue.serverTimestamp()
        ])

        guard let updatedUser = await UserProfileService.shared.fetchUserProfile(uid: uid) else {
            throw AppError.notFound
        }

        return updatedUser
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
}
