import FirebaseAuth

final class AuthService {
    static let shared = AuthService()

    let authState = AuthState()

    var currentUser: User? { Auth.auth().currentUser }
    var isAuthenticated: Bool { currentUser != nil }

    @MainActor
    func signInAnonymously() async {
        if let currentUser {
            print("Already signed in")
            await ensureUserProfileExists(for: currentUser.uid)
            return
        }

        do {
            let result = try await Auth.auth().signInAnonymously()
            let uid = result.user.uid
            print("Signed in: \(uid)")
            await ensureUserProfileExists(for: uid)
        } catch {
            print("Auth error: \(error.localizedDescription)")
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            print("Signed out")
        } catch {
            print("Sign out error: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func ensureUserProfileExists(for uid: String) async {
        print("Calling ensureUserDocumentExists")
        await UserProfileService.shared.ensureUserDocumentExists(for: uid)
        await authState.loadUser(uid: uid)
        print("User profile ensured: \(uid)")
    }

    private init() {
        #if DEBUG
        print("AuthService init")
        #endif
    }
}
