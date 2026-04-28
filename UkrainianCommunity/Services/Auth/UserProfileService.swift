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
}
