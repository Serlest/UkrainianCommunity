import Foundation
import FirebaseFirestore

final class UserProfileService {
    static let shared = UserProfileService()

    private init() {}

    func ensureUserDocumentExists(for uid: String) async {
        let document = Firestore.firestore().collection("users").document(uid)

        do {
            let snapshot = try await document.getDocument()

            if snapshot.exists {
                print("User profile already exists: \(uid)")
                return
            }

            print("Creating new user document: \(uid)")
            try await document.setData([
                "id": uid,
                "role": "user",
                "isBlocked": false,
                "globalRole": GlobalRole.user.rawValue,
                "moderatorSections": [],
                "accountStatus": AccountStatus.active.rawValue,
                "warningCount": 0,
                "communityMemberships": [],
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ])
            print("User profile created: \(uid)")
        } catch {
            print("User profile Firestore error: \(error)")
        }
    }

    func fetchUserProfile(uid: String) async -> AppUser? {
        let document = Firestore.firestore().collection("users").document(uid)

        do {
            let snapshot = try await document.getDocument()

            guard snapshot.exists, let data = snapshot.data() else {
                print("User profile not found: \(uid)")
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
                city: data["city"] as? String ?? "",
                email: data["email"] as? String ?? "",
                bio: data["bio"] as? String ?? "",
                role: data["role"] as? String ?? UserRole.user.rawValue,
                blockState: data["blockState"] as? String ?? (isBlocked ? UserBlockState.blocked.rawValue : UserBlockState.active.rawValue),
                globalRole: data["globalRole"] as? String,
                moderatorSections: moderatorSections,
                accountStatus: data["accountStatus"] as? String,
                banExpiresAt: (data["banExpiresAt"] as? Timestamp)?.dateValue(),
                warningCount: data["warningCount"] as? Int,
                communityMemberships: communityMemberships,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))

            print("User profile fetched successfully: \(uid)")
            #if DEBUG
            print("User profile debug uid=\(user.id)")
            print("User profile debug globalRole=\(user.globalRole.rawValue)")
            print("User profile debug accountStatus=\(user.accountStatus.rawValue)")
            print("User profile debug isBlocked=\(isBlocked)")
            #endif
            return user
        } catch {
            print("User profile fetch error: \(error)")
            return nil
        }
    }
}
