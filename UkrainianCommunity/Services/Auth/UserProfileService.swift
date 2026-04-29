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
                try await document.updateData([
                    "updatedAt": FieldValue.serverTimestamp()
                ])
                print("User profile already exists. Updated timestamp: \(uid)")
                return
            }

            print("Creating new user document: \(uid)")
            try await document.setData([
                "id": uid,
                "role": "user",
                "isBlocked": false,
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

            let roleRawValue = data["role"] as? String ?? UserRole.user.rawValue
            let role = UserRole(rawValue: roleRawValue) ?? .user
            let isBlocked = data["isBlocked"] as? Bool ?? false
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? .now
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? createdAt

            let user = AppUser(
                id: data["id"] as? String ?? uid,
                fullName: data["fullName"] as? String ?? "",
                city: data["city"] as? String ?? "",
                email: data["email"] as? String ?? "",
                bio: data["bio"] as? String ?? "",
                role: role,
                blockState: isBlocked ? .blocked : .active,
                createdAt: createdAt,
                updatedAt: updatedAt
            )

            print("User profile fetched successfully: \(uid)")
            return user
        } catch {
            print("User profile fetch error: \(error)")
            return nil
        }
    }
}
