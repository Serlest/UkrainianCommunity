import FirebaseAuth

final class AuthService {
    static let shared = AuthService()

    let authState = AuthState()

    var currentUser: User? { Auth.auth().currentUser }
    var isAuthenticated: Bool { currentUser != nil }

    @MainActor
    func signInAnonymously() async {
        if let currentUser {
            await ensureUserProfileExists(for: currentUser.uid)
            return
        }

        do {
            let result = try await Auth.auth().signInAnonymously()
            let uid = result.user.uid
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
        await UserProfileService.shared.ensureUserDocumentExists(for: uid)
        await authState.loadUser(uid: uid)
    }

    private init() {}
}
